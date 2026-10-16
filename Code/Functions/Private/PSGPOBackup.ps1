<#
    Backups of GPOs, and what changed between two of them (the timeline of a GPO).

    A backup is a folder <root>/<GPO name> {<GUID>}/<last change, UTC: yyyy-MM-dd_HH-mm-ss>/ with:
    - manifest.json: the GPO (identity, versions, status, security filtering, links) and the
      SHA-256 of each file;
    - Files/: the files of its SYSVOL folder, as they are (GPT.INI, Registry.pol, GptTmpl.inf,
      scripts, preferences...).
    - notes.json, when the backup has notes: its comment and labels, written with the backup or
      later (Set-PSGPOBackup, History tab); the manifest and the files never change.
    The GUID keeps the history of a GPO that is renamed. A backup is written only when the GPO
    changed since the last one (its files or its properties), as Backup-GPO by date of change.

    The newest backup with the approved label of the configuration (Backup.ApprovedLabel) is the
    approved version of the GPO: what changed since, made in the console or elsewhere (GPMC,
    samba-tool), is its drift (Get-PSGPODriftState).

    The settings of a backup (Get-PSGPOBackupSetting) are those of the Settings tab: the policies
    of the Registry.pol files (by category path, with the loaded ADMX), the security settings,
    the other files by their hash, and the properties of the GPO; two backups are compared
    setting by setting (Compare-PSGPOSettingReport).
#>

$script:PSGPOBackupFormat = 'PSGPOTools.Backup/1'
$script:PSGPOBackupNotesFormat = 'PSGPOTools.BackupNotes/1'

# The labels of a backup, checked: trimmed, each once (case ignored), in their order.
function ConvertTo-PSGPOBackupLabel {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowNull()] [AllowEmptyCollection()] [string[]]$Label)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $labels = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Label)) {
        $text = "$item".Trim()
        if (-not $text) { continue }
        if ($text.Length -gt 64 -or $text -match '[,\r\n\t]') {
            throw "A label has at most 64 characters, and no comma, tab or line break: '$text'."
        }
        if ($seen.Add($text)) { $labels.Add($text) }
    }
    , [string[]]$labels
}

# Label of the approved versions of the GPOs (Configuration.psd1, Backup.ApprovedLabel).
function Get-PSGPOApprovedLabel {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    (Get-PSGPOConfigurationData).Backup.ApprovedLabel
}

# The notes of a backup folder: Comment, Labels, Updated (UTC) and UpdatedBy; empty when it has none.
function Read-PSGPOBackupNote {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    $notes = @{ Comment = ''; Labels = [string[]]@(); Updated = $null; UpdatedBy = $null }
    $file = Join-Path $Path 'notes.json'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $notes }
    try {
        $read = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
        if ($read.Format -ne $script:PSGPOBackupNotesFormat) { throw "unknown format '$($read.Format)'" }
        $notes.Comment = "$($read.Comment)"
        $notes.Labels = ConvertTo-PSGPOBackupLabel -Label @($read.Labels)
        $notes.UpdatedBy = $read.UpdatedBy
        if ($read.Updated) {
            $notes.Updated = if ($read.Updated -is [datetime]) { $read.Updated.ToUniversalTime() }
                else { [datetime]::Parse($read.Updated, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal) }
        }
    } catch {
        Write-Warning "The notes of the backup $Path are ignored: $($_.Exception.Message)"
    }
    $notes
}

