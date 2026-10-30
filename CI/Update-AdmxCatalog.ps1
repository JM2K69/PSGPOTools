#Requires -Version 7.4
<#
    .SYNOPSIS
        Pins the package of Microsoft that holds the ADMX files of Windows, and its files, in HGPM/Resources/PolicyDefinitions.json.
    .DESCRIPTION
        Install-PSGPOAdmx installs only the package this catalog pins (its address, size and
        SHA-256) and, from it, only the files pinned: for each set (the .admx files, then each
        language folder of .adml files) its number of files and a SHA-256 of their names and
        contents. Run it for a new package of Microsoft (Administrative Templates (.admx) for
        Windows 11, on www.microsoft.com/download), downloaded first, the module built first
        (CI/03_Build.ps1); then CI/Get-AdmxSource.ps1 installs its files for the tests, and the
        tests (PSGPOTools.AdmxInstall.tests.ps1) check that the catalog is the one of the files.
    .PARAMETER MsiPath
        The package downloaded (the .msi file).
    .PARAMETER Uri
        Its address on download.microsoft.com; the one pinned by default.
    .PARAMETER Name
        Its name, as the page of Microsoft gives it; the one pinned by default.
    .PARAMETER Page
        The page of Microsoft to download it from; the one pinned by default.
    .EXAMPLE
        ./CI/03_Build.ps1; ./CI/Update-AdmxCatalog.ps1 -MsiPath ./package.msi -Uri <address of the .msi> -Name <name> -Page <page>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$MsiPath,
    [string]$Uri,
    [string]$Name,
    [string]$Page
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$catalog = Join-Path $root 'HGPM' 'Resources' 'PolicyDefinitions.json'
$pinned = (Get-Content -LiteralPath $catalog -Raw | ConvertFrom-Json).Package
if (-not $Uri) { $Uri = $pinned.Uri }
if (-not $Name) { $Name = $pinned.Name }
if (-not $Page) { $Page = $pinned.Page }
$MsiPath = (Resolve-Path -LiteralPath $MsiPath).ProviderPath

$module = Import-Module (Join-Path $root 'HGPM' 'HGPM.psd1') -Force -PassThru
$sets = & $module {
    param($Package)
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-Catalog-$([guid]::NewGuid().ToString('N'))"
    try {
        Expand-PSGPOAdmxMsi -Package $Package -Folder $work
        @(Get-PSGPOAdmxSet -Path (Get-PSGPOAdmxPackageFolder -Path $work -Package $Package).FullName)
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
} $MsiPath

$json = [ordered]@{
    Package = [ordered]@{
        Name     = $Name
        Page     = $Page
        Uri      = $Uri
        FileName = [uri]::UnescapeDataString(([uri]$Uri).Segments[-1])
        Size     = (Get-Item -LiteralPath $MsiPath).Length
        Sha256   = (Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash
    }
    Sets    = @($sets | ForEach-Object { [ordered]@{ Name = $_.Name; Files = $_.Files; Sha256 = $_.Sha256 } })
} | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($catalog, "$json`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "Catalog of $Name and its $($sets.Count) sets of ADMX files written."
