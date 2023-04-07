# Retrieves all active network interfaces and logs network traffic for each interface

# Configuration parameters
param (
    $NetworkLog = "network_log.csv",
    $SleepInterval = 60
)

# Function to get the network interfaces
function Get-NetworkInterfaces {
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
        $Interface
    )
    
    try {
        # Get network interface statistics
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
        $outputObject | Export-Csv -Path $NetworkLog -Append -NoTypeInformation
    } catch {
        Write-Warning "Error logging network traffic: $_"
    }
}

# Schedule this script to run periodically using loop with a sleep timer
while ($true) {
    # Get the network interfaces
    $interfaces = Get-NetworkInterfaces

    # Log network traffic for each interface
    foreach ($interface in $interfaces) {
        Log-NetworkTraffic -Interface $interface
    }

    # Wait for the specified interval (in seconds) before running again
    Start-Sleep -Seconds $SleepInterval
}