# Writes the notes of a backup (all of them: the comment and the labels replace those it had), at
# once through a temporary file; no comment and no label removes notes.json. Returns the backup
# with its new notes.
function Save-PSGPOBackupNote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Backup,
        [AllowNull()] [AllowEmptyString()] [string]$Comment,
        [AllowNull()] [AllowEmptyCollection()] [string[]]$Label,
        [string]$Account
    )

    $labels = ConvertTo-PSGPOBackupLabel -Label $Label
    $Comment = "$Comment".Trim()
    $file = Join-Path $Backup.Path 'notes.json'
    if (-not $Comment -and -not $labels.Count) {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        $updated = $null
        $Account = $null
    } else {
        if (-not $Account) { $Account = [Environment]::UserName }
        $updated = [datetime]::UtcNow
        $temporary = Join-Path $Backup.Path "notes.$([guid]::NewGuid().ToString('N')).tmp"
        [ordered]@{
            Format = $script:PSGPOBackupNotesFormat
            Comment = $Comment
            Labels = $labels
            Updated = $updated.ToString('o')
            UpdatedBy = $Account
        } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $temporary -Encoding utf8
        Move-Item -LiteralPath $temporary -Destination $file -Force
    }
    $Backup.Comment = $Comment
    $Backup.Labels = $labels
    $Backup.NotesUpdated = $updated
    $Backup.NotesUpdatedBy = $Account
    $Backup
}

# Name of the folder of a GPO in the backups: its display name, without the characters a file
# name cannot hold, and its GUID.
function Get-PSGPOBackupFolderName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [GPOToolsGpo]$Gpo)

    $name = ("$($Gpo.DisplayName)".Trim() -replace '[\\/:*?"<>|\x00-\x1F]', '_').TrimEnd('.', ' ')
    if ($name.Length -gt 80) { $name = $name.Substring(0, 80).TrimEnd() }
    '{0} {{{1}}}' -f $name, $Gpo.Id.ToString().ToUpperInvariant()
}

function Get-PSGPOFileHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Bytes)

    [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes))
}

# What a backup keeps of a GPO besides its files.
function Get-PSGPOBackupProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    # Not "if (...) { @(...) }": the output of if unrolls an empty list into $null.
    $filtering = $null
    if ($null -ne $Gpo.SecurityFiltering) { $filtering = [string[]]@($Gpo.SecurityFiltering) }
    $denied = $null
    if ($null -ne $Gpo.DeniedTo) { $denied = [string[]]@($Gpo.DeniedTo) }
    [ordered]@{
        DisplayName = $Gpo.DisplayName
        Version = $Gpo.Version
        ComputerVersion = $Gpo.GetComputerVersion()
        UserVersion = $Gpo.GetUserVersion()
        Flags = $Gpo.Flags
        Status = $Gpo.GetStatus()
        SecurityFiltering = $filtering
        DeniedTo = $denied
        MachineExtensionNames = $Gpo.MachineExtensionNames
        UserExtensionNames = $Gpo.UserExtensionNames
        Links = @(foreach ($pair in @($Directory.GetLinksOf($Gpo) | Sort-Object { $_.Som.DistinguishedName })) {
                [ordered]@{ Container = $pair.Som.DistinguishedName; Enabled = $pair.Link.Enabled; Enforced = $pair.Link.Enforced; Order = $pair.Link.Order }
            })
    }
}

# Backups of a root folder, newest first; those of one GPO with -Id.
function Get-PSGPOBackupEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [guid]$Id = [guid]::Empty
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $folders = if ($Id -ne [guid]::Empty) {
        @(Get-ChildItem -LiteralPath $Path -Directory | Where-Object { $_.Name.EndsWith("{$($Id.ToString().ToUpperInvariant())}", [System.StringComparison]::OrdinalIgnoreCase) })
    } else {
        @(Get-ChildItem -LiteralPath $Path -Directory)
    }
    $entries = foreach ($gpoFolder in $folders) {
        foreach ($backupFolder in @(Get-ChildItem -LiteralPath $gpoFolder.FullName -Directory)) {
            $manifest = Join-Path $backupFolder.FullName 'manifest.json'
            if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
            try {
                $read = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -AsHashtable
            } catch {
                Write-Warning "Backup ignored, its manifest cannot be read: $manifest"
                continue
            }
            if ($read.Format -ne $script:PSGPOBackupFormat) { Write-Warning "Backup ignored, unknown format '$($read.Format)': $manifest"; continue }
            ConvertTo-PSGPOBackupEntry -Manifest $read -Path $backupFolder.FullName -Note (Read-PSGPOBackupNote -Path $backupFolder.FullName)
        }
    }
    @($entries | Sort-Object -Property @{ Expression = 'BackedUp'; Descending = $true })
}

