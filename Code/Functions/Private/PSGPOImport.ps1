<#
    Import of the settings of a backed up GPO into a GPO of the domain, as GPMC "Import Settings"
    does, with a migration table (.migtable) for the security principals and the UNC paths.

    The backups: those of GPMC (Backup-GPO, the Backup command of GPMC: a folder per backup, named
    by its ID, with bkupInfo.xml, Backup.xml and DomainSysvol\GPO\Machine|User), and those of
    HGPM (Backup-PSGPO). Backup.xml lists the accounts of the GPO (SecurityGroups: SID,
    sAMAccountName, type, NetBIOS and DNS domain, UPN) and its client-side extensions.

    The migration table, as the Migration Table Editor of GPMC writes it (UTF-16):
      <MigrationTable xmlns="http://www.microsoft.com/GroupPolicy/GPOOperations/MigrationTable">
        <Mapping>
          <Type>GlobalGroup</Type>                 User, Computer, LocalGroup, GlobalGroup,
                                                   UniversalGroup, UNCPath, Unknown (free text or SID)
          <Source>Domain Admins@contoso.com</Source>
          <DestinationByRelativeName />            or <DestinationSameAsSource />, <DestinationNone />,
        </Mapping>                                    <Destination>CONTOSO\Group</Destination>
      </MigrationTable>

    What is migrated, as GPMC does: the security settings (GptTmpl.inf: user rights, restricted
    groups, the permissions of files, registry keys and services), the preferences (their accounts
    and UNC paths), the scripts and the folder redirection (their UNC paths and accounts). The
    administrative templates (Registry.pol) are copied as they are: GPMC does not migrate them.
#>

$script:PSGPOMigrationNamespace = 'http://www.microsoft.com/GroupPolicy/GPOOperations/MigrationTable'
$script:PSGPOMigrationTypes = @('User', 'Computer', 'LocalGroup', 'GlobalGroup', 'UniversalGroup', 'UNCPath', 'Unknown')

# The accounts every domain has, by the SID of their own: the names the Migration Table Editor shows
# them with (a free text entry), and the SIDs a table with that name stands for.
$script:PSGPOWellKnownAccounts = [ordered]@{
    'S-1-1-0' = 'Everyone'; 'S-1-3-0' = 'CREATOR OWNER'; 'S-1-3-1' = 'CREATOR GROUP'
    'S-1-5-2' = 'NETWORK'; 'S-1-5-3' = 'BATCH'; 'S-1-5-4' = 'INTERACTIVE'; 'S-1-5-6' = 'SERVICE'; 'S-1-5-7' = 'ANONYMOUS LOGON'
    'S-1-5-9' = 'ENTERPRISE DOMAIN CONTROLLERS'; 'S-1-5-10' = 'SELF'; 'S-1-5-11' = 'Authenticated Users'; 'S-1-5-13' = 'TERMINAL SERVER USER'
    'S-1-5-14' = 'REMOTE INTERACTIVE LOGON'; 'S-1-5-18' = 'SYSTEM'; 'S-1-5-19' = 'LOCAL SERVICE'; 'S-1-5-20' = 'NETWORK SERVICE'
    'S-1-5-32-544' = 'Administrators'; 'S-1-5-32-545' = 'Users'; 'S-1-5-32-546' = 'Guests'; 'S-1-5-32-547' = 'Power Users'
    'S-1-5-32-548' = 'Account Operators'; 'S-1-5-32-549' = 'Server Operators'; 'S-1-5-32-550' = 'Print Operators'
    'S-1-5-32-551' = 'Backup Operators'; 'S-1-5-32-552' = 'Replicator'; 'S-1-5-32-554' = 'Pre-Windows 2000 Compatible Access'
    'S-1-5-32-555' = 'Remote Desktop Users'; 'S-1-5-32-556' = 'Network Configuration Operators'; 'S-1-5-32-558' = 'Performance Monitor Users'
    'S-1-5-32-559' = 'Performance Log Users'; 'S-1-5-32-560' = 'Windows Authorization Access Group'; 'S-1-5-32-561' = 'Terminal Server License Servers'
    'S-1-5-32-562' = 'Distributed COM Users'; 'S-1-5-32-568' = 'IIS_IUSRS'; 'S-1-5-32-569' = 'Cryptographic Operators'
    'S-1-5-32-573' = 'Event Log Readers'; 'S-1-5-32-574' = 'Certificate Service DCOM Access'; 'S-1-5-32-575' = 'RDS Remote Access Servers'
    'S-1-5-32-576' = 'RDS Endpoint Servers'; 'S-1-5-32-577' = 'RDS Management Servers'; 'S-1-5-32-578' = 'Hyper-V Administrators'
    'S-1-5-32-579' = 'Access Control Assistance Operators'; 'S-1-5-32-580' = 'Remote Management Users'; 'S-1-5-90-0' = 'Window Manager Group'
}

