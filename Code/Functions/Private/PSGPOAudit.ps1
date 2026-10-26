<#
    Audit log: what the consoles and the commands change in a domain, one JSON line per change,
    never rewritten: when, who (the account of the directory), from which computer, on which
    domain controller, what (Action), on what (Target: a GPO, a container, the configuration) and
    how (Details). Only the changes the domain accepted are written: they are logged once made.

    The central log is Audit.Path of the configuration of the domain, the same for every console:
    a share of a file server (not SYSVOL, copied to every domain controller), prepared by
    Initialize-PSGPOAuditShare with a folder per tier. Each account adds its lines to its own file
    in the folder of its tier (Update-PSGPOAuditTier): <tier>\<domain>-<yyyy-MM>-<account>-
    <computer>.jsonl; no two consoles write the same file. Tier 0 and the readers read every tier,
    the accounts of a tier read theirs: the permissions of the share decide, the log shows what
    the account can read. On Linux the share is reached with smbclient (Kerberos).

    Without Audit.Path, the folder Audit of the backups of the account, one file per domain and
    month: <domain>-<yyyy-MM>.jsonl. On by default: Audit.Enabled = $false in the configuration of
    the domain stops it.
#>

$script:PSGPOAuditFormat = 'PSGPOTools.Audit/1'

# What each action is, as the audit log window shows it (translated by Get-PSGPOText).
$script:PSGPOAuditActionText = [ordered]@{
    NewGpo = 'GPO created'; RenameGpo = 'GPO renamed'; SetGpoStatus = 'GPO status changed'; RemoveGpo = 'GPO deleted'
    RemoveDeletedGpoBackup = 'Deleted GPO removed for good'; RestoreGpo = 'GPO restored'; ImportGpo = 'GPO imported'
    SaveGpoFile = 'Settings of a GPO saved'; ImportPolicyRuleSet = 'Rule set written in a GPO'
    PendingGpo = 'GPO waiting for approval'; ApproveGpo = 'GPO approved'
    NewLink = 'Link created'; SetLink = 'Link changed'; RemoveLink = 'Link deleted'; SetBlockInheritance = 'Inheritance blocked or unblocked'
    SetGpoPermission = 'Permissions of a GPO changed'; SetGpoSecurityFiltering = 'Security filtering changed'; NewFilteringGroups = 'Security filtering groups created'
    SetWmiFilter = 'WMI filter of a GPO changed'; NewWmiFilter = 'WMI filter created'; EditWmiFilter = 'WMI filter changed'
    RemoveWmiFilter = 'WMI filter deleted'; SetWmiFilterPermission = 'Permissions of a WMI filter changed'
    NewPasswordPolicy = 'Password policy created'; SetPasswordPolicy = 'Password policy changed'; RemovePasswordPolicy = 'Password policy deleted'
    SaveConfiguration = 'Configuration saved'; InstallAdmx = 'ADMX files installed'; InitializeAuditShare = 'Share of the audit log prepared'
}

# What an action is, in the language of the interface; the action itself when unknown.
function Get-PSGPOAuditActionText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Action)

    if ($script:PSGPOAuditActionText.Contains($Action)) { return Get-PSGPOText $script:PSGPOAuditActionText[$Action] }
    $Action
}

# The details of an entry, one "name: value" per line (a list or a table as JSON).
function Format-PSGPOAuditDetail {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [System.Collections.IDictionary]$Details)

    if (-not $Details -or -not $Details.Count) { return '' }
    @(foreach ($name in @($Details.Keys | Sort-Object)) {
            $value = $Details[$name]
            $text = if ($null -eq $value) { '' }
            elseif ($value -is [string] -or $value -is [ValueType]) { "$value" }
            else { ConvertTo-Json -InputObject $value -Depth 5 -Compress }
            "${name}: $text"
        }) -join [Environment]::NewLine
}

# Entries of the audit log as a CSV file (UTF-8, the time in UTC as ISO 8601, the details as JSON).
function Export-PSGPOAuditLogCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Entry,
        [Parameter(Mandatory)] [string]$Path
    )

    $folder = [System.IO.Path]::GetDirectoryName($Path)
    if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop }
    @(foreach ($item in $Entry) {
            [pscustomobject][ordered]@{
                Time = $item.Time.ToUniversalTime().ToString('o')
                Domain = $item.Domain
                Server = $item.Server
                Account = $item.Account
                Computer = $item.Computer
                Action = $item.Action
                Target = $item.Target
                Tier = $item.Tier
                GpoName = $item.GpoName
                GpoId = if ($item.GpoId) { $item.GpoId.ToString() } else { '' }
                Details = if ($item.Details -and $item.Details.Count) { ConvertTo-Json -InputObject $item.Details -Depth 5 -Compress } else { '' }
            }
        }) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8 -ErrorAction Stop
    Get-Item -LiteralPath $Path
}

