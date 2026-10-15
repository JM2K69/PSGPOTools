<#
    Files of a GPO in SYSVOL (Registry.pol, GPT.INI) for a GPOToolsLdapDirectory, on the domain
    controller the directory was read from: with Samba, SYSVOL is not replicated between domain
    controllers, so the changes go where the directory comes from.

    - Windows: the UNC path \\<server>\<share>\..., with the identity of the session.
    - Linux/macOS: smbclient with Kerberos (kinit), as .NET has no SMB client there.

    Saving a file of the GPO (Registry.pol, GptTmpl.inf) also increases the version of the GPO
    for its scope, in GPT.INI and in the versionNumber of the group policy container, and
    declares the client-side extension of the file (gPCMachineExtensionNames /
    gPCUserExtensionNames): without them the computers would not apply the change, as with GPMC.
#>

# Share and path of the GPO folder, from its gPCFileSysPath (\\<domain>\SysVol\<domain>\Policies\{GUID}).
function Get-PSGPOSysvolLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $match = [regex]::Match("$($Gpo.FileSysPath)", '^\\\\[^\\]+\\([^\\]+)\\(.+?)\\?$')
    if ($match.Success) {
        [pscustomobject]@{ Share = $match.Groups[1].Value; Path = $match.Groups[2].Value }
    } else {
        [pscustomobject]@{ Share = 'SysVol'; Path = '{0}\Policies\{{{1}}}' -f $Directory.DomainName, $Gpo.Id.ToString().ToUpperInvariant() }
    }
}

# Runs smbclient commands on a share; returns its output, $null when the file is missing and
# -AllowMissing is set, and throws on any other error.
function Invoke-PSGPOSmbClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$Share,
        [Parameter(Mandatory)] [string]$Command,
        [switch]$AllowMissing,
        # NT_STATUS errors that are not failures (an existing folder for mkdir).
        [string[]]$IgnoreStatus = @(),
        [int]$TimeoutSeconds = 120
    )

    $smbclient = Get-Command -Name 'smbclient' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $smbclient) { throw 'Reading SYSVOL needs smbclient on this computer (Debian/Ubuntu: apt install smbclient; RHEL/Fedora: dnf install samba-client).' }
    # Never a password prompt: no standard input, Kerberos only. Not --no-pass: with it,
    # smbclient does not use the Kerberos ticket ("No password for user principal").
    $result = Invoke-PSGPONativeCommand -FilePath $smbclient.Source -TimeoutSeconds $TimeoutSeconds `
        -ArgumentList "//$Server/$Share", '--use-kerberos=required', '-c', $Command
    $output = @($result.Output) + @("$($result.Error)" -split '\r?\n' | Where-Object { $_ })
    $status = @($output | Select-String -Pattern 'NT_STATUS_[A-Z_]+' -AllMatches | ForEach-Object { $_.Matches.Value } | Where-Object { $_ -notin $IgnoreStatus })
    $missing = @($status | Where-Object { $_ -in 'NT_STATUS_OBJECT_NAME_NOT_FOUND', 'NT_STATUS_OBJECT_PATH_NOT_FOUND', 'NT_STATUS_NO_SUCH_FILE' })
    if ($AllowMissing -and $missing.Count) { return $null }
    if ($status.Count -or $result.ExitCode -ne 0) {
        throw "smbclient //$Server/$Share failed: $(($output | Where-Object { $_ }) -join ' ')"
    }
    , $output
}

# A file of the GPO folder: its bytes, $null when it does not exist.
function Read-PSGPOSysvolFile {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        # Path in the GPO folder, with \ (Machine\Registry.pol)
        [Parameter(Mandatory)] [string]$Path
    )

    $location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
    if ($IsWindows) {
        $file = "\\$($Directory.Server)\$($location.Share)\$($location.Path)\$Path"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
        return , [System.IO.File]::ReadAllBytes($file)
    }
    Assert-PSGPOKerberosOnly -Directory $Directory
    $local = [System.IO.Path]::GetTempFileName()
    try {
        $result = Invoke-PSGPOSmbClient -Server $Directory.Server -Share $location.Share -AllowMissing -Command ('get "{0}\{1}" "{2}"' -f $location.Path, $Path, $local)
        if ($null -eq $result) { return $null }
        return , [System.IO.File]::ReadAllBytes($local)
    } finally {
        Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
    }
}

# Every file of the GPO folder, by path in the folder (Machine\Registry.pol), sorted: for a
# backup. Linux copies the folder with smbclient into a temporary folder first.
function Read-PSGPOSysvolFolder {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
    $local = $null
    if ($IsWindows) {
        $root = "\\$($Directory.Server)\$($location.Share)\$($location.Path)"
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "The folder of the GPO '$($Gpo.DisplayName)' is not in SYSVOL: $root" }
    } else {
        Assert-PSGPOKerberosOnly -Directory $Directory
        $local = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-$([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $local
        $root = $local
    }
    try {
        if ($local) {
            $null = Invoke-PSGPOSmbClient -Server $Directory.Server -Share $location.Share -TimeoutSeconds 600 `
                -Command ('prompt OFF; recurse ON; lcd "{0}"; cd "{1}"; mget *' -f $local, $location.Path)
        }
        $files = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
        $prefix = $root.TrimEnd('\', '/').Length + 1
        foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Sort-Object FullName)) {
            $files[($file.FullName.Substring($prefix) -replace '/', '\')] = [System.IO.File]::ReadAllBytes($file.FullName)
        }
        , $files
    } finally {
        if ($local) { Remove-Item -LiteralPath $local -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Writes a file of the GPO folder, creating its folder when needed.
function Write-PSGPOSysvolFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Bytes
    )

    $location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
    # Not Split-Path: on Linux it turns the \ of the path in the GPO folder into /.
    $separator = $Path.LastIndexOfAny([char[]]'\/')
    $folder = if ($separator -gt 0) { $Path.Substring(0, $separator) } else { '' }
    if ($IsWindows) {
        $file = "\\$($Directory.Server)\$($location.Share)\$($location.Path)\$Path"
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $file -Parent) -Force
        [System.IO.File]::WriteAllBytes($file, $Bytes)
        return
    }
    Assert-PSGPOKerberosOnly -Directory $Directory
    $local = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllBytes($local, $Bytes)
        # smbclient creates one folder at a time: each level of the path.
        $level = ''
        foreach ($part in @($folder -split '[\\/]' | Where-Object { $_ })) {
            $level = if ($level) { "$level\$part" } else { $part }
            $null = Invoke-PSGPOSmbClient -Server $Directory.Server -Share $location.Share -IgnoreStatus 'NT_STATUS_OBJECT_NAME_COLLISION' -Command ('mkdir "{0}\{1}"' -f $location.Path, $level)
        }
        $null = Invoke-PSGPOSmbClient -Server $Directory.Server -Share $location.Share -Command ('put "{2}" "{0}\{1}"' -f $location.Path, $Path, $local)
    } finally {
        Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
    }
}

