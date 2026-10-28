<#
    The Avalonia runtime of the window, installed on first use: the NuGet packages of
    Resources/AvaloniaPackages.json for the runtime of this computer (win-x64, linux-arm64...),
    downloaded from nuget.org (or PSGPOTOOLS_NUGET_SOURCE), each checked against its pinned
    SHA-512 before anything is extracted, then put in place at once.

    Where: the Avalonia\bin\<rid> folder of the module when it can be written to, else the data
    folder of the user (%LOCALAPPDATA% on Windows, ~/.local/share on Linux), so that a module
    installed for all users needs no administrator. PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1 forbids the
    download (computers without internet: the offline package of a release has the runtime, or run
    HGPM/Avalonia/Get-AvaloniaBinaries.ps1 on a computer with it, then copy the folder).

    Each file of the runtime has its SHA-256 pinned too (Files of AvaloniaPackages.json, written by
    CI/Update-AvaloniaFiles.ps1): checked when it is installed and each time the console loads it,
    with no other library in its folder. A runtime whose files changed, in a folder others can
    write to, is never loaded.
#>

function Get-PSGPOAvaloniaPackageData {
    [CmdletBinding()]
    param()

    if (-not $script:PSGPOAvaloniaPackages) {
        $script:PSGPOAvaloniaPackages = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Resources' 'AvaloniaPackages.json') -Raw | ConvertFrom-Json
    }
    $script:PSGPOAvaloniaPackages
}

function Get-PSGPOAvaloniaPackage {
    [CmdletBinding()]
    param()

    (Get-PSGPOAvaloniaPackageData).Packages
}

# The files of the runtime of a RID and their SHA-256 (hexadecimal), by name: what the pinned
# packages give. Empty when none is pinned for the RID.
function Get-PSGPOAvaloniaFileHash {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string]$Rid)

    $hashes = @{}
    $files = (Get-PSGPOAvaloniaPackageData).Files
    if ($files -and $files.PSObject.Properties[$Rid]) {
        foreach ($property in $files.$Rid.PSObject.Properties) { $hashes[$property.Name] = "$($property.Value)" }
    }
    $hashes
}

# The runtime of a folder is the one pinned: each of its files there with its SHA-256, and no other
# library (.dll, .so, .dylib) the loader could pick up next to them. Throws what differs.
function Assert-PSGPOAvaloniaRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Rid
    )

    $expected = Get-PSGPOAvaloniaFileHash -Rid $Rid
    if (-not $expected.Count) { throw "No file of the Avalonia runtime is pinned for $Rid (Files of AvaloniaPackages.json)." }
    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($expected.Keys | Sort-Object)) {
        $file = Join-Path $Path $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $problems.Add("$name is missing"); continue }
        $hash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($file)))
        if ($hash -ne $expected[$name]) { $problems.Add("$name differs") }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Force | Where-Object { $_.Extension -in '.dll', '.so', '.dylib' -and -not $expected.ContainsKey($_.Name) })) {
        $problems.Add("$($file.Name) is not part of it")
    }
    if ($problems.Count) {
        throw "The Avalonia runtime in $Path is not the one HGPM pinned ($($problems -join '; ')): nothing of it is loaded. Delete the folder, the console installs it again, checked."
    }
}

# The folders where the runtime of a RID can be: the module, then the data folder of the user.
function Get-PSGPOAvaloniaFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Rid)

    Join-Path $PSScriptRoot 'Avalonia' 'bin' $Rid
    $data = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $data) { $data = Join-Path $HOME '.local' 'share' }
    $version = (Get-PSGPOAvaloniaPackage | Where-Object Id -EQ 'Avalonia').Version
    Join-Path $data 'PSGPOTools' 'Avalonia' $version $Rid
}

# The folder holding the runtime of this computer, $null when it is not installed.
function Get-PSGPOAvaloniaPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Rid = (Get-PSGPOAvaloniaRid))

    Get-PSGPOAvaloniaFolder -Rid $Rid | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'Avalonia.dll') -PathType Leaf } | Select-Object -First 1
}

# Where the packages come from, as a text for the messages: nuget.org, or PSGPOTOOLS_NUGET_SOURCE.
function Get-PSGPONuGetSource {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $source = "$env:PSGPOTOOLS_NUGET_SOURCE".Trim()
    if ($source) { $source } else { 'https://api.nuget.org/v3-flatcontainer/' }
}

