# Pester tests for MonitoringTools module
# Each test validates core functionality with mocks so the module can run
# without touching the real system. The tests focus on edge cases and
# ensure that logging continues even when optional properties are missing.
# These tests serve as executable documentation for expected behavior.

BeforeAll {
    Import-Module "$PSScriptRoot/../MonitoringTools.psd1"
}

# Ensure the performance logging routine creates an output file
Describe 'Log-PerformanceData' {
    It 'writes data to the performance CSV' {
        $temp = New-TemporaryFile
        try {
            Log-PerformanceData -PerformanceLog $temp.FullName
            (Get-Content $temp.FullName).Length | Should -BeGreaterThan 1
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
        }
    }

    It 'triggers alert when CPU threshold exceeded' {
        Mock Get-Counter {
            [pscustomobject]@{
                CounterSamples = @(
                    [pscustomobject]@{ CounterName='\\Processor(_Total)\\% Processor Time'; CookedValue=95 },
                    [pscustomobject]@{ CounterName='\\Memory\\Available MBytes'; CookedValue=1000 },
                    [pscustomobject]@{ CounterName='\\PhysicalDisk(_Total)\\Disk Reads/sec'; CookedValue=50 },
                    [pscustomobject]@{ CounterName='\\PhysicalDisk(_Total)\\Disk Writes/sec'; CookedValue=50 }
                )
            }
        }
        Mock Send-Alert {}
        $temp = New-TemporaryFile
        try {
            Log-PerformanceData -PerformanceLog $temp.FullName -CpuThreshold 90
            Assert-MockCalled Send-Alert -Times 1
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
            Remove-Mock Get-Counter
            Remove-Mock Send-Alert
        }
    }

    # When a value of 0 is supplied the function should alert on every sample.
    It 'alerts when CPU threshold is zero' {
        Mock Get-Counter {
            [pscustomobject]@{
                CounterSamples = @(
                    [pscustomobject]@{ CounterName='\\Processor(_Total)\\% Processor Time'; CookedValue=10 }
                )
            }
        }
        Mock Send-Alert {}
        $temp = New-TemporaryFile
        try {
            Log-PerformanceData -PerformanceLog $temp.FullName -CpuThreshold 0
            Assert-MockCalled Send-Alert -Times 1
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
            Remove-Mock Get-Counter
            Remove-Mock Send-Alert
        }
    }

    It 'throws when CpuThreshold is out of range' {
        { Log-PerformanceData -CpuThreshold 150 } | Should -Throw
    }
}

# Validate event logging updates the last processed timestamp across logs
Describe 'Log-EventData' {
    It 'tracks the latest event across all logs' {
        $now = Get-Date
        Mock Get-WinEvent {
            param($FilterHashTable)
            $time = switch ($FilterHashTable.LogName) {
                'System' { $now.AddMinutes(-5) }
                'Application' { $now }
                'Security' { $now.AddMinutes(-2) }
            }
            [pscustomobject]@{
                TimeCreated = $time
                Id = 1
                LevelDisplayName = 'Error'
                Message = 'test'
            }
        } -Verifiable

        $temp = New-TemporaryFile
        try {
            $script:lastEventTime = $now.AddMinutes(-10)
            Log-EventData -EventLog $temp.FullName
            $script:lastEventTime | Should -Be $now
            (Import-Csv $temp.FullName).Count | Should -Be 3
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
            Remove-Mock Get-WinEvent
        }
    }
}

