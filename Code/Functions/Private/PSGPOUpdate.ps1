<#
    Versions of HGPM, as semantic versions (0.1.4-alpha): the one loaded, and those of the PowerShell
    Gallery (Test-PSGPOUpdate). A prerelease comes before its release (0.1.4-alpha < 0.1.4), and the
    prereleases sort by their label (alpha < beta < rc).
#>

# A semantic version from the version and the prerelease label of a manifest or of the Gallery.
function ConvertTo-PSGPOSemanticVersion {
    [CmdletBinding()]
    [OutputType([semver])]
    param(
        [Parameter(Mandatory)] [version]$Version,
        [AllowNull()] [AllowEmptyString()] [string]$Prerelease
    )

    $label = "$Prerelease".Trim().TrimStart('-')
    [semver]::new($Version.Major, [Math]::Max($Version.Minor, 0), [Math]::Max($Version.Build, 0), $(if ($label) { $label } else { $null }))
}

# The version of the module loaded, and the folder it is loaded from.
function Get-PSGPOModuleVersion {
    [CmdletBinding()]
    param()

    # The manifest itself: while the module is imported, its PSModuleInfo has no version yet (0.0).
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'HGPM.psd1')
    [pscustomobject]@{
        Version = ConvertTo-PSGPOSemanticVersion -Version $manifest.ModuleVersion -Prerelease $manifest.PrivateData.PSData.Prerelease
        Path = $PSScriptRoot
    }
}

# The command that installs a newer version: Update-PSResource for a module installed from the
# repository, Install-PSResource otherwise (a copy of the repository, for instance).
function Get-PSGPOUpdateCommand {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$InstalledPath,
        [Parameter(Mandatory)] [semver]$Latest,
        [string]$Repository = 'PSGallery'
    )

    $fromRepository = $false
    try {
        $fromRepository = [bool](@(Get-InstalledPSResource -Name 'HGPM' -ErrorAction Stop) |
                Where-Object { $_.InstalledLocation -and $InstalledPath.StartsWith($_.InstalledLocation, [System.StringComparison]::OrdinalIgnoreCase) })
    } catch {
        Write-Verbose "The modules installed by PSResourceGet cannot be read: $($_.Exception.Message)"
    }
    '{0}-PSResource -Name HGPM{1}{2}' -f $(if ($fromRepository) { 'Update' } else { 'Install' }),
        $(if ($Latest.PreReleaseLabel) { ' -Prerelease' }), $(if ($Repository -ne 'PSGallery') { " -Repository $Repository" })
}

# Where the import of the module keeps what it last read of the PowerShell Gallery:
# <local data>/PSGPOTools/UpdateCheck.json.
function Get-PSGPOUpdateCheckPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $data = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $data) { $data = Join-Path $HOME '.local' 'share' }
    Join-Path $data 'PSGPOTools' 'UpdateCheck.json'
}

