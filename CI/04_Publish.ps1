#Requires -Version 7.4
<#
    .SYNOPSIS
        Publishes the built module on the PowerShell Gallery, for the tag of its version.
    .DESCRIPTION
        Run by the Release workflow (.github/workflows/release.yml) when a tag v<version> is pushed,
        after the tests: a commit alone never publishes. The module must be built (CI/03_Build.ps1).

        Before anything is sent, it checks that:
        - the tag is the version of the manifest: v<ModuleVersion>, with -<Prerelease> when the
          manifest has one (v0.1.3-alpha for 0.1.3 and alpha);
        - CHANGELOG.md has a section for this version (## 0.1.3 - alpha);
        - the manifest is valid (Test-ModuleManifest) and the module is built;
        - this version is not on the gallery yet (the gallery refuses a version twice).

        The package is the folder HGPM without the Avalonia runtime (Avalonia/bin): the console
        downloads it the first time it opens, checked against its pinned SHA-512.

        Writes the notes of the version (its section of CHANGELOG.md) to -NotesPath, for the release
        of GitHub.
    .PARAMETER Tag
        The tag pushed (v0.1.3-alpha).
    .PARAMETER ApiKey
        The API key of the PowerShell Gallery; without it, everything is checked and the package
        made, nothing is published.
    .PARAMETER NotesPath
        Where to write the notes of the version.
    .EXAMPLE
        ./CI/03_Build.ps1; ./CI/04_Publish.ps1 -Tag v0.1.3-alpha
        Checks the version and makes the package, without publishing it.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Tag,
    [string]$ApiKey,
    [string]$NotesPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$moduleName = 'HGPM'
$source = Join-Path $root $moduleName
$manifestPath = Join-Path $source "$moduleName.psd1"

# The version of the manifest, and the tag it has.
$data = Import-PowerShellDataFile -Path $manifestPath
$prerelease = "$($data.PrivateData.PSData.Prerelease)".Trim()
$version = if ($prerelease) { "$($data.ModuleVersion)-$prerelease" } else { "$($data.ModuleVersion)" }
if ($Tag -cne "v$version") { throw "The tag '$Tag' is not the version of the manifest: tag v$version, or change ModuleVersion and Prerelease of $moduleName.psd1." }

# The section of the version in CHANGELOG.md: its notes.
$changelog = [System.IO.File]::ReadAllText((Join-Path $root 'CHANGELOG.md')) -replace '\r\n', "`n"
$heading = '## {0}{1}' -f $data.ModuleVersion, $(if ($prerelease) { " - $prerelease" })
$section = [regex]::Match($changelog, "(?ms)^$([regex]::Escape($heading))[ \t]*\n(.*?)(?=^## |\z)")
if (-not $section.Success) { throw "CHANGELOG.md has no section '$heading': name the changes of this version." }
$notes = $section.Groups[1].Value.Trim()
if ($NotesPath) { [System.IO.File]::WriteAllText($NotesPath, "$notes`n", [System.Text.UTF8Encoding]::new($false)) }

if (-not (Test-Path -LiteralPath (Join-Path $source "$moduleName.psm1"))) { throw "The module is not built: run CI/03_Build.ps1 first." }
$null = Test-ModuleManifest -Path $manifestPath

# The package: the module without the Avalonia runtime, in a folder of its name.
$package = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-publish-$([guid]::NewGuid().ToString('N'))" $moduleName
$null = New-Item -ItemType Directory -Path $package -Force
Copy-Item -Path (Join-Path $source '*') -Destination $package -Recurse
Remove-Item -LiteralPath (Join-Path $package 'Avalonia' 'bin') -Recurse -Force -ErrorAction SilentlyContinue
# The license and its attribution go with every copy of the module (Apache License 2.0, section 4).
foreach ($file in 'LICENSE', 'NOTICE') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..' $file) -Destination $package }
$files = @(Get-ChildItem -LiteralPath $package -Recurse -File)
Write-Host "[PUBLISH] $moduleName $version : $($files.Count) files, $([math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1)) MB in $package"

$published = Find-PSResource -Name $moduleName -Version $data.ModuleVersion -Prerelease -Repository PSGallery -ErrorAction SilentlyContinue |
    Where-Object { "$($_.Prerelease)" -eq $prerelease }
if ($published) { throw "$moduleName $version is already on the PowerShell Gallery: a version is published once, change ModuleVersion." }

if (-not $ApiKey) {
    Write-Host "[PUBLISH] No API key: checked, not published."
    return
}
Publish-PSResource -Path $package -Repository PSGallery -ApiKey $ApiKey
Write-Host "[PUBLISH] $moduleName $version published: https://www.powershellgallery.com/packages/$moduleName/$version"
