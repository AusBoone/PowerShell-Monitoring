# PowerShell-Monitoring

Scripts and a PowerShell module for gathering system and network statistics on
Windows hosts. Metrics are written to CSV files for easy analysis.

## Table of Contents
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Automation](#automation)
- [Publishing](#publishing)
- [Testing](#testing)
- [Customization](#customization)
- [License](#license)

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
The monitoring commands are packaged as a module named **MonitoringTools**. Import
it directly from the repository or install it locally:

```powershell
# From the repository directory
Import-Module .\MonitoringTools.psd1
# Or install for use anywhere
Install-Module -Name MonitoringTools -Scope CurrentUser -Force -SourcePath .
```

## Usage
Basic usage examples are provided in [docs/usage.md](docs/usage.md).

## Automation
Instructions for scheduling the scripts with Windows Task Scheduler are in
[docs/scheduled_tasks.md](docs/scheduled_tasks.md).

## Publishing
Maintainers can publish new versions using `publish_module.ps1` as documented in
[docs/publishing.md](docs/publishing.md).

## Testing
Pester tests run automatically via GitHub Actions. Execute them locally with:

```powershell
Invoke-Pester -Path .\tests
```

If module installation fails due to network restrictions, clone the
[Pester](https://github.com/pester/Pester) repository and import `Pester.psd1`
from the `src` folder before running the tests.

## Customization
Modify counters or threshold parameters in `MonitoringTools.psm1` to suit your
environment. The module emits warnings rather than errors when a particular
metric cannot be collected.

## License
This project is licensed under the MIT License. See [LICENSE](LICENSE) for
details.

