<#
    Audit log: what the consoles and the commands change in a domain, one JSON line per change,
    appended only and chained to the previous line of its file (Write-PSGPOAuditEntry), checked
    when read (Read-PSGPOAuditFile): when, who (the account of the directory), from which computer, on which
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
    SaveConfiguration = 'Configuration saved'; InstallAdmx = 'ADMX files installed'; InitializeAuditShare = 'Share of the audit log prepared'; InitializeBackupShare = 'Share of the backups prepared'; PurgeAuditLog = 'Old months of the audit log archived'
}

# What an action is, in the language of the interface; the action itself when unknown.
function Get-PSGPOAuditActionText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Action)

    if ($script:PSGPOAuditActionText.Contains($Action)) { return Get-PSGPOText $script:PSGPOAuditActionText[$Action] }
    $Action
}

# A tier as the windows show it: Tier 0, Tier 1, Tier 2, Unassigned, in the language of the interface.
function Get-PSGPOAuditTierText {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string]$Tier)

    if ($Tier -match '^Tier(\d)$') { return Get-PSGPOText 'Tier {0}' $Matches[1] }
    if ($Tier) { return Get-PSGPOText $Tier }
    ''
}

# What the check of an entry found (Read-PSGPOAuditFile), as the windows show it, and why.
$script:PSGPOAuditCheckText = [ordered]@{
    Verified = @('Verified', 'Its line follows the previous one of its file, its tier is the folder of its file, and its file belongs to its account.')
    Altered = @('Altered', 'A line before it in its file was changed or removed: the chain of its file breaks here.')
    NotChained = @('Not chained', 'Written before HGPM 0.1.15: its line is not chained, it is not checked.')
    TierMismatch = @('Tier differs', 'Its tier is not the folder of its file: it was written elsewhere than in its tier.')
    OwnerMismatch = @('Owner differs', 'Its file does not belong to its account (nor to the account that imported it): someone else wrote it.')
}