# Verify disk usage is calculated correctly when the Used property is absent
Describe 'Log-DiskUsage' {
    It 'calculates used space when Used is missing' {
        Mock Get-PSDrive {
            [pscustomobject]@{ Name='C'; Free=1GB; Size=5GB; Provider='FileSystem' }
        }
        $temp = New-TemporaryFile
        try {
            Log-DiskUsage -DiskUsageLog $temp.FullName
            $record = Import-Csv $temp.FullName | Select-Object -First 1
            [double]$record.UsedPercentage | Should -Be 80
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
            Remove-Mock Get-PSDrive
        }
    }

    It 'alerts when disk usage exceeds threshold' {
        Mock Get-PSDrive {
            [pscustomobject]@{ Name='D'; Free=1GB; Size=2GB; Provider='FileSystem'; Used=$null }
        }
        Mock Send-Alert {}
        $temp = New-TemporaryFile
        try {
            Log-DiskUsage -DiskUsageLog $temp.FullName -UsageThreshold 50
            Assert-MockCalled Send-Alert -Times 1
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
            Remove-Mock Get-PSDrive
            Remove-Mock Send-Alert
        }
    }

    # A threshold of 0 should also generate an alert for any non-zero usage.
    It 'alerts when disk usage threshold is zero' {
        Mock Get-PSDrive {
            [pscustomobject]@{ Name='E'; Free=9GB; Size=10GB; Provider='FileSystem'; Used=$null }
        }
        Mock Send-Alert {}
        $temp = New-TemporaryFile
        try {
            Log-DiskUsage -DiskUsageLog $temp.FullName -UsageThreshold 0
            Assert-MockCalled Send-Alert -Times 1
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
            Remove-Mock Get-PSDrive
            Remove-Mock Send-Alert
        }
    }

    It 'skips drives reporting zero size' {
        # Simulate a drive where the Size property is zero which could cause a divide-by-zero
        Mock Get-PSDrive {
            [pscustomobject]@{ Name='Z'; Free=0; Size=0; Provider='FileSystem'; Used=0 }
        }
        $dir = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid()))
        $file = Join-Path $dir.FullName 'disk.csv'
        try {
            Log-DiskUsage -DiskUsageLog $file
            # File should not exist because the entry is skipped
            Test-Path $file | Should -BeFalse
        } finally {
            Remove-Item $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Mock Get-PSDrive
        }
    }

    It 'skips drives missing Used and Free properties' {
        # Some drives may omit both Used and Free metrics; the function should
        # warn and move on without creating a log entry for such drives.
        Mock Get-PSDrive {
            [pscustomobject]@{ Name='F'; Free=$null; Size=5GB; Provider='FileSystem'; Used=$null }
        }
        # Use a path that does not exist; skipping should prevent file creation.
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        $file = Join-Path $dir 'disk.csv'

        $warnings = & {
            Log-DiskUsage -DiskUsageLog $file
        } 3>&1 4>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        $warnings.Message | Should -Match 'missing free space'
        Test-Path $file | Should -BeFalse
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Mock Get-PSDrive
    }

    It 'throws when UsageThreshold is out of range' {
        { Log-DiskUsage -UsageThreshold 150 } | Should -Throw
    }
}

# Confirm network adapters are filtered to those that are operational
Describe 'Get-NetworkInterfaces' {
    It 'returns only adapters with status Up' {
        Mock Get-NetAdapter {
            @(
                [pscustomobject]@{ Name='Ethernet'; Status='Up'; InterfaceIndex=1 },
                [pscustomobject]@{ Name='WiFi'; Status='Down'; InterfaceIndex=2 }
            )
        }
        $adapters = Get-NetworkInterfaces
        $adapters.Count | Should -Be 1
        $adapters[0].Name | Should -Be 'Ethernet'
        Remove-Mock Get-NetAdapter
    }
}

