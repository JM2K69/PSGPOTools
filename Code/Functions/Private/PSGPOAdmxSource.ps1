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
    param(
        [Parameter(Mandatory)] [string]$Path,

        # The folders named after a culture, without looking for .adml files in each one: one
        # listing, for a central store read through the network.
        [switch]$NameOnly
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($folder in @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $culture = $null
        try { $culture = [cultureinfo]::GetCultureInfo($folder.Name) } catch { continue }
        if (-not $culture.Name) { continue }
        if ($NameOnly -or (Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.adml' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
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
        [cultureinfo]$Current = [cultureinfo]::CurrentUICulture,
        # See Get-PSGPOAdmxCulture.
        [switch]$NameOnly
    )

    $available = @(Get-PSGPOAdmxCulture -Path $Path -NameOnly:$NameOnly)
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

# The folders of $Path that hold .admx files, each once, as full paths.
function Select-PSGPOAdmxFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyCollection()] [string[]]$Path)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Path) {
        if (-not $item) { continue }
        $full = try { [System.IO.Path]::GetFullPath($item).TrimEnd('\', '/') } catch { continue }
        if (-not $seen.Add($full)) { continue }
        $hasAdmx = try { [bool](Get-ChildItem -LiteralPath $full -File -Filter '*.admx' -ErrorAction Stop | Select-Object -First 1) } catch { $false }
        if ($hasAdmx) { $full }
    }
}

# The ADMX files loaded by Initialize-PSGPOAdmx: their folder, their language, and whether the
# folder is a central store (the node Administrative Templates of the editor says it, as GPMC).
$script:PSGPOAdmxFolder = $null

# Is a PolicyDefinitions folder the central store of a domain, SYSVOL\<domain>\Policies\
# PolicyDefinitions: through its share (Windows), the share mounted (Linux) or on the disk of a
# Samba domain controller? A copy elsewhere is not.
function Test-PSGPOAdmxCentralStorePath {
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Path)

    "$Path".TrimEnd('\', '/') -match '[\\/][^\\/]+[\\/]Policies[\\/]PolicyDefinitions$'
}

# The central stores in the SYSVOL shares mounted on this computer (Linux: mount.cifs, Kerberos;
# New-PSGPOShareMount.sh //<dc>/sysvol): what is mounted (/proc/mounts), then what mounts itself
# when it is reached (/etc/fstab, x-systemd.automount), as <mount point>/<domain>/Policies/
# PolicyDefinitions. The SYSVOL of the domain controller given first.
function Get-PSGPOSysvolMountStore {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$DomainName,
        [string]$Server,
        # The lines of /proc/mounts, then of /etc/fstab (the tests give theirs).
        [string[]]$Mounts
    )

    if (-not $PSBoundParameters.ContainsKey('Mounts')) { $Mounts = @(Get-Content -LiteralPath '/proc/mounts', '/etc/fstab' -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^\s*#' }) }
    # A server by its full name or its short one: the first label is compared.
    $shortName = { param($Name) ("$Name" -split '\.')[0] }
    $first = [System.Collections.Generic.List[string]]::new()
    $others = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Mounts) {
        $fields = "$line".Trim() -split '\s+'
        if ($fields.Count -lt 3 -or $fields[2] -notin 'cifs', 'smb3') { continue }
        $source = [regex]::Match($fields[0], '^//([^/]+)/([^/]+)(?:/(.*))?$')
        if (-not $source.Success -or $source.Groups[2].Value -ne 'sysvol') { continue }
        # \040 is a space in /proc/mounts.
        $mountPoint = $fields[1] -replace '\\040', ' '
        # A part of the share mounted (//dc/sysvol/<domain>): the rest of the path below it.
        $mounted = @(($source.Groups[3].Value -replace '\\', '/').Split('/') | Where-Object { $_ })
        $domains = if ($mounted.Count) { @($mounted[0]) } elseif ($DomainName) { @($DomainName) }
            else { @(Get-ChildItem -LiteralPath $mountPoint -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }
        foreach ($domain in $domains) {
            if ($DomainName -and -not [string]::Equals($domain, $DomainName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $parts = @($domain, 'Policies', 'PolicyDefinitions')
            if ($mounted.Count -gt $parts.Count) { continue }
            $below = $true
            for ($index = 0; $index -lt $mounted.Count; $index++) {
                if (-not [string]::Equals($mounted[$index], $parts[$index], [System.StringComparison]::OrdinalIgnoreCase)) { $below = $false }
            }
            if (-not $below) { continue }
            $tail = @(if ($mounted.Count -lt $parts.Count) { $parts[$mounted.Count..($parts.Count - 1)] })
            $path = if ($tail.Count) { [System.IO.Path]::Combine([string[]](@($mountPoint) + $tail)) } else { $mountPoint }
            if ($Server -and (& $shortName $source.Groups[1].Value) -eq (& $shortName $Server)) { $first.Add($path) } else { $others.Add($path) }
        }
    }
    $first
    $others
}

# The central store of the domain, when it holds ADMX files, as GPMC uses it before the files of
# the computer: \\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions on a computer of the domain
# (Windows, the domain controllers Windows or Samba); on Linux, the SYSVOL share mounted
# (Get-PSGPOSysvolMountStore), then Policies/PolicyDefinitions in the SYSVOL of a Samba domain
# controller, which Samba gives to root and the administrators only.
function Get-PSGPOAdmxCentralStore {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The domain of the store (the domain the console shows); that of the computer by default.
        [string]$DomainName,

        # The domain controller the domain is read from: its SYSVOL first, when the name of the
        # domain does not resolve (Windows), its mounted SYSVOL first (Linux).
        [string]$Server,

        # The SYSVOL of Samba (a parameter for the tests).
        [string]$SambaSysvol = '/var/lib/samba/sysvol',

        # The lines of /proc/mounts and /etc/fstab (a parameter for the tests).
        [string[]]$Mounts
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    if ($IsWindows) {
        $domain = if ($DomainName) { $DomainName } else { (Get-PSGPOPlatform).DomainName }
        if ($domain -and $Server) { $paths.Add("\\$Server\SYSVOL\$domain\Policies\PolicyDefinitions") }
        if ($domain) { $paths.Add("\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions") }
    } else {
        $mount = @{ DomainName = $DomainName; Server = $Server }
        if ($PSBoundParameters.ContainsKey('Mounts')) { $mount.Mounts = $Mounts }
        foreach ($store in @(Get-PSGPOSysvolMountStore @mount)) { $paths.Add($store) }
        foreach ($sysvol in @(Get-ChildItem -LiteralPath $SambaSysvol -Directory -ErrorAction SilentlyContinue)) {
            if ($DomainName -and $sysvol.Name -ne $DomainName) { continue }
            $paths.Add((Join-Path $sysvol.FullName 'Policies' 'PolicyDefinitions'))
        }
    }
    Select-PSGPOAdmxFolder -Path $paths
}

# PolicyDefinitions folders found on this computer, the most relevant first: the central store of
# the domain, the folder chosen last, the folder of Windows, and the copy next to the module or of
# Install-PSGPOAdmx.
function Get-PSGPOAdmxCandidate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The central store found already (Get-PSGPOAdmxCentralStore), not looked for again.
        [AllowEmptyCollection()] [string[]]$CentralStore
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    if (-not $PSBoundParameters.ContainsKey('CentralStore')) { $CentralStore = @(Get-PSGPOAdmxCentralStore) }
    foreach ($store in $CentralStore) { $paths.Add($store) }
    $settings = Get-PSGPOUserSetting
    foreach ($last in $settings.PolicyDefinitions, $settings.AdmxFallback) { if ($last) { $paths.Add($last) } }
    if ($IsWindows -and $env:windir) { $paths.Add((Join-Path $env:windir 'PolicyDefinitions')) }
    foreach ($base in $PSScriptRoot, (Split-Path -Parent $PSScriptRoot)) {
        $paths.Add((Join-Path $base 'sources' 'PolicyDefinitions'))
    }
    # Those of Install-PSGPOAdmx in the data folder of the user.
    $paths.Add(@(Get-PSGPOAdmxInstallFolder)[-1])
    Select-PSGPOAdmxFolder -Path $paths
}

# The ADMX files the console loads without asking, the first time it needs them: as GPMC, the
# central store of the domain shown whenever it holds ADMX files; else the folder chosen last in
# the ADMX window (a folder, or the central store of another domain); else the folder chosen while
# no store was reached (AdmxFallback). In the language chosen last when the folder has it, else in
# the one of the session (Resolve-PSGPOAdmxCulture: else the same language, else en-US...), else
# en-US. Path is $null when there is none, or when the last load of the console failed
# (AdmxFailed): the ADMX window asks then, with the central stores found (CentralStore).
function Get-PSGPOAdmxStartSource {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # The domain shown, for its central store; that of the computer by default.
        [string]$DomainName,

        # The domain controller it is read from (Get-PSGPOAdmxCentralStore).
        [string]$Server
    )

    $source = @{ Path = $null; UICulture = $null; CentralStore = $null }
    $settings = Get-PSGPOUserSetting
    # The language of a folder by the names of its language folders (one listing through the
    # network), then one listing of the folder chosen: the .adml files are read by the load.
    $languageOf = {
        param([string]$Path)
        $names = @(Get-PSGPOAdmxCulture -Path $Path -NameOnly)
        $culture = $null
        if ($settings.UICulture) { $culture = @($names | Where-Object { $_ -eq "$($settings.UICulture)" })[0] }
        if (-not $culture) { $culture = try { (Resolve-PSGPOAdmxCulture -Path $Path -NameOnly).Culture } catch { $null } }
        $hasAdml = { param($Name) [bool](Get-ChildItem -LiteralPath (Join-Path $Path $Name) -File -Filter '*.adml' -ErrorAction SilentlyContinue | Select-Object -First 1) }
        if ($culture -and -not (& $hasAdml $culture)) { $culture = @($names | Where-Object { $_ -eq 'en-US' -and (& $hasAdml $_) })[0] }
        $culture
    }

    $take = {
        param([string]$Path)
        $culture = & $languageOf $Path
        if ($culture) { $source.Path = $Path; $source.UICulture = $culture }
        [bool]$culture
    }
    $source.CentralStore = @(Get-PSGPOAdmxCentralStore -DomainName $DomainName -Server $Server)
    if ($settings.AdmxFailed) { return $source }
    foreach ($store in $source.CentralStore) { if (& $take $store) { return $source } }
    $saved = if ($settings.PolicyDefinitions) { @(Select-PSGPOAdmxFolder -Path "$($settings.PolicyDefinitions)")[0] }
    if ($saved -and (& $take $saved)) { return $source }
    $fallback = if ($settings.AdmxFallback) { @(Select-PSGPOAdmxFolder -Path "$($settings.AdmxFallback)")[0] }
    if ($fallback -and (& $take $fallback)) { return $source }
    $source
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
