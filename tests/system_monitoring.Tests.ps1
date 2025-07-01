# Pester tests for the monitoring scripts
# Each test verifies key behavior for typical scenarios.

Describe 'Log-PerformanceData' {
    It 'writes data to the performance CSV' {
        $temp = New-TemporaryFile
        try {
            $script:PerformanceLog = $temp.FullName
            Log-PerformanceData
            (Get-Content $temp.FullName).Length | Should -BeGreaterThan 1
        } finally { Remove-Item $temp -ErrorAction SilentlyContinue }
    }
}

Describe 'Log-EventData' {
    It 'captures only new events based on lastEventTime' {
        $temp = New-TemporaryFile
        try {
            $script:EventLog = $temp.FullName
            $script:lastEventTime = (Get-Date).AddMinutes(-1)
            Log-EventData
            $count1 = (Import-Csv $temp.FullName).Count
            Start-Sleep -Seconds 1
            Log-EventData
            $count2 = (Import-Csv $temp.FullName).Count
            $count2 | Should -Be $count1
        } finally { Remove-Item $temp -ErrorAction SilentlyContinue }
    }
}

Describe 'Log-NetworkTraffic' {
    It 'handles empty interface set without error' {
        $temp = New-TemporaryFile
        try {
            $script:NetworkLog = $temp.FullName
            Log-NetworkTraffic -Interface @{ InterfaceIndex = 0; Name = 'None' }
            Test-Path $temp.FullName | Should -BeTrue
        } finally { Remove-Item $temp -ErrorAction SilentlyContinue }
    }
}