# Test that logging handles an interface record without failing
Describe 'Log-NetworkTraffic' {
    It 'handles empty interface set without error' {
        $temp = New-TemporaryFile
        try {
            Log-NetworkTraffic -Interface @{ InterfaceIndex = 0; Name = 'None' } -NetworkLog $temp.FullName
            Test-Path $temp.FullName | Should -BeTrue
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
        }
    }

    It 'resolves interfaces by name' {
        # Mock adapter retrieval and statistics so no real network calls occur.
        Mock Get-NetAdapter { @{ Name='eth0'; InterfaceIndex=1; Status='Up' } }
        Mock Get-NetAdapterStatistics { @{ BytesReceived=1; BytesSent=1; PacketsReceived=1; PacketsSent=1 } }
        $temp = New-TemporaryFile
        try {
            Log-NetworkTraffic -InterfaceName eth0 -NetworkLog $temp.FullName
            (Import-Csv $temp.FullName).InterfaceName | Should -Be 'eth0'
        } finally {
            Remove-Item $temp -ErrorAction SilentlyContinue
            Remove-Mock Get-NetAdapter
            Remove-Mock Get-NetAdapterStatistics
        }
    }

    # When the specified interface names fail to resolve to any adapters, the
    # function should emit a warning and avoid creating the log file. This
    # protects scheduled monitoring jobs from unnecessary errors.
    It 'warns when interface name does not match any adapter' {
        # Mock only one adapter so the requested name is absent.
        Mock Get-NetAdapter { @{ Name='eth0'; InterfaceIndex=1; Status='Up' } }

        # Use a path that does not exist; the function should return before
        # attempting to create the directory or file.
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        $file = Join-Path $dir 'net.csv'

        # Capture any warnings emitted during execution.
        $warnings = & {
            Log-NetworkTraffic -InterfaceName 'missing' -NetworkLog $file
        } 3>&1 4>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        $warnings.Message | Should -Match 'No network interfaces matched'
        Test-Path $file | Should -BeFalse
        Remove-Mock Get-NetAdapter
    }
}

Describe 'Send-Alert' {
    It 'sends mail without credential or SSL' {
        Mock Send-MailMessage {}
        Send-Alert -Message 'm' -SmtpServer 's' -From 'f@e.com' -To 't@e.com'
        Assert-MockCalled Send-MailMessage -ParameterFilter { -not $Credential -and -not $UseSsl } -Times 1
        Remove-Mock Send-MailMessage
    }

    It 'includes credential and SSL when provided' {
        Mock Send-MailMessage {}
        $cred = New-Object System.Management.Automation.PSCredential('u',(ConvertTo-SecureString 'p' -AsPlainText -Force))
        Send-Alert -Message 'm' -SmtpServer 's' -From 'f@e.com' -To 't@e.com' -Credential $cred -UseSsl
        Assert-MockCalled Send-MailMessage -ParameterFilter { $Credential -eq $cred -and $UseSsl } -Times 1
        Remove-Mock Send-MailMessage
    }

    # Validate the function passes a credential when SSL is not used. This
    # scenario ensures optional parameters are forwarded independently.
    It 'forwards credential without SSL when only credential specified' {
        Mock Send-MailMessage {}
        $cred = New-Object System.Management.Automation.PSCredential('u',(ConvertTo-SecureString 'p' -AsPlainText -Force))
        Send-Alert -Message 'm' -SmtpServer 's' -From 'f@e.com' -To 't@e.com' -Credential $cred
        Assert-MockCalled Send-MailMessage -ParameterFilter { $Credential -eq $cred -and -not $UseSsl } -Times 1
        Remove-Mock Send-MailMessage
    }

    # Validate the SSL switch works on its own. This protects against a bug
    # where the flag might be ignored when no credential is supplied.
    It 'forwards SSL without credential when only SSL specified' {
        Mock Send-MailMessage {}
        Send-Alert -Message 'm' -SmtpServer 's' -From 'f@e.com' -To 't@e.com' -UseSsl
        Assert-MockCalled Send-MailMessage -ParameterFilter { -not $Credential -and $UseSsl } -Times 1
        Remove-Mock Send-MailMessage
    }

    # When the mail cmdlet throws an exception the function should catch it and
    # emit a warning so monitoring continues. This test confirms that behavior.
    It 'emits warning when Send-MailMessage fails' {
        Mock Send-MailMessage { throw 'smtp failed' }
        $warnings = & {
            Send-Alert -Message 'm' -SmtpServer 's' -From 'f@e.com' -To 't@e.com'
        } 3>&1 4>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        $warnings.Message | Should -Match 'Failed to send alert'
        Remove-Mock Send-MailMessage
    }

    # Verify non-terminating SMTP errors still surface a warning. The mock
    # writes an error instead of throwing, which would ordinarily be ignored
    # without -ErrorAction Stop in Send-Alert.
    It 'emits warning when Send-MailMessage writes a non-terminating error' {
        Mock Send-MailMessage { Write-Error 'smtp failed' }
        $warnings = & {
            Send-Alert -Message 'm' -SmtpServer 's' -From 'f@e.com' -To 't@e.com'
        } 3>&1 4>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        $warnings.Message | Should -Match 'Failed to send alert'
        Remove-Mock Send-MailMessage
    }

    It 'validates mandatory parameters are not empty' {
        { Send-Alert -Message '' -SmtpServer 's' -From 'f@e.com' -To 't@e.com' } | Should -Throw
        { Send-Alert -Message 'm' -SmtpServer '' -From 'f@e.com' -To 't@e.com' } | Should -Throw
        { Send-Alert -Message 'm' -SmtpServer 's' -From '' -To 't@e.com' } | Should -Throw
        { Send-Alert -Message 'm' -SmtpServer 's' -From 'f@e.com' -To '' } | Should -Throw
    }
}