function Get-PSGPOAuditCheckText {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string]$Check, [switch]$Reason)

    if (-not $script:PSGPOAuditCheckText.Contains($Check)) { return $Check }
    Get-PSGPOText $script:PSGPOAuditCheckText[$Check][[int][bool]$Reason]
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
                Check = $item.Check
                ImportedBy = $item.ImportedBy
                Details =if ($item.Details -and $item.Details.Count) { ConvertTo-Json -InputObject $item.Details -Depth 5 -Compress } else { '' }
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
    # The folder of the account, not the central backups (Tier 0 only).
    Join-Path (Get-PSGPOLocalBackupPath) 'Audit'
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
    try {
        $token = Get-PSGPOAccountGroupSid -Connection $Connection -DomainDistinguishedName $Directory.Domain.DistinguishedName -Account $Directory.Account
        if ($token.Count) { $Directory.AccountSid = $token[0] }
    } catch {
        Write-Verbose "The SID of $($Directory.Account) cannot be read: $($_.Exception.GetBaseException().Message)"
    }
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
# not undo the change, which is made: the log of the system has it first (for a SIEM), and the
# line waits in a local file (Get-PSGPOAuditSpoolPath), written before the next change.
#
# Each line is chained to the previous one of its file: Seq (1, 2...) and PrevHash (SHA-256 of the
# previous line), first in the line, so that the reader finds a line changed or removed in the
# middle of a file. The file of an account is append-only (FILE_APPEND_DATA without
# FILE_WRITE_DATA): Windows appends at its end, Samba refuses to open it to write, but lets a
# handle opened to append write anywhere: the chain shows it.
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
        AccountSid = if ($Directory.AccountSid) { $Directory.AccountSid }
        Computer = [Environment]::MachineName
        Action = $Action
        Target = $Target
        GpoId = if ($Gpo) { $Gpo.Id.ToString() }
        GpoName = if ($Gpo) { $Gpo.DisplayName }
        Tier = if ($Directory.AuditTier) { $Directory.AuditTier }
        Details = $Details
    }
    # The change for a SIEM first, whatever happens to the share.
    try { Write-PSGPOAuditSystemLog -Entry $entry } catch { Write-Verbose "The log of the system: $($_.Exception.GetBaseException().Message)" }
    $item = [ordered]@{ Folder = $null; Name = $null; Line = ConvertTo-Json -InputObject $entry -Depth 5 -Compress }
    try {
        $item.Folder = Get-PSGPOAuditPath
        $item.Name = Get-PSGPOAuditFileName -Directory $Directory -Time $now
    } catch {
        Write-Warning "$Action of $Target is done, but not written to the audit log: $($_.Exception.GetBaseException().Message)"
        return
    }
    # The lines that waited first, in their order, then this one.
    # Each one on its own: one that cannot be written (its folder is gone) does not stop the others.
    $waiting = @(Read-PSGPOAuditSpool)
    $left = [System.Collections.Generic.List[object]]::new()
    $failure = $null
    foreach ($line in @($waiting) + @([pscustomobject]$item)) {
        try {
            Add-PSGPOAuditLine -Folder $line.Folder -Name $line.Name -Line $line.Line
        } catch {
            $left.Add($line)
            if ([object]::ReferenceEquals($line.Line, $item.Line) -or -not $failure) { $failure = $_ }
        }
    }
    if ($waiting.Count -or $left.Count) { Save-PSGPOAuditSpool -Item @($left) }
    if (-not $left.Count) { return }
    $done = if (@($left | Where-Object { [object]::ReferenceEquals($_.Line, $item.Line) }).Count) { "$Action of $Target is done, but not written to the audit log yet" } else { "$Action of $Target is written to the audit log, but older changes are not yet" }
    Write-PSGPOLogEntry -Level Warning -Source 'Audit log' -Message "${done}: $($left.Count) change(s) wait in $(Get-PSGPOAuditSpoolPath)." -ErrorRecord $failure
    Write-Warning "$done ($($failure.Exception.GetBaseException().Message)): $($left.Count) change(s) wait in $(Get-PSGPOAuditSpoolPath), written with the next change."
}

# The local file of the changes not written to the audit log yet (the share could not be
# reached), one JSON line each: Folder, Name, Line.
function Get-PSGPOAuditSpoolPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path (Get-PSGPOLogPath) 'audit-waiting.jsonl'
}

function Read-PSGPOAuditSpool {
    [CmdletBinding()]
    param()

    $path = Get-PSGPOAuditSpoolPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    foreach ($text in [System.IO.File]::ReadAllLines($path)) {
        if (-not $text.Trim()) { continue }
        try { [pscustomobject](ConvertFrom-Json -InputObject $text -AsHashtable) } catch { Write-Warning "A line of $path is not a change of the audit log: left out." }
    }
}

function Save-PSGPOAuditSpool {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Item)

    $path = Get-PSGPOAuditSpoolPath
    if (-not $PSCmdlet.ShouldProcess($path, 'Keep the changes not written to the audit log')) { return }
    if (-not $Item.Count) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue; return }
    New-PSGPOFolder -Path ([System.IO.Path]::GetDirectoryName($path))
    $lines = foreach ($one in $Item) { ConvertTo-Json -InputObject ([ordered]@{ Folder = $one.Folder; Name = $one.Name; Line = $one.Line }) -Compress }
    [System.IO.File]::WriteAllLines($path, [string[]]$lines)
}

# A line chained to the last line of its file: {"Seq":<n>,"PrevHash":"<SHA-256>",...}. The first
# line of a file, or after a line without Seq (written before 0.1.15), starts again at the Seq it
# finds + 1.
function Add-PSGPOAuditChain {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Line,
        [AllowEmptyString()] [AllowNull()] [string]$Previous
    )

    $seq = 1
    $hash = ''
    if ($Previous) {
        $hash = Get-PSGPOAuditLineHash -Line $Previous
        if ($Previous -match '^\{"Seq":(\d+),') { $seq = [long]$Matches[1] + 1 }
    }
    '{"Seq":' + $seq + ',"PrevHash":"' + $hash + '",' + $Line.Substring(1)
}

