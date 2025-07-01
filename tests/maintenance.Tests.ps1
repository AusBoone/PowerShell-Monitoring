# Tests covering helper scripts for module maintenance and automation.
# These tests mock Windows-specific cmdlets so they can run on any platform.
# Each scenario verifies that the helper scripts behave correctly without
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
        & "$PSScriptRoot/../publish_module.ps1" -GalleryUri 'https://example.com' -ApiKey 'key' -Version '1.2.3' -Confirm:$false
        Assert-MockCalled Publish-Module -Times 1
    }
}

Describe 'setup-scheduled-task.ps1' {
    BeforeEach {
        Mock Get-Command { [pscustomobject]@{ Name='Register-ScheduledTask' } }
        Mock Register-ScheduledTask {}
        Mock Unregister-ScheduledTask {}
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

    It 'passes threshold parameters to system script' {
        Mock Register-ScheduledTask {
            param($TaskName, $TaskPath, $Action, $Trigger, $Force, $Description)
            $script:argsCaptured = $Action.Argument
        }
        & "$PSScriptRoot/../setup-scheduled-task.ps1" -CpuThreshold 90 -DiskUsageThreshold 80
        $script:argsCaptured | Should -Match '-CpuThreshold 90'
        $script:argsCaptured | Should -Match '-DiskUsageThreshold 80'
    }

    It 'throws when threshold values are out of range' {
        { & "$PSScriptRoot/../setup-scheduled-task.ps1" -CpuThreshold 200 } | Should -Throw
        { & "$PSScriptRoot/../setup-scheduled-task.ps1" -DiskUsageThreshold -5 } | Should -Throw
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

