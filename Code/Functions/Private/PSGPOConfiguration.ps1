<#
    Configuration of PSGPOTools: Resources/Configuration.psd1 of the module (every key, with its
    default), then the Configuration.psd1 of the user, which only holds the keys it changes:
    in the configuration folder of the user, or at PSGPOTOOLS_CONFIGURATION_PATH. Both are read
    as data (Import-PowerShellDataFile), never run. A configuration of the user that cannot be
    read or holds a wrong value is reported and left out: the defaults apply.
#>

function Get-PSGPOConfigurationPath {
    [CmdletBinding()]
    param()

    $user = if ($env:PSGPOTOOLS_CONFIGURATION_PATH) { $env:PSGPOTOOLS_CONFIGURATION_PATH } else {
        $config = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
        if (-not $config) { $config = Join-Path $HOME '.config' }
        Join-Path $config 'PSGPOTools' 'Configuration.psd1'
    }
    [pscustomobject]@{ Default = Join-Path $PSScriptRoot 'Resources' 'Configuration.psd1'; User = $user }
}

# The values of $Override over those of $Base, key by key, nested tables included.
function Merge-PSGPOConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [hashtable]$Base,
        [Parameter(Mandatory)] [hashtable]$Override,
        [string]$Path = ''
    )

    $result = @{}
    foreach ($key in $Base.Keys) { $result[$key] = $Base[$key] }
    foreach ($key in $Override.Keys) {
        if (-not $Base.ContainsKey($key)) { throw "Unknown setting $Path$key." }
        if ($Base[$key] -is [hashtable]) {
            if ($Override[$key] -isnot [hashtable]) { throw "$Path$key must be a table (@{ ... })." }
            $result[$key] = Merge-PSGPOConfiguration -Base $Base[$key] -Override $Override[$key] -Path "$Path$key."
        } else {
            $result[$key] = $Override[$key]
        }
    }
    $result
}

# Wrong values of a configuration: their messages.
function Test-PSGPOConfiguration {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [hashtable]$Configuration)

    $newGpo = $Configuration.NewGpo
    $groups = $newGpo.SecurityFilteringGroups
    if ($newGpo.Status -notin 'Enabled', 'ComputerOnly', 'UserOnly') { "NewGpo.Status must be Enabled, ComputerOnly or UserOnly, not '$($newGpo.Status)'." }
    if ("$($newGpo.DefaultName)".Trim() -eq '') { 'NewGpo.DefaultName must not be empty.' }
    if ($groups.Create -isnot [bool]) { 'NewGpo.SecurityFilteringGroups.Create must be $true or $false.' }
    if ($groups.Scope -notin 'Global', 'DomainLocal', 'Universal') { "NewGpo.SecurityFilteringGroups.Scope must be Global, DomainLocal or Universal, not '$($groups.Scope)'." }
    foreach ($name in 'ApplyPrefix', 'DenyPrefix') {
        $prefix = "$($groups[$name])"
        if (-not $prefix -or $prefix -match '["/\\\[\]:;|=,+*?<>@]') { "NewGpo.SecurityFilteringGroups.$name must not be empty, nor hold a character a group name cannot hold." }
    }
    if ($groups.ApplyPrefix -eq $groups.DenyPrefix) { 'NewGpo.SecurityFilteringGroups.ApplyPrefix and DenyPrefix must differ.' }
    foreach ($name in 'ApprovedLabel', 'TemplateLabel') {
        $label = "$($Configuration.Backup[$name])".Trim()
        if (-not $label -or $label.Length -gt 64 -or $label -match '[,\r\n\t]') { "Backup.$name must not be empty, and has at most 64 characters, without comma, tab or line break." }
    }
    if ("$($Configuration.Backup.ApprovedLabel)".Trim() -eq "$($Configuration.Backup.TemplateLabel)".Trim()) { 'Backup.ApprovedLabel and TemplateLabel must differ.' }
    if ($groups.Container -and "$($groups.Container)" -notmatch '^(?:(?:OU|CN)=[^,]+)(?:,(?:OU|CN|DC)=[^,]+)*$') { "NewGpo.SecurityFilteringGroups.Container is not a distinguished name: '$($groups.Container)'." }
}