function Assert-PSGPOKerberosOnly {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory)

    if ($Directory.Credential) {
        throw "SYSVOL is reached with Kerberos: run kinit $($Directory.Credential.UserName), then read the domain without -Credential."
    }
}

# GPT.INI with the given version (Version= of [General]), in the encoding it had.
function Set-PSGPOGptIniVersion {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [byte[]]$Bytes,
        [Parameter(Mandatory)] [int]$Version
    )

    $unicode = $Bytes -and $Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE
    $encoding = if ($unicode) { [System.Text.Encoding]::Unicode } else { [System.Text.Encoding]::ASCII }
    $text = if ($Bytes) { $encoding.GetString($Bytes, $(if ($unicode) { 2 } else { 0 }), $Bytes.Length - $(if ($unicode) { 2 } else { 0 })) } else { '' }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($text -split '\r?\n')) { $lines.Add($line) }
    while ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $general = -1; $versionLine = -1; $section = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[(.+)\]\s*$') { $section = $Matches[1]; if ($section -eq 'General') { $general = $i }; continue }
        if ($section -eq 'General' -and $lines[$i] -match '^\s*Version\s*=') { $versionLine = $i }
    }
    if ($versionLine -ge 0) { $lines[$versionLine] = "Version=$Version" }
    elseif ($general -ge 0) { $lines.Insert($general + 1, "Version=$Version") }
    else { $lines.Insert(0, '[General]'); $lines.Insert(1, "Version=$Version") }

    $result = $encoding.GetBytes(($lines -join "`r`n") + "`r`n")
    if ($unicode) { $result = [byte[]](0xFF, 0xFE) + $result }
    , [byte[]]$result
}

