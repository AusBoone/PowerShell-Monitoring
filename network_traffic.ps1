# ============================================================================
# Network Traffic Logger
# ---------------------------------------------------------------------------
# Purpose:    Monitors all active network adapters and logs traffic statistics
#             to a CSV file for later analysis.
# Usage:      .\network_traffic.ps1 [-NetworkLog <path>] [-SleepInterval <seconds>]
# Assumptions: Requires PowerShell 3.0+ and administrative privileges to query
#              adapter statistics. Designed for Windows environments.
# Design:     The script runs indefinitely, capturing interface statistics at
#             the configured interval until interrupted with Ctrl+C.
# ----------------------------------------------------------------------------

# Configuration parameters
param (
    $NetworkLog = "network_log.csv",
    $SleepInterval = 60
)

# Function to get the network interfaces
function Get-NetworkInterfaces {
    <#
        .SYNOPSIS
            Returns all network adapters that are currently active.

        .OUTPUTS
            [Microsoft.Management.Infrastructure.CimInstance[]] of network adapters.

        .NOTES
            Any failure to query adapters is surfaced as a warning so the main
            monitoring loop can continue running.
    #>
    try {
        # Get all network interfaces
        $interfaces = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

        # Return the network interfaces
        return $interfaces
    } catch {
        Write-Warning "Error retrieving network interfaces: $_"
    }
}

# Function to log network traffic data
function Log-NetworkTraffic {
    param (
        [Parameter(Mandatory)]
        $Interface
    )
    <#
        .SYNOPSIS
            Logs byte and packet counts for a specific network interface.

        .PARAMETER Interface
            A network adapter object returned from Get-NetworkInterfaces.

        .OUTPUTS
            Appends a record to $NetworkLog containing traffic statistics.
    #>
    
    try {
        # Query statistics for the specific adapter. If the adapter disappears
        # (e.g., disabled or unplugged) an error will be thrown and caught
        # so that monitoring continues for remaining interfaces.
        $networkStats = Get-NetAdapterStatistics -InterfaceIndex $Interface.InterfaceIndex

        # Log the data to the network log file
        $output = [ordered]@{
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            InterfaceName = $Interface.Name
            InterfaceIndex = $Interface.InterfaceIndex
            BytesReceived = $networkStats.BytesReceived
            BytesSent = $networkStats.BytesSent
            PacketsReceived = $networkStats.PacketsReceived
            PacketsSent = $networkStats.PacketsSent
        }
        $outputObject = New-Object -TypeName PSObject -Property $output
        # Append the traffic statistics to the CSV log for later analysis
        $outputObject | Export-Csv -Path $NetworkLog -Append -NoTypeInformation
    } catch {
        Write-Warning "Error logging network traffic: $_"
    }
}

# Main monitoring loop runs indefinitely until interrupted by the user.
while ($true) {
    # Retrieve currently active adapters. If none are present the foreach loop
    # below simply skips logging for this iteration.
    $interfaces = Get-NetworkInterfaces

    # Log network traffic for each interface
    foreach ($interface in $interfaces) {
        Log-NetworkTraffic -Interface $interface
    }

    # Pause before collecting the next set of statistics to reduce overhead
    Start-Sleep -Seconds $SleepInterval
}
