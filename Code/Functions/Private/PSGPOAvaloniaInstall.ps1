<#
    The Avalonia runtime of the window, installed on first use: the NuGet packages of
    Resources/AvaloniaPackages.json for the runtime of this computer (win-x64, linux-arm64...),
    downloaded from nuget.org, each checked against its pinned SHA-512 before anything is
    extracted, then put in place at once.

    Where: the Avalonia\bin\<rid> folder of the module when it can be written to, else the data
    folder of the user (%LOCALAPPDATA% on Windows, ~/.local/share on Linux), so that a module
    installed for all users needs no administrator. PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1 forbids the
    download (computers without internet: run PSGPOTools/Avalonia/Get-AvaloniaBinaries.ps1 on a
    computer with it, then copy the folder).
#>

function Get-PSGPOAvaloniaPackage {
    [CmdletBinding()]
    param()

    if (-not $script:PSGPOAvaloniaPackages) {
        $script:PSGPOAvaloniaPackages = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Resources' 'AvaloniaPackages.json') -Raw | ConvertFrom-Json
    }
    $script:PSGPOAvaloniaPackages.Packages
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

# Downloads, checks and installs the runtime of a RID; returns its folder.
function Install-PSGPOAvaloniaRuntime {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx')]
        [string]$Rid = (Get-PSGPOAvaloniaRid),

        # Where to install; by default the module when it can be written to, else the user folder.
        [string]$Destination,

        [switch]$Force
    )

    if ($env:PSGPOTOOLS_AVALONIA_NO_DOWNLOAD -eq '1') {
        throw "The Avalonia runtime ($Rid) is not installed and PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1 forbids its download: run PSGPOTools/Avalonia/Get-AvaloniaBinaries.ps1 -Rid $Rid on a computer with internet, then copy its bin\$Rid folder to $(@(Get-PSGPOAvaloniaFolder -Rid $Rid)[0])."
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
            Invoke-WebRequest -Uri "https://api.nuget.org/v3-flatcontainer/$id/$($package.Version)/$id.$($package.Version).nupkg" -OutFile $file -UseBasicParsing -ErrorAction Stop
            # Nothing is extracted from a package that is not the one pinned.
            $hash = [Convert]::ToBase64String([System.Security.Cryptography.SHA512]::HashData([System.IO.File]::ReadAllBytes($file)))
            if ($hash -ne $package.Sha512) { throw "$($package.Id) $($package.Version) downloaded from nuget.org is not the package expected (SHA-512 differs): nothing is installed." }
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