$script:PSGPOSidPattern = '(?<![\w-])S-1-\d+(?:-\d+)+(?![\w-])'
# \\server\share: the start of a UNC path, the part a migration table maps.
$script:PSGPOUncPattern = '\\\\[^\\/\s"''<>|*?,;=]+\\[^\\/\s"''<>|*?,;=]+'

# --- Backups -------------------------------------------------------------------------------------

# The value of a child element of $Node by its local name (the namespaces of GPMC change).
function Get-PSGPOXmlChildText {
    param([System.Xml.XmlNode]$Node, [string]$Name)
    if (-not $Node) { return $null }
    $child = $Node.SelectSingleNode("*[local-name()='$Name']")
    if ($child) { $child.InnerText.Trim() }
}

# The backups of GPMC in a folder: the folder itself when it is one, else the folders it holds
# (a folder per backup, as Backup-GPO writes them). One object per backup, newest first.
function Get-PSGPOGpmcBackupEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "The folder '$Path' does not exist." }
    $folders = if (Test-Path -LiteralPath (Join-Path $Path 'bkupInfo.xml')) { @(Get-Item -LiteralPath $Path) }
        else { @(Get-ChildItem -LiteralPath $Path -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bkupInfo.xml') }) }
    $entries = foreach ($folder in $folders) {
        try {
            $info = [xml][System.IO.File]::ReadAllText((Join-Path $folder.FullName 'bkupInfo.xml'))
            $instance = $info.DocumentElement
            $backup = [xml][System.IO.File]::ReadAllText((Join-Path $folder.FullName 'Backup.xml'))
            $core = $backup.SelectSingleNode("//*[local-name()='GroupPolicyCoreSettings']")
            $time = [datetime]::MinValue
            $stamp = Get-PSGPOXmlChildText $instance 'BackupTime'
            $backedUp = if ([datetime]::TryParse($stamp, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$time)) { $time } else { $null }
            $groups = @(foreach ($group in @($backup.SelectNodes("//*[local-name()='SecurityGroups']/*[local-name()='Group']"))) {
                    [pscustomobject]@{
                        Sid = Get-PSGPOXmlChildText $group 'Sid'
                        Name = Get-PSGPOXmlChildText $group 'SamAccountName'
                        Type = Get-PSGPOXmlChildText $group 'Type'
                        NetBIOSDomain = Get-PSGPOXmlChildText $group 'NetBIOSDomainName'
                        DnsDomain = Get-PSGPOXmlChildText $group 'DnsDomainName'
                        Upn = Get-PSGPOXmlChildText $group 'UPN'
                        FromDacl = $group.GetAttribute('Source', 'http://www.microsoft.com/GroupPolicy/GPOOperations') -eq 'FromDACL'
                    }
                })
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.GpmcBackup'
                Kind = 'GPMC'
                DisplayName = Get-PSGPOXmlChildText $instance 'GPODisplayName'
                Id = [guid](Get-PSGPOXmlChildText $instance 'GPOGuid')
                Domain = Get-PSGPOXmlChildText $instance 'GPODomain'
                BackedUp = $backedUp
                Comment = Get-PSGPOXmlChildText $instance 'Comment'
                BackupId = [guid](Get-PSGPOXmlChildText $instance 'ID')
                Path = $folder.FullName
                SecurityGroups = $groups
                MachineExtensionNames = Get-PSGPOXmlChildText $core 'MachineExtensionGuids'
                UserExtensionNames = Get-PSGPOXmlChildText $core 'UserExtensionGuids'
            }
        } catch {
            Write-Warning "The GPMC backup in $($folder.FullName) cannot be read: $($_.Exception.Message)"
        }
    }
    @($entries | Sort-Object BackedUp -Descending)
}

# The files of a backup of GPMC (DomainSysvol\GPO), by their path in the folder of the GPO.
function Read-PSGPOGpmcBackupFile {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] $Backup)

    $files = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
    $root = Join-Path $Backup.Path 'DomainSysvol' 'GPO'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return , $files }
    $prefix = (Get-Item -LiteralPath $root).FullName.TrimEnd('\', '/').Length + 1
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Sort-Object FullName)) {
        $path = $file.FullName.Substring($prefix) -replace '/', '\'
        # Machine and User as the folder of a GPO names them.
        $path = $path -replace '^(?i)machine\\', 'Machine\' -replace '^(?i)user\\', 'User\'
        if ($path -ieq 'GPT.INI') { continue }
        Assert-PSGPOGpoFilePath -Path $path
        $files[$path] = [System.IO.File]::ReadAllBytes($file.FullName)
    }
    , $files
}