function ConvertTo-PSGPOBackupEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Manifest,
        [string]$Path,
        [string]$Result,
        [hashtable]$Note = @{ Comment = ''; Labels = [string[]]@() }
    )

    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        if ($Value) { return [datetime]::Parse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal) }
        $null
    }
    $gpo = $Manifest.Gpo
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Backup'
        Path = $Path
        Id = [guid]$gpo.Id
        DisplayName = $gpo.DisplayName
        Domain = $Manifest.Domain
        BackedUp = & $date $Manifest.BackedUp
        # Account the backup was made with
        BackedUpBy = $Manifest.Account
        Modified = & $date $gpo.Modified
        Version = [int]$gpo.Version
        ComputerVersion = [int]$gpo.ComputerVersion
        UserVersion = [int]$gpo.UserVersion
        Status = $gpo.Status
        SecurityFiltering = $gpo.SecurityFiltering
        DeniedTo = $gpo.DeniedTo
        Links = @($gpo.Links)
        Flags = [int]$gpo.Flags
        # $null in a backup of a GPO whose extensions were not read
        MachineExtensionNames = $gpo.MachineExtensionNames
        UserExtensionNames = $gpo.UserExtensionNames
        Files = @($Manifest.Files)
        # Notes of the backup (notes.json)
        Comment = "$($Note.Comment)"
        Labels = [string[]]@($Note.Labels)
        NotesUpdated = $Note.Updated
        NotesUpdatedBy = $Note.UpdatedBy
        Result = $Result
    }
}

