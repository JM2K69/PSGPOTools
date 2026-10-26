<#
    Configuration of HGPM: Resources/Configuration.psd1 of the module (every key, with its
    default), then the configuration of the domain, which only holds the keys it changes:
    Configuration.psd1 in SYSVOL\<domain>\PSGPOTools on the domain controller the console reads
    the domain from (GPOToolsDirectory.ReadConfigurationFile). One configuration for every
    console of the domain, written by its administrators: SYSVOL lets Authenticated Users read
    it and only the administrators write it, so a technician cannot give itself another one.
    There is no configuration of the user, and no local file says where the configuration is:
    the domain does.

    Both files are read as data (Import-PowerShellDataFile), never run. A configuration of the
    domain that cannot be read, holds a wrong value or needs a newer console (Console.
    MinimumVersion) is reported and left out: the defaults apply, and the approval workflow it
    may set is unknown, so the accounts that are not administrators of the domain create no GPO
    (Update-PSGPODomainWorkflow). A setting this console does not know (a newer console wrote it)
    is left out with a warning, the others are used, and it is kept when the configuration is
    saved again. The configuration in use is the one of the last directory read (Get-PSGPODirectory,
    Show-GPOManagerAvalonia, or a command given -Directory); without one, the defaults.
#>

# The configuration of the module: every key, with its default.
function Get-PSGPODefaultConfigurationPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path $PSScriptRoot 'Resources' 'Configuration.psd1'
}

# The configuration of the domain in use: Directory, Path, Exists, Override (the keys it sets,
# checked), Unknown (the keys this console does not know, by key with dots, left out) and
# Problem (why it is not used).
$script:PSGPOConfigurationState = @{ Directory = $null; Path = $null; Exists = $false; Override = @{}; Unknown = @{}; Problem = $null }

# Reads the configuration of the domain of $Directory, used from now on; nothing again for the
# same directory unless -Force. Without a directory: the defaults of the module.
function Use-PSGPODomainConfiguration {
    [CmdletBinding()]
    param(
        [AllowNull()] [GPOToolsDirectory]$Directory,
        [switch]$Force
    )

    if (-not $Force -and $Directory -and [object]::ReferenceEquals($script:PSGPOConfigurationState.Directory, $Directory)) { return }
    $state = @{ Directory = $Directory; Path = $null; Exists = $false; Override = @{}; Unknown = @{}; Problem = $null }
    if ($Directory) {
        $state.Path = $Directory.GetConfigurationPath()
        try {
            $bytes = $Directory.ReadConfigurationFile()
            if ($bytes) {
                $state.Exists = $true
                $defaults = Import-PowerShellDataFile -LiteralPath (Get-PSGPODefaultConfigurationPath)
                $split = Split-PSGPOUnknownSetting -Defaults $defaults -Override (ConvertFrom-PSGPOConfigurationByte -Bytes $bytes)
                $state.Unknown = $split.Unknown
                if ($split.Unknown.Count) {
                    Write-Warning "The configuration of the domain $($state.Path) has settings this console does not know, left out (a newer version of HGPM wrote them): $(@($split.Unknown.Keys | Sort-Object) -join ', ')."
                }
                $override = $split.Known
                $merged = Merge-PSGPOConfiguration -Base $defaults -Override $override
                $problems = @(Test-PSGPOConfiguration -Configuration $merged)
                if ($problems.Count) { throw ($problems -join ' ') }
                $minimum = "$($merged.Console.MinimumVersion)".Trim()
                if ($minimum) {
                    $version = (Get-PSGPOModuleVersion).Version
                    if ([version]"$($version.Major).$($version.Minor).$($version.Patch)" -lt [version]$minimum) {
                        throw "this console is HGPM $version, the domain needs $minimum at least (Console.MinimumVersion): update it (Update-PSResource HGPM)."
                    }
                }
                $state.Override = $override
            }
        } catch {
            $state.Problem = $_.Exception.Message
            Write-Warning "The configuration of the domain $($state.Path) is not used: $($state.Problem)"
        }
    }
    $script:PSGPOConfigurationState = $state
}