# The backups a folder holds that can be imported: those of GPMC, and the newest backup of each
# GPO of HGPM. Kind, DisplayName, Id, Domain, BackedUp, Comment, BackupId, Path...
function Get-PSGPOImportSource {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    $gpmc = @(Get-PSGPOGpmcBackupEntry -Path $Path)
    $own = @(Get-PSGPOBackupEntry -Path $Path -ErrorAction SilentlyContinue | Group-Object Id | ForEach-Object {
            $newest = $_.Group[0]
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.ImportSource'
                Kind = 'PSGPOTools'
                DisplayName = $newest.DisplayName
                Id = $newest.Id
                Domain = $newest.Domain
                BackedUp = $newest.BackedUp
                Comment = $newest.Comment
                BackupId = Split-Path $newest.Path -Leaf
                Path = $newest.Path
                SecurityGroups = @()
                MachineExtensionNames = $newest.MachineExtensionNames
                UserExtensionNames = $newest.UserExtensionNames
                Backup = $newest
            }
        })
    @($gpmc) + @($own)
}

# The files of an import source, by their path in the folder of a GPO (without GPT.INI).
function Read-PSGPOImportFile {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] $Source)

    if ($Source.Kind -eq 'GPMC') { return , (Read-PSGPOGpmcBackupFile -Backup $Source) }
    $files = Get-PSGPOVerifiedBackupFile -Backup $Source.Backup
    $files.Remove('GPT.INI')
    , $files
}

# --- Text of the files ---------------------------------------------------------------------------

# A text file of a GPO: its text, and how to write it back as it was (UTF-16 or UTF-8, BOM or not).
function ConvertFrom-PSGPOFileByte {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Bytes)

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return [pscustomobject]@{ Text = [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2); Encoding = 'Unicode'; Bom = $true } }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return [pscustomobject]@{ Text = [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3); Encoding = 'UTF8'; Bom = $true } }
    if ($Bytes.Length -ge 2 -and $Bytes[1] -eq 0) { return [pscustomobject]@{ Text = [System.Text.Encoding]::Unicode.GetString($Bytes); Encoding = 'Unicode'; Bom = $false } }
    [pscustomobject]@{ Text = [System.Text.Encoding]::UTF8.GetString($Bytes); Encoding = 'UTF8'; Bom = $false }
}

function ConvertTo-PSGPOFileByte {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)] $File, [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)

    $encoding = if ($File.Encoding -eq 'Unicode') { [System.Text.UnicodeEncoding]::new($false, $File.Bom) } else { [System.Text.UTF8Encoding]::new($File.Bom) }
    , [byte[]](@($encoding.GetPreamble()) + @($encoding.GetBytes($Text)))
}

# The files of a GPO the migration reads and rewrites: the text ones. Registry.pol and the other
# binary files are copied as they are, as GPMC does.
function Test-PSGPOMigratedFile {
    param([string]$Path)
    $Path -match '\.(inf|ini|xml)$'
}

# --- References of a backup ----------------------------------------------------------------------

# The account named by $Sid in a backup: its names as a table may give them (SID, name, NETBIOS\name,
# dns\name, name@dns, UPN; a well-known account by its name), its type and how a table names it.
function New-PSGPOMigrationPrincipal {
    param([string]$Sid, [string]$Name, $Group)

    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $type = 'Unknown'
    $source = if ($Sid) { $Sid } else { $Name }
    if ($Sid) { [void]$keys.Add($Sid) }
    if ($Group) {
        $type = if ($Group.Type -in $script:PSGPOMigrationTypes) { $Group.Type } else { 'Unknown' }
        foreach ($key in @($Group.Name, "$($Group.NetBIOSDomain)\$($Group.Name)", "$($Group.DnsDomain)\$($Group.Name)", "$($Group.Name)@$($Group.DnsDomain)", $Group.Upn)) { if ($key -and $key -notmatch '^\\|@$') { [void]$keys.Add($key) } }
        $source = if ($Group.Upn) { $Group.Upn } elseif ($Group.DnsDomain) { "$($Group.Name)@$($Group.DnsDomain)" } else { $Group.Name }
    } elseif ($Sid -and $script:PSGPOWellKnownAccounts.Contains($Sid)) {
        $source = $script:PSGPOWellKnownAccounts[$Sid]
        [void]$keys.Add($source)
    }
    if ($Name) {
        [void]$keys.Add($Name)
        if (-not $Sid) {
            # A name of a well-known account stands for its SID.
            foreach ($known in $script:PSGPOWellKnownAccounts.GetEnumerator()) {
                if ($known.Value -eq ($Name -split '\\')[-1]) { $Sid = $known.Key; [void]$keys.Add($Sid) }
            }
        }
    }
    [pscustomobject]@{ Type = $type; Source = $source; Sid = $Sid; Name = $Name; Keys = $keys; Files = [System.Collections.Generic.List[string]]::new(); FromDacl = $false }
}

