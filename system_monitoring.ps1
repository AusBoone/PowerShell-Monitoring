# ============================================================================
# System Monitoring Script
# ---------------------------------------------------------------------------
# Purpose:    Wrapper to run monitoring functions from the MonitoringTools
#             module on a schedule. Each invocation of the script imports the
#             module from the current directory so it can be executed without
#             installation.
# Usage:      .\system_monitoring.ps1 [-PerformanceLog <path>] [-DiskUsageLog <path>]
#                                     [-EventLog <path>] [-SleepInterval <seconds>]
#                                     [-CpuThreshold <percent>] [-DiskUsageThreshold <percent>]
#                                     [-Iterations <count>]
# Design:     Runs continuously or for a limited number of iterations when
#             -Iterations is specified. Logs metrics each cycle using the
#             interval provided. Optional threshold
#             parameters generate alerts when usage exceeds limits. Parameters
#             include validation to catch values outside acceptable ranges
#             before the monitoring loop begins.
#             Suitable for use with
#             scheduled tasks or manual execution.
# ----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string]$PerformanceLog = 'performance_log.csv',
    [string]$DiskUsageLog = 'disk_usage_log.csv',
    [string]$EventLog = 'event_log.csv',
    [ValidateRange(1,[int]::MaxValue)]
    [int]$SleepInterval = 900,
    [ValidateRange(0,100)]
    [int]$CpuThreshold,
    [ValidateRange(0,100)]
    [int]$DiskUsageThreshold,
    [ValidateRange(1,[int]::MaxValue)]
    # Number of monitoring cycles to run. Using [int]::MaxValue effectively
    # means run indefinitely when a limit is not specified.
    [int]$Iterations = [int]::MaxValue
)

Import-Module "$PSScriptRoot/MonitoringTools.psd1"

# Repeat the monitoring cycle the requested number of times. Leaving
# -Iterations at the default effectively continues indefinitely.
for ($i = 0; $i -lt $Iterations; $i++) {
    # Collect various system metrics and append them to their logs. This keeps
    # historical records that other tools can ingest.
    # Build the parameter sets dynamically so optional threshold values are only
    # supplied when explicitly specified by the caller. Passing `$null` directly to
    # the functions would otherwise be interpreted as `0` due to the strongly typed
    # integer parameters, resulting in constant alerts.
    $perfParams = @{ PerformanceLog = $PerformanceLog }
    if ($PSBoundParameters.ContainsKey('CpuThreshold')) {
        $perfParams.CpuThreshold = $CpuThreshold
    }
    Log-PerformanceData @perfParams

    $diskParams = @{ DiskUsageLog = $DiskUsageLog }
    if ($PSBoundParameters.ContainsKey('DiskUsageThreshold')) {
        $diskParams.UsageThreshold = $DiskUsageThreshold
    }
    Log-DiskUsage @diskParams

    Log-EventData -EventLog $EventLog
    # Pause before the next collection cycle so the log interval is predictable
    Start-Sleep -Seconds $SleepInterval
}
