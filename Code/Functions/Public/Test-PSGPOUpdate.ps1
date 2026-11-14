function Test-PSGPOUpdate {
    <#
    .SYNOPSIS
        Tells whether a newer version of HGPM, or of its add-ons, is published on the PowerShell
        Gallery.
    .DESCRIPTION
        Compares the version of HGPM loaded in the session with the latest one of the PowerShell
        Gallery (Find-PSResource), as semantic versions: a prerelease comes before its release
        (0.1.4-alpha before 0.1.4), and the prereleases sort by their label (alpha, beta, rc).

        The prereleases of the Gallery count when the version loaded is one, or with -Prerelease; a
        stable version is otherwise only compared with the stable ones. The result gives the command
        that updates the module: Update-PSResource when it was installed from the Gallery,
        Install-PSResource otherwise (a copy of the repository, for instance).

        The add-ons installed that follow the Gallery (their manifest requires a minimum version of
        HGPM, ModuleVersion) are compared too, in AddOns, and the command updates those installed
        from the Gallery with HGPM: Update-PSResource -Name HGPM, HGPM.Contoso. An add-on whose
        package brings HGPM (its manifest requires one version of HGPM only, RequiredVersion) is
        named in Package: HGPM is updated with that package, not from the Gallery, so
        UpdateAvailable is false and no command is given.

        Nothing is installed: the command only reads the Gallery.
    .PARAMETER Prerelease
        Takes the prereleases of the Gallery into account, even when the version loaded is stable.
    .PARAMETER Quiet
        Returns $true when a newer version of HGPM or of an add-on is published, $false otherwise,
        instead of the details.
    .PARAMETER Repository
        Repository of PSResourceGet to look in (Get-PSResourceRepository); PSGallery by default.
    .EXAMPLE
        Test-PSGPOUpdate
    .EXAMPLE
        (Test-PSGPOUpdate).AddOns
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

    # The add-ons that follow the Gallery, each with the latest version of the repository: none
    # when it is not published there.
    $addOns = @(foreach ($module in @(Get-PSGPOGalleryAddOn)) {
            $label = "$($module.PrivateData.PSData.Prerelease)"
            $newest = $null
            try {
                $newest = @(Find-PSResource -Name $module.Name -Repository $Repository -Prerelease:$withPrerelease -ErrorAction Stop) |
                    Sort-Object -Property { ConvertTo-PSGPOCoreVersion "$($_.Version)" }, { ConvertTo-PSGPOSemanticVersion -Version '0.0.0' -Prerelease $_.Prerelease } -Descending |
                    Select-Object -First 1
            } catch {
                Write-Verbose "$($module.Name) is not found in the repository ${Repository}: $($_.Exception.GetBaseException().Message)"
            }
            [pscustomobject]@{
                Name = $module.Name
                InstalledVersion = "$($module.Version)$(if ($label) { "-$label" })"
                LatestVersion = if ($newest) { "$($newest.Version)$(if ($newest.Prerelease) { "-$($newest.Prerelease)" })" }
                UpdateAvailable = [bool]($newest -and (Test-PSGPONewerVersion -Version $newest.Version -Prerelease $newest.Prerelease -Than $module.Version -ThanPrerelease $label))
            }
        })
    $package = @(Get-PSGPOPackageAddOn | ForEach-Object Name)

    $available = -not $package.Count -and ($latest.Version -gt $installed.Version -or [bool]@($addOns | Where-Object UpdateAvailable).Count)
    if ($Quiet) { return $available }

    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Update'
        Name = 'HGPM'
        InstalledVersion = $installed.Version.ToString()
        LatestVersion = $latest.Version.ToString()
        UpdateAvailable = $available
        Published = $latest.Resource.PublishedDate
        Repository = $Repository
        ReleaseNotes = "$($latest.Resource.ReleaseNotes)"
        UpdateCommand = if ($available) { Get-PSGPOUpdateCommand -InstalledPath $installed.Path -Latest $latest.Version -Repository $Repository }
        AddOns = $addOns
        Package = $package -join ', '
    }
}