# Saves a pinned package in $OutFile, from nuget.org or PSGPOTOOLS_NUGET_SOURCE: a NuGet v3 feed
# (its index.json, or the base address of its packages, .../v3-flatcontainer/), or a folder of
# .nupkg files (a share of the network, for computers without internet), flat or as a feed lays
# them out (<id>/<version>/<id>.<version>.nupkg). A download is tried three times, two minutes
# each: a mirror or a proxy fails now and then. Whatever the source, the caller checks the package
# against its pinned SHA-512. Returns where it came from.
function Save-PSGPONuGetPackage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Package,
        [Parameter(Mandatory)] [string]$OutFile
    )

    $id = $Package.Id.ToLowerInvariant()
    $version = $Package.Version.ToLowerInvariant()
    $name = "$id.$version.nupkg"
    $source = Get-PSGPONuGetSource
    if ($source -notmatch '^https?://') {
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "PSGPOTOOLS_NUGET_SOURCE is neither an address nor a folder: $source" }
        # Any case: the names of the packages keep theirs (Avalonia.11.2.3.nupkg).
        $found = @(Get-ChildItem -LiteralPath $source -Filter '*.nupkg' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $name }) | Select-Object -First 1
        if (-not $found) { throw "$($Package.Id) $($Package.Version) is not in $source ($name)." }
        Copy-Item -LiteralPath $found.FullName -Destination $OutFile -Force
        return $found.FullName
    }
    for ($attempt = 1; ; $attempt++) {
        try {
            $base = $source
            # A service index: the base address of its packages (PackageBaseAddress/3.0.0).
            if ($source -match 'index\.json$') {
                $index = Invoke-RestMethod -Uri $source -TimeoutSec 120 -ErrorAction Stop
                $base = @($index.resources | Where-Object { "$($_.'@type')" -like 'PackageBaseAddress/3.0.0*' } | ForEach-Object { $_.'@id' }) | Select-Object -First 1
                if (-not $base) { throw "$source gives no base address of packages (PackageBaseAddress/3.0.0)." }
            }
            $uri = '{0}/{1}/{2}/{3}' -f $base.TrimEnd('/'), $id, $version, $name
            Invoke-WebRequest -Uri $uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
            return $uri
        } catch {
            if ($attempt -ge 3) { throw "$($Package.Id) $($Package.Version) cannot be downloaded from ${source}: $($_.Exception.Message)" }
            Write-Verbose "$($Package.Id) $($Package.Version) not downloaded (attempt $attempt of 3): $($_.Exception.Message)"
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

# Downloads, checks and installs the runtime of a RID; returns its folder.
function Install-PSGPOAvaloniaRuntime {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx')]
        [string]$Rid = (Get-PSGPOAvaloniaRid),

        # Where to install; by default the module when it can be written to, else the user folder.
        [string]$Destination,

        [switch]$Force,

        # The files are not checked against their pinned SHA-256: only to pin them
        # (CI/Update-AvaloniaFiles.ps1); the packages are checked all the same.
        [switch]$NoFileCheck
    )

    if ($env:PSGPOTOOLS_AVALONIA_NO_DOWNLOAD -eq '1') {
        throw "The Avalonia runtime ($Rid) is not installed and PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1 forbids its download: take the offline package of the release for $Rid, or run HGPM/Avalonia/Get-AvaloniaBinaries.ps1 -Rid $Rid on a computer with internet, then copy its bin\$Rid folder to $(@(Get-PSGPOAvaloniaFolder -Rid $Rid)[0])."
    }
    if (-not $Destination) {
        foreach ($candidate in @(Get-PSGPOAvaloniaFolder -Rid $Rid)) {
            $parent = Split-Path -Parent $candidate
            try {
                $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
                $probe = Join-Path $parent ".write-$([guid]::NewGuid())"
                [System.IO.File]::WriteAllText($probe, '')
                Remove-Item -LiteralPath $probe -Force
                $Destination = $candidate
                break
            } catch {
                Write-Verbose "Not writable: $parent"
            }
        }
        if (-not $Destination) { throw "No folder to install the Avalonia runtime in: neither the module nor the data folder of the user can be written to." }
    }
    if ((Test-Path -LiteralPath (Join-Path $Destination 'Avalonia.dll')) -and -not $Force) { return $Destination }

    $packages = @(Get-PSGPOAvaloniaPackage | Where-Object { $_.Rids -contains $Rid })
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-Avalonia-$([guid]::NewGuid())"
    $staging = Join-Path $work 'staging'
    $null = New-Item -ItemType Directory -Path $staging -Force
    try {
        $index = 0
        foreach ($package in $packages) {
            $index++
            $id = $package.Id.ToLowerInvariant()
            Write-Progress -Activity "Installing the Avalonia runtime ($Rid)" -Status "$($package.Id) $($package.Version)" -PercentComplete ([int](100 * $index / $packages.Count))
            $file = Join-Path $work "$id.nupkg"
            $from = Save-PSGPONuGetPackage -Package $package -OutFile $file
            # Nothing is extracted from a package that is not the one pinned.
            $hash = [Convert]::ToBase64String([System.Security.Cryptography.SHA512]::HashData([System.IO.File]::ReadAllBytes($file)))
            if ($hash -ne $package.Sha512) { throw "$($package.Id) $($package.Version) of $from is not the package expected (SHA-512 differs): nothing is installed." }
            $extracted = Join-Path $work $id
            Expand-Archive -LiteralPath $file -DestinationPath $extracted -Force
            if ($package.Assets -in 'Managed', 'Both') {
                $lib = foreach ($framework in 'net8.0', 'net6.0', 'net5.0', 'netstandard2.0') {
                    $path = Join-Path $extracted 'lib' $framework
                    if (Test-Path -LiteralPath $path) { $path; break }
                }
                if (-not $lib) { throw "$($package.Id) has no assembly for .NET 8." }
                Get-ChildItem -LiteralPath $lib -Filter '*.dll' -File | Copy-Item -Destination $staging -Force
            }
            if ($package.Assets -in 'Native', 'Both') {
                $native = Join-Path $extracted 'runtimes' $Rid 'native'
                if (Test-Path -LiteralPath $native) { Get-ChildItem -LiteralPath $native -File | Copy-Item -Destination $staging -Force }
                elseif ($package.Assets -eq 'Native') { throw "$($package.Id) has no native library for $Rid." }
            }
        }
        Write-Progress -Activity "Installing the Avalonia runtime ($Rid)" -Completed
        if (-not $NoFileCheck) { Assert-PSGPOAvaloniaRuntime -Path $staging -Rid $Rid }
        # In place at once: a download that failed leaves nothing half installed.
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force
        Move-Item -LiteralPath $staging -Destination $Destination
        @($packages | ForEach-Object { [ordered]@{ Id = $_.Id; Version = $_.Version; Sha512 = $_.Sha512 } }) | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $Destination 'packages.json') -Encoding utf8
        Write-Verbose "Avalonia runtime ($Rid) installed in $Destination."
        $Destination
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
