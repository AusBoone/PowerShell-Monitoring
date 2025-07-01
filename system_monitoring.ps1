# ============================================================================
# System Monitoring Script
# ---------------------------------------------------------------------------
# Purpose:    Collects performance counters, disk usage metrics, and Windows
#             event log entries and stores them in CSV files for later review.
# Usage:      .\system_monitoring.ps1 [-PerformanceLog <path>] [-DiskUsageLog <path>]
#                                     [-EventLog <path>] [-SleepInterval <seconds>]
# Assumptions: Tested on Windows with PowerShell 3.0+ and requires privileges to
#              read performance counters and event logs.
# Design:     This script runs continuously in a loop. Each iteration records
#              data and then sleeps for the configured interval. Use Ctrl+C to
#              exit gracefully.
# ----------------------------------------------------------------------------

# Configuration parameters
param (
    $PerformanceLog = "performance_log.csv",
    $DiskUsageLog = "disk_usage_log.csv",
    $EventLog = "event_log.csv",
    $SleepInterval = 900
)

# Function to log performance counters
function Log-PerformanceData {
    <#
        .SYNOPSIS
            Collects a predefined set of system performance counters.

        .OUTPUTS
            Appends a CSV record containing counter values and a timestamp to
            $PerformanceLog.

        .NOTES
            Any failure while querying counters is caught so monitoring can
            continue in the next loop iteration.
    #>
    try {
        # Define the performance counters to monitor. These counters were
        # chosen to provide a general overview of CPU, memory and disk activity
        # without requiring additional modules.
        $counters = @(
            "\Processor(_Total)\% Processor Time",
            "\Memory\Available MBytes",
            "\PhysicalDisk(_Total)\Disk Reads/sec",
            "\PhysicalDisk(_Total)\Disk Writes/sec"
        )

        # Get the counter data
        $counterData = Get-Counter -Counter $counters

        # Create an ordered hashtable to maintain column order when exported.
        # The first property is the timestamp of collection.
        $output = [ordered]@{Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")}

        # Process the counter data
        foreach ($counter in $counterData.CounterSamples) {
            $output[$counter.CounterName] = $counter.CookedValue
        }

        # Convert to a custom object and append to the performance log CSV.
        $outputObject = New-Object -TypeName PSObject -Property $output
        $outputObject | Export-Csv -Path $PerformanceLog -Append -NoTypeInformation
    } catch {
        Write-Warning "Error logging performance data: $_"
    }
}

# Function to log disk usage
function Log-DiskUsage {
    <#
        .SYNOPSIS
            Records disk utilization for each mounted drive.

        .OUTPUTS
            Appends timestamped usage percentages to $DiskUsageLog.

        .NOTES
            Uses Get-PSDrive so it works with all filesystem drives, including
            network shares. Any failures are logged as warnings.
    #>
    try {
        # Get the disk drives
        $drives = Get-PSDrive -PSProvider FileSystem

        # Process each drive
        foreach ($drive in $drives) {
            # Calculate how much of the drive is used. The Built-in properties
            # report total, used and free space so we derive a usage percentage.
            $usedSpace = $drive.Used - ($drive.Free)
            $usedPercentage = ($usedSpace / $drive.Size) * 100

            # Log the data to the disk usage log file
            $output = [ordered]@{
                Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                Drive = $drive.Name
                UsedPercentage = $usedPercentage
            }
            $outputObject = New-Object -TypeName PSObject -Property $output
            # Append this drive's usage statistics to the disk usage log
            $outputObject | Export-Csv -Path $DiskUsageLog -Append -NoTypeInformation
        }
    } catch {
        Write-Warning "Error logging disk usage: $_"
    }
}

# Tracks the most recent event processed to avoid re-reading old events.
# The variable is updated in Log-EventData using the script scope so that
# subsequent calls continue from the last processed time across iterations.
$script:lastEventTime = (Get-Date).AddHours(-24)

# Function to log event data
function Log-EventData {
    <#
        .SYNOPSIS
            Queries selected Windows event logs for recent error-level entries.

        .OUTPUTS
            Appends each new event to $EventLog as a CSV row including the
            timestamp, log name, event ID, level and message.

        .NOTES
            The function maintains a global $script:lastEventTime variable so
            events are not duplicated across iterations.
    #>
    try {
        # Define the logs to monitor
        $logs = @("System", "Application", "Security")

        # Define the event level (1 = Critical, 2 = Error, 3 = Warning)
        $eventLevel = 2

        # Define the start time for the event query (since the last event time)
        # Use the last processed event time as the starting point so only new
        # events are retrieved on each iteration.
        $startTime = $script:lastEventTime

        # Iterate over the configured logs and export any new events found.
        foreach ($log in $logs) {
            # Query recent events from the specified log. Using a hash table
            # filter is efficient and avoids retrieving unnecessary entries.
            $events = Get-WinEvent -FilterHashTable @{LogName = $log; Level = $eventLevel; StartTime = $startTime}

            # Log each event to the event log file
            foreach ($event in $events) {
                $output = [ordered]@{
                    Timestamp = $event.TimeCreated
                    LogName = $log
                    EventID = $event.Id
                    Level = $event.LevelDisplayName
                    Message = $event.Message
                }
                # Convert the hashtable into a PSCustomObject for consistent output
                $outputObject = New-Object -TypeName PSObject -Property $output
                $outputObject | Export-Csv -Path $EventLog -Append -NoTypeInformation
            }
        }

        # Update the global last event timestamp so the next iteration only
        # queries events newer than those already processed.
        if ($events) {
            $script:lastEventTime = ($events | Sort-Object TimeCreated -Descending)[0].TimeCreated
        }
    } catch {
        Write-Warning "Error logging event data: $_"
    }
}

# Function to send alerts
function Send-Alert($message) {
    # Placeholder for alerting logic. Implement as needed to integrate with
    # email, messaging platforms or logging systems.
    # This function can be called from within the monitoring functions when a
    # threshold is exceeded.
}

# Main loop: gather data then sleep until the next iteration. Exit with Ctrl+C.
while ($true) {
    # Call functions to log performance data, disk usage, and event data
    Log-PerformanceData
    Log-DiskUsage
    Log-EventData

    # Pause before the next collection cycle to avoid excessive resource usage
    Start-Sleep -Seconds $SleepInterval
}
