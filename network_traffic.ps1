# ============================================================================
# Network Traffic Logger
# ---------------------------------------------------------------------------
# Purpose:    Wrapper invoking module functions to log adapter statistics on a
#             repeating interval. The module is loaded from the repository so it
#             can be executed without installation. Parameter validation ensures
#             the sleep interval is always a positive integer.
# Usage:      .\network_traffic.ps1 [-NetworkLog <path>] [-SleepInterval <seconds>] [-Iterations <count>]
# ----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string]$NetworkLog = 'network_log.csv',
    [ValidateRange(1,[int]::MaxValue)]
    [int]$SleepInterval = 60,
    [ValidateRange(1,[int]::MaxValue)]
    # How many times to collect traffic data. Default runs effectively
    # forever by using the largest integer value.
    [int]$Iterations = [int]::MaxValue
)

Import-Module "$PSScriptRoot/MonitoringTools.psd1"

# Iterate up to the requested number of times. With the default value this
# behaves like the prior infinite while loop used for continuous logging.
for ($i = 0; $i -lt $Iterations; $i++) {
    # Retrieve the active interfaces on each iteration so that newly added
    # adapters are automatically included in monitoring.
    $interfaces = Get-NetworkInterfaces
    foreach ($iface in $interfaces) {
        # Record traffic counters for each adapter
        Log-NetworkTraffic -Interface $iface -NetworkLog $NetworkLog
    }
    # Wait before collecting the next sample
    Start-Sleep -Seconds $SleepInterval
}