# Every security principal and UNC path the settings of a backup reference, as the Migration Table
# Editor finds them (Populate from Backup): Type, Source (as a table names it), Sid, Files. With
# -IncludePermission, the accounts of the permissions of the GPO too.
function Get-PSGPOMigrationReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [AllowEmptyCollection()] [object[]]$SecurityGroups = @(),
        [switch]$IncludePermission
    )

    $bySid = @{}
    foreach ($group in @($SecurityGroups)) { if ($group.Sid) { $bySid[$group.Sid] = $group } }
    $found = [ordered]@{}
    $add = {
        param([string]$Key, [scriptblock]$New, [string]$File)
        if (-not $found.Contains($Key)) { $found[$Key] = & $New }
        if ($File -and -not $found[$Key].Files.Contains($File)) { $found[$Key].Files.Add($File) }
    }
    foreach ($path in @($Files.Keys)) {
        if (-not (Test-PSGPOMigratedFile -Path $path)) { continue }
        $text = (ConvertFrom-PSGPOFileByte -Bytes ([byte[]]$Files[$path])).Text
        foreach ($match in [regex]::Matches($text, $script:PSGPOSidPattern)) {
            $sid = $match.Value
            & $add "sid:$sid" { New-PSGPOMigrationPrincipal -Sid $sid -Group $bySid[$sid] } $path
        }
        # Names written as names: the user rights and restricted groups of a security template, the
        # accounts of the services and of the tasks of the preferences.
        $names = @(
            if ($path -match '\.inf$') {
                foreach ($line in $text -split '\r?\n') {
                    if ($line -notmatch '^\s*(Se\w+|[^=]+__Mem\w+)\s*=\s*(.*)$') { continue }
                    foreach ($token in $Matches[2] -split ',') { $token = $token.Trim(); if ($token -and -not $token.StartsWith('*')) { $token } }
                }
            } elseif ($path -match '\.xml$') {
                foreach ($match in [regex]::Matches($text, '\b(?:accountName|runAs|userName|name)="([^"%]*\\[^"%]+)"')) { [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value) }
            })
        foreach ($name in $names) {
            if ($name -match "^$script:PSGPOSidPattern$") { continue }
            & $add "name:$($name.ToLowerInvariant())" { New-PSGPOMigrationPrincipal -Name $name } $path
        }
        foreach ($match in [regex]::Matches($text, $script:PSGPOUncPattern)) {
            $unc = $match.Value
            & $add "unc:$($unc.ToLowerInvariant())" {
                $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                [void]$keys.Add($unc)
                [pscustomobject]@{ Type = 'UNCPath'; Source = $unc; Sid = $null; Name = $null; Keys = $keys; Files = [System.Collections.Generic.List[string]]::new(); FromDacl = $false }
            } $path
        }
    }
    if ($IncludePermission) {
        foreach ($group in @($SecurityGroups | Where-Object FromDacl)) {
            & $add "sid:$($group.Sid)" { New-PSGPOMigrationPrincipal -Sid $group.Sid -Group $group } $null
            $found["sid:$($group.Sid)"].FromDacl = $true
        }
    }
    # A name the backup also names by its SID is one account.
    foreach ($key in @($found.Keys | Where-Object { $_ -like 'name:*' })) {
        $byName = $found[$key]
        $same = @($found.Values | Where-Object { $_.Sid -and $_ -ne $byName -and $_.Keys.Contains($byName.Name) }) | Select-Object -First 1
        if ($same) { foreach ($file in $byName.Files) { if (-not $same.Files.Contains($file)) { $same.Files.Add($file) } }; [void]$same.Keys.Add($byName.Name); $found.Remove($key) }
    }
    @($found.Values)
}

# --- Migration tables ----------------------------------------------------------------------------

