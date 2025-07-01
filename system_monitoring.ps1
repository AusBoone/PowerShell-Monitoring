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
# Design:     Runs continuously until terminated, logging metrics on every
#             iteration using the interval provided. Optional threshold
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
    [int]$DiskUsageThreshold
)

Import-Module "$PSScriptRoot/MonitoringTools.psd1"

while ($true) {
    # Collect various system metrics and append them to their logs. This keeps
    # historical records that other tools can ingest.
    Log-PerformanceData -PerformanceLog $PerformanceLog -CpuThreshold $CpuThreshold
    Log-DiskUsage -DiskUsageLog $DiskUsageLog -UsageThreshold $DiskUsageThreshold
    Log-EventData -EventLog $EventLog
    # Pause before the next collection cycle so the log interval is predictable
    Start-Sleep -Seconds $SleepInterval
}
