# ============================================================================
# Publish MonitoringTools Module to PowerShell Gallery
# ----------------------------------------------------------------------------
# Purpose   : Updates the module manifest version and pushes the module to a
#             PowerShell Gallery repository. Intended for maintainers preparing
#             official releases so versioning stays consistent.
# Usage     : .\publish_module.ps1 -GalleryUri <URI> -ApiKey <key> -Version <ver>
# Notes     : Requires PowerShellGet and Publish-Module. Pass -WhatIf to preview
#             the publish process without uploading. The script now cleans up the
#             temporary repository entry after publishing.
# Revision  : Added -ErrorAction Stop to all publishing cmdlets so non-terminating
#             errors become terminating exceptions, allowing automation to react
#             reliably to failures.
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
    # such as description and author are preserved automatically. Using
    # -ErrorAction Stop ensures any issues updating the manifest surface as
    # terminating errors so the catch block can handle them.
    Update-ModuleManifest -Path $manifestPath -ModuleVersion $Version -ErrorAction Stop

    # Register a temporary repository for the provided gallery URI. Using
    # a dedicated name avoids modifying any existing repository definitions
    # on the user's system.
    $repoName = 'TempPublishRepo'
    if (-not (Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Name $repoName -SourceLocation $GalleryUri \
            -PublishLocation $GalleryUri -InstallationPolicy Trusted -ErrorAction Stop
    }

    # Respect -WhatIf via ShouldProcess so callers can preview the actions.
    if ($PSCmdlet.ShouldProcess('MonitoringTools module', 'Publish')) {
        # -ErrorAction Stop converts non-terminating errors from Publish-Module
        # into terminating exceptions, guaranteeing failures propagate out of
        # this script for callers to handle appropriately.
        Publish-Module -Path $PSScriptRoot -Repository $repoName -NuGetApiKey $ApiKey -ErrorAction Stop
    }
} catch {
    throw "Failed to publish module: $_"
} finally {
    # Remove the temporary repository regardless of success or failure so
    # publishing does not leave an extra entry in the repository list.
    Unregister-PSRepository -Name $repoName -ErrorAction SilentlyContinue
}

