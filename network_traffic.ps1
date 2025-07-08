# ============================================================================
# Network Traffic Logger
# ---------------------------------------------------------------------------
# Purpose:    Wrapper invoking module functions to log adapter statistics on a
#             repeating interval. The module is loaded from the repository so it
#             can be executed without installation. Parameter validation ensures
#             the sleep interval is always a positive integer. Adapters can be
#             targeted using -InterfaceName to reduce noise when only certain
#             interfaces matter.
# Usage:      .\network_traffic.ps1 [-NetworkLog <path>] [-SleepInterval <seconds>] [-Iterations <count>] [-InterfaceName <name>]
# ----------------------------------------------------------------------------
# Revision:   Added optional interface filtering so traffic can be monitored for
#             specific adapters by name or index. Includes module import
#             validation to surface clear errors when dependencies cannot be
#             loaded.
#             Removed sleep after the final iteration so the script exits
#             immediately when iteration limits are reached.

[CmdletBinding()]
param(
    [string]$NetworkLog = 'network_log.csv',
    [ValidateRange(1,[int]::MaxValue)]
    [int]$SleepInterval = 60,
    [ValidateRange(1,[int]::MaxValue)]
    # How many times to collect traffic data. Default runs effectively
    # forever by using the largest integer value.
    [int]$Iterations = [int]::MaxValue,
    # Optional list of adapter names or indexes to monitor. When omitted all
    # active adapters are logged. Names and indexes are compared as strings so
    # either `Ethernet` or `1` work interchangeably.
    [string[]]$InterfaceName
)

try {
    # Load the MonitoringTools module from this repository. Using -ErrorAction
    # Stop causes a terminating error if the module cannot be found, which we
    # trap to provide a user friendly message.
    Import-Module "$PSScriptRoot/MonitoringTools.psd1" -ErrorAction Stop
} catch {
    throw "Failed to import MonitoringTools module: $_"
}

# Iterate up to the requested number of times. With the default value this
# behaves like the prior infinite while loop used for continuous logging.
for ($i = 0; $i -lt $Iterations; $i++) {
    # Retrieve the active interfaces on each iteration so that newly added
    # adapters are automatically included in monitoring. When -InterfaceName was
    # specified limit results to the requested adapters by comparing both the
    # friendly name and interface index string.
    $interfaces = Get-NetworkInterfaces
    if ($InterfaceName) {
        $interfaces = $interfaces | Where-Object {
            $InterfaceName -contains $_.Name -or
            $InterfaceName -contains $_.InterfaceIndex.ToString()
        }
    }
    foreach ($iface in $interfaces) {
        # Record traffic counters for each adapter
        Log-NetworkTraffic -Interface $iface -NetworkLog $NetworkLog
    }
    # Sleep only when another iteration will run to avoid delaying script exit
    if ($i + 1 -lt $Iterations) {
        Start-Sleep -Seconds $SleepInterval
    }
}