# The folder of the audit log.
function Get-PSGPOAuditPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $path = "$((Get-PSGPOConfigurationData).Audit.Path)".Trim()
    if ($path) { return $path }
    Join-Path (Get-PSGPODefaultBackupPath) 'Audit'
}

# A share of the audit log: Server, Share and Folder (below the share, with \); $null for a folder
# of the computer. Only Linux needs it: Windows reaches \\server\share as a path.
function Get-PSGPOAuditShare {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Path)

    $match = [regex]::Match($Path, '^(?:\\\\|//)([^\\/]+)[\\/]([^\\/]+)(?:[\\/](.*))?$')
    if (-not $match.Success) { return $null }
    [pscustomobject]@{ Server = $match.Groups[1].Value; Share = $match.Groups[2].Value; Folder = ($match.Groups[3].Value -replace '/', '\').Trim('\') }
}

# The file of the log an account writes, below the folder of the log: <tier>\<domain>-<yyyy-MM>-
# <account>-<computer>.jsonl in the central log, <domain>-<yyyy-MM>.jsonl in the folder of the
# account.
function Get-PSGPOAuditFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [datetime]$Time
    )

    if (-not "$((Get-PSGPOConfigurationData).Audit.Path)".Trim()) { return '{0}-{1}.jsonl' -f ($Directory.DomainName -replace '[^\w.-]', '_'), $Time.ToString('yyyy-MM', [cultureinfo]::InvariantCulture) }
    Get-PSGPOAuditCentralFileName -Tier $Directory.AuditTier -Domain $Directory.DomainName -Time $Time `
        -Account $(if ($Directory.Account) { $Directory.Account } else { [Environment]::UserName }) -Computer ([Environment]::MachineName)
}

# The file of the central log of an account: <tier>\<domain>-<yyyy-MM>-<account>-<computer>.jsonl.
function Get-PSGPOAuditCentralFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string]$Tier,
        [Parameter(Mandatory)] [string]$Domain,
        [Parameter(Mandatory)] [datetime]$Time,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Account,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Computer,
        # Added to the name: the changes another account imported (Import-PSGPOAuditLog), in a file
        # of their own, as the account writes only the file it made.
        [string]$Suffix
    )

    $name = { param($Text) $Text -replace '[^\w.-]', '_' }
    '{0}\{1}-{2}-{3}-{4}{5}.jsonl' -f $(if ($Tier) { $Tier } else { 'Unassigned' }), (& $name $Domain), $Time.ToUniversalTime().ToString('yyyy-MM', [cultureinfo]::InvariantCulture), (& $name $Account), (& $name $Computer), $(if ($Suffix) { "-$Suffix" })
}

# The tier of the account of $Directory in the central log: Tier0 (an administrator of the domain,
# or an approver of the workflow), Tier1 or Tier2 (Audit.Tiers), else Unassigned. Read in its
# groups (tokenGroups); a group of the configuration that is not found is said, not a failure.
function Update-PSGPOAuditTier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory
    )

    $Directory.AuditTier = 'Unassigned'
    if ($Directory.IsDomainAdministrator) { $Directory.AuditTier = 'Tier0'; return }
    try {
        $Directory.AuditTier = Get-PSGPOAuditAccountTier -Connection $Connection -Directory $Directory -Account $Directory.Account
    } catch {
        Write-Warning "The tier of $($Directory.Account) in the audit log cannot be read, its changes go to Unassigned: $($_.Exception.GetBaseException().Message)"
    }
}

# The tier of an account of the domain: Tier0 (an administrator of the domain by the SID of its
# groups, or an approver), Tier1, Tier2 (Audit.Tiers), else Unassigned (an account the domain does
# not know too). $Cache keeps the SIDs of the groups of the configuration between accounts.
function Get-PSGPOAuditAccountTier {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Account,
        [hashtable]$Cache = @{}
    )

    if (-not $Account) { return 'Unassigned' }
    $domainDN = $Directory.Domain.DistinguishedName
    $token = Get-PSGPOAccountGroupSid -Connection $Connection -DomainDistinguishedName $domainDN -Account $Account
    if (-not $token.Count) { return 'Unassigned' }
    if (@($token | Where-Object { $_ -match '^S-1-5-21-\d+-\d+-\d+-(512|519)$' -or $_ -eq 'S-1-5-32-544' }).Count) { return 'Tier0' }
    $configuration = Get-PSGPOConfigurationData
    $tiers = [ordered]@{ Tier0 = $configuration.Workflow.Approvers; Tier1 = $configuration.Audit.Tiers.Tier1; Tier2 = $configuration.Audit.Tiers.Tier2 }
    foreach ($tier in $tiers.Keys) {
        foreach ($name in @("$($tiers[$tier])" -split ',' | ForEach-Object Trim | Where-Object { $_ })) {
            if (-not $Cache.ContainsKey($name)) {
                try {
                    $Cache[$name] = @(Find-PSGPODomainAccount -Connection $Connection -DomainDistinguishedName $domainDN -Name $name)[0].Sid
                } catch {
                    $Cache[$name] = $null
                    Write-Warning "The audit log: $($_.Exception.Message) (the groups of $tier in the configuration)."
                }
            }
            if ($Cache[$name] -and $token -contains $Cache[$name]) { return $tier }
        }
    }
    'Unassigned'
}

# Adds a change to the audit log of the domain of $Directory. A log that cannot be written does
# not undo the change, which is made: it is said (a warning) and the change goes on.
function Write-PSGPOAuditEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Action,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Target,
        [GPOToolsGpo]$Gpo,
        [System.Collections.IDictionary]$Details = @{}
    )

    if ((Get-PSGPOConfigurationData).Audit.Enabled -eq $false) { return }
    $now = [datetime]::UtcNow
    $entry = [ordered]@{
        Format = $script:PSGPOAuditFormat
        Time = $now.ToString('o')
        Domain = $Directory.DomainName
        Server = if ($Directory -is [GPOToolsLdapDirectory]) { $Directory.Server }
        Account = if ($Directory.Account) { $Directory.Account } else { [Environment]::UserName }
        Computer = [Environment]::MachineName
        Action = $Action
        Target = $Target
        GpoId = if ($Gpo) { $Gpo.Id.ToString() }
        GpoName = if ($Gpo) { $Gpo.DisplayName }
        Tier = if ($Directory.AuditTier) { $Directory.AuditTier }
        Details = $Details
    }
    $line = (ConvertTo-Json -InputObject $entry -Depth 5 -Compress) + "`n"
    try {
        $folder = Get-PSGPOAuditPath
        $name = Get-PSGPOAuditFileName -Directory $Directory -Time $now
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
        $share = if (-not $IsWindows) { Get-PSGPOAuditShare -Path $folder }
        if ($share) {
            Add-PSGPOAuditShareLine -Share $share -Name $name -Bytes $bytes
            return
        }
        # Not Join-Path with the name: on Linux its \ would stay in the file name.
        # [string[]]: an object[] makes .NET take another Combine, which joins with spaces.
        $file = [System.IO.Path]::Combine([string[]](@($folder) + @($name -split '\\')))
        $null = New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($file)) -Force -ErrorAction Stop
        # Several consoles may write the same file: a few tries, each line in one write.
        for ($try = 1; ; $try++) {
            try {
                $stream = [System.IO.FileStream]::new($file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
                break
            } catch [System.IO.IOException] {
                if ($try -ge 5) { throw }
                Start-Sleep -Milliseconds (100 * $try)
            }
        }
    } catch {
        Write-Warning "$Action of $Target is done, but not written to the audit log: $($_.Exception.GetBaseException().Message)"
    }
}

