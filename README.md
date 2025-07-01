# PowerShell-Monitoring

This PowerShell script monitors system performance, disk usage, and event logs, logging the data into separate CSV files. 
It is designed to run periodically and can be easily configured using parameters.

# Features
- Monitor system performance counters such as CPU usage, available memory, and disk read/write rates
- Monitor disk usage by calculating the used space and percentage for each drive
- Monitor event logs for critical, error, and warning events
- Log the data into separate CSV files for performance, disk usage, and event logs
- Runs periodically using a loop with a sleep timer
- Error handling for each function to ensure script continues running even if an error occurs
- Function template for sending alerts based on specific conditions (e.g., email or messaging platform)

# Requirements
- PowerShell 3.0 or higher
- Windows operating system (tested on Windows 10)
- Local administrator rights to query performance counters and event logs
- The `NetAdapter` module installed (included with modern Windows versions)

# Usage
1) Save the script (e.g., system_monitoring.ps1).
2) Open PowerShell and navigate to the directory containing the script.
3) Run the script using the following command:

.\system_monitoring.ps1

4) By default, the script logs performance data, disk usage, and event logs into separate CSV files (performance_log.csv, disk_usage_log.csv, and event_log.csv). You can change the file paths and sleep interval by providing parameters when running the script:

.\system_monitoring.ps1 -PerformanceLog "path\to\performance_log.csv" -DiskUsageLog "path\to\disk_usage_log.csv" -EventLog "path\to\event_log.csv" -SleepInterval 1800

5) The script will run indefinitely and collect data at the specified interval. To stop the script, press Ctrl+C or close the PowerShell console.
6) To send alerts based on specific conditions, implement the desired alert logic within the Send-Alert function in the script.

The `Send-Alert` function is a stub you can extend to integrate with email or
chat systems. Call it from the monitoring functions when thresholds are
exceeded to receive real-time notifications.

# Scheduling
You can run the monitoring scripts automatically using **Task Scheduler**:
1. Open Task Scheduler and create a new task.
2. Set the trigger to start at boot or on a schedule of your choice.
3. For the action, use `powershell.exe` with the full path to `system_monitoring.ps1` or `network_traffic.ps1`.
4. Ensure the task runs with highest privileges so it can access system counters and logs.


# Running Tests
Pester tests are located in the `tests/` directory. Execute them from PowerShell:

```powershell
Invoke-Pester -Path .\tests
```

# Customization

- Modify the performance counters in the Log-PerformanceData function to monitor additional or different counters.
- Adjust the event level in the Log-EventData function to include or exclude specific event types.
- Implement additional monitoring functions or modify existing ones to fit your specific requirements.