# The entries of a migration table: Type, Source, Destination and Mode (SameAsSource,
# ByRelativeName, None or Explicit).
function Read-PSGPOMigrationTable {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "The migration table '$Path' does not exist." }
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($Path) } catch { throw "The migration table '$Path' is not XML: $($_.Exception.Message)" }
    if ($document.DocumentElement.LocalName -ne 'MigrationTable') { throw "'$Path' is not a migration table (its root is $($document.DocumentElement.LocalName), not MigrationTable)." }
    foreach ($mapping in @($document.DocumentElement.SelectNodes("*[local-name()='Mapping']"))) {
        $type = Get-PSGPOXmlChildText $mapping 'Type'
        $source = Get-PSGPOXmlChildText $mapping 'Source'
        if (-not $source) { throw "The migration table '$Path' has an entry without source." }
        if ($type -notin $script:PSGPOMigrationTypes) { throw "The entry '$source' of the migration table has an unknown type '$type' ($($script:PSGPOMigrationTypes -join ', '))." }
        $mode = 'SameAsSource'
        $destination = $null
        if ($mapping.SelectSingleNode("*[local-name()='DestinationNone']")) { $mode = 'None' }
        elseif ($mapping.SelectSingleNode("*[local-name()='DestinationByRelativeName']")) { $mode = 'ByRelativeName' }
        elseif ($mapping.SelectSingleNode("*[local-name()='Destination']")) { $mode = 'Explicit'; $destination = Get-PSGPOXmlChildText $mapping 'Destination' }
        if ($type -eq 'UNCPath' -and $mode -in 'None', 'ByRelativeName') { throw "The UNC path '$source' of the migration table can only be mapped to a path, or kept (same as source)." }
        if ($type -eq 'Unknown' -and $mode -eq 'ByRelativeName') { throw "The entry '$source' of the migration table is free text or a SID: it cannot be mapped by relative name." }
        if ($mode -eq 'Explicit' -and $destination -match "^$script:PSGPOSidPattern$") { throw "The destination of '$source' is a SID: a migration table names its destinations." }
        [pscustomobject]@{ PSTypeName = 'PSGPOTools.MigrationEntry'; Type = $type; Source = $source; Destination = $destination; Mode = $mode }
    }
}

# Writes a migration table as the Migration Table Editor of GPMC does (UTF-16, its namespace), so
# that GPMC opens it too.
function Save-PSGPOMigrationTable {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path, [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Entry)

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UnicodeEncoding]::new($false, $true)
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.Xml.XmlWriter]::Create($stream, $settings)
    $writer.WriteStartDocument()
    $writer.WriteStartElement('MigrationTable', $script:PSGPOMigrationNamespace)
    $writer.WriteAttributeString('xmlns', 'xsd', $null, 'http://www.w3.org/2001/XMLSchema')
    $writer.WriteAttributeString('xmlns', 'xsi', $null, 'http://www.w3.org/2001/XMLSchema-instance')
    foreach ($item in @($Entry)) {
        $writer.WriteStartElement('Mapping', $script:PSGPOMigrationNamespace)
        $writer.WriteElementString('Type', $script:PSGPOMigrationNamespace, $item.Type)
        $writer.WriteElementString('Source', $script:PSGPOMigrationNamespace, $item.Source)
        switch ($item.Mode) {
            'None' { $writer.WriteElementString('DestinationNone', $script:PSGPOMigrationNamespace, $null) }
            'ByRelativeName' { $writer.WriteElementString('DestinationByRelativeName', $script:PSGPOMigrationNamespace, $null) }
            'Explicit' { $writer.WriteElementString('Destination', $script:PSGPOMigrationNamespace, $item.Destination) }
            default { $writer.WriteElementString('DestinationSameAsSource', $script:PSGPOMigrationNamespace, $null) }
        }
        $writer.WriteEndElement()
    }
    $writer.WriteEndElement()
    $writer.WriteEndDocument()
    $writer.Flush()
    [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
}

# --- Migration -----------------------------------------------------------------------------------

# A destination of a migration table, as an account of the domain of the import: its Name and Sid.
# A name of another domain is refused: the console resolves the destinations in its domain.
function Resolve-PSGPOMigrationDestination {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsDirectory]$Directory, [Parameter(Mandatory)] [string]$Name)

    $account = $Name
    $domain = $null
    if ($Name -match '^([^\\]+)\\(.+)$') { $domain = $Matches[1]; $account = $Matches[2] }
    elseif ($Name -match '^(.+)@([^@]+)$') { $account = $Matches[1]; $domain = $Matches[2] }
    foreach ($known in $script:PSGPOWellKnownAccounts.GetEnumerator()) {
        if ($known.Value -eq $account -and (-not $domain -or $domain -in 'BUILTIN', 'NT AUTHORITY')) { return [pscustomobject]@{ Name = $known.Value; Sid = $known.Key; QualifiedName = $known.Value } }
    }
    $netbios = if ($Directory.Account -match '^([^\\]+)\\') { $Matches[1] }
    if ($domain -and $domain -ne $Directory.DomainName -and $domain -ne $netbios) {
        throw "The destination '$Name' is not an account of $($Directory.DomainName)$(if ($netbios) { " ($netbios)" }): the destinations are found in the domain of the import."
    }
    $found = Resolve-PSGPOApplyTo -Directory $Directory -Name $account
    # As the settings name an account of the domain: NETBIOS\name.
    [pscustomobject]@{ Name = $found.Name; Sid = $found.Sid; QualifiedName = $(if ($netbios) { "$netbios\$($found.Name)" } else { $found.Name }) }
}

