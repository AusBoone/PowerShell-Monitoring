# ============================================================================
# System Monitoring Script
# ---------------------------------------------------------------------------
# Purpose:    Wrapper to run monitoring functions from the MonitoringTools
#             module on a schedule. Each invocation of the script imports the
#             module from the current directory so it can be executed without
#             installation.
# Usage:      .\system_monitoring.ps1 [-PerformanceLog <path>] [-DiskUsageLog <path>]
#                                     [-EventLog <path>] [-SleepInterval <seconds>]
# Design:     Runs continuously until terminated, logging metrics on every
#             iteration using the interval provided.
# ----------------------------------------------------------------------------

param(
    [string]$PerformanceLog = 'performance_log.csv',
    [string]$DiskUsageLog = 'disk_usage_log.csv',
    [string]$EventLog = 'event_log.csv',
    [int]$SleepInterval = 900
)

Import-Module "$PSScriptRoot/MonitoringTools.psd1"

while ($true) {
    # Collect various system metrics and append them to their logs
    Log-PerformanceData -PerformanceLog $PerformanceLog
    Log-DiskUsage -DiskUsageLog $DiskUsageLog
    Log-EventData -EventLog $EventLog
    # Pause before the next collection cycle
    Start-Sleep -Seconds $SleepInterval
}