# The configuration in use: the defaults, with the configuration of the user over them.
function Get-PSGPOConfigurationData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $paths = Get-PSGPOConfigurationPath
    $configuration = Import-PowerShellDataFile -LiteralPath $paths.Default
    if (Test-Path -LiteralPath $paths.User -PathType Leaf) {
        try {
            $merged = Merge-PSGPOConfiguration -Base $configuration -Override (Import-PowerShellDataFile -LiteralPath $paths.User -ErrorAction Stop)
            $problems = @(Test-PSGPOConfiguration -Configuration $merged)
            if ($problems.Count) { throw ($problems -join ' ') }
            $configuration = $merged
        } catch {
            Write-Warning "The configuration $($paths.User) is not used: $($_.Exception.Message)"
        }
    }
    $configuration
}

# The container of the security filtering groups for a directory: the configuration, made a
# distinguished name of the domain, else the users container.
function Resolve-PSGPOGroupContainer {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [AllowEmptyString()] [string]$Container
    )

    if (-not $Container) { return $Directory.GetUsersContainer() }
    if ($Container -match '(?i)(?:^|,)DC=') { return $Container }
    "$Container,$($Directory.Domain.DistinguishedName)"
}

# The values a setting can take, for the settings whose values are a list.
$script:PSGPOConfigurationChoices = @{
    'NewGpo.Status' = @('Enabled', 'ComputerOnly', 'UserOnly')
    'NewGpo.SecurityFilteringGroups.Scope' = @('Global', 'DomainLocal', 'Universal')
}

# The settings one by one (NewGpo.SecurityFilteringGroups.Scope...): their default, their value
# in the configuration of the user if it sets it, their kind (Bool, Choice, Text) and the comment
# that describes them in the configuration of the module.
function Get-PSGPOConfigurationSetting {
    [CmdletBinding()]
    param(
        # The values the user sets, by key; read from its configuration when not given.
        [hashtable]$Override
    )

    $paths = Get-PSGPOConfigurationPath
    # Comments of the defaults: the comment lines just above each key.
    $comments = @{}
    $stack = [System.Collections.Generic.List[string]]::new()
    $pending = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $paths.Default) {
        $text = $line.Trim()
        if ($text -match '^#\s?(.*)$') { $pending.Add($Matches[1]); continue }
        if ($text -match '^(\w+)\s*=\s*@\{\s*$') { $stack.Add($Matches[1]); $pending.Clear(); continue }
        if ($text -match '^(\w+)\s*=') {
            $comments[(@($stack | Select-Object -Skip 0) + $Matches[1]) -join '.'] = ($pending -join ' ').Trim()
            $pending.Clear()
            continue
        }
        if ($text -eq '}' -and $stack.Count) { $stack.RemoveAt($stack.Count - 1) }
        if (-not $text) { $pending.Clear() }
    }

    if (-not $PSBoundParameters.ContainsKey('Override')) {
        $Override = @{}
        if (Test-Path -LiteralPath $paths.User -PathType Leaf) {
            try { $Override = ConvertTo-PSGPOFlatConfiguration -Data (Import-PowerShellDataFile -LiteralPath $paths.User -ErrorAction Stop) }
            catch { Write-Warning "The configuration $($paths.User) cannot be read: $($_.Exception.Message)" }
        }
    }
    $defaults = ConvertTo-PSGPOFlatConfiguration -Data (Import-PowerShellDataFile -LiteralPath $paths.Default)
    foreach ($key in @($defaults.Keys | Sort-Object)) {
        $default = $defaults[$key]
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.ConfigurationSetting'
            Key = $key
            Default = $default
            Value = if ($Override.ContainsKey($key)) { $Override[$key] } else { $default }
            IsSet = $Override.ContainsKey($key)
            Kind = if ($default -is [bool]) { 'Bool' } elseif ($script:PSGPOConfigurationChoices.ContainsKey($key)) { 'Choice' } else { 'Text' }
            Choices = $script:PSGPOConfigurationChoices[$key]
            Description = $comments[$key]
        }
    }
}