# Linux: a line added to a file of the share of the log, with smbclient (Kerberos): the file of
# the account read, the line added, the file written back, the folder of the tier created when
# needed. The account is the only one to write its file.
function Add-PSGPOAuditShareLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Share,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [byte[]]$Bytes
    )

    $remote = (@($Share.Folder, $Name) | Where-Object { $_ }) -join '\'
    $local = [System.IO.Path]::GetTempFileName()
    try {
        $read = Invoke-PSGPOSmbClient -Server $Share.Server -Share $Share.Share -AllowMissing -Command ('get "{0}" "{1}"' -f $remote, $local)
        if ($null -eq $read) { [System.IO.File]::WriteAllBytes($local, [byte[]]@()) }
        $stream = [System.IO.FileStream]::new($local, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
        try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
        $level = ''
        foreach ($part in @($remote -split '\\' | Select-Object -SkipLast 1)) {
            $level = if ($level) { "$level\$part" } else { $part }
            $null = Invoke-PSGPOSmbClient -Server $Share.Server -Share $Share.Share -IgnoreStatus 'NT_STATUS_OBJECT_NAME_COLLISION', 'NT_STATUS_ACCESS_DENIED' -Command ('mkdir "{0}"' -f $level)
        }
        $null = Invoke-PSGPOSmbClient -Server $Share.Server -Share $Share.Share -Command ('put "{0}" "{1}"' -f $local, $remote)
    } finally {
        Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
    }
}

