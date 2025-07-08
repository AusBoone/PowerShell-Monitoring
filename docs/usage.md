# Usage Guide

This document explains how to run the provided scripts and functions.

## Importing the Module

```powershell
# From the repository root
Import-Module .\MonitoringTools.psd1
```

Alternatively install for global use:

```powershell
Register-PSRepository -Name LocalRepo -SourceLocation (Get-Item .).FullName -InstallationPolicy Trusted
Install-Module -Name MonitoringTools -Repository LocalRepo -Scope CurrentUser -Force
```

## System Monitoring Script

`system_monitoring.ps1` continually collects CPU, disk and event log data. Use
`-Iterations` to limit how many cycles run for testing or short monitoring
windows. Example:

```powershell
./system_monitoring.ps1 -PerformanceLog perf.csv -DiskUsageLog disk.csv \
    -EventLog events.csv -SleepInterval 900 -CpuThreshold 90 -DiskUsageThreshold 80 \ 
    -Iterations 5
```

Metrics append to CSV files so other tools can ingest them.

## Network Traffic Script

`network_traffic.ps1` logs interface statistics every interval. Specify
`-InterfaceName` to monitor particular adapters by name or index. The script
also accepts `-Iterations` for finite execution.

```powershell
# Monitor all adapters
./network_traffic.ps1 -NetworkLog net.csv -SleepInterval 60 -Iterations 10

# Monitor a specific interface by name
./network_traffic.ps1 -InterfaceName Ethernet -Iterations 5
```

## Alerting

Functions raise warnings or call `Send-Alert` when optional thresholds are
exceeded. Configure SMTP details when calling `Send-Alert`:

```powershell
Send-Alert -Message "High CPU" -Subject "Alert" -SmtpServer "smtp.example.com" \
    -Port 587 -From "monitor@example.com" -To "admin@example.com" \
    -Credential (Get-Credential) -UseSsl
```
Both `-Credential` and `-UseSsl` are optional depending on your mail server.

## Function Examples and CSV Output

### Log-PerformanceData
Collect CPU, memory and disk statistics and append them to a log file:

```powershell
Log-PerformanceData -PerformanceLog .\perf.csv
```

Resulting CSV excerpt:

```
Timestamp,\\Processor(_Total)\\% Processor Time,\\Memory\\Available MBytes,\\PhysicalDisk(_Total)\\Disk Reads/sec,\\PhysicalDisk(_Total)\\Disk Writes/sec
2023-01-01 12:00:00,15,2048,30,45
```

Typical analysis pulls the log into a variable and calculates averages:

```powershell
$perf = Import-Csv .\perf.csv
($perf.'\\Processor(_Total)\\% Processor Time' | Measure-Object -Average).Average
```

### Log-DiskUsage
Write drive usage percentages to a log:

```powershell
Log-DiskUsage -DiskUsageLog .\disk.csv
```

CSV example:

```
Timestamp,Drive,UsedPercentage
2023-01-01 12:00:00,C,75.5
```

You can plot `UsedPercentage` over time or find spikes:

```powershell
$disk = Import-Csv .\disk.csv
$disk | Sort-Object UsedPercentage -Descending | Select-Object -First 5
```

### Log-EventData
Record recent error events from common Windows logs:

```powershell
Log-EventData -EventLog .\events.csv
```

CSV output looks like:

```
Timestamp,LogName,EventID,Level,Message
2023-01-01 12:00:00,System,101,Error,Service failed to start.
```

View counts by `LogName` to see which log is most active:

```powershell
$events = Import-Csv .\events.csv
$events | Group-Object LogName | Select-Object Name,Count
```

### Get-NetworkInterfaces
List the adapters currently up on the system:

```powershell
Get-NetworkInterfaces
```

```
Name     InterfaceIndex Status
----     -------------- ------
Ethernet 1              Up
Wi-Fi    2              Up
```

### Log-NetworkTraffic
Capture traffic counters for one or more interfaces:

```powershell
Log-NetworkTraffic -InterfaceName Ethernet -NetworkLog .\net.csv
```

CSV snippet:

```
Timestamp,InterfaceName,InterfaceIndex,BytesReceived,BytesSent,PacketsReceived,PacketsSent
2023-01-01 12:00:00,Ethernet,1,100000,50000,1000,900
```

To compute total bytes sent over the logging period:

```powershell
$net = Import-Csv .\net.csv
($net | Measure-Object BytesSent -Sum).Sum
```