function Get-PSGPOAuditLineHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Line)

    [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Line)))
}

# The last line of a file of the log (its last 64 KB read), $null when there is none.
function Get-PSGPOAuditLastLine {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$File)

    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return $null }
    $stream = [System.IO.FileStream]::new($File, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $size = [Math]::Min($stream.Length, 65536)
        if (-not $size) { return $null }
        $null = $stream.Seek(-$size, [System.IO.SeekOrigin]::End)
        $buffer = [byte[]]::new($size)
        $read = 0
        while ($read -lt $size) { $count = $stream.Read($buffer, $read, $size - $read); if (-not $count) { break }; $read += $count }
    } finally {
        $stream.Dispose()
    }
    @([System.Text.Encoding]::UTF8.GetString($buffer, 0, $read) -split "`n" | Where-Object { $_.Trim() })[-1]
}

# Lines added to their file of the log, each chained to the previous one; on Linux to a share with
# the Python bindings of Samba. A file of the same name someone else made (it cannot be opened):
# the lines go to a file of a new name next to it.
function Add-PSGPOAuditLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string[]]$Line
    )

    $share = if (-not $IsWindows) { Get-PSGPOAuditShare -Path $Folder }
    foreach ($try in 1, 2) {
        $target = if ($try -eq 1) { $Name } else { $Name -replace '\.jsonl$', "-$([guid]::NewGuid().ToString('N').Substring(0, 8)).jsonl" }
        try {
            if ($share) { Add-PSGPOAuditShareLine -Share $share -Name $target -Line $Line }
            else {
                $file = [System.IO.Path]::Combine([string[]](@($Folder) + @($target -split '\\')))
                foreach ($one in $Line) { Add-PSGPOAuditFileLine -File $file -Line $one }
            }
            if ($try -eq 2) { Write-Warning "The file $Name of the audit log is not the account's (someone else made it): the change is in $target." }
            return
        } catch [System.UnauthorizedAccessException] {
            if ($try -eq 2) { throw }
        } catch {
            if ($try -eq 2 -or "$($_.Exception.Message)" -notmatch 'ACCESS_DENIED') { throw }
        }
    }
}

# Windows, or a folder of the computer: the line appended to the file with FILE_APPEND_DATA only
# (the owner of a file of the share has no more), the folder of the tier created when needed.
function Add-PSGPOAuditFileLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$File,
        [Parameter(Mandatory)] [string]$Line
    )

    New-PSGPOFolder -Path ([System.IO.Path]::GetDirectoryName($File))
    # Several consoles may write the same file: a few tries, each line in one write.
    for ($try = 1; ; $try++) {
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes((Add-PSGPOAuditChain -Line $Line -Previous (Get-PSGPOAuditLastLine -File $File)) + "`n")
            $stream = if ($IsWindows) {
                [System.IO.FileSystemAclExtensions]::Create([System.IO.FileInfo]::new($File), [System.IO.FileMode]::Append,
                    [System.Security.AccessControl.FileSystemRights]'AppendData, Synchronize', [System.IO.FileShare]::ReadWrite, 4096, [System.IO.FileOptions]::None, $null)
            } else {
                [System.IO.FileStream]::new($File, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            }
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
            return
        } catch [System.UnauthorizedAccessException] {
            throw
        } catch [System.IO.IOException] {
            if ($try -ge 5) { throw }
            Start-Sleep -Milliseconds (100 * $try)
        }
    }
}

# A change of the audit log in the log of the system: what, by whom, from where, on what, and the
# entry itself as JSON, with the event ID of its action.
function Write-PSGPOAuditSystemLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Collections.IDictionary]$Entry)

    $id = $script:PSGPOAuditEventId["$($Entry.Action)"]
    if (-not $id) { $id = 1000 }
    $on = @($Entry.GpoName, $Entry.Target | Where-Object { $_ }) -join ' - '
    $text = "HGPM audit: $($Entry.Action) by $($Entry.Account) from $($Entry.Computer) on $($Entry.Domain): $on" + [Environment]::NewLine + (ConvertTo-Json -InputObject $Entry -Depth 5 -Compress)
    Write-PSGPOSystemLog -Level Information -EventId $id -Message $text
}

