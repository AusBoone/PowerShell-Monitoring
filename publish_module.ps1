# ============================================================================
# Publish MonitoringTools Module to PowerShell Gallery
# ----------------------------------------------------------------------------
# Purpose : Updates the module manifest version and pushes the module to a
#           PowerShell Gallery repository. Intended for maintainers preparing
#           official releases so versioning stays consistent.
# Usage   : .\publish_module.ps1 -GalleryUri <URI> -ApiKey <key> -Version <ver>
# Notes   : Requires PowerShellGet and Publish-Module. Pass -WhatIf to preview
#           the publish process without uploading.
# ----------------------------------------------------------------------------
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory)]
    [string]$GalleryUri,

    [Parameter(Mandatory)]
    [string]$ApiKey,

    [Parameter(Mandatory)]
    [string]$Version
)

# Locate the manifest relative to this script so it works from any path.
$manifestPath = Join-Path $PSScriptRoot 'MonitoringTools.psd1'

try {
    # Update-ModuleManifest increments the ModuleVersion field so the
    # published package carries an accurate version number. Existing metadata
    # such as description and author are preserved automatically.
    Update-ModuleManifest -Path $manifestPath -ModuleVersion $Version

    # Register a temporary repository for the provided gallery URI. Using
    # a dedicated name avoids modifying any existing repository definitions
    # on the user's system.
    $repoName = 'TempPublishRepo'
    if (-not (Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Name $repoName -SourceLocation $GalleryUri \
            -PublishLocation $GalleryUri -InstallationPolicy Trusted
    }

    # Respect -WhatIf via ShouldProcess so callers can preview the actions.
    if ($PSCmdlet.ShouldProcess('MonitoringTools module', 'Publish')) {
        Publish-Module -Path $PSScriptRoot -Repository $repoName -NuGetApiKey $ApiKey
    }
} catch {
    throw "Failed to publish module: $_"
}