# gPC*ExtensionNames with an extension and its tool: [{extension}{tool}...] sorted by GUID.
function Add-PSGPOExtensionName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [AllowNull()] [string]$Current,
        [Parameter(Mandatory)] [string]$Extension,
        [Parameter(Mandatory)] [string]$Tool
    )

    $groups = [ordered]@{}
    foreach ($group in [regex]::Matches("$Current", '\[([^\]]*)\]')) {
        $guids = @([regex]::Matches($group.Groups[1].Value, '\{[0-9A-Fa-f-]{36}\}') | ForEach-Object { $_.Value.ToUpperInvariant() })
        if (-not $guids.Count) { continue }
        if (-not $groups.Contains($guids[0])) { $groups[$guids[0]] = [System.Collections.Generic.List[string]]::new() }
        foreach ($guid in $guids | Select-Object -Skip 1) { if (-not $groups[$guids[0]].Contains($guid)) { $groups[$guids[0]].Add($guid) } }
    }
    $extensionKey = $Extension.ToUpperInvariant()
    if (-not $groups.Contains($extensionKey)) { $groups[$extensionKey] = [System.Collections.Generic.List[string]]::new() }
    if (-not $groups[$extensionKey].Contains($Tool.ToUpperInvariant())) { $groups[$extensionKey].Add($Tool.ToUpperInvariant()) }

    (@($groups.Keys | Sort-Object | ForEach-Object { '[' + $_ + ((@($groups[$_]) | Sort-Object) -join '') + ']' })) -join ''
}

# Modify request that replaces an attribute value only if it is still the value read.
function Add-PSGPOLdapValueChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.DirectoryServices.Protocols.ModifyRequest]$Request,
        [Parameter(Mandatory)] [string]$Name,
        [AllowNull()] [string]$Old,
        # Empty: the attribute is removed.
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string]$New
    )

    # A [string] parameter turns $null into '': an attribute absent from the entry is empty here.
    if ($Old -ceq $New) { return }
    if (-not [string]::IsNullOrEmpty($Old)) {
        $remove = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
        $remove.Name = $Name
        $remove.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Delete
        [void]$remove.Add($Old)
        [void]$Request.Modifications.Add($remove)
    }
    if ([string]::IsNullOrEmpty($New)) { return }
    $add = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
    $add.Name = $Name
    $add.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
    [void]$add.Add($New)
    [void]$Request.Modifications.Add($add)
}

# Saves a file of the GPO, then increases the version of the GPO for its scope and declares
# the client-side extension that applies it.
function Save-PSGPODomainGpoFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        # Path in the GPO folder (Machine\Registry.pol)
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Bytes,
        # Scope whose version increases
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Folder,
        [Parameter(Mandatory)] [string]$Extension,
        [Parameter(Mandatory)] [string]$Tool
    )

    $extensionAttribute = if ($Folder -eq 'Machine') { 'gPCMachineExtensionNames' } else { 'gPCUserExtensionNames' }
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Base -Attribute 'versionNumber', $extensionAttribute
        if (-not $entry) { throw "The GPO $($Gpo.DisplayName) is not in the domain anymore." }
        $oldVersion = Get-PSGPOLdapValue $entry 'versionNumber'
        $version = [GPOToolsDirectory]::GetNextVersion([int]$oldVersion, $Folder)
        $oldExtensions = Get-PSGPOLdapValue $entry $extensionAttribute
        $extensions = Add-PSGPOExtensionName -Current $oldExtensions -Extension $Extension -Tool $Tool

        # SYSVOL first, then the version in GPT.INI and in the directory, as GPMC does.
        Write-PSGPOSysvolFile -Directory $Directory -Gpo $Gpo -Path $Path -Bytes $Bytes
        $gptIni = Set-PSGPOGptIniVersion -Bytes (Read-PSGPOSysvolFile -Directory $Directory -Gpo $Gpo -Path 'GPT.INI') -Version $version
        Write-PSGPOSysvolFile -Directory $Directory -Gpo $Gpo -Path 'GPT.INI' -Bytes $gptIni

        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Gpo.DistinguishedName
        Add-PSGPOLdapValueChange -Request $request -Name 'versionNumber' -Old $oldVersion -New "$version"
        if ($extensions -ne $oldExtensions) {
            Add-PSGPOLdapValueChange -Request $request -Name $extensionAttribute -Old $oldExtensions -New $extensions
        }
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -in 'NoSuchAttribute', 'AttributeOrValueExists') {
                throw "The GPO $($Gpo.DisplayName) changed in the domain meanwhile: $Path was saved, read the domain again and apply the setting again so that its version increases."
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    $Gpo.Version = $version
    if ($Folder -eq 'Machine') { $Gpo.MachineExtensionNames = $extensions } else { $Gpo.UserExtensionNames = $extensions }
    Write-Verbose "$Path of $($Gpo.DisplayName) saved, version $version."
}