# What the migration does with each reference of the backup: the entry of the table that names it,
# its destination resolved in the domain of the import. Rows: Type, Source, Mode (SameAsSource,
# ByRelativeName, None, Explicit, or NotInTable), Destination (Name, Sid; a UNC path), Files.
# -Exclusive refuses a reference the table does not name, as "Use migration table exclusively" of
# GPMC; a destination that cannot be found stops the import, as in GPMC.
function Resolve-PSGPOMigrationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Reference,
        [AllowEmptyCollection()] [object[]]$Table = @(),
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [switch]$Exclusive
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    $plan = foreach ($item in @($Reference)) {
        $entry = @($Table | Where-Object { $item.Keys.Contains($_.Source) -or ($item.Type -eq 'UNCPath' -and $_.Type -eq 'UNCPath' -and $item.Source.StartsWith($_.Source, [System.StringComparison]::OrdinalIgnoreCase)) }) | Select-Object -First 1
        $mode = if ($entry) { $entry.Mode } else { 'NotInTable' }
        if (-not $entry -and $Exclusive) { $missing.Add($item.Source) }
        $destination = $null
        try {
            if ($mode -eq 'ByRelativeName') {
                $relative = if ($item.Name) { ($item.Name -split '\\')[-1] } else { ($entry.Source -split '@')[0] -replace '^.*\\', '' }
                $destination = Resolve-PSGPOMigrationDestination -Directory $Directory -Name $relative
            } elseif ($mode -eq 'Explicit' -and $item.Type -eq 'UNCPath') {
                # The part of the path the entry names, replaced; the rest kept.
                $unc = $entry.Destination.TrimEnd('\') + $item.Source.Substring($entry.Source.TrimEnd('\').Length)
                $destination = [pscustomobject]@{ Name = $unc; Sid = $null; QualifiedName = $unc }
            } elseif ($mode -eq 'Explicit') {
                $destination = Resolve-PSGPOMigrationDestination -Directory $Directory -Name $entry.Destination
            }
        } catch {
            throw "The import is stopped: the destination of '$($entry.Source)' cannot be found: $($_.Exception.Message)"
        }
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.MigrationResult'
            Type = $item.Type
            Source = $item.Source
            Sid = $item.Sid
            Name = $item.Name
            Mode = $mode
            Destination = $destination
            Files = @($item.Files)
        }
    }
    if ($missing.Count) { throw "The import is stopped: the migration table does not name $($missing -join ', ') (it is used exclusively)." }
    @($plan)
}

# The files of the backup with the plan applied: the SIDs, names and UNC paths of the references
# replaced by their destinations, or removed (DestinationNone) where a list or an element holds
# them. The other files are copied as they are.
function Convert-PSGPOMigratedFile {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Plan
    )

    $changes = @($Plan | Where-Object { $_.Mode -in 'ByRelativeName', 'Explicit', 'None' })
    $result = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in @($Files.Keys)) {
        $bytes = [byte[]]$Files[$path]
        if (-not $changes.Count -or -not (Test-PSGPOMigratedFile -Path $path) -or -not @($changes | Where-Object { $_.Files -contains $path }).Count) {
            $result[$path] = $bytes
            continue
        }
        $file = ConvertFrom-PSGPOFileByte -Bytes $bytes
        $text = $file.Text
        foreach ($change in @($changes | Where-Object { $_.Files -contains $path })) {
            if ($change.Type -eq 'UNCPath') {
                $text = [regex]::Replace($text, [regex]::Escape($change.Source) + '(?![^\\/\s"''<>|*?,;=])', $change.Destination.Name.Replace('$', '$$'), 'IgnoreCase')
                continue
            }
            $text = Convert-PSGPOMigratedText -Path $path -Text $text -Change $change
        }
        $result[$path] = ConvertTo-PSGPOFileByte -File $file -Text $text
    }
    , $result
}

