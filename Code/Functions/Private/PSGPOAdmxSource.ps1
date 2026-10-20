<#
    Where the ADMX files come from: a PolicyDefinitions folder (the .admx files, and one folder
    per language named after its culture, en-US, fr-FR..., with the .adml files), the languages
    it has, the language to load, and the folders found on this computer. The folder and the
    language chosen last are remembered for the next time (settings.json of the user).
#>

# Languages of a PolicyDefinitions folder: the names of its sub-folders holding .adml files.
function Get-PSGPOAdmxCulture {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($folder in @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $culture = $null
        try { $culture = [cultureinfo]::GetCultureInfo($folder.Name) } catch { continue }
        if (-not $culture.Name) { continue }
        if (Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.adml' -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $folder.Name
        }
    }
}

# Language to load from a folder: the one asked for, else the language of the session (its exact
# culture, then the same language in another country), else en-US, else the only one there is.
# Culture is $null when the folder has several languages and none of them can be chosen.
function Resolve-PSGPOAdmxCulture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$Requested,
        [cultureinfo]$Current = [cultureinfo]::CurrentUICulture
    )

    $available = @(Get-PSGPOAdmxCulture -Path $Path)
    if (-not $available.Count) { throw "No language folder with .adml files in '$Path' (en-US, fr-FR...): is it a PolicyDefinitions folder?" }
    $pick = {
        param([string]$Name)
        $available | Where-Object { [string]::Equals($_, $Name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    }
    if ($Requested) {
        $found = & $pick $Requested
        if (-not $found) { throw "No '$Requested' language folder in '$Path': $($available -join ', ')." }
        return [pscustomobject]@{ Culture = $found; Available = $available }
    }
    $found = $null
    if ($Current -and $Current.Name) {
        $found = & $pick $Current.Name
        if (-not $found) {
            $found = $available | Where-Object { ([cultureinfo]::GetCultureInfo($_)).TwoLetterISOLanguageName -eq $Current.TwoLetterISOLanguageName } | Select-Object -First 1
        }
    }
    if (-not $found) { $found = & $pick 'en-US' }
    if (-not $found -and $available.Count -eq 1) { $found = $available[0] }
    [pscustomobject]@{ Culture = $found; Available = $available }
}

# PolicyDefinitions folders found on this computer, the most relevant first: the central store of
# the domain (Windows), the folder chosen last, the folder of Windows, the SYSVOL of a Samba
# domain controller when readable, and the copy next to the module or of Install-PSGPOAdmx.
function Get-PSGPOAdmxCandidate {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $paths = [System.Collections.Generic.List[string]]::new()
    $platform = Get-PSGPOPlatform
    if ($IsWindows -and $platform.DomainName) {
        $paths.Add("\\$($platform.DomainName)\SYSVOL\$($platform.DomainName)\Policies\PolicyDefinitions")
    }
    $last = (Get-PSGPOUserSetting).PolicyDefinitions
    if ($last) { $paths.Add($last) }
    if ($IsWindows -and $env:windir) { $paths.Add((Join-Path $env:windir 'PolicyDefinitions')) }
    if (-not $IsWindows) {
        foreach ($sysvol in @(Get-ChildItem -LiteralPath '/var/lib/samba/sysvol' -Directory -ErrorAction SilentlyContinue)) {
            $paths.Add((Join-Path $sysvol.FullName 'Policies' 'PolicyDefinitions'))
        }
    }
    foreach ($base in $PSScriptRoot, (Split-Path -Parent $PSScriptRoot)) {
        $paths.Add((Join-Path $base 'sources' 'PolicyDefinitions'))
    }
    # Those of Install-PSGPOAdmx in the data folder of the user.
    $paths.Add(@(Get-PSGPOAdmxInstallFolder)[-1])

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $paths) {
        $full = try { [System.IO.Path]::GetFullPath($path).TrimEnd('\', '/') } catch { continue }
        if (-not $seen.Add($full)) { continue }
        $hasAdmx = try { [bool](Get-ChildItem -LiteralPath $full -File -Filter '*.admx' -ErrorAction Stop | Select-Object -First 1) } catch { $false }
        if ($hasAdmx) { $full }
    }
}

# Settings of the user kept between sessions: <config>/PSGPOTools/settings.json (~/.config on
# Linux, %APPDATA% on Windows). Unreadable settings are as no settings.
function Get-PSGPOUserSettingPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:PSGPOTOOLS_SETTINGS_PATH) { return $env:PSGPOTOOLS_SETTINGS_PATH }
    $config = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    if (-not $config) { $config = Join-Path $HOME '.config' }
    Join-Path $config 'PSGPOTools' 'settings.json'
}

function Get-PSGPOUserSetting {
    [CmdletBinding()]
    param()

    $path = Get-PSGPOUserSettingPath
    $settings = @{}
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $read = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($read -is [hashtable]) { $settings = $read }
        } catch {
            Write-Verbose "Settings $path ignored: $($_.Exception.Message)"
        }
    }
    $settings
}

function Set-PSGPOUserSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable]$Values)

    $path = Get-PSGPOUserSettingPath
    $settings = Get-PSGPOUserSetting
    foreach ($name in $Values.Keys) { $settings[$name] = $Values[$name] }
    if (-not $PSCmdlet.ShouldProcess($path, 'Save the settings')) { return }
    try {
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force -ErrorAction Stop
        $settings | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8 -ErrorAction Stop
    } catch {
        Write-Verbose "Settings not saved in ${path}: $($_.Exception.Message)"
    }
}