# Writes a backup of the GPO in $Path, unless the last one is the same (Result 'Unchanged'), with
# a comment and labels. When the GPO did not change, the last backup is the GPO as it is: it gets
# the labels, not the comment (Set-PSGPOBackup changes it).
function Save-PSGPOBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [string]$Path,
        [string]$Comment,
        [string[]]$Label,
        [switch]$Force
    )

    $Comment = "$Comment".Trim()
    $labels = ConvertTo-PSGPOBackupLabel -Label $Label

    # The GPO as it is now: it may have changed since the directory was read.
    $Directory.RefreshGpo($Gpo)
    $files = $Directory.ReadGpoFolder($Gpo)
    $properties = Get-PSGPOBackupProperty -Directory $Directory -Gpo $Gpo
    $fileList = @(foreach ($name in $files.Keys) {
            [ordered]@{ Path = $name; Size = $files[$name].Length; Sha256 = Get-PSGPOFileHash -Bytes $files[$name] }
        })

    $last = Get-PSGPOBackupEntry -Path $Path -Id $Gpo.Id | Select-Object -First 1
    if ($last -and -not $Force) {
        $same = (ConvertTo-Json -Depth 5 -Compress @($last.Files)) -eq (ConvertTo-Json -Depth 5 -Compress $fileList) -and
            $last.Version -eq $properties.Version -and $last.Status -eq $properties.Status -and $last.DisplayName -ceq $properties.DisplayName -and
            (ConvertTo-Json -Compress @($last.SecurityFiltering)) -eq (ConvertTo-Json -Compress @($properties.SecurityFiltering)) -and
            (ConvertTo-Json -Compress @($last.DeniedTo)) -eq (ConvertTo-Json -Compress @($properties.DeniedTo)) -and
            (ConvertTo-Json -Depth 5 -Compress @($last.Links)) -eq (ConvertTo-Json -Depth 5 -Compress @($properties.Links))
        if ($same) {
            # Its labels (the approval of the GPO as it is); the comment is of a change: none here.
            if (@($labels | Where-Object { $_ -notin @($last.Labels) }).Count) {
                $last = Save-PSGPOBackupNote -Backup $last -Comment $last.Comment -Label (@($last.Labels) + @($labels)) -Account $Directory.Account
            }
            $last.Result = 'Unchanged'
            return $last
        }
    }

    $now = [datetime]::UtcNow
    $stamp = if ($Gpo.Modified) { ([datetime]$Gpo.Modified).ToUniversalTime() } else { $now }
    $gpoFolder = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.EndsWith("{$($Gpo.Id.ToString().ToUpperInvariant())}", [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    $gpoFolder = if ($gpoFolder) { $gpoFolder.FullName } else { Join-Path $Path (Get-PSGPOBackupFolderName -Gpo $Gpo) }
    $name = $stamp.ToString('yyyy-MM-dd_HH-mm-ss', [cultureinfo]::InvariantCulture)
    $destination = Join-Path $gpoFolder $name
    for ($i = 2; Test-Path -LiteralPath $destination; $i++) { $destination = Join-Path $gpoFolder "$name-$i" }

    $null = New-Item -ItemType Directory -Path (Join-Path $destination 'Files') -Force
    foreach ($file in $files.Keys) {
        $target = Join-Path $destination 'Files' ($file -split '\\')
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
        [System.IO.File]::WriteAllBytes($target, [byte[]]$files[$file])
    }
    $gpoManifest = [ordered]@{
        Id = $Gpo.Id.ToString()
        DistinguishedName = $Gpo.DistinguishedName
        FileSysPath = $Gpo.FileSysPath
        Modified = if ($Gpo.Modified) { ([datetime]$Gpo.Modified).ToUniversalTime().ToString('o') } else { $null }
    }
    foreach ($key in $properties.Keys) { $gpoManifest[$key] = $properties[$key] }
    $manifest = [ordered]@{
        Format = $script:PSGPOBackupFormat
        BackedUp = $now.ToString('o')
        Domain = $Directory.DomainName
        Server = if ($Directory -is [GPOToolsLdapDirectory]) { $Directory.Server } else { $null }
        Account = $Directory.Account
        Gpo = $gpoManifest
        Files = $fileList
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $destination 'manifest.json') -Encoding utf8
    Write-Verbose "GPO '$($Gpo.DisplayName)' backed up in $destination."
    $entry = ConvertTo-PSGPOBackupEntry -Manifest ($manifest | ConvertTo-Json -Depth 6 | ConvertFrom-Json -AsHashtable) -Path $destination -Result 'Created'
    if ($Comment -or $labels.Count) { $entry = Save-PSGPOBackupNote -Backup $entry -Comment $Comment -Label $labels -Account $Directory.Account }
    $entry
}

# The approved version of a GPO and what changed since: State InSync (the GPO is the approved
# version), Drifted (Changes: from the approved version to the GPO now) or NotApproved (no backup
# with the label). $Backups: the backups of the GPO, read when not given; $Current: the settings
# of the GPO now (Get-PSGPOSettingReport), read when not given.
function Get-PSGPODriftState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [string]$Path,
        [AllowEmptyCollection()] [object[]]$Backups,
        [AllowEmptyCollection()] [object[]]$Current,
        [object[]]$ApprovedSetting,
        [string]$Label = (Get-PSGPOApprovedLabel)
    )

    if ($null -eq $Backups) { $Backups = @(Get-PSGPOBackupEntry -Path $Path -Id $Gpo.Id) }
    $approved = $Backups | Where-Object { $_.Labels -contains $Label } | Sort-Object BackedUp -Descending | Select-Object -First 1
    $state = [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Drift'
        DisplayName = $Gpo.DisplayName
        Id = $Gpo.Id
        State = 'NotApproved'
        Approved = $null
        ApprovedBy = $null
        ApprovedBackup = $approved
        Changes = @()
    }
    if (-not $approved) { return $state }
    if ($null -eq $Current) {
        $Directory.RefreshGpo($Gpo)
        $Current = @(Get-PSGPOSettingReport -Files $Directory.ReadGpoFolder($Gpo) -Property (Get-PSGPOBackupProperty -Directory $Directory -Gpo $Gpo))
    }
    if ($null -eq $ApprovedSetting) { $ApprovedSetting = @(Get-PSGPOBackupSetting -Backup $approved) }
    $state.Approved = if ($approved.Modified) { $approved.Modified } else { $approved.BackedUp }
    $state.ApprovedBy = if ($approved.NotesUpdatedBy) { $approved.NotesUpdatedBy } else { $approved.BackedUpBy }
    $state.Changes = @(Compare-PSGPOSettingReport -Reference $ApprovedSetting -Difference $Current)
    $state.State = if ($state.Changes.Count) { 'Drifted' } else { 'InSync' }
    $state
}