# One reference changed in the text of a file: in a security template, the accounts of the lists
# (*SID or name) and the SIDs of the permissions (SDDL); in a preference, the sid and name of its
# elements; elsewhere, the SID.
function Convert-PSGPOMigratedText {
    param([string]$Path, [string]$Text, $Change)

    $remove = $Change.Mode -eq 'None'
    $sid = $Change.Sid
    $names = @($Change.Name) + @($Change.Source) | Where-Object { $_ } | Select-Object -Unique
    $isSource = { param([string]$Token) ($sid -and $Token.TrimStart('*') -eq $sid) -or ($names | Where-Object { [string]::Equals($_, $Token, [System.StringComparison]::OrdinalIgnoreCase) }) }
    $newToken = if ($remove) { $null } elseif ($Change.Destination.Sid -match '^S-1-') { "*$($Change.Destination.Sid)" } else { $Change.Destination.Name }

    if ($Path -match '\.inf$') {
        $lines = foreach ($line in $Text -split '(?<=\n)') {
            $ending = if ($line -match '(\r?\n)$') { $Matches[1] } else { '' }
            $body = $line.TrimEnd("`r", "`n")
            if ($body -match '^(\s*)(Se\w+|[^=;\[]+__Mem\w+)(\s*=\s*)(.*)$') {
                $key = $Matches[2]
                $before = $Matches[1]
                $equals = $Matches[3]
                # Read before the key is matched again ($Matches changes).
                $list = $Matches[4]
                # The group of a restricted group: the line goes with it, or names its destination.
                if ($key -match '^(.+?)(__Mem\w+)$' -and (& $isSource $Matches[1].Trim())) {
                    if ($remove) { continue }
                    $key = "$newToken$($Matches[2])"
                }
                $tokens = @(foreach ($token in @($list -split ',')) {
                        $value = $token.Trim()
                        if (-not $value) { continue }
                        if (& $isSource $value) { if (-not $remove) { $newToken } } else { $value }
                    })
                # An account the destination already had is not listed twice.
                $unique = [System.Collections.Generic.List[string]]::new()
                foreach ($token in $tokens) { if (-not ($unique | Where-Object { [string]::Equals($_, $token, [System.StringComparison]::OrdinalIgnoreCase) })) { $unique.Add($token) } }
                "$before$key$equals$($unique -join ',')$ending"
                continue
            }
            if ($sid) {
                # The permissions (SDDL) of files, registry keys and services.
                if ($remove) { $body = [regex]::Replace($body, "\([^()]*;$([regex]::Escape($sid))\)", '') }
                else { $body = [regex]::Replace($body, "(?<![\w-])$([regex]::Escape($sid))(?![\w-])", $Change.Destination.Sid) }
            }
            "$body$ending"
        }
        return -join $lines
    }
    if ($Path -match '\.xml$' -and $Path -match '(?i)\\Preferences\\') {
        $preference = [GPOToolsPreferenceFile]::Parse([System.Text.Encoding]::UTF8.GetBytes($Text))
        foreach ($element in @($preference.Document.SelectNodes('//*'))) {
            foreach ($pair in @(@('sid', 'name'), @('groupSid', 'groupName'), @('userSid', 'userName'), @($null, 'accountName'), @($null, 'runAs'))) {
                $sidValue = if ($pair[0]) { $element.GetAttribute($pair[0]) }
                $nameValue = $element.GetAttribute($pair[1])
                $match = ($sid -and $sidValue -eq $sid) -or ($nameValue -and -not $sidValue -and (& $isSource $nameValue))
                if (-not $match) { continue }
                if ($remove) {
                    # A member or a targeting filter goes; elsewhere the account stays, said by the plan.
                    if ($element.LocalName -in 'Member', 'FilterUser', 'FilterGroup', 'FilterComputer') { [void]$element.ParentNode.RemoveChild($element) }
                    break
                }
                if ($pair[0] -and $sidValue) { $element.SetAttribute($pair[0], $Change.Destination.Sid) }
                if ($nameValue) { $element.SetAttribute($pair[1], $Change.Destination.QualifiedName) }
            }
        }
        return (ConvertFrom-PSGPOFileByte -Bytes $preference.ToBytes()).Text
    }
    if ($sid) {
        if ($remove) { return (($Text -split '(?<=\n)') | Where-Object { $_ -notmatch "(?<![\w-])$([regex]::Escape($sid))(?![\w-])" }) -join '' }
        return [regex]::Replace($Text, "(?<![\w-])$([regex]::Escape($sid))(?![\w-])", $Change.Destination.Sid)
    }
    $Text
}