# Whether the folder of the log exists (a share on Linux: listed with smbclient).
function Test-PSGPOAuditFolder {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$Path)

    $share = if (-not $IsWindows) { Get-PSGPOAuditShare -Path $Path }
    if (-not $share) { return (Test-Path -LiteralPath $Path -PathType Container) }
    $command = if ($Share.Folder) { 'cd "{0}"; ls' -f $share.Folder } else { 'ls' }
    $null -ne (Invoke-PSGPOSmbClient -Server $share.Server -Share $share.Share -AllowMissing -IgnoreStatus 'NT_STATUS_ACCESS_DENIED' -Command $command)
}

# The entries of the audit log, newest first: every file of the folder and of its folders the
# account can read (a central log: the tiers it may read).
function Read-PSGPOAuditEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$Domain
    )

    $share = if (-not $IsWindows) { Get-PSGPOAuditShare -Path $Path }
    $local = $null
    if ($share) {
        # Linux: the files of the share the account can read, copied first (the folders of the
        # other tiers are refused: not a failure).
        $local = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-audit-$([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $local
        $command = 'prompt OFF; recurse ON; lcd "{0}"; {1}mget *' -f $local, $(if ($share.Folder) { 'cd "{0}"; ' -f $share.Folder })
        $copied = Invoke-PSGPOSmbClient -Server $share.Server -Share $share.Share -TimeoutSeconds 600 -AllowMissing -IgnoreExitCode -IgnoreStatus 'NT_STATUS_ACCESS_DENIED', 'NT_STATUS_NO_SUCH_FILE' -Command $command
        if ($null -eq $copied) { Remove-Item -LiteralPath $local -Recurse -Force; return }
        $Path = $local
    }
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
        $filter = if ($Domain) { "$($Domain -replace '[^\w.-]', '_')-*.jsonl" } else { '*.jsonl' }
        # The folders the account cannot read (the other tiers) are left out.
        $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Filter $filter -ErrorAction SilentlyContinue | Sort-Object FullName)
        Read-PSGPOAuditFile -File $files
    } finally {
        if ($local) { Remove-Item -LiteralPath $local -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# The entries of files of the log, newest first.
function Read-PSGPOAuditFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [System.IO.FileInfo[]]$File)

    # The order of the lines breaks the ties: two changes of the same instant.
    $order = 0
    $entries = foreach ($file in $File) {
        $number = 0
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            $number++
            if (-not $line.Trim()) { continue }
            try {
                $read = ConvertFrom-Json -InputObject $line -AsHashtable
            } catch {
                Write-Warning "Line $number of $($file.FullName) ignored: it is not an entry of the audit log."
                continue
            }
            if ($read.Format -ne $script:PSGPOAuditFormat) { continue }
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.AuditEntry'
                # ConvertFrom-Json turns the time into a date of the local time zone itself: back to UTC.
                Time = if ($read.Time -is [datetime]) { $read.Time.ToUniversalTime() } else { [datetime]::Parse($read.Time, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) }
                Domain = $read.Domain
                Server = $read.Server
                Account = $read.Account
                Computer = $read.Computer
                Action = $read.Action
                Target = $read.Target
                GpoId = if ($read.GpoId) { [guid]$read.GpoId }
                GpoName = $read.GpoName
                Tier = $read.Tier
                Details = $read.Details
                Order = $order++
            }
        }
    }
    @($entries | Sort-Object -Property @{ Expression = 'Time'; Descending = $true }, @{ Expression = 'Order'; Descending = $true } | Select-Object -Property * -ExcludeProperty Order |
            ForEach-Object { $_.PSObject.TypeNames.Insert(0, 'PSGPOTools.AuditEntry'); $_ })
}
