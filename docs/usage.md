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