# The keys of a configuration file, read as data from its bytes.
function ConvertFrom-PSGPOConfigurationByte {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [byte[]]$Bytes)

    $local = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-$([guid]::NewGuid()).psd1"
    try {
        [System.IO.File]::WriteAllBytes($local, $Bytes)
        Import-PowerShellDataFile -LiteralPath $local -ErrorAction Stop
    } catch {
        # Not the temporary file in the message.
        throw "it is not PowerShell data: $($_.Exception.Message.Replace($local, 'Configuration.psd1'))"
    } finally {
        Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
    }
}

# The keys of a configuration of the domain this console knows (Known, nested), and the others
# (Unknown, by key with dots): a newer console wrote them. A key whose value is not of the kind of
# its default (a value where a table is expected) is known: Merge-PSGPOConfiguration refuses it.
function Split-PSGPOUnknownSetting {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [hashtable]$Defaults, [Parameter(Mandatory)] [hashtable]$Override)

    $known = @{}
    $unknown = @{}
    foreach ($key in $Override.Keys) {
        if (-not $Defaults.ContainsKey($key)) {
            if ($Override[$key] -is [hashtable]) {
                $flat = ConvertTo-PSGPOFlatConfiguration -Data $Override[$key] -Prefix "$key."
                foreach ($name in $flat.Keys) { $unknown[$name] = $flat[$name] }
            } else {
                $unknown[$key] = $Override[$key]
            }
        } elseif ($Defaults[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            $inner = Split-PSGPOUnknownSetting -Defaults $Defaults[$key] -Override $Override[$key]
            $known[$key] = $inner.Known
            foreach ($name in $inner.Unknown.Keys) { $unknown["$key.$name"] = $inner.Unknown[$name] }
        } else {
            $known[$key] = $Override[$key]
        }
    }
    @{ Known = $known; Unknown = $unknown }
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
    if ($Configuration.View.ShowUnmanaged -isnot [bool]) { 'View.ShowUnmanaged must be $true or $false.' }
    $workflow = $Configuration.Workflow
    if ($workflow.Enabled -isnot [bool]) { 'Workflow.Enabled must be $true or $false.' }
    if ($workflow.CreatorRights -notin 'ReadOnly', 'EditSettings') { "Workflow.CreatorRights must be ReadOnly or EditSettings, not '$($workflow.CreatorRights)'." }
    foreach ($name in 'Approvers', 'ApprovedOwner') {
        if ("$($workflow[$name])".Trim() -eq '') { "Workflow.$name must not be empty." }
    }
    if ("$($workflow.ApprovedOwner)" -match ',') { 'Workflow.ApprovedOwner is one group.' }
    if ($workflow.Enabled -and "$($workflow.Creators)".Trim() -eq '') { 'Workflow.Creators must name the groups of the creators when the workflow is enabled.' }
    # The roles by their names; the workflow checks them again by their SIDs (Test-PSGPOWorkflowRole).
    $names = { param($Text) @("$Text" -split ',' | ForEach-Object { ($_.Trim() -split '\\')[-1] } | Where-Object { $_ }) }
    $approvers = & $names $workflow.Approvers
    $creators = & $names $workflow.Creators
    foreach ($name in @($creators | Where-Object { $approvers -contains $_ })) { "$name is in Workflow.Approvers and Workflow.Creators: keep the roles apart." }
    $everyone = 'Everyone', 'Authenticated Users', 'Anonymous Logon', 'Users', 'Guests', 'Domain Users', 'Domain Guests', 'Domain Computers', 'S-1-1-0', 'S-1-5-7', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-32-546'
    foreach ($name in @(@($approvers) + @($creators) | Where-Object { $everyone -contains $_ } | Select-Object -Unique)) { "Workflow.Approvers and Workflow.Creators name groups of the domain, not ${name}: a group of every account." }
    $audit = "$($Configuration.Audit.Path)".Trim()
    # A share (\\server\share, //server/share on Linux too) or a folder of the computer.
    if ($audit -and $audit -notmatch '^(\\\\|//)[^\\/]+[\\/][^\\/]+' -and -not [System.IO.Path]::IsPathRooted($audit)) { "Audit.Path must be a full path (a share: \\server\gpo-audit), not '$audit'." }
    $backup = "$($Configuration.Backup.Path)".Trim()
    if ($backup -and $backup -notmatch '^(\\\\|//)[^\\/]+[\\/][^\\/]+' -and -not [System.IO.Path]::IsPathRooted($backup)) { "Backup.Path must be a full path (a share: \\server\gpo-backups), not '$backup'." }
    if ($Configuration.Log.Level -notin 'Error', 'Warning', 'Information', 'Verbose') { "Log.Level must be Error, Warning, Information or Verbose, not '$($Configuration.Log.Level)'." }
    if ($Configuration.Log.SystemLog -isnot [bool]) { 'Log.SystemLog must be $true or $false.' }
    foreach ($name in 'Log.RetentionDays', 'Audit.RetentionMonths') {
        $parts = $name -split '\.'
        $number = 0
        if (-not [int]::TryParse("$($Configuration[$parts[0]][$parts[1]])", [ref]$number) -or $number -lt 0) { "$name must be a number of 0 or more." }
    }
    if ($Configuration.Audit.Enabled -isnot [bool]) { 'Audit.Enabled must be $true or $false.' }
    foreach ($name in 'Tier1', 'Tier2') {
        if ("$($Configuration.Audit.Tiers[$name])" -match '[";|=+*?<>]') { "Audit.Tiers.$name holds names of groups separated by commas." }
    }
    foreach ($name in 'Readers', 'Purgers') {
        if ("$($Configuration.Audit[$name])" -match '[";|=+*?<>]') { "Audit.$name holds names of groups separated by commas." }
    }
    $minimum = "$($Configuration.Console.MinimumVersion)".Trim()
    if ($minimum -and $minimum -notmatch '^\d+\.\d+(\.\d+)?$') { "Console.MinimumVersion must be a version of HGPM (0.1.14), not '$minimum'." }
    if ($groups.Container -and "$($groups.Container)" -notmatch '^(?:(?:OU|CN)=[^,]+)(?:,(?:OU|CN|DC)=[^,]+)*$') { "NewGpo.SecurityFilteringGroups.Container is not a distinguished name: '$($groups.Container)'." }
}

