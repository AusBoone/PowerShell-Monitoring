# ============================================================================
# Setup Scheduled Tasks for Monitoring Scripts
# ----------------------------------------------------------------------------
# Purpose : Registers or removes Windows Scheduled Tasks that execute the
#           monitoring scripts on a schedule. Useful for automating data
#           collection without keeping a console session open. Supports
#           passing CPU and disk usage thresholds to the monitoring script so
#           alerts can be generated automatically. Parameter validation prevents
#           percentage values outside 0-100 from being accepted. Network
#           monitoring can be limited to specific adapters using -InterfaceName.
# Usage   : .\setup-scheduled-task.ps1 [-Frequency <Hourly|Daily>] [-Remove] \
#               [-PerformanceLog <path>] [-DiskUsageLog <path>] [-EventLog <path>] \
#               [-NetworkLog <path>] [-CpuThreshold <percent>] [-DiskUsageThreshold <percent>] \
#               [-InterfaceName <name>]
# ----------------------------------------------------------------------------
# Revision : Updated parameter checks to use PSBoundParameters.ContainsKey so
#             zero can be passed as a valid threshold value.
#             Added module import verification for clearer failures when the
#             MonitoringTools module is missing.
#             Introduced optional -InterfaceName parameter for network task
#             filtering.
#             Refactored argument quoting so file paths are safely escaped
#             using a helper function. This prevents issues when directories
#             contain spaces or embedded quotes.
[CmdletBinding()]
param(
    [ValidateSet('Hourly','Daily')]
    [string]$Frequency = 'Hourly',
    [switch]$Remove,
    [string]$PerformanceLog = 'performance_log.csv',
    [string]$DiskUsageLog = 'disk_usage_log.csv',
    [string]$EventLog = 'event_log.csv',
    [string]$NetworkLog = 'network_log.csv',
    [ValidateNotNullOrEmpty()]
    [string[]]$InterfaceName,
    [ValidateRange(0,100)]
    [int]$CpuThreshold,
    [ValidateRange(0,100)]
    [int]$DiskUsageThreshold
)

# Ensure required cmdlets exist. Register-ScheduledTask is only present on
# Windows, so bail out early if it cannot be found.
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'Scheduled tasks are only supported on Windows platforms.'
}

try {
    # Load the module so task arguments can be validated before scheduling. A
    # missing module would otherwise cause runtime failures when the tasks run.
    Import-Module "$PSScriptRoot/MonitoringTools.psd1" -ErrorAction Stop
} catch {
    throw "Failed to import MonitoringTools module: $_"
}

$taskPath = '\MonitoringTools'       # Folder in Task Scheduler for grouping tasks
$sysTask = 'SystemMonitoring'         # Name of the system metrics task
$netTask = 'NetworkTraffic'           # Name of the network metrics task
$sysScript = Join-Path $PSScriptRoot 'system_monitoring.ps1'
$netScript = Join-Path $PSScriptRoot 'network_traffic.ps1'

function Escape-TaskPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    <#
        .SYNOPSIS
        Escapes a file system path for use in a scheduled task argument string.

        .DESCRIPTION
        Any embedded quotation marks are doubled so the resulting string can be
        surrounded with quotes safely. The final value is wrapped in double
        quotes so paths containing spaces are handled correctly when passed to
        powershell.exe.

        .PARAMETER Path
        The file system path to escape.

        .OUTPUTS
        System.String - the escaped path surrounded with quotes.
    #>

    # Surround the path in quotes after escaping any existing quote characters.
    return '"' + ($Path -replace '"', '``"') + '"'
}

function New-TaskTrigger {
    param([string]$Freq)

    # Create a trigger representing the selected schedule frequency.
    switch ($Freq) {
        'Hourly' {
            # Run once at script invocation then repeat every hour indefinitely.
            return New-ScheduledTaskTrigger -Once -At (Get-Date) \
                -RepetitionInterval (New-TimeSpan -Hours 1) \
                -RepetitionDuration ([TimeSpan]::MaxValue)
        }
        default {
            # Daily trigger executes at midnight each day.
            return New-ScheduledTaskTrigger -Daily -At 00:00
        }
    }
}

if ($Remove.IsPresent) {
    # Remove any existing tasks quietly. Errors are ignored so rerunning with
    # -Remove is idempotent even if tasks do not exist.
    Unregister-ScheduledTask -TaskName $sysTask -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $netTask -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
    return
}

$trigger = New-TaskTrigger -Freq $Frequency

$sysArgs = "-File $(Escape-TaskPath $sysScript) -PerformanceLog $(Escape-TaskPath $PerformanceLog) -DiskUsageLog $(Escape-TaskPath $DiskUsageLog) -EventLog $(Escape-TaskPath $EventLog)"
# PSBoundParameters.ContainsKey allows zero to be treated as a valid value
# rather than an indication that the parameter was omitted.
if ($PSBoundParameters.ContainsKey('CpuThreshold')) {
    $sysArgs += " -CpuThreshold $CpuThreshold"
}
if ($PSBoundParameters.ContainsKey('DiskUsageThreshold')) {
    $sysArgs += " -DiskUsageThreshold $DiskUsageThreshold"
}
$netArgs = "-File $(Escape-TaskPath $netScript) -NetworkLog $(Escape-TaskPath $NetworkLog)"
if ($PSBoundParameters.ContainsKey('InterfaceName')) {
    # Pass a comma separated list so the network script can interpret multiple
    # adapter names or indexes correctly.
    $netArgs += " -InterfaceName $($InterfaceName -join ',')"
}

# Each action starts PowerShell with the script path and log file arguments.
$sysAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $sysArgs
$netAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $netArgs

try {
    # Register the tasks with the configured trigger and actions. -Force ensures
    # any existing definition is replaced.
    Register-ScheduledTask -TaskName $sysTask -TaskPath $taskPath -Action $sysAction -Trigger $trigger -Force -Description 'System monitoring task'
    Register-ScheduledTask -TaskName $netTask -TaskPath $taskPath -Action $netAction -Trigger $trigger -Force -Description 'Network traffic logging task'
} catch {
    throw "Failed to register scheduled tasks: $_"
}

