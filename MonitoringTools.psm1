<#
.SYNOPSIS
    PowerShell utilities for system and network monitoring.
.DESCRIPTION
    Module containing functions to collect CPU, memory, disk and
    network statistics. Logs are written as CSV records so that other
    tooling can ingest them easily. Optional alerting via SMTP is
    provided when CPU or disk usage thresholds are crossed. Designed for Windows
    hosts running PowerShell 5.1 or later and uses only built-in cmdlets.
.EXAMPLE
    Import-Module .\MonitoringTools.psd1
    Log-PerformanceData -PerformanceLog perf.csv
.NOTES
    Functions emit warnings rather than terminating so monitoring
    continues even if a single query fails.
    Added optional credential/SSL handling and automatic log directory
    creation to improve robustness.
    This revision adds strict error handling (-ErrorAction Stop) to critical
    cmdlets and skips disk usage entries when a drive reports zero size.
    Threshold comparisons now check PSBoundParameters.ContainsKey so a value
    of 0 triggers alerts.
    Log-NetworkTraffic now warns and returns when requested adapters cannot be
    resolved, preventing log attempts on nonexistent interfaces.
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
        .PARAMETER UseSsl
            Include this switch to send the message over an SSL connection.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty]
        [string]$Message,
        [string]$Subject = 'Monitoring Alert',
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty]
        [string]$SmtpServer,
        [int]$Port = 25,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty]
        [string]$From,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty]
        [string]$To,
        [pscredential]$Credential,
        [switch]$UseSsl
    )
    try {
        # Build parameter set dynamically so optional values are only passed
        $mailParams = @{
            To         = $To
            From       = $From
            Subject    = $Subject
            Body       = $Message
            SmtpServer = $SmtpServer
            Port       = $Port
        }
        if ($Credential) { $mailParams.Credential = $Credential }
        if ($UseSsl.IsPresent) { $mailParams.UseSsl = $true }

        # Use the built-in cmdlet so sending mail works without extra modules
        Send-MailMessage @mailParams
    } catch {
        Write-Warning "Failed to send alert: $_"
    }
}

$script:lastEventTime = (Get-Date).AddHours(-24)

