# Pester tests for the maintenance helper scripts.
#
# The helper scripts manage module publishing and creation of Windows
# scheduled tasks. These tests run cross-platform by mocking the
# Windows-specific cmdlets they depend on. Each scenario validates that
# expected commands are invoked with the correct parameters without
# modifying the real environment.

BeforeAll {
    # Ensure module is available for scripts that reference it
    Import-Module "$PSScriptRoot/../MonitoringTools.psd1"
}

Describe 'publish_module.ps1' {
    It 'requires mandatory parameters' {
        { & "$PSScriptRoot/../publish_module.ps1" } | Should -Throw
    }

    It 'updates and publishes when parameters provided' {
        Mock Publish-Module {}
        Mock Update-ModuleManifest {}
        Mock Register-PSRepository {}
        Mock Unregister-PSRepository {}
        & "$PSScriptRoot/../publish_module.ps1" -GalleryUri 'https://example.com' -ApiKey 'key' -Version '1.2.3' -Confirm:$false
        Assert-MockCalled Publish-Module -Times 1
        Assert-MockCalled Unregister-PSRepository -Times 1
    }
}

Describe 'setup-scheduled-task.ps1' {
    BeforeEach {
        Mock Get-Command { [pscustomobject]@{ Name='Register-ScheduledTask' } }
        Mock Register-ScheduledTask {}
        Mock Unregister-ScheduledTask {}
        # Default trigger and action mocks prevent platform-specific calls
        # from executing during tests. Individual examples override these
        # mocks when inspecting parameters.
        Mock New-ScheduledTaskTrigger { 'trigger' }
        Mock New-ScheduledTaskAction { 'action' }
    }

    It 'removes tasks when -Remove is specified' {
        & "$PSScriptRoot/../setup-scheduled-task.ps1" -Remove
        Assert-MockCalled Unregister-ScheduledTask -Times 2
        Assert-MockNotCalled Register-ScheduledTask
    }

    It 'throws on invalid frequency' {
        { & "$PSScriptRoot/../setup-scheduled-task.ps1" -Frequency Weekly } | Should -Throw
    }

    # Verify the helper function creates the expected hourly trigger configuration
    It 'returns hourly trigger with one hour interval' {
        # Load the function by executing the script with -Remove so no tasks
        # are registered. The function remains defined for direct invocation.
        & "$PSScriptRoot/../setup-scheduled-task.ps1" -Remove

        # Capture parameters passed to New-ScheduledTaskTrigger
        Mock New-ScheduledTaskTrigger {
            param($Once,$At,$RepetitionInterval,$RepetitionDuration)
            $script:hourlyParams = $PSBoundParameters
            return 'hourlyTrigger'
        }

        $result = New-TaskTrigger -Freq 'Hourly'

        $result | Should -Be 'hourlyTrigger'
        $script:hourlyParams.Once | Should -BeTrue
        $script:hourlyParams.RepetitionInterval.Hours | Should -Be 1
        $script:hourlyParams.RepetitionDuration | Should -Be [TimeSpan]::MaxValue
    }

    # Verify the helper function creates the expected daily trigger configuration
    It 'returns daily trigger at midnight' {
        & "$PSScriptRoot/../setup-scheduled-task.ps1" -Remove

        Mock New-ScheduledTaskTrigger {
            param($Daily,$At)
            $script:dailyParams = $PSBoundParameters
            return 'dailyTrigger'
        }

        $result = New-TaskTrigger -Freq 'Daily'

        $result | Should -Be 'dailyTrigger'
        $script:dailyParams.Daily | Should -BeTrue
        $script:dailyParams.At.ToString('HH:mm') | Should -Be '00:00'
    }

    It 'passes threshold parameters to system script' {
        Mock Register-ScheduledTask {
            param($TaskName, $TaskPath, $Action, $Trigger, $Force, $Description)
            $script:argsCaptured = $Action.Argument
        }
        & "$PSScriptRoot/../setup-scheduled-task.ps1" -CpuThreshold 90 -DiskUsageThreshold 80
        $script:argsCaptured | Should -Match '-CpuThreshold 90'
        $script:argsCaptured | Should -Match '-DiskUsageThreshold 80'
    }

    It 'forwards zero values for thresholds' {
        Mock Register-ScheduledTask {
            param($TaskName, $TaskPath, $Action, $Trigger, $Force, $Description)
            $script:zeroArgs = $Action.Argument
        }
        & "$PSScriptRoot/../setup-scheduled-task.ps1" -CpuThreshold 0 -DiskUsageThreshold 0
        $script:zeroArgs | Should -Match '-CpuThreshold 0'
        $script:zeroArgs | Should -Match '-DiskUsageThreshold 0'
    }

    It 'forwards interface names to network script' {
        Mock Register-ScheduledTask {
            param($TaskName, $TaskPath, $Action, $Trigger, $Force, $Description)
            if ($TaskName -eq 'NetworkTraffic') { $script:ifaceArgs = $Action.Argument }
        }
        & "$PSScriptRoot/../setup-scheduled-task.ps1" -InterfaceName WiFi
        $script:ifaceArgs | Should -Match '-InterfaceName\s+"WiFi"'
    }

    # Ensure Register-ScheduledTask receives the proper script paths and arguments
    It 'registers tasks with correct script details' {
        Mock Register-ScheduledTask {
            param($TaskName, $TaskPath, $Action, $Trigger, $Force, $Description)
            if ($TaskName -eq 'SystemMonitoring') { $script:sysArgs = $Action.Argument }
            if ($TaskName -eq 'NetworkTraffic') { $script:netArgs = $Action.Argument }
        }

        & "$PSScriptRoot/../setup-scheduled-task.ps1"

        $repoRoot = Split-Path $PSScriptRoot -Parent
        $expectedSys = Join-Path $repoRoot 'system_monitoring.ps1'
        $expectedNet = Join-Path $repoRoot 'network_traffic.ps1'

        $script:sysArgs | Should -Match [regex]::Escape($expectedSys)
        $script:netArgs | Should -Match [regex]::Escape($expectedNet)
        $script:sysArgs | Should -Match '-PerformanceLog'
        $script:netArgs | Should -Match '-NetworkLog'
    }

    It 'escapes file paths containing spaces' {
        Mock Register-ScheduledTask {
            param($TaskName, $TaskPath, $Action, $Trigger, $Force, $Description)
            if ($TaskName -eq 'SystemMonitoring') { $script:sysArgsSpace = $Action.Argument }
            if ($TaskName -eq 'NetworkTraffic') { $script:netArgsSpace = $Action.Argument }
        }

        $perfPath = 'C:\Temp Logs\perf.csv'
        $diskPath = 'C:\Temp Logs\disk.csv'
        $eventPath = 'C:\Temp Logs\event.csv'
        $netPath  = 'C:\Temp Logs\net.csv'
        $ifaceNames = 'WiFi Adapter', 'Ethernet "Corp"'

        & "$PSScriptRoot/../setup-scheduled-task.ps1" -PerformanceLog $perfPath -DiskUsageLog $diskPath -EventLog $eventPath -NetworkLog $netPath -InterfaceName $ifaceNames

        $expectedPerf   = '"' + ($perfPath -replace '"','``"') + '"'
        $expectedDisk   = '"' + ($diskPath -replace '"','``"') + '"'
        $expectedEvent  = '"' + ($eventPath -replace '"','``"') + '"'
        $expectedNet    = '"' + ($netPath  -replace '"','``"') + '"'
        $expectedIfaces = $ifaceNames | ForEach-Object { '"' + ($_ -replace '"','``"') + '"' }

        $script:sysArgsSpace | Should -Match ('-PerformanceLog\s+' + [regex]::Escape($expectedPerf))
        $script:sysArgsSpace | Should -Match ('-DiskUsageLog\s+' + [regex]::Escape($expectedDisk))
        $script:sysArgsSpace | Should -Match ('-EventLog\s+' + [regex]::Escape($expectedEvent))
        $script:netArgsSpace | Should -Match ('-NetworkLog\s+' + [regex]::Escape($expectedNet))
        $script:netArgsSpace | Should -Match ('-InterfaceName\s+' + [regex]::Escape(($expectedIfaces -join ',')))
    }

    It 'throws when threshold values are out of range' {
        { & "$PSScriptRoot/../setup-scheduled-task.ps1" -CpuThreshold 200 } | Should -Throw
        { & "$PSScriptRoot/../setup-scheduled-task.ps1" -DiskUsageThreshold -5 } | Should -Throw
    }

    It 'throws when module import fails' {
        Mock Import-Module { throw 'missing' }
        { & "$PSScriptRoot/../setup-scheduled-task.ps1" } | Should -Throw -ErrorMessage 'Failed to import MonitoringTools module:'
        Remove-Mock Import-Module
    }
}

Describe 'system_monitoring.ps1 parameter validation' {
    It 'throws when CpuThreshold is invalid' {
        { & "$PSScriptRoot/../system_monitoring.ps1" -CpuThreshold 150 } | Should -Throw
    }
    It 'throws when DiskUsageThreshold is invalid' {
        { & "$PSScriptRoot/../system_monitoring.ps1" -DiskUsageThreshold 150 } | Should -Throw
    }
}

