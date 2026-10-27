<#
    The health of the GPOs of a domain, and their replication between its domain controllers, as
    the Status tab of GPMC (Group Policy Infrastructure Status) and gpotool check them: each
    domain controller is read, its directory (the group policy containers) and its SYSVOL (the
    folders of Policies, the GPT.INI of each GPO), and compared to the baseline, the domain
    controller the directory was read from (its PDC emulator, as GPMC reads it). Test-PSGPOHealth
    and Get-PSGPOReplicationStatus return them, the Status tab of the domain shows them.
#>

# A folder of a GPO in Policies: named after its GUID, with what a conflict of the replication
# may add after it ({GUID}_NTFRS_xxxxxxxx).
$script:PSGPOGpoFolderPattern = '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'

# The files of a GPO that hold settings, and the client-side extension the GPO declares for them:
# without it, the computers do not apply them. Preferences: the extension of their type.
$script:PSGPOExtensionFile = @(
    @{ Pattern = '^(?<scope>Machine|User)\\Registry\.pol$'; Extension = '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'; Name = 'Registry Policy' }
    @{ Pattern = '^(?<scope>Machine)\\Microsoft\\Windows NT\\SecEdit\\GptTmpl\.inf$'; Extension = '{827D319E-6EAC-11D2-A4EA-00C04F79F83A}'; Name = 'Security' }
    @{ Pattern = '^(?<scope>Machine)\\Microsoft\\Windows NT\\Audit\\audit\.csv$'; Extension = '{F3CCC681-B74C-4060-9F26-CD84525DCA2A}'; Name = 'Audit Policy Configuration' }
    @{ Pattern = '^(?<scope>Machine|User)\\Scripts\\(ps)?scripts\.ini$'; Extension = '{42B5FAAE-6536-11D2-AE5A-0000F87571E3}'; Name = 'Scripts' }
    @{ Pattern = '^(?<scope>Machine|User)\\Preferences\\(?<path>.+\.xml)$'; Extension = $null; Name = $null }
)

