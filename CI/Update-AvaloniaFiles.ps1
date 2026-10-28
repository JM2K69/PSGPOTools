#Requires -Version 7.4
<#
.SYNOPSIS
    Pins the SHA-256 of each file of the Avalonia runtime of each RID (Files of
    HGPM/Resources/AvaloniaPackages.json).
.DESCRIPTION
    Run after a change of the packages of AvaloniaPackages.json (a new version of Avalonia): the
    runtime of each RID is installed from the pinned packages (each checked against its SHA-512)
    in a temporary folder, and the SHA-256 of each of its files written. The console then loads a
    runtime only when its files are those, and refuses any other library next to them.
.PARAMETER Rid
    The runtimes to pin; all of those the packages have by default.
.EXAMPLE
    ./CI/03_Build.ps1; ./CI/Update-AvaloniaFiles.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx')]
    [string[]]$Rid = @('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$path = Join-Path $root 'HGPM' 'Resources' 'AvaloniaPackages.json'
if (-not (Test-Path -LiteralPath (Join-Path $root 'HGPM' 'HGPM.psm1'))) { throw 'The module is not built: run CI/03_Build.ps1 first.' }
$module = Import-Module (Join-Path $root 'HGPM' 'HGPM.psd1') -PassThru -Force
$data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
$files = [ordered]@{}
if ($data.Files) { foreach ($name in $data.Files.Keys) { $files[$name] = $data.Files[$name] } }
foreach ($runtime in $Rid) {
    $hashes = & $module {
        param($Runtime)
        $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-AvaloniaFiles-$([guid]::NewGuid())"
        try {
            $folder = Install-PSGPOAvaloniaRuntime -Rid $Runtime -Destination (Join-Path $work $Runtime) -Force -NoFileCheck
            $names = @(Get-ChildItem -LiteralPath $folder -File | Where-Object Name -NE 'packages.json' | ForEach-Object Name)
            [Array]::Sort($names, [System.StringComparer]::Ordinal)
            $result = [ordered]@{}
            foreach ($name in $names) { $result[$name] = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes((Join-Path $folder $name)))) }
            $result
        } finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    } $runtime
    $files[$runtime] = $hashes
    Write-Host "[Avalonia] $runtime : $($hashes.Count) files pinned"
}
# The keys in a fixed order: the same file from the same packages.
$ordered = [ordered]@{ Source = $data.Source; Packages = $data.Packages; Files = $files }
[System.IO.File]::WriteAllText($path, (($ordered | ConvertTo-Json -Depth 6) -replace "`r`n", "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "[Avalonia] $path written."
