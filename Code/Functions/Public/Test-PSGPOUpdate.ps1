function Test-PSGPOUpdate {
    <#
    .SYNOPSIS
        Tells whether a newer version of HGPM is published on the PowerShell Gallery.
    .DESCRIPTION
        Compares the version of HGPM loaded in the session with the latest one of the PowerShell
        Gallery (Find-PSResource), as semantic versions: a prerelease comes before its release
        (0.1.4-alpha before 0.1.4), and the prereleases sort by their label (alpha, beta, rc).

        The prereleases of the Gallery count when the version loaded is one, or with -Prerelease; a
        stable version is otherwise only compared with the stable ones. The result gives the command
        that updates the module: Update-PSResource when it was installed from the Gallery,
        Install-PSResource otherwise (a copy of the repository, for instance).

        Nothing is installed: the command only reads the Gallery.
    .PARAMETER Prerelease
        Takes the prereleases of the Gallery into account, even when the version loaded is stable.
    .PARAMETER Quiet
        Returns $true when a newer version is published, $false otherwise, instead of the details.
    .PARAMETER Repository
        Repository of PSResourceGet to look in (Get-PSResourceRepository); PSGallery by default.
    .EXAMPLE
        Test-PSGPOUpdate
    .EXAMPLE
        if (Test-PSGPOUpdate -Quiet) { Update-PSResource -Name HGPM -Prerelease }
    .OUTPUTS
        PSGPOTools.Update
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/test-psgpoupdate/
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.Update', [bool])]
    param(
        [switch]$Prerelease,
        [switch]$Quiet,
        [string]$Repository = 'PSGallery'
    )

    $installed = Get-PSGPOModuleVersion
    $withPrerelease = $Prerelease -or [bool]$installed.Version.PreReleaseLabel
    try {
        $published = @(Find-PSResource -Name 'HGPM' -Repository $Repository -Prerelease:$withPrerelease -ErrorAction Stop)
    } catch {
        throw "The repository $Repository cannot be read, the version of HGPM there is unknown: $($_.Exception.GetBaseException().Message)"
    }
    $latest = $published | ForEach-Object {
        [pscustomobject]@{ Version = ConvertTo-PSGPOSemanticVersion -Version $_.Version -Prerelease $_.Prerelease; Resource = $_ }
    } | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $latest) { throw "HGPM is not published in the repository $Repository." }

    $available = $latest.Version -gt $installed.Version
    if ($Quiet) { return $available }

    # From the Gallery: Update-PSResource; a copy of the repository: Install-PSResource.
    $fromGallery = $false
    try {
        $fromGallery = [bool](@(Get-InstalledPSResource -Name 'HGPM' -ErrorAction Stop) | Where-Object { $_.InstalledLocation -and $installed.Path.StartsWith($_.InstalledLocation, [System.StringComparison]::OrdinalIgnoreCase) })
    } catch {
        Write-Verbose "The modules installed by PSResourceGet cannot be read: $($_.Exception.Message)"
    }
    $command = '{0}-PSResource -Name HGPM{1}{2}' -f $(if ($fromGallery) { 'Update' } else { 'Install' }),
        $(if ($latest.Version.PreReleaseLabel) { ' -Prerelease' }), $(if ($Repository -ne 'PSGallery') { " -Repository $Repository" })
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Update'
        Name = 'HGPM'
        InstalledVersion = $installed.Version.ToString()
        LatestVersion = $latest.Version.ToString()
        UpdateAvailable = $available
        Published = $latest.Resource.PublishedDate
        Repository = $Repository
        ReleaseNotes = "$($latest.Resource.ReleaseNotes)"
        UpdateCommand = if ($available) { $command }
    }
}
