# Pester tests for MonitoringTools module
# Each test validates core functionality with mocks so the module can run
# without touching the real system. The tests focus on edge cases and
# ensure that logging continues even when optional properties are missing.

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