# The versions of HGPM listed on the PowerShell Gallery, read from its feed (a few seconds at
# most: the import does not wait for a slow network).
function Get-PSGPOGalleryVersion {
    [CmdletBinding()]
    [OutputType([semver])]
    param([int]$TimeoutSeconds = 8)

    $response = Invoke-WebRequest -Uri "https://www.powershellgallery.com/api/v2/FindPackagesById()?id=%27HGPM%27" -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
    $feed = [xml]$response.Content
    $namespaces = @{ m = 'http://schemas.microsoft.com/ado/2007/08/dataservices/metadata' }
    foreach ($node in @(Select-Xml -Xml $feed -XPath '//m:properties' -Namespace $namespaces | ForEach-Object Node)) {
        # An unlisted version is published in 1900.
        $published = [datetime]::MinValue
        if ([datetime]::TryParse("$($node.Published.InnerText)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$published) -and $published.Year -le 1900) { continue }
        $version = $null
        if ([semver]::TryParse("$($node.Version)", [ref]$version)) { $version }
    }
}

# The latest version of the Gallery for this version of HGPM (the prereleases count for a
# prerelease), read at most once a day: the answer is kept in UpdateCheck.json. $null when the
# Gallery cannot be read; that is kept for an hour, so that a computer without network does not
# wait for the Gallery at each import and each console.
function Get-PSGPOLatestGalleryVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [semver]$Installed,
        [TimeSpan]$MaxAge = [TimeSpan]::FromDays(1),
        [TimeSpan]$FailedMaxAge = [TimeSpan]::FromHours(1)
    )

    $path = Get-PSGPOUpdateCheckPath
    $cache = $null
    try { $cache = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $cache = $null }
    # ConvertFrom-Json gives the date of the check as a DateTime (its time zone kept), else a text.
    $checked = [datetime]::MinValue
    $known = if ($cache.Checked -is [datetime]) { $checked = $cache.Checked; $true }
        else { [datetime]::TryParse("$($cache.Checked)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$checked) }
    $fresh = $cache -and $known -and [datetime]::UtcNow - $checked.ToUniversalTime() -lt $(if ($cache.Failed) { $FailedMaxAge } else { $MaxAge })
    if (-not $fresh) {
        $failed = $false
        try {
            $versions = @(Get-PSGPOGalleryVersion)
        } catch {
            Write-Verbose "The PowerShell Gallery cannot be read: $($_.Exception.GetBaseException().Message)"
            $failed = $true
            $versions = @()
        }
        $cache = [pscustomobject]@{
            Checked = [datetime]::UtcNow.ToString('o')
            Failed = $failed
            Latest = "$($versions | Sort-Object -Descending | Select-Object -First 1)"
            LatestStable = "$($versions | Where-Object { -not $_.PreReleaseLabel } | Sort-Object -Descending | Select-Object -First 1)"
        }
        try {
            $null = New-Item -ItemType Directory -Path (Split-Path -Path $path -Parent) -Force -ErrorAction Stop
            Set-Content -LiteralPath $path -Value ($cache | ConvertTo-Json) -Encoding utf8 -ErrorAction Stop
        } catch {
            Write-Verbose "What the PowerShell Gallery has is not kept: $($_.Exception.Message)"
        }
    }
    if ($cache.Failed) { return $null }
    $latest = if ($Installed.PreReleaseLabel) { $cache.Latest } else { $cache.LatestStable }
    if ($latest) { [semver]$latest }
}

# The import does not read the Gallery: in a CI, in a non-interactive session, or with
# PSGPOTOOLS_SKIP_UPDATE_CHECK=1.
function Test-PSGPOUpdateCheckSkipped {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($env:PSGPOTOOLS_SKIP_UPDATE_CHECK -eq '1') { return $true }
    foreach ($name in 'CI', 'GITHUB_ACTIONS', 'TF_BUILD') { if ([Environment]::GetEnvironmentVariable($name)) { return $true } }
    if (-not [Environment]::UserInteractive) { return $true }
    [bool](@([Environment]::GetCommandLineArgs()) | Where-Object { $_ -match '^-(?i:noni|noninteractive)$' })
}

# What the import of the module says: its version, and the command that installs a newer one.
# Never fails the import.
function Write-PSGPOImportBanner {
    [CmdletBinding()]
    param()

    try {
        $installed = Get-PSGPOModuleVersion
        $message = "HGPM $($installed.Version)"
        if (-not (Test-PSGPOUpdateCheckSkipped)) {
            $latest = Get-PSGPOLatestGalleryVersion -Installed $installed.Version
            if ($latest -and $latest -gt $installed.Version) {
                $message += "`nHGPM $latest is available on the PowerShell Gallery: $(Get-PSGPOUpdateCommand -InstalledPath $installed.Path -Latest $latest), then open a new PowerShell session. (Test-PSGPOUpdate for the details; PSGPOTOOLS_SKIP_UPDATE_CHECK=1 skips this check.)"
            }
        }
        Write-Information -MessageData $message -InformationAction Continue
    } catch {
        Write-Verbose "The version of HGPM is not shown: $($_.Exception.Message)"
    }
}
