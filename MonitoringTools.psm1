<#
.SYNOPSIS
    PowerShell utilities for system and network monitoring.
.DESCRIPTION
    Module containing functions to collect CPU, memory, disk and
    network statistics. Logs are written as CSV records so that other
    tooling can ingest them easily. Optional alerting via SMTP is
    provided when thresholds are crossed. Designed for Windows hosts
    running PowerShell 5.1 or later and uses only built-in cmdlets.
.EXAMPLE
    Import-Module .\MonitoringTools.psd1
    Log-PerformanceData -PerformanceLog perf.csv
.NOTES
    Functions emit warnings rather than terminating so monitoring
    continues even if a single query fails.
#>

# Exported functions must be dot-sourced in scripts or imported as a module

function Send-Alert {
    <#
        .SYNOPSIS
            Sends an alert message via SMTP.
        .DESCRIPTION
            Uses Send-MailMessage to deliver alert notifications. Requires SMTP
            server information and credentials. If any required parameter is
            missing the function writes a warning and returns.
        .PARAMETER Message
            Body of the alert.
        .PARAMETER Subject
            Subject line for the alert email.
        .PARAMETER SmtpServer
            Address of the SMTP server.
        .PARAMETER Port
            Port for the SMTP server. Defaults to 25.
        .PARAMETER From
            Email address to send from.
        .PARAMETER To
            Recipient address.
        .PARAMETER Credential
            Credential object for SMTP authentication if required.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Subject = 'Monitoring Alert',
        [Parameter(Mandatory)]
        [string]$SmtpServer,
        [int]$Port = 25,
        [Parameter(Mandatory)]
        [string]$From,
        [Parameter(Mandatory)]
        [string]$To,
        [pscredential]$Credential
    )
    try {
        # Use the built in cmdlet so sending mail works without extra modules
        Send-MailMessage -To $To -From $From -Subject $Subject -Body $Message \
            -SmtpServer $SmtpServer -Port $Port -Credential $Credential -UseSsl
    } catch {
        Write-Warning "Failed to send alert: $_"
    }
}

$script:lastEventTime = (Get-Date).AddHours(-24)

function Log-PerformanceData {
    <#
        .SYNOPSIS
            Collects CPU, memory and disk counters.
    #>
    param(
        [string]$PerformanceLog = 'performance_log.csv'
    )
    try {
        # Query a few common counters representing CPU, memory and disk usage
        $counters = @(
            '\\Processor(_Total)\\% Processor Time',
            '\\Memory\\Available MBytes',
            '\\PhysicalDisk(_Total)\\Disk Reads/sec',
            '\\PhysicalDisk(_Total)\\Disk Writes/sec'
        )
        $data = Get-Counter -Counter $counters
        # Build a record keyed by counter name with the current timestamp
        $out = [ordered]@{ Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
        foreach ($sample in $data.CounterSamples) {
            $out[$sample.CounterName] = $sample.CookedValue
        }
        # Append the record to the log for historical analysis
        [PSCustomObject]$out | Export-Csv -Path $PerformanceLog -Append -NoTypeInformation
    } catch {
        Write-Warning "Error logging performance data: $_"
    }
}

function Log-DiskUsage {
    <#
        .SYNOPSIS
            Records disk usage for mounted drives.
    #>
    param(
        [string]$DiskUsageLog = 'disk_usage_log.csv'
    )
    try {
        # Query local file system drives and calculate used percentage
        $drives = Get-PSDrive -PSProvider FileSystem
        foreach ($drive in $drives) {
            if ($null -eq $drive.Size) {
                # Some special drives do not expose size information
                Write-Warning "Drive $($drive.Name) missing size information"
                continue
            }
            # On some systems the Used property is unavailable, so compute it
            if ($null -eq $drive.Used) {
                $usedSpace = $drive.Size - $drive.Free
            } else {
                $usedSpace = $drive.Used
            }
            $usagePercent = ($usedSpace / $drive.Size) * 100
            $entry = [ordered]@{
                Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                Drive = $drive.Name
                UsedPercentage = $usagePercent
            }
            # Append usage stats to the CSV log
            [PSCustomObject]$entry | Export-Csv -Path $DiskUsageLog -Append -NoTypeInformation
        }
    } catch {
        Write-Warning "Error logging disk usage: $_"
    }
}

function Log-EventData {
    <#
        .SYNOPSIS
            Logs recent error events from key Windows logs.
    #>
    param(
        [string]$EventLog = 'event_log.csv'
    )
    try {
        # Monitor a few primary logs for new error entries
        $logs = @('System','Application','Security')
        $eventLevel = 2
        $start = $script:lastEventTime
        $latest = $script:lastEventTime
        foreach ($log in $logs) {
            $events = Get-WinEvent -FilterHashTable @{LogName=$log; Level=$eventLevel; StartTime=$start}
            foreach ($e in $events) {
                $obj = [ordered]@{
                    Timestamp = $e.TimeCreated
                    LogName = $log
                    EventID = $e.Id
                    Level = $e.LevelDisplayName
                    Message = $e.Message
                }
                # Append each event to the log file
                [PSCustomObject]$obj | Export-Csv -Path $EventLog -Append -NoTypeInformation
            }
            if ($events) {
                # Track the newest timestamp across all logs to avoid duplicates
                $candidate = ($events | Sort-Object TimeCreated -Descending)[0].TimeCreated
                if ($candidate -gt $latest) { $latest = $candidate }
            }
        }
        $script:lastEventTime = $latest
    } catch {
        Write-Warning "Error logging event data: $_"
    }
}

function Get-NetworkInterfaces {
    <#
        .SYNOPSIS
            Retrieves active network adapters.
    #>
    try {
        # Filter to adapters that are currently operational
        Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    } catch {
        Write-Warning "Error retrieving network interfaces: $_"
    }
}

function Log-NetworkTraffic {
    <#
        .SYNOPSIS
            Logs traffic statistics for a given adapter.
    #>
    param(
        [Parameter(Mandatory)]
        $Interface,
        [string]$NetworkLog = 'network_log.csv'
    )
    try {
        # Gather byte and packet counts for the specified adapter
        $stats = Get-NetAdapterStatistics -InterfaceIndex $Interface.InterfaceIndex
        $out = [ordered]@{
            Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            InterfaceName = $Interface.Name
            InterfaceIndex = $Interface.InterfaceIndex
            BytesReceived = $stats.BytesReceived
            BytesSent = $stats.BytesSent
            PacketsReceived = $stats.PacketsReceived
            PacketsSent = $stats.PacketsSent
        }
        # Log the snapshot of current traffic counters
        [PSCustomObject]$out | Export-Csv -Path $NetworkLog -Append -NoTypeInformation
    } catch {
        Write-Warning "Error logging network traffic: $_"
    }
}

Export-ModuleMember -Function Log-PerformanceData, Log-DiskUsage, Log-EventData, Get-NetworkInterfaces, Log-NetworkTraffic, Send-Alert