# The files of a backup, by path in the GPO folder (Machine\Registry.pol).
function Read-PSGPOBackupFile {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] $Backup)

    $files = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($Backup.Files)) {
        $local = Join-Path $Backup.Path 'Files' ("$($file.Path)" -split '\\')
        if (Test-Path -LiteralPath $local -PathType Leaf) { $files[$file.Path] = [System.IO.File]::ReadAllBytes($local) }
    }
    , $files
}

# Settings of a GPO from its files and properties, as rows Scope / Path / Name / State / Options
# with a Key to compare them: the Settings tab (policies of the loaded ADMX, security settings,
# extra registry values), the other files by their hash, and the properties of the GPO.
function Get-PSGPOSettingReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Property
    )

    function New-ReportRow {
        param([string]$Scope, [string]$Path, [string]$Name, [string]$State, [string]$Options, [string]$Detail)
        [pscustomobject]@{
            Key = "$Scope|$Path|$Name$(if ($Detail) { "|$Detail" })"
            Scope = $Scope; Path = $Path; Name = $Name; State = $State; Options = $Options
        }
    }

    New-ReportRow 'GPO' 'Properties' 'Name' $Property.DisplayName
    New-ReportRow 'GPO' 'Properties' 'GPO status' $Property.Status
    New-ReportRow 'GPO' 'Properties' 'Security filtering' $(if ($null -eq $Property.SecurityFiltering) { 'Not read' } else { @($Property.SecurityFiltering) -join ', ' })
    New-ReportRow 'GPO' 'Properties' 'Denied to' (@($Property.DeniedTo) -join ', ')
    foreach ($link in @($Property.Links)) {
        New-ReportRow 'GPO' 'Links' $link.Container ('{0}, {1}' -f $(if ($link.Enabled) { 'Link enabled' } else { 'Link disabled' }), $(if ($link.Enforced) { 'enforced' } else { 'not enforced' }))
    }

    $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($scope in 'Machine', 'User') {
        $polPath = "$scope\Registry.pol"
        [void]$known.Add($polPath)
        $label = if ($scope -eq 'Machine') { 'Computer' } else { 'User' }
        $rows = @()
        if ($Files.Contains($polPath)) {
            $rows += @(Get-PSGPOConfiguredSetting -Pol ([GPOToolsRegistryPol]::Parse([byte[]]$Files[$polPath])) -Scope $scope)
        }
        if ($scope -eq 'Machine') {
            $template = [GPOToolsDirectory]::SecurityTemplatePath
            [void]$known.Add($template)
            if ($Files.Contains($template)) {
                $rows = @(Get-PSGPOConfiguredSecuritySetting -Template ([GPOToolsSecurityTemplate]::Parse([byte[]]$Files[$template]))) + $rows
            }
        }
        foreach ($row in $rows) {
            # Extra registry values share their key: the value name tells them apart.
            $detail = if ($row.IsExtra -and $row.Options) { ($row.Options -split ' = ', 2)[0] }
            New-ReportRow $label $row.Path $row.Name $row.State $row.Options $detail
        }
        # The preference items, by their uid.
        foreach ($extension in @(Get-PSGPOPreferenceExtension -Scope $scope)) { [void]$known.Add((Get-PSGPOPreferencePath -Extension $extension -Scope $scope)) }
        foreach ($row in @(Get-PSGPOConfiguredPreference -Files $Files -Scope $scope)) {
            [pscustomobject]@{ Key = $row.Key; Scope = $row.Scope; Path = $row.Path; Name = $row.Name; State = $row.State; Options = $row.Options }
        }
    }

    # The other files: changed when their content changed. GPT.INI only holds the version.
    foreach ($name in $Files.Keys) {
        if ($known.Contains($name) -or $name -eq 'GPT.INI') { continue }
        $hash = Get-PSGPOFileHash -Bytes ([byte[]]$Files[$name])
        New-ReportRow 'Files' 'Other files of the GPO' $name "$($Files[$name].Length) bytes, SHA-256 $($hash.Substring(0, 12))"
    }
}

