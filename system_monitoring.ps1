# Configuration parameters
param (
    $PerformanceLog = "performance_log.csv",
    $DiskUsageLog = "disk_usage_log.csv",
    $EventLog = "event_log.csv",
    $SleepInterval = 900
)

# Function to log performance counters
function Log-PerformanceData {
    try {
        # Define the performance counters to monitor
        $counters = @(
            "\Processor(_Total)\% Processor Time",
            "\Memory\Available MBytes",
            "\PhysicalDisk(_Total)\Disk Reads/sec",
            "\PhysicalDisk(_Total)\Disk Writes/sec"
        )

        # Get the counter data
        $counterData = Get-Counter -Counter $counters

        # Create an output object and set the timestamp
        $output = [ordered]@{Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")}

        # Process the counter data
        foreach ($counter in $counterData.CounterSamples) {
            $output[$counter.CounterName] = $counter.CookedValue
        }

        # Log the data to the performance log file
        $outputObject = New-Object -TypeName PSObject -Property $output
        $outputObject | Export-Csv -Path $PerformanceLog -Append -NoTypeInformation
    } catch {
        Write-Warning "Error logging performance data: $_"
    }
}

# Function to log disk usage
function Log-DiskUsage {
    try {
        # Get the disk drives
        $drives = Get-PSDrive -PSProvider FileSystem

        # Process each drive
        foreach ($drive in $drives) {
            # Calculate the used space and percentage
            $usedSpace = $drive.Used - ($drive.Free)
            $usedPercentage = ($usedSpace / $drive.Size) * 100

            # Log the data to the disk usage log file
            $output = [ordered]@{
                Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                Drive = $drive.Name
                UsedPercentage = $usedPercentage
            }
            $outputObject = New-Object -TypeName PSObject -Property $output
            $outputObject | Export-Csv -Path $DiskUsageLog -Append -NoTypeInformation
        }
    } catch {
        Write-Warning "Error logging disk usage: $_"
    }
}

# Initialize the last event time
$lastEventTime = (Get-Date).AddHours(-24)

# Function to log event data
function Log-EventData {
    try {
        # Define the logs to monitor
        $logs = @("System", "Application", "Security")

        # Define the event level (1 = Critical, 2 = Error, 3 = Warning)
        $eventLevel = 2

        # Define the start time for the event query (since the last event time)
        $startTime = $lastEventTime

        # Process each log
        foreach ($log in $logs) {
            # Get the events from the log
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
                $outputObject = New-Object -TypeName PSObject -Property $outputObject | Export-Csv -Path $EventLog -Append -NoTypeInformation
            }
        }

        # Update the last event time to the most recent event's time
        if ($events) {
            $lastEventTime = ($events | Sort-Object TimeCreated -Descending)[0].TimeCreated
        }
    } catch {
        Write-Warning "Error logging event data: $_"
    }
}

# Function to send alerts
function Send-Alert($message) {
    # Implement alert logic here (e.g., send an email or a message)
    # You can call this function within other functions to send alerts based on specific conditions
}

# Schedule this script to run periodically using loop with a sleep timer.
while ($true) {
    # Call functions to log performance data, disk usage, and event data
    Log-PerformanceData
    Log-DiskUsage
    Log-EventData

    # Wait for the specified interval (in seconds) before running again
    Start-Sleep -Seconds $SleepInterval
}