# A nested configuration as keys with dots (NewGpo.Status), and back.
function ConvertTo-PSGPOFlatConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [hashtable]$Data, [string]$Prefix = '')

    $flat = @{}
    foreach ($key in $Data.Keys) {
        if ($Data[$key] -is [hashtable]) {
            $inner = ConvertTo-PSGPOFlatConfiguration -Data $Data[$key] -Prefix "$Prefix$key."
            foreach ($name in $inner.Keys) { $flat[$name] = $inner[$name] }
        } else {
            $flat["$Prefix$key"] = $Data[$key]
        }
    }
    $flat
}

function ConvertFrom-PSGPOFlatConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable]$Flat)

    $data = @{}
    foreach ($key in $Flat.Keys) {
        $parts = $key -split '\.'
        $table = $data
        foreach ($part in $parts | Select-Object -SkipLast 1) {
            if (-not $table.ContainsKey($part)) { $table[$part] = @{} }
            $table = $table[$part]
        }
        $table[$parts[-1]] = $Flat[$key]
    }
    $data
}

# PowerShell data text of a configuration: tables, strings, booleans and numbers only.
function ConvertTo-PSGPODataText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable]$Data, [int]$Depth = 0)

    $indent = '    ' * ($Depth + 1)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('@{')
    foreach ($key in @($Data.Keys | Sort-Object)) {
        if ($key -notmatch '^\w+$') { throw "The setting '$key' is not a name." }
        $value = $Data[$key]
        $text = if ($value -is [hashtable]) { ConvertTo-PSGPODataText -Data $value -Depth ($Depth + 1) }
            elseif ($value -is [bool]) { if ($value) { '$true' } else { '$false' } }
            elseif ($value -is [int] -or $value -is [long]) { "$value" }
            else { "'" + ("$value" -replace "'", "''") + "'" }
        $lines.Add("$indent$key = $text")
    }
    $lines.Add(('    ' * $Depth) + '}')
    $lines -join [Environment]::NewLine
}

# Writes the configuration of the user: the values it sets (by key), checked first with the
# defaults; nothing is written when one is wrong. No value: the file is removed.
function Save-PSGPOUserConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable]$Values)

    $paths = Get-PSGPOConfigurationPath
    $defaults = Import-PowerShellDataFile -LiteralPath $paths.Default
    $flatDefaults = ConvertTo-PSGPOFlatConfiguration -Data $defaults
    foreach ($key in $Values.Keys) {
        if (-not $flatDefaults.ContainsKey($key)) { throw "Unknown setting $key." }
        if ($flatDefaults[$key] -is [bool] -and $Values[$key] -isnot [bool]) { throw "$key must be True or False." }
    }
    $override = ConvertFrom-PSGPOFlatConfiguration -Flat $Values
    $problems = @(Test-PSGPOConfiguration -Configuration (Merge-PSGPOConfiguration -Base $defaults -Override $override))
    if ($problems.Count) { throw ($problems -join ' ') }
    if (-not $PSCmdlet.ShouldProcess($paths.User, 'Save the configuration')) { return }
    if (-not $Values.Count) {
        Remove-Item -LiteralPath $paths.User -Force -ErrorAction SilentlyContinue
        return
    }
    $text = "# Configuration of PSGPOTools for $([Environment]::UserName): the settings changed from the defaults`r`n" +
        "# of the module (Get-PSGPOConfiguration shows them all). Written by the console; read as data.`r`n" +
        (ConvertTo-PSGPODataText -Data $override) + "`r`n"
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $paths.User) -Force
    $temporary = "$($paths.User).$([guid]::NewGuid()).tmp"
    Set-Content -LiteralPath $temporary -Value $text -Encoding utf8 -NoNewline
    # Read back before it replaces the file.
    $null = Import-PowerShellDataFile -LiteralPath $temporary
    Move-Item -LiteralPath $temporary -Destination $paths.User -Force
}