# Linux: a line appended to a file of the share of the log with the SMB client of Samba (Python
# bindings, Kerberos): the file opened with FILE_APPEND_DATA (no more for its owner), its last
# line read, the line chained to it and written at its end, the folder of the tier created when
# needed. Not smbclient get and put: the owner cannot write the file, and each line would copy it.
$script:PSGPOAuditAppendPython = @'
import base64, hashlib, re, sys
from samba import param, NTSTATUSError
from samba.credentials import Credentials, MUST_USE_KERBEROS, SMB_SIGNING_REQUIRED
from samba.samba3 import param as s3param
from samba.samba3 import libsmb_samba_internal as libsmb

server, share, path = sys.argv[1:4]
new = [base64.b64decode(text).decode('utf-8') for text in sys.argv[4:]]
lp = param.LoadParm()
lp.load_default()
creds = Credentials()
creds.guess(lp)
creds.set_kerberos_state(MUST_USE_KERBEROS)
creds.set_smb_signing(SMB_SIGNING_REQUIRED)
s3_lp = s3param.get_context()
if lp.configfile:
    s3_lp.load(lp.configfile)
conn = libsmb.Conn(server, share, lp=s3_lp, creds=creds)
parts = path.split('\\')
for index in range(1, len(parts)):
    folder = '\\'.join(parts[:index])
    if not conn.chkpath(folder):
        try:
            conn.mkdir(folder)
        except NTSTATUSError:
            pass
# FILE_READ_DATA | FILE_APPEND_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE, open or create.
try:
    fnum, created, _ = conn.create_ex(path, DesiredAccess=0x1 | 0x4 | 0x80 | 0x20000 | 0x100000, ShareAccess=7, CreateDisposition=3)
except NTSTATUSError as error:
    if error.args[0] == 0xC0000022:
        print('ACCESS_DENIED: ' + path)
        sys.exit(3)
    raise
try:
    end = created['end_of_file']
    previous = None
    if end:
        start = max(0, end - 65536)
        tail = conn.read(fnum, start, end - start).decode('utf-8', 'replace')
        lines = [text for text in tail.split('\n') if text.strip()]
        previous = lines[-1] if lines else None
    for line in new:
        seq, digest = 1, ''
        if previous is not None:
            digest = hashlib.sha256(previous.encode('utf-8')).hexdigest().upper()
            match = re.match(r'^\{"Seq":(\d+),', previous)
            if match:
                seq = int(match.group(1)) + 1
        chained = '{"Seq":%d,"PrevHash":"%s",%s' % (seq, digest, line[1:])
        data = (chained + '\n').encode('utf-8')
        conn.write(fnum, data, end)
        end += len(data)
        previous = chained
finally:
    conn.close(fnum)
print(path)
'@

