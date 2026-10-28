#Requires -Version 7.4
<#
.SYNOPSIS
    Downloads the Avalonia UI runtime of Show-GPOManagerAvalonia ahead of time.
.DESCRIPTION
    Show-GPOManagerAvalonia installs the runtime of the computer by itself the first time it
    opens. This script installs it beforehand, or for another platform: for a computer without
    internet (then copy the bin\<rid> folder next to its module), or for a deployment.

    The NuGet packages of Resources/AvaloniaPackages.json are downloaded from nuget.org (or the
    feed or folder of PSGPOTOOLS_NUGET_SOURCE) and each one is checked against its pinned SHA-512
    before anything is extracted; the assemblies for .NET 8 and the native libraries of the
    runtime, each checked against its pinned SHA-256, are put in <Destination>\<rid> at once. The
    offline archives of each release already have the runtime of each platform.
.PARAMETER Rid
    Runtime: win-x64, win-arm64, linux-x64, linux-arm64 or osx; the one of this computer by default.
.PARAMETER Destination
    Root folder of the runtimes; bin next to this script by default.
.PARAMETER Force
    Installs again a runtime already there.
.EXAMPLE
    .\Get-AvaloniaBinaries.ps1
.EXAMPLE
    .\Get-AvaloniaBinaries.ps1 -Rid linux-x64 -Destination C:\Temp\Avalonia
#>
[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx')]
    [string]$Rid,

    [string]$Destination = (Join-Path $PSScriptRoot 'bin'),

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$moduleRoot = Join-Path $PSScriptRoot '..'
if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot 'HGPM.psm1'))) {
    # A clone of the repository: the module is built from Code/ by CI/03_Build.ps1.
    throw "The HGPM module is not built in $((Resolve-Path $moduleRoot).Path): run CI/03_Build.ps1 first."
}
$module = Import-Module (Join-Path $moduleRoot 'HGPM.psd1') -PassThru -Force
& $module {
    param($Rid, $Destination, $Force)
    if (-not $Rid) { $Rid = Get-PSGPOAvaloniaRid }
    $path = Install-PSGPOAvaloniaRuntime -Rid $Rid -Destination (Join-Path $Destination $Rid) -Force:$Force
    Write-Host "[Avalonia] $Rid runtime in $path ($(@(Get-ChildItem -LiteralPath $path -File).Count) files)" -ForegroundColor Green
} $Rid $Destination $Force
