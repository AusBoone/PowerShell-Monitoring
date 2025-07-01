@{
    RootModule = 'MonitoringTools.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'd0a7e53f-9e1b-4e44-9cc4-1ea401e9bc28'
    Author = 'PowerShell Monitoring Maintainers'
    Description = 'Utilities for system and network monitoring'
    FunctionsToExport = @('Log-PerformanceData','Log-DiskUsage','Log-EventData','Get-NetworkInterfaces','Log-NetworkTraffic','Send-Alert')
    PowerShellVersion = '5.1'
}