function Add-PSGPOAuditShareLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Share,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string[]]$Line
    )

    $python = Get-Command -Name 'python3' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) { throw 'The audit log on a share needs python3 and the Samba Python bindings (Debian/Ubuntu: apt install python3-samba).' }
    $remote = (@($Share.Folder, $Name) | Where-Object { $_ }) -join '\'
    $encoded = foreach ($one in $Line) { [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($one)) }
    $result = Invoke-PSGPONativeCommand -FilePath $python.Source -ArgumentList (@('-c', $script:PSGPOAuditAppendPython, $Share.Server, $Share.Share, $remote) + @($encoded))
    if ($result.ExitCode -eq 3) { throw "ACCESS_DENIED: the file $remote of the audit log cannot be opened." }
    if ($result.ExitCode -ne 0) {
        $lines = @("$($result.Error)" -split '\r?\n' | Where-Object { $_ })
        $message = if ($lines -match 'ModuleNotFoundError') { 'the Samba Python bindings are missing (Debian/Ubuntu: apt install python3-samba)' } elseif ($lines) { $lines[-1] } else { "exit code $($result.ExitCode)" }
        throw "The line is not added to $remote of the audit log: $message"
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
# account can read (a central log: the tiers it may read), each checked (Read-PSGPOAuditFile) with
# the owner of its file.
function Read-PSGPOAuditEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$Domain
    )

    $share = if (-not $IsWindows) { Get-PSGPOAuditShare -Path $Path }
    $local = $null
    $owners = @{}
    if ($share) {
        # Linux: the files of the share the account can read, copied first (the folders of the
        # other tiers are refused: not a failure), and the owners of the files.
        $local = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-audit-$([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $local
        $command = 'prompt OFF; recurse ON; lcd "{0}"; {1}mget *' -f $local, $(if ($share.Folder) { 'cd "{0}"; ' -f $share.Folder })
        $copied = Invoke-PSGPOSmbClient -Server $share.Server -Share $share.Share -TimeoutSeconds 600 -AllowMissing -IgnoreExitCode -IgnoreStatus 'NT_STATUS_ACCESS_DENIED', 'NT_STATUS_NO_SUCH_FILE' -Command $command
        if ($null -eq $copied) { Remove-Item -LiteralPath $local -Recurse -Force; return }
        try {
            foreach ($pair in (Get-PSGPOAuditShareOwner -Share $share).GetEnumerator()) { $owners[(Join-Path $local ($pair.Key -replace '\\', [System.IO.Path]::DirectorySeparatorChar))] = $pair.Value }
        } catch {
            Write-Verbose "The owners of the files of the audit log cannot be read: $($_.Exception.GetBaseException().Message)"
        }
        $Path = $local
    }
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
        $filter = if ($Domain) { "$($Domain -replace '[^\w.-]', '_')-*.jsonl" } else { '*.jsonl' }
        # The folders the account cannot read (the other tiers) are left out.
        $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Filter $filter -ErrorAction SilentlyContinue | Sort-Object FullName)
        if (-not $share -and $IsWindows) {
            foreach ($file in $files) {
                try { $owners[$file.FullName] = ([System.IO.FileSystemAclExtensions]::GetAccessControl($file)).GetOwner([System.Security.Principal.SecurityIdentifier]).Value } catch { Write-Verbose "The owner of $($file.FullName) cannot be read." }
            }
        }
        Read-PSGPOAuditFile -File $files -Owner $owners
    } finally {
        if ($local) { Remove-Item -LiteralPath $local -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Linux: the owner (SID) of each file of the log on its share, by path in the share folder.
$script:PSGPOAuditOwnerPython = @'
import sys
from samba import param, NTSTATUSError
from samba.credentials import Credentials, MUST_USE_KERBEROS, SMB_SIGNING_REQUIRED
from samba.dcerpc import security
from samba.samba3 import param as s3param
from samba.samba3 import libsmb_samba_internal as libsmb

server, share, root = sys.argv[1:4]
lp = param.LoadParm()
lp.load_default()
creds = Credentials()
creds.guess(lp)
creds.set_kerberos_state(MUST_USE_KERBEROS)
creds.set_smb_signing(SMB_SIGNING_REQUIRED)
s3_lp = s3param.get_context()
if lp.configfile:
    s3_lp.load(lp.configfile)
conn = libsmb.Conn(server, share, lp=s3_lp, creds=creds)

def walk(folder, relative):
    try:
        items = conn.list(folder)
    except NTSTATUSError:
        return
    for item in items:
        name = item['name']
        if name in ('.', '..'):
            continue
        path = folder + '\\' + name if folder else name
        rel = relative + '\\' + name if relative else name
        if item['attrib'] & 0x10:
            walk(path, rel)
        elif name.endswith('.jsonl'):
            try:
                owner = conn.get_acl(path, security.SECINFO_OWNER).owner_sid
                print('%s\t%s' % (rel, owner))
            except NTSTATUSError:
                pass

walk(root, '')
'@

function Get-PSGPOAuditShareOwner {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [pscustomobject]$Share)

    $owners = @{}
    $python = Get-Command -Name 'python3' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) { return $owners }
    $result = Invoke-PSGPONativeCommand -FilePath $python.Source -ArgumentList '-c', $script:PSGPOAuditOwnerPython, $Share.Server, $Share.Share, "$($Share.Folder)" -TimeoutSeconds 600
    if ($result.ExitCode -ne 0) { throw "The owners of the files of the audit log cannot be read: $(@("$($result.Error)" -split '\r?\n' | Where-Object { $_ })[-1])" }
    # The output is a line each, or one text: both split into lines.
    foreach ($text in @(@($result.Output) | ForEach-Object { "$_" -split '\r?\n' } | Where-Object { $_ -match "`t" })) {
        $path, $sid = $text -split "`t", 2
        $owners[$path] = $sid.Trim()
    }
    $owners
}