Describe 'Log directory creation' {
    It 'creates directory for performance log automatically' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        $file = Join-Path $dir 'perf.csv'
        try {
            Log-PerformanceData -PerformanceLog $file
            Test-Path $file | Should -BeTrue
        } finally {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates directory for disk usage log automatically' {
        Mock Get-PSDrive {
            [pscustomobject]@{ Name='C'; Free=1GB; Size=2GB; Provider='FileSystem'; Used=1GB }
        }
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        $file = Join-Path $dir 'disk.csv'
        try {
            Log-DiskUsage -DiskUsageLog $file
            Test-Path $file | Should -BeTrue
        } finally {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Mock Get-PSDrive
        }
    }

    It 'creates directory for event log automatically' {
        Mock Get-WinEvent { @() }
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        $file = Join-Path $dir 'events.csv'
        try {
            Log-EventData -EventLog $file
            Test-Path $file | Should -BeTrue
        } finally {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Mock Get-WinEvent
        }
    }

    It 'creates directory for network log automatically' {
        Mock Get-NetAdapterStatistics { [pscustomobject]@{ BytesReceived=0; BytesSent=0; PacketsReceived=0; PacketsSent=0 } }
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        $file = Join-Path $dir 'net.csv'
        try {
            Log-NetworkTraffic -Interface @{ InterfaceIndex = 1; Name='eth0' } -NetworkLog $file
            Test-Path $file | Should -BeTrue
        } finally {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Mock Get-NetAdapterStatistics
        }
    }
}

