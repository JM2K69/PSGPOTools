<#
    Audit log: what the consoles and the commands change in a domain, one JSON line per change,
    never rewritten: when, who (the account of the directory), from which computer, on which
    domain controller, what (Action), on what (Target: a GPO, a container, the configuration) and
    how (Details). Only the changes the domain accepted are written: they are logged once made.

    The folder is Audit.Path of the configuration of the domain, the same for every console (a
    share the administrators write); by default the folder Audit of the backups of the account.
    One file per domain and month: <domain>-<yyyy-MM>.jsonl. On by default: Audit.Enabled = $false
    in the configuration of the domain stops it.
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
    SaveConfiguration = 'Configuration saved'; InstallAdmx = 'ADMX files installed'
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
        Details = $Details
    }
    $line = (ConvertTo-Json -InputObject $entry -Depth 5 -Compress) + "`n"
    try {
        $folder = Get-PSGPOAuditPath
        $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop
        $file = Join-Path $folder ('{0}-{1}.jsonl' -f ($Directory.DomainName -replace '[^\w.-]', '_'), $now.ToString('yyyy-MM'))
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
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

# The entries of the audit log, newest first.
function Read-PSGPOAuditEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$Domain
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $filter = if ($Domain) { "$($Domain -replace '[^\w.-]', '_')-*.jsonl" } else { '*.jsonl' }
    # The order of the lines breaks the ties: two changes of the same instant.
    $order = 0
    $entries = foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Filter $filter | Sort-Object Name)) {
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
                Time = [datetime]::Parse($read.Time, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                Domain = $read.Domain
                Server = $read.Server
                Account = $read.Account
                Computer = $read.Computer
                Action = $read.Action
                Target = $read.Target
                GpoId = if ($read.GpoId) { [guid]$read.GpoId }
                GpoName = $read.GpoName
                Details = $read.Details
                Order = $order++
            }
        }
    }
    @($entries | Sort-Object -Property @{ Expression = 'Time'; Descending = $true }, @{ Expression = 'Order'; Descending = $true } | Select-Object -Property * -ExcludeProperty Order |
            ForEach-Object { $_.PSObject.TypeNames.Insert(0, 'PSGPOTools.AuditEntry'); $_ })
}