# The entries of files of the log, newest first, each checked: Check is Verified (its line is
# chained to the previous one of its file, its tier is the folder of its file, the owner of its
# file is its account, or the account that imported it), Altered (the chain breaks: a line
# before it was changed or removed), TierMismatch, OwnerMismatch, or NotChained (written before
# 0.1.15). $Owner: the owner (SID) of each file, by its full path.
function Read-PSGPOAuditFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.IO.FileInfo[]]$File,
        [hashtable]$Owner = @{}
    )

    $tiers = 'Tier0', 'Tier1', 'Tier2', 'Unassigned'
    # The order of the lines breaks the ties: two changes of the same instant.
    $order = 0
    $entries = foreach ($file in $File) {
        $number = 0
        $previous = $null
        $folder = Split-Path -Leaf (Split-Path -Parent $file.FullName)
        $fileOwner = $Owner[$file.FullName]
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            $number++
            if (-not $line.Trim()) { continue }
            $before = $previous
            $previous = $line
            try {
                $read = ConvertFrom-Json -InputObject $line -AsHashtable
            } catch {
                Write-Warning "Line $number of $($file.FullName) ignored: it is not an entry of the audit log."
                continue
            }
            if ($read.Format -ne $script:PSGPOAuditFormat) { continue }
            $check = 'Verified'
            if ($null -eq $read.Seq) {
                $check = 'NotChained'
            } else {
                $expected = if ($null -ne $before -and $before -match '^\{"Seq":(\d+),') { [long]$Matches[1] + 1 } else { 1 }
                $hash = if ($null -ne $before) { Get-PSGPOAuditLineHash -Line $before } else { '' }
                if ([long]$read.Seq -ne $expected -or "$($read.PrevHash)" -ne $hash) { $check = 'Altered' }
            }
            if ($check -in 'Verified', 'NotChained' -and $read.Tier -and $tiers -contains $folder -and $read.Tier -ne $folder) { $check = 'TierMismatch' }
            $writer = if ($read.ImportedBySid) { $read.ImportedBySid } else { $read.AccountSid }
            # A file a member of Administrators made belongs to Administrators (Windows and Samba):
            # only an administrator has such a file, the owner of a line of Tier 0.
            $owned = $writer -eq $fileOwner -or ($fileOwner -eq 'S-1-5-32-544' -and $read.Tier -eq 'Tier0')
            if ($check -in 'Verified', 'NotChained' -and $writer -and $fileOwner -and -not $owned) { $check = 'OwnerMismatch' }
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
                Check = $check
                ImportedBy = $read.ImportedBy
                ImportedFrom = $read.ImportedFrom
                File = $file.Name
                Order = $order++
            }
        }
    }
    @($entries | Sort-Object -Property @{ Expression = 'Time'; Descending = $true }, @{ Expression = 'Order'; Descending = $true } | Select-Object -Property * -ExcludeProperty Order |
            ForEach-Object { $_.PSObject.TypeNames.Insert(0, 'PSGPOTools.AuditEntry'); $_ })
}
