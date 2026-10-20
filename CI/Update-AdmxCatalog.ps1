#Requires -Version 7.4
<#
    .SYNOPSIS
        Pins the ADMX files of the repository (sources/PolicyDefinitions) in HGPM/Resources/PolicyDefinitions.json.
    .DESCRIPTION
        Install-PSGPOAdmx downloads sources/PolicyDefinitions from GitHub and installs only the files
        this catalog pins: for each set (the .admx files, then each language folder of .adml files)
        its number of files and a SHA-256 of their names and contents. Run it after a change of
        sources/PolicyDefinitions (the build first: CI/03_Build.ps1); the tests
        (PSGPOTools.AdmxInstall.tests.ps1) check that the catalog is the one of the files.
    .EXAMPLE
        ./CI/03_Build.ps1; ./CI/Update-AdmxCatalog.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$module = Import-Module (Join-Path $root 'HGPM' 'HGPM.psd1') -Force -PassThru
$sets = & $module { param($Path) @(Get-PSGPOAdmxSet -Path $Path) } (Join-Path $root 'sources' 'PolicyDefinitions')
$json = [ordered]@{ Source = 'sources/PolicyDefinitions'; Sets = @($sets | ForEach-Object { [ordered]@{ Name = $_.Name; Files = $_.Files; Sha256 = $_.Sha256 } }) } | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText((Join-Path $root 'HGPM' 'Resources' 'PolicyDefinitions.json'), "$json`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "Catalog of $($sets.Count) sets of ADMX files written."
