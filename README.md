# PowerShell-Monitoring

This project provides scripts and a PowerShell module for collecting system and
network statistics on Windows hosts. Metrics are written to CSV files so they
can be reviewed or fed into other tools.

## Features
- Monitor CPU, memory and disk performance counters
- Track disk usage for each mounted drive
- Capture recent system, application and security event log entries
- Record network interface traffic statistics
- Optional SMTP alerting via `Send-Alert`
- Pester unit tests and GitHub Actions workflow

## Requirements
- PowerShell 5.1 or higher
- Windows operating system
- Administrative rights to query counters and logs

## Installation
The monitoring commands are packaged as a module named **MonitoringTools**.
You may import it directly from the repository or install it locally:

```powershell
# From the repository directory
Import-Module .\MonitoringTools.psd1
# Or install for use anywhere
Install-Module -Name MonitoringTools -Scope CurrentUser -Force -SourcePath .
```

## Usage
Example running the system monitor script which imports the module and loops
indefinitely:

```powershell
.\system_monitoring.ps1 -PerformanceLog perf.csv -DiskUsageLog disk.csv -EventLog events.csv -SleepInterval 900
```

Network traffic monitoring works similarly:

```powershell
.\network_traffic.ps1 -NetworkLog net.csv -SleepInterval 60
```

### Sending Alerts
The `Send-Alert` function requires SMTP details:

```powershell
Send-Alert -Message "High CPU" -Subject "Alert" -SmtpServer "smtp.example.com" `
    -Port 587 -From "monitor@example.com" -To "admin@example.com" `
    -Credential (Get-Credential)
```

You can call `Send-Alert` from custom logic within the module functions when
thresholds are exceeded.

## Continuous Integration
Pester tests run automatically via GitHub Actions. The workflow lives in
`.github/workflows/pester.yml` and executes `Invoke-Pester` on Windows runners.

Run tests locally with:

```powershell
Invoke-Pester -Path .\tests
```

If PowerShell cannot download modules from the gallery due to network restrictions, clone the [Pester](https://github.com/pester/Pester) repository and import `Pester.psd1` from the `src` folder before running the tests.
## Customization
Modify the counters in `Log-PerformanceData` or adjust event levels in
`Log-EventData` to match your environment. Additional functions can be added to
`MonitoringTools.psm1` as needed.