# The settings of a backup (Get-PSGPOSettingReport).
function Get-PSGPOBackupSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Backup)

    $property = @{
        DisplayName = $Backup.DisplayName; Status = $Backup.Status; SecurityFiltering = $Backup.SecurityFiltering
        DeniedTo = $Backup.DeniedTo; Links = $Backup.Links
    }
    Get-PSGPOSettingReport -Files (Read-PSGPOBackupFile -Backup $Backup) -Property $property
}

# What changed from $Reference (older) to $Difference (newer), setting by setting: Added,
# Removed or Changed, with the value before and after.
function Compare-PSGPOSettingReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Reference,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Difference
    )

    $text = { param($Row) if (-not $Row) { return '' }; (@($Row.State, $Row.Options) | Where-Object { $_ }) -join [Environment]::NewLine }
    $before = [ordered]@{}
    foreach ($row in $Reference) { $before[$row.Key] = $row }
    $after = [ordered]@{}
    foreach ($row in $Difference) { $after[$row.Key] = $row }

    $changes = foreach ($key in @($before.Keys) + @($after.Keys | Where-Object { -not $before.Contains($_) })) {
        $old = $before[$key]
        $new = $after[$key]
        $change = if (-not $old) { 'Added' } elseif (-not $new) { 'Removed' } elseif ((& $text $old) -ne (& $text $new)) { 'Changed' } else { continue }
        $row = if ($new) { $new } else { $old }
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.SettingChange'
            Change = $change; Scope = $row.Scope; Path = $row.Path; Name = $row.Name
            Before = & $text $old; After = & $text $new
        }
    }
    $order = @{ GPO = 0; Computer = 1; User = 2; Files = 3 }
    @($changes | Sort-Object { $order[$_.Scope] }, Path, Name)
}

# Folder of the backups of the console: the one chosen last, else "PSGPOTools Backups" in the
# documents of the user.
function Get-PSGPODefaultBackupPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $saved = (Get-PSGPOUserSetting).BackupPath
    if ($saved) { return $saved }
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    if (-not $documents) { $documents = $HOME }
    Join-Path $documents 'PSGPOTools Backups'
}

# The files of a backup, checked against the SHA-256 of its manifest: a file missing or changed
# since the backup stops a restore.
function Get-PSGPOVerifiedBackupFile {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] $Backup)

    $files = Read-PSGPOBackupFile -Backup $Backup
    foreach ($file in @($Backup.Files)) {
        if (-not $files.Contains($file.Path)) { throw "The backup $($Backup.Path) is incomplete: $($file.Path) is missing." }
        if ((Get-PSGPOFileHash -Bytes ([byte[]]$files[$file.Path])) -ne $file.Sha256) { throw "The backup $($Backup.Path) was changed: $($file.Path) is not the file backed up." }
    }
    , $files
}

# Client-side extensions of the files of a GPO for a scope: Registry for its Registry.pol, and
# Security for GptTmpl.inf (computer).
function Get-PSGPOFileExtensionName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope
    )

    $names = ''
    if ($Files.Contains("$Scope\Registry.pol")) {
        $names = Add-PSGPOExtensionName -Current $names -Extension ([GPOToolsDirectory]::RegistryExtension) -Tool ([GPOToolsDirectory]::RegistryTool[$Scope])
    }
    if ($Scope -eq 'Machine' -and $Files.Contains([GPOToolsDirectory]::SecurityTemplatePath)) {
        $names = Add-PSGPOExtensionName -Current $names -Extension ([GPOToolsDirectory]::SecurityExtension) -Tool ([GPOToolsDirectory]::SecurityTool)
    }
    $names
}