# Deletes a file of the GPO folder; nothing when it is not there.
function Remove-PSGPOSysvolFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [string]$Path
    )

    $location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
    if ($IsWindows) {
        Remove-Item -LiteralPath "\\$($Directory.Server)\$($location.Share)\$($location.Path)\$Path" -Force -ErrorAction SilentlyContinue
        return
    }
    Assert-PSGPOKerberosOnly -Directory $Directory
    $null = Invoke-PSGPOSmbClient -Server $Directory.Server -Share $location.Share -AllowMissing -Command ('del "{0}\{1}"' -f $location.Path, $Path)
}

# Puts a GPO of the domain back as a backup has it (GPOToolsDirectory.RestoreGpo): its files
# in SYSVOL, then its version (both scopes increased), status and client-side extensions in the
# directory, refused if the version changed meanwhile.
function Restore-PSGPODomainGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Files,
        [int]$Flags,
        [AllowEmptyString()] [AllowNull()] [string]$MachineExtensionNames,
        [AllowEmptyString()] [AllowNull()] [string]$UserExtensionNames
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Base `
            -Attribute 'versionNumber', 'flags', 'gPCMachineExtensionNames', 'gPCUserExtensionNames'
        if (-not $entry) { throw "The GPO $($Gpo.DisplayName) is not in the domain anymore." }
        $oldVersion = Get-PSGPOLdapValue $entry 'versionNumber'
        $version = [GPOToolsDirectory]::GetNextVersion([GPOToolsDirectory]::GetNextVersion([int]$oldVersion, 'Machine'), 'User')

        # SYSVOL first: the files of the backup, without those it does not have, then GPT.INI.
        $current = Read-PSGPOSysvolFolder -Directory $Directory -Gpo $Gpo
        foreach ($name in $Files.Keys) {
            if ($name -ne 'GPT.INI') { Write-PSGPOSysvolFile -Directory $Directory -Gpo $Gpo -Path $name -Bytes ([byte[]]$Files[$name]) }
        }
        foreach ($name in @($current.Keys)) {
            if ($name -ne 'GPT.INI' -and -not $Files.Contains($name)) { Remove-PSGPOSysvolFile -Directory $Directory -Gpo $Gpo -Path $name }
        }
        $gptIni = if ($Files.Contains('GPT.INI')) { [byte[]]$Files['GPT.INI'] } else { [byte[]]$current['GPT.INI'] }
        Write-PSGPOSysvolFile -Directory $Directory -Gpo $Gpo -Path 'GPT.INI' -Bytes (Set-PSGPOGptIniVersion -Bytes $gptIni -Version $version)

        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Gpo.DistinguishedName
        Add-PSGPOLdapValueChange -Request $request -Name 'versionNumber' -Old $oldVersion -New "$version"
        Add-PSGPOLdapValueChange -Request $request -Name 'flags' -Old (Get-PSGPOLdapValue $entry 'flags') -New "$Flags"
        Add-PSGPOLdapValueChange -Request $request -Name 'gPCMachineExtensionNames' -Old (Get-PSGPOLdapValue $entry 'gPCMachineExtensionNames') -New $MachineExtensionNames
        Add-PSGPOLdapValueChange -Request $request -Name 'gPCUserExtensionNames' -Old (Get-PSGPOLdapValue $entry 'gPCUserExtensionNames') -New $UserExtensionNames
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -in 'NoSuchAttribute', 'AttributeOrValueExists') {
                throw "The GPO $($Gpo.DisplayName) changed in the domain meanwhile: its files were restored, restore it again so that its version increases."
            }
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
                throw "The account cannot edit the GPO '$($Gpo.DisplayName)': $($base.Message)"
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    $Gpo.Version = $version
    $Gpo.Flags = $Flags
    $Gpo.MachineExtensionNames = $MachineExtensionNames
    $Gpo.UserExtensionNames = $UserExtensionNames
    Write-Verbose "GPO $($Gpo.DisplayName) restored, version $version."
}
