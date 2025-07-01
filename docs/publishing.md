# Publishing the Module

This document is intended for maintainers who want to publish a new release of
`MonitoringTools` to a PowerShell gallery.

1. Ensure the desired version number is selected.
2. Run the helper script with the gallery URI and API key:

```powershell
./publish_module.ps1 -GalleryUri "https://www.powershellgallery.com/api/v2" -ApiKey <key> -Version 1.0.1
```

The script updates the manifest and calls `Publish-Module`. Use `-WhatIf` to
preview actions without pushing the package.