# The configuration in use: the defaults, with the configuration of the domain over them.
function Get-PSGPOConfigurationData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Merge-PSGPOConfiguration -Base (Import-PowerShellDataFile -LiteralPath (Get-PSGPODefaultConfigurationPath)) -Override $script:PSGPOConfigurationState.Override
}

# The console shows what the account does not manage, greyed (View.ShowUnmanaged), or only what it
# manages.
function Test-PSGPOUnmanagedShown {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    [bool](Get-PSGPOConfigurationData).View.ShowUnmanaged
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
    'Workflow.CreatorRights' = @('ReadOnly', 'EditSettings')
    'Log.Level' = @('Error', 'Warning', 'Information', 'Verbose')
}

# The settings one by one (NewGpo.SecurityFilteringGroups.Scope...): their default, their value
# in the configuration of the domain if it sets it, their kind (Bool, Choice, Text) and the
# comment that describes them in the configuration of the module.
function Get-PSGPOConfigurationSetting {
    [CmdletBinding()]
    param(
        # The values the domain sets, by key; those of the configuration in use when not given.
        [hashtable]$Override
    )

    $paths = @{ Default = Get-PSGPODefaultConfigurationPath }
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

    if (-not $PSBoundParameters.ContainsKey('Override')) { $Override = ConvertTo-PSGPOFlatConfiguration -Data $script:PSGPOConfigurationState.Override }
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

# Writes the configuration of the domain of $Directory: the values it sets (by key), checked first
# with the defaults; nothing is written when one is wrong. No value: an empty configuration, every
# setting with its default. Only the administrators of the domain can write it (SYSVOL). The
# configuration is then read again.
function Save-PSGPODomainConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable]$Values
    )

    $defaults = Import-PowerShellDataFile -LiteralPath (Get-PSGPODefaultConfigurationPath)
    $flatDefaults = ConvertTo-PSGPOFlatConfiguration -Data $defaults
    foreach ($key in $Values.Keys) {
        if (-not $flatDefaults.ContainsKey($key)) { throw "Unknown setting $key." }
        if ($flatDefaults[$key] -is [bool] -and $Values[$key] -isnot [bool]) { throw "$key must be True or False." }
    }
    $override = ConvertFrom-PSGPOFlatConfiguration -Flat $Values
    $problems = @(Test-PSGPOConfiguration -Configuration (Merge-PSGPOConfiguration -Base $defaults -Override $override))
    if ($problems.Count) { throw ($problems -join ' ') }
    # The settings of a newer console this one does not know: kept as they are, not checked.
    $state = $script:PSGPOConfigurationState
    if ($state.Unknown.Count -and [object]::ReferenceEquals($state.Directory, $Directory)) {
        $all = @{}
        foreach ($key in $Values.Keys) { $all[$key] = $Values[$key] }
        foreach ($key in $state.Unknown.Keys) { $all[$key] = $state.Unknown[$key] }
        $override = ConvertFrom-PSGPOFlatConfiguration -Flat $all
    }
    $path = $Directory.GetConfigurationPath()
    if (-not $PSCmdlet.ShouldProcess($path, 'Save the configuration of the domain')) { return }
    $by = if ($Directory.Account) { $Directory.Account } else { [Environment]::UserName }
    $text = "# Configuration of HGPM for the domain $($Directory.DomainName), for every console of the domain:`r`n" +
        "# the settings changed from the defaults of the module (Get-PSGPOConfiguration shows them all).`r`n" +
        "# Written by $by with the console; read as data.`r`n" +
        (ConvertTo-PSGPODataText -Data $override) + "`r`n"
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
    # Read back before it replaces the file.
    $null = ConvertFrom-PSGPOConfigurationByte -Bytes $bytes
    try {
        $Directory.WriteConfigurationFile($bytes)
    } catch {
        $message = $_.Exception.GetBaseException().Message
        if ($message -match 'ACCESS_DENIED|denied') { throw "The account $($Directory.Account) cannot write the configuration of the domain $($path): only the administrators of the domain can ($message)." }
        throw "The configuration of the domain $path is not saved: $message"
    }
    Use-PSGPODomainConfiguration -Directory $Directory -Force
}