function Log-PerformanceData {
    <#
        .SYNOPSIS
            Collects CPU, memory and disk counters.
        .PARAMETER PerformanceLog
            Path to the CSV log file that records counter samples.
        .PARAMETER CpuThreshold
            Optional percentage above which a CPU usage alert is generated.
    #>
    param(
        [string]$PerformanceLog = 'performance_log.csv',
        [ValidateRange(0,100)]
        [int]$CpuThreshold
    )
    try {
        # Query a few common counters representing CPU, memory and disk usage
        $counters = @(
            '\\Processor(_Total)\\% Processor Time',
            '\\Memory\\Available MBytes',
            '\\PhysicalDisk(_Total)\\Disk Reads/sec',
            '\\PhysicalDisk(_Total)\\Disk Writes/sec'
        )
        $data = Get-Counter -Counter $counters -ErrorAction Stop
        # Build a record keyed by counter name with the current timestamp
        $out = [ordered]@{ Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
        foreach ($sample in $data.CounterSamples) {
            $out[$sample.CounterName] = $sample.CookedValue
            # Check if caller supplied -CpuThreshold to allow zero values. Using
            # ContainsKey avoids treating 0 as $false which would skip alerts.
            if ($PSBoundParameters.ContainsKey('CpuThreshold') -and $sample.CounterName -match 'Processor' -and $sample.CookedValue -ge $CpuThreshold) {
                $msg = "CPU usage $($sample.CookedValue)% exceeded threshold $CpuThreshold%"
                Send-Alert -Message $msg -Subject 'CPU Threshold Exceeded'
            }
        }
        # Ensure log directory exists so Export-Csv succeeds on first run
        $dir = Split-Path -Path $PerformanceLog -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
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
        .PARAMETER DiskUsageLog
            Path to the CSV log storing drive usage history.
        .PARAMETER UsageThreshold
            Optional percentage that triggers an alert when drive usage exceeds it.
    #>
    param(
        [string]$DiskUsageLog = 'disk_usage_log.csv',
        [ValidateRange(0,100)]
        [int]$UsageThreshold
    )
    try {
        # Query local file system drives and calculate used percentage
        $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction Stop
        foreach ($drive in $drives) {
            if ($null -eq $drive.Size) {
                # Some special drives do not expose size information
                Write-Warning "Drive $($drive.Name) missing size information"
                continue
            }
            if ($drive.Size -eq 0) {
                Write-Warning "Drive $($drive.Name) size reported as zero; skipping"
                continue
            }
            # On some systems the Used property is unavailable, so compute it
            if ($null -eq $drive.Used) {
                $usedSpace = $drive.Size - $drive.Free
            } else {
                $usedSpace = $drive.Used
            }
            $usagePercent = ($usedSpace / $drive.Size) * 100
            # Use ContainsKey so a threshold value of 0 still triggers alerts.
            if ($PSBoundParameters.ContainsKey('UsageThreshold') -and $usagePercent -ge $UsageThreshold) {
                $msg = "Drive $($drive.Name) usage $([math]::Round($usagePercent,2))% exceeded threshold $UsageThreshold%"
                Send-Alert -Message $msg -Subject 'Disk Usage Threshold Exceeded'
            }
            $entry = [ordered]@{
                Timestamp     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                Drive         = $drive.Name
                UsedPercentage = $usagePercent
            }
            # Ensure target directory exists before writing
            $dir = Split-Path -Path $DiskUsageLog -Parent
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
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
            $events = Get-WinEvent -FilterHashTable @{LogName=$log; Level=$eventLevel; StartTime=$start} -ErrorAction Stop
            foreach ($e in $events) {
                $obj = [ordered]@{
                    Timestamp = $e.TimeCreated
                    LogName = $log
                    EventID = $e.Id
                    Level = $e.LevelDisplayName
                    Message = $e.Message
                }
                # Ensure target directory exists before writing
                $dir = Split-Path -Path $EventLog -Parent
                if ($dir -and -not (Test-Path $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
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
        Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
    } catch {
        Write-Warning "Error retrieving network interfaces: $_"
    }
}

function Log-NetworkTraffic {
    <#
        .SYNOPSIS
            Logs traffic statistics for one or more adapters.
        .DESCRIPTION
            Accepts either a network adapter object via -Interface or an adapter
            name/index via -InterfaceName. This design supports both advanced
            scripts that already hold adapter objects and quick one-off calls by
            name.
        .PARAMETER Interface
            Adapter object returned from Get-NetworkInterfaces.
        .PARAMETER InterfaceName
            One or more adapter names or interface indexes to record.
        .PARAMETER NetworkLog
            Path to the CSV file where statistics will be appended.
    #>
    param(
        [Parameter(Mandatory, ParameterSetName='ByObject')]
        $Interface,
        [Parameter(Mandatory, ParameterSetName='ByName')]
        [string[]]$InterfaceName,
        [string]$NetworkLog = 'network_log.csv'
    )
    try {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            # Resolve adapters from the system each call to ensure the latest
            # devices are logged when called repeatedly.
            $interfaces = Get-NetAdapter -ErrorAction Stop | Where-Object {
                $InterfaceName -contains $_.Name -or
                $InterfaceName -contains $_.InterfaceIndex.ToString()
            }
        } else {
            $interfaces = @($Interface)
        }

        # Ensure at least one adapter was resolved before attempting to log.
        # When the requested names or indexes do not match any system
        # interfaces, continuing would raise errors for each missing adapter.
        # Warn the caller and exit early so the monitoring job can continue
        # without generating unnecessary failures or empty log entries.
        if (-not $interfaces) {
            Write-Warning "No network interfaces matched the specified criteria."
            return
        }

        foreach ($iface in $interfaces) {
            # Gather byte and packet counts for each adapter
            $stats = Get-NetAdapterStatistics -InterfaceIndex $iface.InterfaceIndex -ErrorAction Stop
            $out = [ordered]@{
                Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                InterfaceName   = $iface.Name
                InterfaceIndex  = $iface.InterfaceIndex
                BytesReceived   = $stats.BytesReceived
                BytesSent       = $stats.BytesSent
                PacketsReceived = $stats.PacketsReceived
                PacketsSent     = $stats.PacketsSent
            }
            # Ensure directory exists before writing the snapshot
            $dir = Split-Path -Path $NetworkLog -Parent
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            # Log the snapshot of current traffic counters
            [PSCustomObject]$out | Export-Csv -Path $NetworkLog -Append -NoTypeInformation
        }
    } catch {
        Write-Warning "Error logging network traffic: $_"
    }
}

Export-ModuleMember -Function Log-PerformanceData, Log-DiskUsage, Log-EventData, Get-NetworkInterfaces, Log-NetworkTraffic, Send-Alert
