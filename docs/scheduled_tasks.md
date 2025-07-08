# Scheduled Task Automation

Use `setup-scheduled-task.ps1` to run the monitoring scripts on a recurring
schedule. The helper registers Windows tasks that launch PowerShell with the
appropriate arguments.

Example hourly setup:

```powershell
./setup-scheduled-task.ps1 -Frequency Hourly -PerformanceLog perf.csv \
    -DiskUsageLog disk.csv -EventLog events.csv -NetworkLog net.csv \
    -CpuThreshold 90 -DiskUsageThreshold 80 -InterfaceName Ethernet
```

`-InterfaceName` restricts logging to one or more adapters when multiple are
present. Provide a comma-separated list to track several interfaces at once.

Remove tasks by running:

```powershell
./setup-scheduled-task.ps1 -Remove
```

Threshold parameters follow the same validation rules as the scripts and will
throw if values fall outside 0-100.

