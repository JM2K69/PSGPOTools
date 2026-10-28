#Requires -Version 7.4
<#
.SYNOPSIS
    Makes what a release publishes from the built module: the package of the PowerShell Gallery,
    its archive, the offline packages with the Avalonia runtime, and SHA256SUMS.
.DESCRIPTION
    Run by the Release workflow on the module the tests ran (the artifact of the build job of the
    CI), and locally to check a release. In -OutputPath, which must be empty:
    - HGPM/: the package of the PowerShell Gallery: the module without the Avalonia runtime, with
      LICENSE and NOTICE; signed when a certificate is given;
    - HGPM-<version>.zip: the same package, as an archive;
    - HGPM-<version>-<rid>.zip: the same with the Avalonia runtime of <rid> in Avalonia/bin/<rid>,
      for the computers without internet, its packages and files checked against those pinned;
    - SHA256SUMS: the SHA-256 of each file of the package (HGPM/...) and of each archive, as
      sha256sum writes them: the release attests them (GitHub artifact attestations).

    Signing (Windows): with -CertificatePath (a PFX with its private key) and
    -CertificatePassword, each .ps1, .psm1 and .psd1 of the package is signed with Authenticode
    and timestamped, then a catalog of the package (HGPM.cat) is made and signed: Test-FileCatalog
    checks every file of it.
.PARAMETER OutputPath
    The folder of the release, empty or not there.
.PARAMETER Rid
    The runtimes of the offline packages; win-x64, win-arm64, linux-x64 and linux-arm64 by default,
    none with @().
.PARAMETER CertificatePath
    A PFX of a code signing certificate; nothing is signed without it.
.PARAMETER CertificatePassword
    The password of the PFX.
.PARAMETER TimestampServer
    The timestamp server of the signatures (RFC 3161); none with ''.
.EXAMPLE
    ./CI/03_Build.ps1; ./CI/05_Package.ps1 -OutputPath ./release -Rid @()
    The package, its archive and SHA256SUMS, without offline packages nor signature.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$OutputPath,

    [ValidateSet('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx')]
    [string[]]$Rid = @('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64'),

    [string]$CertificatePath,

    [securestring]$CertificatePassword,

    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
# The module is imported to install the runtimes: not to read the PowerShell Gallery.
$env:PSGPOTOOLS_SKIP_UPDATE_CHECK = '1'
$root = Split-Path -Path $PSScriptRoot -Parent
$moduleName = 'HGPM'
$source = Join-Path $root $moduleName
if (-not (Test-Path -LiteralPath (Join-Path $source "$moduleName.psm1"))) { throw 'The module is not built: run CI/03_Build.ps1 first.' }
$data = Import-PowerShellDataFile -Path (Join-Path $source "$moduleName.psd1")
$prerelease = "$($data.PrivateData.PSData.Prerelease)".Trim()
$version = if ($prerelease) { "$($data.ModuleVersion)-$prerelease" } else { "$($data.ModuleVersion)" }

if (Test-Path -LiteralPath $OutputPath) {
    if (@(Get-ChildItem -LiteralPath $OutputPath -Force).Count) { throw "$OutputPath is not empty: give an empty folder, the release is made there." }
} else {
    $null = New-Item -ItemType Directory -Path $OutputPath
}
$OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path

# 1. The package: the module without the Avalonia runtime, with its license and its attribution
# (Apache License 2.0, section 4).
$package = Join-Path $OutputPath $moduleName
$null = New-Item -ItemType Directory -Path $package
Copy-Item -Path (Join-Path $source '*') -Destination $package -Recurse
Remove-Item -LiteralPath (Join-Path $package 'Avalonia' 'bin') -Recurse -Force -ErrorAction SilentlyContinue
foreach ($file in 'LICENSE', 'NOTICE') { Copy-Item -LiteralPath (Join-Path $root $file) -Destination $package }