# The folders of the GPOs in an smbclient listing of Policies (recurse ON; ls "<domain>\Policies\*"):
# by name, the files of each (Path in the folder, with \, and Size) and what could not be listed
# (Problem). The other folders of Policies (PolicyDefinitions) are left out. Throws when Policies
# itself could not be listed.
function ConvertFrom-PSGPOSmbClientListing {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowEmptyCollection()] [string[]]$Line = @(),
        # The folder listed, from the root of the share: <domain>\Policies
        [Parameter(Mandatory)] [string]$Root
    )

    $folders = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
    $top = '\' + $Root.Trim('\')
    $prefix = $top + '\'
    # The folder listed by the lines that follow, from Root: '' for Root, $null outside of it.
    $current = ''
    $listed = $false
    foreach ($text in $Line) {
        if ($text -match '^(NT_STATUS_[A-Z_]+) listing (.+)$') {
            $status = $Matches[1]
            $listed = $Matches[2].TrimEnd('*').TrimEnd('\')
            if ($listed -eq $top -or $listed -eq $Root.Trim('\')) { throw "smbclient cannot list $Root`: $status" }
            $inner = if ($listed.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $listed.Substring($prefix.Length) } else { '' }
            $folder = $folders[($inner -split '\\')[0]]
            if ($folder -and -not $folder.Problem) { $folder.Problem = "$status ($($listed.Substring($top.Length + 1)))" }
            continue
        }
        if ($text.StartsWith('\')) {
            $current = if ($text -eq $top) { '' } elseif ($text.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $text.Substring($prefix.Length) } else { $null }
            continue
        }
        # name, attributes (D: a folder), size, date (Mon Oct 12 16:40:34 2026)
        if ($null -eq $current -or $text -notmatch '^  (?<name>.+?)\s+(?<attributes>[A-Z]*)\s+(?<size>\d+)\s+\S+ \S+\s+\d{1,2} \d{1,2}:\d{2}:\d{2} \d{4}\s*$') { continue }
        $name = $Matches.name
        if ($current -eq '') { $listed = $true }
        if ($name -eq '.' -or $name -eq '..') { continue }
        $isFolder = $Matches.attributes.Contains('D')
        if ($current -eq '') {
            if ($isFolder -and $name -match $script:PSGPOGpoFolderPattern) {
                $folders[$name] = [pscustomobject]@{ Files = [System.Collections.Generic.List[object]]::new(); Problem = $null }
            }
            continue
        }
        $separator = $current.IndexOf('\')
        $folder = $folders[$(if ($separator -lt 0) { $current } else { $current.Substring(0, $separator) })]
        if (-not $folder -or $isFolder) { continue }
        $path = if ($separator -lt 0) { $name } else { "$($current.Substring($separator + 1))\$name" }
        $folder.Files.Add([pscustomobject]@{ Path = $path; Size = [long]$Matches.size })
    }
    # Not even . of Policies: smbclient did not list it (the share refused, the folder is not there).
    if (-not $listed) { throw "smbclient did not list $Root`: $((@($Line) | Where-Object { $_ }) -join ' ')" }
    , $folders
}

# The folders of the GPOs in the Policies folder of the SYSVOL of the domain controller of the
# directory, as ConvertFrom-PSGPOSmbClientListing gives them: one listing of the whole folder.
function Get-PSGPOSysvolPolicyFolder {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory)

    $root = "$($Directory.DomainName)\Policies"
    if (-not $IsWindows) {
        Assert-PSGPOKerberosOnly -Directory $Directory
        # A folder the account cannot list is a problem of that GPO, not of the listing.
        $output = Invoke-PSGPOSmbClient -Server $Directory.Server -Share 'SysVol' -TimeoutSeconds 600 -IgnoreStatus 'NT_STATUS_ACCESS_DENIED' -IgnoreExitCode `
            -Command ('recurse ON; ls "{0}\*"' -f $root)
        return , (ConvertFrom-PSGPOSmbClientListing -Line $output -Root $root)
    }
    Use-PSGPOSysvolCredential -Directory $Directory -Share 'SysVol'
    $folders = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @(Get-ChildItem -LiteralPath "\\$($Directory.Server)\SysVol\$root" -Directory -Force -ErrorAction Stop | Sort-Object Name)) {
        if ($item.Name -notmatch $script:PSGPOGpoFolderPattern) { continue }
        $prefix = $item.FullName.TrimEnd('\').Length + 1
        $denied = $null
        $files = [System.Collections.Generic.List[object]]::new()
        foreach ($file in @(Get-ChildItem -LiteralPath $item.FullName -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable denied)) {
            $files.Add([pscustomobject]@{ Path = $file.FullName.Substring($prefix); Size = $file.Length })
        }
        $folders[$item.Name] = [pscustomobject]@{ Files = $files; Problem = $(if ($denied) { $denied[0].Exception.Message }) }
    }
    , $folders
}

# The GPT.INI of GPOs on the domain controller of the directory, by Id: @{ Bytes; Problem }, Bytes
# $null when it is not read. Only the files the listing of the folders ($Folders) has are read:
# on Linux, in one smbclient for a hundred of them.
function Read-PSGPOSysvolGptIni {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [GPOToolsGpo[]]$Gpo,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Folders
    )

    $result = @{}
    $wanted = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Gpo) {
        $key = "$($item.Id)"
        $redirected = $Directory.GetRedirectedProblem($item)
        if ($redirected) { $result[$key] = @{ Bytes = $null; Problem = $redirected }; continue }
        $folder = $Folders['{' + $item.Id.ToString().ToUpperInvariant() + '}']
        if (-not $folder) { $result[$key] = @{ Bytes = $null; Problem = (Get-PSGPOText 'the GPO has no folder in SYSVOL') }; continue }
        if (-not @($folder.Files | Where-Object { $_.Path -eq 'GPT.INI' }).Count) {
            $problem = if ($folder.Problem) { Get-PSGPOText 'its folder cannot be read: {0}' $folder.Problem } else { Get-PSGPOText 'the folder of the GPO has no GPT.INI' }
            $result[$key] = @{ Bytes = $null; Problem = $problem }
            continue
        }
        $location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $item
        $wanted.Add([pscustomobject]@{ Key = $key; Share = $location.Share; Path = "$($location.Path)\GPT.INI" })
    }
    if ($IsWindows) {
        foreach ($item in $wanted) {
            try { $result[$item.Key] = @{ Bytes = (Read-PSGPOSysvolItem -Directory $Directory -Share $item.Share -Path $item.Path); Problem = $null } }
            catch { $result[$item.Key] = @{ Bytes = $null; Problem = $_.Exception.GetBaseException().Message } }
        }
        return $result
    }
    if (-not $wanted.Count) { return $result }
    Assert-PSGPOKerberosOnly -Directory $Directory
    $local = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-$([guid]::NewGuid())"
    $null = New-Item -ItemType Directory -Path $local -WhatIf:$false
    try {
        foreach ($share in @($wanted | Group-Object -Property Share)) {
            $items = @($share.Group)
            for ($start = 0; $start -lt $items.Count; $start += 100) {
                $batch = @($items[$start..([math]::Min($start + 100, $items.Count) - 1)])
                $commands = for ($i = 0; $i -lt $batch.Count; $i++) { 'get "{0}" "{1}"' -f $batch[$i].Path, (Join-Path $local "$($start + $i).ini") }
                $output = Invoke-PSGPOSmbClient -Server $Directory.Server -Share $share.Name -IgnoreExitCode `
                    -IgnoreStatus 'NT_STATUS_OBJECT_NAME_NOT_FOUND', 'NT_STATUS_OBJECT_PATH_NOT_FOUND', 'NT_STATUS_NO_SUCH_FILE', 'NT_STATUS_ACCESS_DENIED' -Command ($commands -join '; ')
                # A file refused is a problem of its GPO, the share refused of every one.
                if (@($output) -match 'tree connect failed|session setup failed') { throw "smbclient //$($Directory.Server)/$($share.Name) failed: $((@($output) | Where-Object { $_ }) -join ' ')" }
                $status = @{}
                foreach ($text in @($output)) { if ($text -match '^(NT_STATUS_[A-Z_]+) opening remote file \\?(.+)$') { $status[$Matches[2].Trim()] = $Matches[1] } }
                for ($i = 0; $i -lt $batch.Count; $i++) {
                    $file = Join-Path $local "$($start + $i).ini"
                    $result[$batch[$i].Key] = if (Test-Path -LiteralPath $file) { @{ Bytes = [System.IO.File]::ReadAllBytes($file); Problem = $null } }
                        else { @{ Bytes = $null; Problem = (Get-PSGPOText 'GPT.INI cannot be read: {0}' $(if ($status[$batch[$i].Path]) { $status[$batch[$i].Path] } else { 'smbclient' })) } }
                }
            }
        }
    } finally {
        Remove-Item -LiteralPath $local -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
    }
    $result
}

# The GPOs of a domain controller: its directory (Directory: the group policy containers, as a
# GPOToolsLdapDirectory read from it), its SYSVOL (Folders: Get-PSGPOSysvolPolicyFolder) and the
# version of the GPT.INI of each GPO (Versions, by Id: @{ Version; Problem }).
function Read-PSGPOControllerGpo {
    [CmdletBinding()]
    param(
        # The directory read, whose account reads the domain controller
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Server
    )

    $connection = New-PSGPOLdapConnection -Server $Server -Credential $Directory.Credential -UseSsl:$Directory.UseSsl -Port $Directory.Port
    try {
        $rootDse = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase '' -Scope Base -Attribute 'dnsHostName', 'vendorName'
        $domain = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Directory.Domain.DistinguishedName -Scope Base -Attribute 'gPLink'
        if (-not $domain) { throw "The domain object $($Directory.Domain.DistinguishedName) cannot be read on $Server." }
        $gpos = @(Invoke-PSGPOLdapSearch -Connection $connection -SearchBase "CN=Policies,CN=System,$($Directory.Domain.DistinguishedName)" -Scope OneLevel `
                -Filter '(objectClass=groupPolicyContainer)' -Attribute 'cn', 'displayName', 'versionNumber', 'flags', 'gPCFileSysPath', 'whenChanged', 'gPCMachineExtensionNames', 'gPCUserExtensionNames')
    } finally {
        $connection.Dispose()
    }
    $name = Get-PSGPOLdapValue $rootDse 'dnsHostName'
    # The containers that are not GPOs were said when the domain was read.
    $controller = ConvertTo-PSGPOLdapDirectory -Server $(if ($name) { $name } else { $Server }) -VendorName (Get-PSGPOLdapValue $rootDse 'vendorName') -DomainEntry $domain -GpoEntry $gpos 3>$null
    $controller.Credential = $Directory.Credential
    $controller.UseSsl = $Directory.UseSsl
    $controller.Port = $Directory.Port
    $controller.PdcEmulator = $Directory.PdcEmulator
    $folders = Get-PSGPOSysvolPolicyFolder -Directory $controller
    $versions = @{}
    $read = Read-PSGPOSysvolGptIni -Directory $controller -Gpo @($controller.Gpos) -Folders $folders
    foreach ($key in $read.Keys) {
        $entry = $read[$key]
        $version = if ($null -ne $entry.Bytes) { Get-PSGPOGptIniVersion -Bytes $entry.Bytes }
        $problem = if ($entry.Problem) { $entry.Problem } elseif ($null -eq $version) { Get-PSGPOText 'GPT.INI has no version' }
        $versions[$key] = @{ Version = $version; Problem = $problem }
    }
    [pscustomobject]@{ Server = $controller.Server; Directory = $controller; Folders = $folders; Versions = $versions; Problem = $null }
}

# "user 2, computer 5": a versionNumber, or the version of a GPT.INI.
function Get-PSGPOVersionText {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $Version)

    if ($null -eq $Version) { return (Get-PSGPOText 'no version') }
    Get-PSGPOText 'user {0}, computer {1}' (([long]$Version -shr 16) -band 0xFFFF) ([long]$Version -band 0xFFFF)
}

# A file of a GPO holds settings: Registry.pol has entries, GptTmpl.inf keys out of [Unicode] and
# [Version], audit.csv lines after its header, scripts.ini a command line, a preference file an item.
function Test-PSGPOSettingFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Bytes
    )

    if ($Path -match 'Registry\.pol$') { return $Bytes.Length -gt 8 }
    $unicode = $Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE
    $text = if ($unicode) { [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) } else { [System.Text.Encoding]::UTF8.GetString($Bytes) }
    $lines = @($text -split '\r?\n' | Where-Object { $_.Trim() })
    if ($Path -match 'GptTmpl\.inf$') {
        $section = ''
        foreach ($line in $lines) {
            if ($line -match '^\s*\[(.+)\]\s*$') { $section = $Matches[1]; continue }
            if ($section -notin 'Unicode', 'Version' -and $line -notmatch '^\s*;') { return $true }
        }
        return $false
    }
    if ($Path -match 'audit\.csv$') { return $lines.Count -gt 1 }
    if ($Path -match 'scripts\.ini$') { return [bool]@($lines | Where-Object { $_ -match '^\s*\d+CmdLine\s*=\s*\S' }).Count }
    [regex]::Matches($text, '\bclsid\s*=').Count -ge 2
}

# The files of a GPO that hold settings whose client-side extension the GPO does not declare:
# Path, Scope (Machine or User) and Name of the extension. $Files: its files, as listed.
function Get-PSGPOUndeclaredExtension {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Files
    )

    $declared = @(Get-PSGPODeclaredExtension -MachineExtensionNames $Gpo.MachineExtensionNames -UserExtensionNames $Gpo.UserExtensionNames)
    foreach ($file in $Files) {
        if ($file.Size -le 0) { continue }
        foreach ($rule in $script:PSGPOExtensionFile) {
            if ($file.Path -notmatch $rule.Pattern) { continue }
            $scope = if ($Matches.scope -eq 'User') { 'User' } else { 'Machine' }
            $extension = $rule.Extension
            $name = $rule.Name
            if (-not $extension) {
                $preferencePath = $Matches.path
                $type = @(Get-PSGPOPreferenceExtension | Where-Object { [string]::Equals($_.Path, $preferencePath, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
                if (-not $type) { break }
                $extension = $type.Cse
                $name = "Group Policy $($type.Name)"
            }
            if (@($declared | Where-Object { $_.Scope -eq $scope -and [string]::Equals($_.Guid, $extension, [System.StringComparison]::OrdinalIgnoreCase) }).Count) { break }
            # Read only now: a file without its extension is rare.
            $holds = if ($file.Path -match 'Registry\.pol$') { $file.Size -gt 8 } else {
                $bytes = Read-PSGPOSysvolFile -Directory $Directory -Gpo $Gpo -Path $file.Path
                $null -ne $bytes -and (Test-PSGPOSettingFile -Path $file.Path -Bytes $bytes)
            }
            if ($holds) { [pscustomobject]@{ Path = $file.Path; Scope = $scope; Name = $name } }
            break
        }
    }
}

# The health of the GPOs of the domain and their replication, from the domain controller of the
# directory (the baseline) and the other ones ($DomainController, every one by default):
#   Baseline     the domain controller compared to
#   Collected    when
#   Controllers  one row per domain controller: Name, IsBaseline, IsPdcEmulator, ServerType,
#                GpoCount, Differences (its rows of Replication not in sync), Problem
#   Replication  PSGPOTools.ReplicationStatus rows (Get-PSGPOReplicationStatus)
#   Findings     PSGPOTools.HealthFinding rows (Test-PSGPOHealth)
# $Name: the GPOs by display name (wildcards); the folders and links without a GPO are then left out.
function Get-PSGPOHealthData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [string[]]$DomainController,
        [string[]]$Name
    )

    $baseline = $Directory.Server
    $others = if ($DomainController) { $DomainController } else { @(Get-PSGPODomainController -Directory $Directory) }
    $servers = [System.Collections.Generic.List[string]]::new()
    $servers.Add($baseline)
    foreach ($server in $others) {
        if (-not @($servers | Where-Object { [string]::Equals($_, $server, [System.StringComparison]::OrdinalIgnoreCase) }).Count) { $servers.Add($server) }
    }
    $isWanted = { param($Gpo) -not $Name -or @($Name | Where-Object { $Gpo.DisplayName -like $_ }).Count -gt 0 }

    # The details of the GPOs read SYSVOL again.
    $script:PSGPOSysvolVersions = @{}
    $states = @(foreach ($server in $servers) {
        try {
            Read-PSGPOControllerGpo -Directory $Directory -Server $server
        } catch {
            $message = $_.Exception.GetBaseException().Message
            if ($server -eq $baseline) { throw "The baseline domain controller $baseline cannot be read: $message" }
            [pscustomobject]@{ Server = $server; Directory = $null; Folders = $null; Versions = $null; Problem = $message }
        }
    })
    $base = $states[0]
    $baseById = @{}
    foreach ($gpo in $base.Directory.Gpos) { $baseById["$($gpo.Id)"] = $gpo }

    $replication = [System.Collections.Generic.List[object]]::new()
    $controllers = [System.Collections.Generic.List[object]]::new()
    $newRow = {
        param($State, $DisplayName, $Id, [string]$RowState, $DirectoryVersion, $SysvolVersion, $BaselineVersion, [string]$Detail)
        $row = [pscustomobject]@{
            PSTypeName = 'PSGPOTools.ReplicationStatus'
            DomainController = $State.Server
            IsBaseline = [object]::ReferenceEquals($State, $base)
            DisplayName = $DisplayName
            Id = $Id
            State = $RowState
            DirectoryVersion = $DirectoryVersion
            SysvolVersion = $SysvolVersion
            BaselineVersion = $BaselineVersion
            Detail = $Detail
        }
        $replication.Add($row)
        $row
    }
    foreach ($state in $states) {
        $isBaseline = [object]::ReferenceEquals($state, $base)
        $samba = $state.Directory -and $state.Directory.ServerType -eq 'Samba AD'
        $first = $replication.Count
        if ($state.Problem) {
            $null = & $newRow $state $null $null 'Unreachable' $null $null $null (Get-PSGPOText 'The domain controller cannot be read: {0}' $state.Problem)
        } else {
            $byId = @{}
            foreach ($gpo in $state.Directory.Gpos) { $byId["$($gpo.Id)"] = $gpo }
            foreach ($gpo in $base.Directory.Gpos) {
                if (-not (& $isWanted $gpo)) { continue }
                $mine = $byId["$($gpo.Id)"]
                if (-not $mine) {
                    $null = & $newRow $state $gpo.DisplayName $gpo.Id 'Missing' $null $null $gpo.Version (Get-PSGPOText 'The GPO is on {0}, not in the directory of this domain controller: the replication of the directory is not done, or the GPO was deleted here.' $baseline)
                    continue
                }
                $sysvol = $state.Versions["$($mine.Id)"]
                if (-not $isBaseline -and $mine.Version -ne $gpo.Version) {
                    $null = & $newRow $state $mine.DisplayName $mine.Id 'DirectoryDiffers' $mine.Version $sysvol.Version $gpo.Version (Get-PSGPOText '{0} in the directory, {1} on {2}: the replication of the directory is not done.' (Get-PSGPOVersionText $mine.Version) (Get-PSGPOVersionText $gpo.Version) $baseline)
                } elseif ($sysvol.Problem -or $sysvol.Version -ne $mine.Version) {
                    $why = if ($sysvol.Problem) { $sysvol.Problem } else { Get-PSGPOText '{0} in the directory, {1} in SYSVOL' (Get-PSGPOVersionText $mine.Version) (Get-PSGPOVersionText $sysvol.Version) }
                    $detail = if ($isBaseline -and $sysvol.Problem) { Get-PSGPOText '{0}: the computers fail to apply the GPO.' $why }
                        elseif ($isBaseline) { Get-PSGPOText '{0}: a change of the GPO stopped halfway; the computers apply SYSVOL.' $why }
                        elseif ($samba) { Get-PSGPOText '{0}: Samba does not replicate SYSVOL, copy the folder of the GPO from {1}.' $why $baseline }
                        else { Get-PSGPOText '{0}: the replication of SYSVOL is not done.' $why }
                    $null = & $newRow $state $mine.DisplayName $mine.Id 'SysvolDiffers' $mine.Version $sysvol.Version $gpo.Version $detail
                } else {
                    $null = & $newRow $state $mine.DisplayName $mine.Id 'InSync' $mine.Version $sysvol.Version $gpo.Version (Get-PSGPOVersionText $mine.Version)
                }
            }
            foreach ($mine in $state.Directory.Gpos) {
                if ($baseById.ContainsKey("$($mine.Id)") -or -not (& $isWanted $mine)) { continue }
                $sysvol = $state.Versions["$($mine.Id)"]
                $null = & $newRow $state $mine.DisplayName $mine.Id 'Extra' $mine.Version $sysvol.Version $null (Get-PSGPOText 'The GPO is in the directory of this domain controller, not on {0}: the replication of the directory is not done, or the GPO was deleted on {0}.' $baseline)
            }
            if (-not $Name) {
                foreach ($folder in $state.Folders.Keys) {
                    if ($folder -match '^\{([0-9A-Fa-f-]{36})\}$' -and $byId.ContainsKey(([guid]$Matches[1]).ToString())) { continue }
                    $id = if ($folder -match '^\{([0-9A-Fa-f-]{36})\}') { [guid]$Matches[1] }
                    $null = & $newRow $state $folder $id 'OrphanFolder' $null $null $null (Get-PSGPOText 'A folder of SYSVOL without a GPO in the directory: left by a GPO deleted elsewhere, or by a conflict of the replication. Delete it once checked.')
                }
            }
        }
        $differences = 0
        for ($i = $first; $i -lt $replication.Count; $i++) { if ($replication[$i].State -ne 'InSync') { $differences++ } }
        $controllers.Add([pscustomobject]@{
                Name = $state.Server
                IsBaseline = $isBaseline
                IsPdcEmulator = [string]::Equals($state.Server, $Directory.PdcEmulator, [System.StringComparison]::OrdinalIgnoreCase)
                ServerType = if ($state.Directory) { $state.Directory.ServerType }
                GpoCount = if ($state.Directory) { $state.Directory.Gpos.Count } else { $null }
                Differences = $differences
                Problem = $state.Problem
            })
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    $newFinding = {
        param([string]$Severity, [string]$Check, $Target, $Id, $Server, [string]$Detail)
        $findings.Add([pscustomobject]@{
                PSTypeName = 'PSGPOTools.HealthFinding'
                Severity = $Severity
                Check = $Check
                Target = $Target
                Id = $Id
                DomainController = $Server
                Detail = $Detail
            })
    }
    # The GPOs on the baseline: their folder, their versions, their extensions.
    foreach ($gpo in $base.Directory.Gpos) {
        if (-not (& $isWanted $gpo)) { continue }
        $redirected = $base.Directory.GetRedirectedProblem($gpo)
        if ($redirected) { & $newFinding 'Error' 'Redirected' $gpo.DisplayName $gpo.Id $baseline $redirected; continue }
        $sysvol = $base.Versions["$($gpo.Id)"]
        if ($sysvol.Problem) {
            & $newFinding 'Error' 'Folder' $gpo.DisplayName $gpo.Id $baseline (Get-PSGPOText '{0}: the computers fail to apply the GPO.' $sysvol.Problem)
            continue
        }
        if ($sysvol.Version -ne $gpo.Version) {
            & $newFinding 'Error' 'Version' $gpo.DisplayName $gpo.Id $baseline (Get-PSGPOText '{0} in the directory, {1} in SYSVOL: a change of the GPO stopped halfway, and the computers apply SYSVOL. Save a setting of the GPO again.' (Get-PSGPOVersionText $gpo.Version) (Get-PSGPOVersionText $sysvol.Version))
        }
        $folder = $base.Folders['{' + $gpo.Id.ToString().ToUpperInvariant() + '}']
        foreach ($missing in @(Get-PSGPOUndeclaredExtension -Directory $base.Directory -Gpo $gpo -Files @($folder.Files))) {
            $scope = if ($missing.Scope -eq 'User') { Get-PSGPOText 'the users' } else { Get-PSGPOText 'the computers' }
            & $newFinding 'Warning' 'Extension' $gpo.DisplayName $gpo.Id $baseline (Get-PSGPOText '{0} holds settings, but the GPO does not declare their client-side extension ({1}) for {2}: they are not applied. Save one of them again in the console to declare it.' $missing.Path $missing.Name $scope)
        }
    }
    if (-not $Name) {
        # The links to a GPO of the domain that is not there (a link to another domain is not checked).
        $policies = ",CN=Policies,CN=System,$($Directory.Domain.DistinguishedName)"
        $stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        $stack.Push($Directory.Domain)
        while ($stack.Count) {
            $som = $stack.Pop()
            foreach ($child in $som.Children) { $stack.Push($child) }
            foreach ($link in $som.Links) {
                if ($link.Gpo -or -not "$($link.GpoDistinguishedName)".EndsWith($policies, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                & $newFinding 'Warning' 'Link' $som.Name $null $baseline (Get-PSGPOText 'A link to {0}, which is not a GPO of the domain: the computers ignore it. Delete the link.' $link.GpoDistinguishedName)
            }
        }
    }
    # The folders without a GPO, and the other domain controllers.
    foreach ($row in $replication) {
        if ($row.State -eq 'InSync' -or ($row.IsBaseline -and $row.State -ne 'OrphanFolder')) { continue }
        $check = switch ($row.State) { 'OrphanFolder' { 'OrphanFolder' } 'Unreachable' { 'DomainController' } default { 'Replication' } }
        $target = if ($row.State -eq 'Unreachable') { $row.DomainController } else { $row.DisplayName }
        & $newFinding 'Warning' $check $target $row.Id $row.DomainController $row.Detail
    }

    [pscustomobject]@{
        Baseline = $baseline
        Collected = [datetime]::Now
        Controllers = $controllers.ToArray()
        Replication = $replication.ToArray()
        Findings = $findings.ToArray()
    }
}