# The configuration of the domain created at the first start of the console, empty (every setting
# with its default), when the account is an administrator of the domain: from then on it is the
# file every console of the domain reads, and the Settings window changes. Returns whether it was
# created; a domain whose configuration cannot be read is left as it is.
function Initialize-PSGPODomainConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [GPOToolsDirectory]$Directory)

    Use-PSGPODomainConfiguration -Directory $Directory
    $state = $script:PSGPOConfigurationState
    if ($state.Exists -or $state.Problem -or $Directory.IsReadOnly -or -not $Directory.IsDomainAdministrator) { return $false }
    # A domain that delegates the creation of GPOs has its configuration already (the workflow is
    # deployed): missing here, it is on another domain controller (Samba does not replicate
    # SYSVOL). An empty one here would turn the workflow off for the consoles that read this one.
    if ($Directory -is [GPOToolsLdapDirectory]) {
        $connection = New-PSGPODirectoryConnection -Directory $Directory
        try { $delegated = Test-PSGPODomainCreationDelegated -Connection $connection -DomainDistinguishedName $Directory.Domain.DistinguishedName } finally { $connection.Dispose() }
        if ($delegated) {
            Write-Warning "The configuration of the domain $($state.Path) is not created: the domain delegates the creation of GPOs (approval workflow), so its configuration is on another domain controller. Copy it to $($Directory.Server) (Samba does not replicate SYSVOL; on Windows, check the replication of SYSVOL)."
            return $false
        }
    }
    try {
        Save-PSGPODomainConfiguration -Directory $Directory -Values @{} -Confirm:$false
    } catch {
        Write-Warning "The configuration of the domain $($state.Path) is not created: $($_.Exception.Message)"
        return $false
    }
    Write-Verbose "Configuration of the domain created: $($state.Path)"
    $true
}

# The account of $Connection is an administrator of the domain: Domain Admins or Enterprise Admins
# (by the SID of the group, whatever its name in the language of the domain controller), or
# Administrators, in its groups (tokenGroups). $false when they cannot be read.
function Test-PSGPODomainAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DomainDistinguishedName,
        [string]$Account
    )

    if (-not $Account -or $Account -eq 'Anonymous') { return $false }
    try {
        $sids = Get-PSGPOAccountGroupSid -Connection $Connection -DomainDistinguishedName $DomainDistinguishedName -Account $Account
    } catch {
        Write-Verbose "The groups of $Account cannot be read: $($_.Exception.Message)"
        return $false
    }
    [bool]@($sids | Where-Object { $_ -match '^S-1-5-21-\d+-\d+-\d+-(512|519)$' -or $_ -eq 'S-1-5-32-544' }).Count
}