# 2. The signature, when a certificate is given.
if ($CertificatePath) {
    if (-not $IsWindows) { throw 'Authenticode signatures and catalogs are made on Windows.' }
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath, $CertificatePassword)
    if (-not $certificate.HasPrivateKey) { throw "$CertificatePath has no private key: it cannot sign." }
    $sign = @{ Certificate = $certificate; HashAlgorithm = 'SHA256' }
    if ($TimestampServer) { $sign.TimestampServer = $TimestampServer }
    $scripts = @(Get-ChildItem -LiteralPath $package -Recurse -File | Where-Object Extension -In '.ps1', '.psm1', '.psd1')
    foreach ($file in $scripts) {
        $signature = Set-AuthenticodeSignature -LiteralPath $file.FullName @sign
        if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
            throw "$($file.Name) is not signed: $($signature.StatusMessage)"
        }
    }
    # The catalog of every file of the package, signed: Test-FileCatalog -CatalogFilePath HGPM.cat.
    $catalog = Join-Path $package "$moduleName.cat"
    $null = New-FileCatalog -Path $package -CatalogFilePath $catalog -CatalogVersion 2.0
    $signature = Set-AuthenticodeSignature -LiteralPath $catalog @sign
    if (-not $signature.SignerCertificate) { throw "The catalog is not signed: $($signature.StatusMessage)" }
    Write-Host "[PACKAGE] $($scripts.Count) scripts and the catalog signed by $($certificate.Subject)"
}

# 3. The archives: the package, then the package with the runtime of each RID.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archives = [System.Collections.Generic.List[string]]::new()
$archive = Join-Path $OutputPath "$moduleName-$version.zip"
[System.IO.Compression.ZipFile]::CreateFromDirectory($package, $archive, [System.IO.Compression.CompressionLevel]::Optimal, $true)
$archives.Add($archive)
if ($Rid.Count) {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-release-$([guid]::NewGuid().ToString('N'))"
    $module = Import-Module (Join-Path $package "$moduleName.psd1") -PassThru -Force
    try {
        foreach ($runtime in $Rid) {
            $bundle = Join-Path $work $runtime $moduleName
            $null = New-Item -ItemType Directory -Path $bundle -Force
            Copy-Item -Path (Join-Path $package '*') -Destination $bundle -Recurse
            # Its packages checked against their SHA-512, its files against their SHA-256.
            $null = & $module { param($Runtime, $Folder) Install-PSGPOAvaloniaRuntime -Rid $Runtime -Destination $Folder -Force } $runtime (Join-Path $bundle 'Avalonia' 'bin' $runtime)
            $archive = Join-Path $OutputPath "$moduleName-$version-$runtime.zip"
            [System.IO.Compression.ZipFile]::CreateFromDirectory($bundle, $archive, [System.IO.Compression.CompressionLevel]::Optimal, $true)
            $archives.Add($archive)
            Write-Host "[PACKAGE] $(Split-Path -Leaf $archive): $([math]::Round((Get-Item -LiteralPath $archive).Length / 1MB, 1)) MB"
        }
    } finally {
        Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 4. SHA256SUMS: each file of the package, then each archive, as sha256sum writes them.
$lines = [System.Collections.Generic.List[string]]::new()
$prefix = $OutputPath.TrimEnd('\', '/').Length + 1
$files = @(Get-ChildItem -LiteralPath $package -Recurse -File | ForEach-Object { $_.FullName.Substring($prefix) -replace '\\', '/' })
[Array]::Sort($files, [System.StringComparer]::Ordinal)
foreach ($name in @($files) + @($archives | ForEach-Object { Split-Path -Leaf $_ })) {
    $hash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes((Join-Path $OutputPath $name)))).ToLowerInvariant()
    $lines.Add("$hash  $name")
}
[System.IO.File]::WriteAllText((Join-Path $OutputPath 'SHA256SUMS'), (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host "[PACKAGE] $moduleName $version in ${OutputPath}: $($files.Count) files, $($archives.Count) archives, SHA256SUMS"
[pscustomobject]@{ Version = $version; Package = $package; Archives = $archives.ToArray(); Sums = Join-Path $OutputPath 'SHA256SUMS' }
