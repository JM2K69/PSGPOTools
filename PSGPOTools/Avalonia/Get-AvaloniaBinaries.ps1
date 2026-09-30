<#
.SYNOPSIS
    Downloads and stages the Avalonia UI assemblies needed to run Show-GPOManagerAvalonia,
    without requiring the .NET SDK, NuGet.exe or a compiled host project.
.DESCRIPTION
    Fetches the exact set of NuGet packages Avalonia needs for a given runtime identifier
    (win-x64, linux-x64, osx) directly from nuget.org's flat-container API, extracts the
    managed assemblies (lib\net8.0) and native binaries (runtimes\<rid>\native), and flattens
    them into a single folder so they can be loaded at runtime with
    [System.Reflection.Assembly]::LoadFrom() - the same approach documented at
    https://www.deploymentresearch.com/using-avalonia-ui-in-deployr-task-sequences/

    Run this once per target platform. The resulting folder (Avalonia\bin\<rid>) is not
    committed to source control; ship it alongside the module or run this script as part
    of your deployment/CI pipeline.
.PARAMETER Destination
    Root folder that will contain one sub-folder per runtime identifier. Defaults to
    ".\bin" next to this script.
.PARAMETER Rid
    Target runtime identifier: win-x64, win-arm64, linux-x64, linux-arm64 or osx.
    Defaults to the RID of the machine running this script.
.PARAMETER AvaloniaVersion
    Avalonia package version. Must match across Avalonia.* and Avalonia.Markup.Xaml.Loader.
.EXAMPLE
    .\Get-AvaloniaBinaries.ps1 -Rid win-x64
.EXAMPLE
    .\Get-AvaloniaBinaries.ps1 -Rid linux-x64 -Destination C:\Temp\Avalonia
#>
[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $PSScriptRoot 'bin'),

    [ValidateSet('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx')]
    [string]$Rid = $(
        if ($IsWindows -or $null -eq $IsWindows) {
            if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'win-arm64' } else { 'win-x64' }
        } elseif ($IsLinux) {
            if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'linux-arm64' } else { 'linux-x64' }
        } else {
            'osx'
        }
    ),

    [string]$AvaloniaVersion = '11.2.3',
    [string]$SkiaVersion = '2.88.9',
    [string]$HarfBuzzVersion = '7.3.0.3',
    [string]$MicroComVersion = '0.11.0',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$DestForRid = Join-Path $Destination $Rid
if ((Test-Path $DestForRid) -and -not $Force) {
    Write-Host "[Avalonia] $DestForRid already exists. Use -Force to redownload." -ForegroundColor Yellow
    return
}
New-Item -ItemType Directory -Path $DestForRid -Force | Out-Null

$Work = Join-Path ([System.IO.Path]::GetTempPath()) "psgpotools-avalonia-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $Work -Force | Out-Null

function Get-NugetPackage {
    param([string]$Id, [string]$Version)

    $Id = $Id.ToLowerInvariant()
    $Url = "https://api.nuget.org/v3-flatcontainer/$Id/$Version/$Id.$Version.nupkg"
    $ZipPath = Join-Path $Work "$Id.zip"
    $ExtractPath = Join-Path $Work $Id

    Write-Host "[Avalonia] Downloading $Id $Version" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force
    return $ExtractPath
}

function Copy-ManagedAssembly {
    param([string]$PackagePath)

    # Prefer the newest TFM actually shipped, falling back for the small support packages.
    foreach ($tfm in @('net8.0', 'net6.0', 'net5.0', 'netstandard2.0')) {
        $libPath = Join-Path $PackagePath "lib\$tfm"
        if (Test-Path $libPath) {
            Get-ChildItem -Path $libPath -Filter '*.dll' -File | Copy-Item -Destination $DestForRid -Force
            return
        }
    }
    Write-Warning "No compatible lib\* folder found under $PackagePath"
}

function Copy-NativeAssets {
    param([string]$PackagePath, [string[]]$RuntimeFolders)

    foreach ($rf in $RuntimeFolders) {
        $nativePath = Join-Path $PackagePath "runtimes\$rf\native"
        if (Test-Path $nativePath) {
            Get-ChildItem -Path $nativePath -File | Copy-Item -Destination $DestForRid -Force
            return
        }
    }
}

# --- Managed packages common to every platform ---------------------------------
$common = @(
    'Avalonia',
    'Avalonia.Desktop',
    'Avalonia.Themes.Fluent',
    'Avalonia.Skia',
    'Avalonia.Markup.Xaml.Loader',
    'Avalonia.Remote.Protocol',
    'Avalonia.Controls.DataGrid'
)
foreach ($pkg in $common) {
    Copy-ManagedAssembly (Get-NugetPackage -Id $pkg -Version $AvaloniaVersion)
}
Copy-ManagedAssembly (Get-NugetPackage -Id 'MicroCom.Runtime' -Version $MicroComVersion)
Copy-ManagedAssembly (Get-NugetPackage -Id 'SkiaSharp' -Version $SkiaVersion)
Copy-ManagedAssembly (Get-NugetPackage -Id 'HarfBuzzSharp' -Version $HarfBuzzVersion)

# --- Platform-specific windowing backend + native rendering libraries ----------
switch -Wildcard ($Rid) {
    'win-*' {
        Copy-ManagedAssembly (Get-NugetPackage -Id 'Avalonia.Win32' -Version $AvaloniaVersion)
        Copy-NativeAssets (Get-NugetPackage -Id 'SkiaSharp.NativeAssets.Win32' -Version $SkiaVersion) @($Rid)
        Copy-NativeAssets (Get-NugetPackage -Id 'HarfBuzzSharp.NativeAssets.Win32' -Version $HarfBuzzVersion) @($Rid)
    }
    'linux-*' {
        Copy-ManagedAssembly (Get-NugetPackage -Id 'Avalonia.X11' -Version $AvaloniaVersion)
        Copy-ManagedAssembly (Get-NugetPackage -Id 'Avalonia.FreeDesktop' -Version $AvaloniaVersion)
        Copy-NativeAssets (Get-NugetPackage -Id 'SkiaSharp.NativeAssets.Linux' -Version $SkiaVersion) @($Rid)
        Copy-NativeAssets (Get-NugetPackage -Id 'HarfBuzzSharp.NativeAssets.Linux' -Version $HarfBuzzVersion) @($Rid)
    }
    'osx' {
        Copy-ManagedAssembly (Get-NugetPackage -Id 'Avalonia.Native' -Version $AvaloniaVersion)
        # Avalonia.Native ships its own libAvaloniaNative.dylib under runtimes\osx\native.
        Copy-NativeAssets (Join-Path $Work 'avalonia.native') @('osx')
        Copy-NativeAssets (Get-NugetPackage -Id 'SkiaSharp.NativeAssets.macOS' -Version $SkiaVersion) @('osx')
        Copy-NativeAssets (Get-NugetPackage -Id 'HarfBuzzSharp.NativeAssets.macOS' -Version $HarfBuzzVersion) @('osx')
    }
}

Remove-Item -Path $Work -Recurse -Force -ErrorAction SilentlyContinue

$dllCount = (Get-ChildItem -Path $DestForRid -File).Count
Write-Host "[Avalonia] Staged $dllCount files for $Rid in $DestForRid" -ForegroundColor Green