# These tests validate that the wrapper scripts respect iteration counts and
# avoid unnecessary sleeps after the final loop completes.
Describe 'Script iteration limits' {
    It 'system script stops after specified iterations' {
        Mock Log-PerformanceData {}
        Mock Log-DiskUsage {}
        Mock Log-EventData {}
        # Mock Start-Sleep so the test doesn't actually pause. Use the minimum
        # allowed SleepInterval (1) to satisfy parameter validation without
        # introducing delay.
        Mock Start-Sleep {}
        & "$PSScriptRoot/../system_monitoring.ps1" -Iterations 2 -SleepInterval 1
        Assert-MockCalled Log-PerformanceData -Times 2
        # Start-Sleep should only run once because the script exits after the
        # last iteration without pausing.
        Assert-MockCalled Start-Sleep -Times 1
        Remove-Mock Log-PerformanceData
        Remove-Mock Log-DiskUsage
        Remove-Mock Log-EventData
        Remove-Mock Start-Sleep
    }

    It 'network script stops after specified iterations' {
        Mock Get-NetworkInterfaces { @( @{ InterfaceIndex=1; Name='eth0' } ) }
        Mock Log-NetworkTraffic {}
        # Again mock the sleep call and pass the lowest valid interval to keep
        # the test fast while staying within the allowed range.
        Mock Start-Sleep {}
        & "$PSScriptRoot/../network_traffic.ps1" -Iterations 3 -SleepInterval 1 -InterfaceName eth0
        Assert-MockCalled Log-NetworkTraffic -Times 3
        # Sleep should be called once per iteration except the last
        Assert-MockCalled Start-Sleep -Times 2
        Remove-Mock Get-NetworkInterfaces
        Remove-Mock Log-NetworkTraffic
        Remove-Mock Start-Sleep
    }

    It 'filters interfaces by name' {
        $iface0 = @{ InterfaceIndex=1; Name='eth0' }
        $iface1 = @{ InterfaceIndex=2; Name='eth1' }
        Mock Get-NetworkInterfaces { @($iface0,$iface1) }
        Mock Log-NetworkTraffic {}
        Mock Start-Sleep {}
        & "$PSScriptRoot/../network_traffic.ps1" -Iterations 1 -SleepInterval 1 -InterfaceName eth1
        Assert-MockCalled Log-NetworkTraffic -ParameterFilter { $Interface.Name -eq 'eth1' } -Times 1
        # When only one iteration is requested the script should not sleep
        Assert-MockNotCalled Start-Sleep
        Remove-Mock Get-NetworkInterfaces
        Remove-Mock Log-NetworkTraffic
        Remove-Mock Start-Sleep
    }
}

Describe 'Module loading errors' {
    It 'system script throws when module import fails' {
        Mock Import-Module { throw 'missing' }
        { & "$PSScriptRoot/../system_monitoring.ps1" -Iterations 1 -ErrorAction Stop } | Should -Throw -ErrorMessage 'Failed to import MonitoringTools module:'
        Remove-Mock Import-Module
    }
    It 'network script throws when module import fails' {
        Mock Import-Module { throw 'missing' }
        { & "$PSScriptRoot/../network_traffic.ps1" -Iterations 1 -ErrorAction Stop } | Should -Throw -ErrorMessage 'Failed to import MonitoringTools module:'
        Remove-Mock Import-Module
    }
}
Describe 'Loop parameter validation' {
    # Ensure invalid SleepInterval values trigger a parameter error
    It 'system script rejects invalid sleep interval' {
        { & "$PSScriptRoot/../system_monitoring.ps1" -SleepInterval 0 } | Should -Throw
        { & "$PSScriptRoot/../system_monitoring.ps1" -SleepInterval -5 } | Should -Throw
    }
    # Ensure invalid Iterations counts throw an error before execution begins
    It 'system script rejects invalid iterations count' {
        { & "$PSScriptRoot/../system_monitoring.ps1" -Iterations 0 } | Should -Throw
        { & "$PSScriptRoot/../system_monitoring.ps1" -Iterations -2 } | Should -Throw
    }
    # Validate network script parameters with the same boundaries
    It 'network script rejects invalid sleep interval' {
        { & "$PSScriptRoot/../network_traffic.ps1" -SleepInterval 0 } | Should -Throw
        { & "$PSScriptRoot/../network_traffic.ps1" -SleepInterval -3 } | Should -Throw
    }
    It 'network script rejects invalid iterations count' {
        { & "$PSScriptRoot/../network_traffic.ps1" -Iterations 0 } | Should -Throw
        { & "$PSScriptRoot/../network_traffic.ps1" -Iterations -1 } | Should -Throw
    }
    # Validate that interface names cannot be empty strings so parameter
    # validation prevents useless iterations when the argument is blank.
    It 'network script rejects empty interface name' {
        { & "$PSScriptRoot/../network_traffic.ps1" -InterfaceName '' } | Should -Throw
    }
}
