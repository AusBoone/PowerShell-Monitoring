# ============================================================================
# Network Traffic Logger
# ---------------------------------------------------------------------------
# Purpose:    Wrapper invoking module functions to log adapter statistics
#             on a repeating interval. The module is loaded from the
#             repository so the script can be run without installation.
# Usage:      .\network_traffic.ps1 [-NetworkLog <path>] [-SleepInterval <seconds>]
# ----------------------------------------------------------------------------

param(
    [string]$NetworkLog = 'network_log.csv',
    [int]$SleepInterval = 60
)

Import-Module "$PSScriptRoot/MonitoringTools.psd1"

while ($true) {
    # Retrieve the active interfaces on each iteration
    $interfaces = Get-NetworkInterfaces
    foreach ($iface in $interfaces) {
        # Record traffic counters for each adapter
        Log-NetworkTraffic -Interface $iface -NetworkLog $NetworkLog
    }
    # Wait before collecting the next sample
    Start-Sleep -Seconds $SleepInterval
}
