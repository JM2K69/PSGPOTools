#Requires -Version 7.4
<#
    .SYNOPSIS
        Installs the ADMX files of Windows the tests read into sources/PolicyDefinitions, from the package of Microsoft HGPM pins.
    .DESCRIPTION
        The repository keeps no file of Microsoft: the tests read the ADMX files of Windows from
        sources/PolicyDefinitions (not in Git), which this script fills with Install-PSGPOAdmx,
        every language, from the package the module pins (HGPM/Resources/PolicyDefinitions.json).
        The package is kept in sources/package (the CI caches it), downloaded from Microsoft only
        when it is not there, and checked each time; its files are extracted again each time.
        Build the module first (CI/03_Build.ps1). Linux and macOS need msiextract (msitools).
    .PARAMETER MsiPath
        The package already downloaded (the .msi file): copied into sources/package.
    .EXAMPLE
        ./CI/03_Build.ps1; ./CI/Get-AdmxSource.ps1
#>
[CmdletBinding()]
param([string]$MsiPath)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$module = Import-Module (Join-Path $root 'HGPM' 'HGPM.psd1') -Force -PassThru
$package = & $module { Get-PSGPOAdmxPackage }

$folder = Join-Path $root 'sources' 'package'
$msi = Join-Path $folder $package.FileName
$null = New-Item -ItemType Directory -Path $folder -Force
if (-not ((Test-Path -LiteralPath $msi) -and (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -eq $package.Sha256)) {
    # Another package (the one pinned before), or none.
    Get-ChildItem -LiteralPath $folder -File | Remove-Item -Force
    $save = @{ Path = $msi; Package = $package }
    if ($MsiPath) { $save.Source = (Resolve-Path -LiteralPath $MsiPath).ProviderPath }
    & $module { param($Save) Save-PSGPOAdmxPackage @Save } $save
    Write-Host "$($package.FileName) $(if ($MsiPath) { 'copied' } else { "downloaded from $($package.Uri)" })."
}

$target = Join-Path $root 'sources' 'PolicyDefinitions'
if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
$result = Install-PSGPOAdmx -AllLanguages -Path $target -MsiPath $msi -Confirm:$false
Write-Host "$($result.Files) files of $($result.Package) in $target."