# --- Import --------------------------------------------------------------------------------------

# The backup of a folder to import: the only one, else the one of the GPO named $Name (its newest),
# else the backup $BackupId.
function Select-PSGPOImportSource {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path, [string]$Name, [string]$BackupId)

    $sources = @(Get-PSGPOImportSource -Path $Path)
    if (-not $sources.Count) { throw "No backup of GPMC or of HGPM in '$Path'." }
    if ($BackupId) { $sources = @($sources | Where-Object { "$($_.BackupId)".Trim('{', '}') -eq $BackupId.Trim('{', '}') }) }
    if ($Name) { $sources = @($sources | Where-Object { Test-PSGPONameMatch -Name $_.DisplayName -Pattern $Name }) }
    $names = @($sources | ForEach-Object DisplayName | Select-Object -Unique)
    if (-not $sources.Count) { throw "No backup in '$Path' matches$(if ($Name) { " the GPO '$Name'" })$(if ($BackupId) { " the ID $BackupId" })." }
    if ($names.Count -gt 1) { throw "'$Path' holds backups of several GPOs ($($names -join ', ')): give the one to import." }
    # The newest backup of the GPO.
    @($sources | Sort-Object BackedUp -Descending)[0]
}

# Imports the settings of a backup into a GPO, as GPMC "Import Settings": the GPO backed up first
# (unless -NoBackup), its files replaced by those of the backup with the migration table applied,
# its version increased; its links, permissions, status and WMI filter do not change. Returns what
# was done: the GPO, the source, its backup before the import, and the migration of each reference.
function Invoke-PSGPOImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] $Source,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [string]$MigrationTable,
        [switch]$Exclusive,
        [string]$BackupPath,
        [switch]$NoBackup
    )

    $files = Read-PSGPOImportFile -Source $Source
    $references = @(Get-PSGPOMigrationReference -Files $files -SecurityGroups $Source.SecurityGroups)
    $table = if ($MigrationTable) { @(Read-PSGPOMigrationTable -Path $MigrationTable) } else { @() }
    $plan = @(Resolve-PSGPOMigrationPlan -Reference $references -Table $table -Directory $Directory -Exclusive:$Exclusive)
    $migrated = Convert-PSGPOMigratedFile -Files $files -Plan $plan
    # The client-side extensions the backup declares; those of its files when it declares none for a
    # scope (a backup of a GPO without settings then given some): the computers ignore the
    # settings of an extension the GPO does not declare.
    $machine = "$($Source.MachineExtensionNames)"
    $user = "$($Source.UserExtensionNames)"
    if (-not $machine) { $machine = Get-PSGPOFileExtensionName -Files $migrated -Scope Machine }
    if (-not $user) { $user = Get-PSGPOFileExtensionName -Files $migrated -Scope User }
    $before = $null
    if (-not $NoBackup -and -not $BackupPath -and -not (Test-PSGPOBackupAllowed -Directory $Directory)) {
        Write-Warning "The backups of $($Directory.DomainName) are for Tier 0: '$($Gpo.DisplayName)' is not backed up before the import."
        $NoBackup = $true
    }
    if (-not $NoBackup) {
        if (-not $BackupPath) { $BackupPath = Get-PSGPODefaultBackupPath }
        $null = New-Item -ItemType Directory -Path $BackupPath -Force -ErrorAction Stop
        $before = Save-PSGPOBackup -Directory $Directory -Gpo $Gpo -Path $BackupPath -Comment "Before the import of the settings of '$($Source.DisplayName)' ($($Source.Kind) backup of $(if ($Source.BackedUp) { $Source.BackedUp.ToString('u') }))."
    }
    $Directory.RestoreGpo($Gpo, $migrated, $Gpo.Flags, $machine, $user)
    if ($Directory -is [GPOToolsLdapDirectory]) {
        Write-PSGPOAuditEntry -Directory $Directory -Action 'ImportGpo' -Target $Gpo.DistinguishedName -Gpo $Gpo -Details ([ordered]@{
                Source = $Source.DisplayName; SourceKind = $Source.Kind; SourceDomain = $Source.Domain; BackupId = "$($Source.BackupId)"
                MigrationTable = $MigrationTable; Migrated = @($plan | Where-Object { $_.Mode -in 'ByRelativeName', 'Explicit', 'None' } | ForEach-Object { "$($_.Source) -> $(if ($_.Mode -eq 'None') { '(none)' } else { $_.Destination.Name })" })
            })
    }
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.ImportResult'
        Gpo = $Gpo
        Source = $Source
        BackupBefore = $before
        Migration = $plan
        Version = $Gpo.Version
    }
}
