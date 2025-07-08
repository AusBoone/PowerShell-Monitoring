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
        & "$PSScriptRoot/../network_traffic.ps1" -Iterations 3 -SleepInterval 1
        Assert-MockCalled Log-NetworkTraffic -Times 3
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
