<#
    The client-side extensions a GPO declares (gPCMachineExtensionNames, gPCUserExtensionNames: the
    computers run each of them, and each reads its own settings), and the files of its folder,
    against what the console reads. What it does not interpret is listed where the GPO is reviewed
    (the Settings tab, its details, its approval, Get-PSGPOReport): the computers apply it all the
    same, and an approver approves it unseen otherwise.
#>

# The extensions the console knows: their name (as Policy Analyzer writes it) and where their
# settings are:
#   Read       files the console reads (Registry.pol, GptTmpl.inf, audit.csv, scripts.ini)
#   Registry   Registry.pol: its values are listed, as policies of the ADMX or extra registry settings
#   Files      other files of the folder of the GPO
#   Directory  objects of the directory under the container of the GPO
# The preference types are read too (Resources/Preferences.json).
$script:PSGPOExtension = @{
    '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}' = @{ Name = 'Registry Policy'; Storage = 'Read' }
    '{827D319E-6EAC-11D2-A4EA-00C04F79F83A}' = @{ Name = 'Security'; Storage = 'Read' }
    '{F3CCC681-B74C-4060-9F26-CD84525DCA2A}' = @{ Name = 'Audit Policy Configuration'; Storage = 'Read' }
    '{42B5FAAE-6536-11D2-AE5A-0000F87571E3}' = @{ Name = 'Scripts'; Storage = 'Read' }
    '{B1BE8D72-6EAC-11D2-A4EA-00C04F79F83A}' = @{ Name = 'EFS Recovery'; Storage = 'Read' }
    '{4CFB60C1-FAA6-47F1-89AA-0B18730C9FD3}' = @{ Name = 'Internet Explorer Zonemapping'; Storage = 'Registry' }
    '{7933F41E-56F8-41D6-A31C-4148A711EE93}' = @{ Name = 'Windows Search Group Policy Extension'; Storage = 'Registry' }
    '{D76B9641-3288-4F75-942D-087DE603E3EA}' = @{ Name = 'Local Administrator Password Solution (LAPS)'; Storage = 'Registry' }
    '{2A8FDC61-2347-4C87-92F6-B05EB91A201A}' = @{ Name = 'Group Policy Mitigation Options'; Storage = 'Registry' }
    '{F312195E-3D9D-447A-A3F5-08DFFA24735E}' = @{ Name = 'Device Guard'; Storage = 'Registry' }
    '{FB2CA36D-0B40-4307-821B-A13B252DE56C}' = @{ Name = 'Enterprise QoS'; Storage = 'Registry' }
    '{25537BA6-77A8-11D2-9B6C-0000F8080861}' = @{ Name = 'Folder Redirection'; Storage = 'Files' }
    '{C6DC5466-785A-11D2-84D0-00C04FB169F7}' = @{ Name = 'Software Installation'; Storage = 'Files' }
    '{3060E8D0-7020-11D2-842D-00C04FA372D4}' = @{ Name = 'Remote Installation Services'; Storage = 'Files' }
    '{A2E30F80-D7DE-11D2-BBDE-00C04F86AE3B}' = @{ Name = 'Internet Explorer Maintenance'; Storage = 'Files' }
    '{E437BC1C-AA7D-11D2-A382-00C04F991E27}' = @{ Name = 'IP Security'; Storage = 'Directory' }
    '{0ACDD40C-75AC-47AB-BAA0-BF6DE7E7FE63}' = @{ Name = 'Wireless Group Policy'; Storage = 'Directory' }
    '{B587E2B1-4D59-4E7E-AED9-22B9DF11D053}' = @{ Name = '802.3 Group Policy'; Storage = 'Directory' }
    '{8A28E2C5-8D06-49A4-A08C-632DAA493E17}' = @{ Name = 'Deployed Printer Connections'; Storage = 'Directory' }
}

# The null GUID under which GPMC lists the tools of the preferences: no extension.
$script:PSGPONullExtension = '{00000000-0000-0000-0000-000000000000}'

# The client-side extensions of gPC*ExtensionNames ([{extension}{tool}...][...]): Scope (Machine,
# User), Guid, Name and Storage (Read, Registry, Files, Directory, or Unknown: an extension the
# console does not know), in their order.
function Get-PSGPODeclaredExtension {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [AllowNull()] [string]$MachineExtensionNames,
        [AllowEmptyString()] [AllowNull()] [string]$UserExtensionNames
    )

    foreach ($scope in 'Machine', 'User') {
        $names = if ($scope -eq 'Machine') { $MachineExtensionNames } else { $UserExtensionNames }
        foreach ($pair in [regex]::Matches("$names", '\[(\{[0-9A-Fa-f-]{36}\})')) {
            $guid = $pair.Groups[1].Value.ToUpperInvariant()
            if ($guid -eq $script:PSGPONullExtension) { continue }
            $known = $script:PSGPOExtension[$guid]
            $preference = if (-not $known) { @(Get-PSGPOPreferenceExtension | Where-Object { [string]::Equals($_.Cse, $guid, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1 }
            [pscustomobject]@{
                Scope = $scope
                Guid = $guid
                Name = if ($known) { $known.Name } elseif ($preference) { "Group Policy $($preference.Name)" } else { $guid }
                Storage = if ($known) { $known.Storage } elseif ($preference) { 'Read' } else { 'Unknown' }
            }
        }
    }
}

# Files of a GPO that apply nothing: its comment (GPO.cmt), the comments of its policies
# (comment.cmtx), the administrative templates (.adm) GPMC copied in its folder.
function Test-PSGPOInertFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$Path)

    $Path -ieq 'GPO.cmt' -or $Path -match '(^|\\)comment\.cmtx$' -or $Path -match '^Adm\\[^\\]+\.adm$'
}

# What the console does not interpret in a GPO, as rows of the Settings tab (AvaloniaSettingRow,
# IsExtra): the client-side extensions whose settings it does not read, and the files of its
# folder none of its readers read ($Known, Get-PSGPOFolderSetting), but those that apply nothing.
function Get-PSGPOUninterpretedSetting {
    [CmdletBinding()]
    [OutputType([AvaloniaSettingRow])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.HashSet[string]]$Known,
        [AllowEmptyString()] [AllowNull()] [string]$MachineExtensionNames,
        [AllowEmptyString()] [AllowNull()] [string]$UserExtensionNames
    )

    # In the order the GPO declares them, the computer first: one row per extension, its scopes.
    $declared = [ordered]@{}
    foreach ($extension in @(Get-PSGPODeclaredExtension -MachineExtensionNames $MachineExtensionNames -UserExtensionNames $UserExtensionNames | Where-Object Storage -NotIn 'Read', 'Registry')) {
        if (-not $declared.Contains($extension.Guid)) { $declared[$extension.Guid] = [System.Collections.Generic.List[object]]::new() }
        $declared[$extension.Guid].Add($extension)
    }
    foreach ($scopes in $declared.Values) {
        $extension = $scopes[0]
        $row = [AvaloniaSettingRow]::new()
        $row.Path = 'Client-side extensions'
        $row.Name = $extension.Name
        $row.State = (@($scopes | ForEach-Object { if ($_.Scope -eq 'Machine') { 'Computer' } else { 'User' } }) | Select-Object -Unique) -join ', '
        # The text on a line of its own, translated in the Settings tab; its GUID below.
        $text = switch ($extension.Storage) {
            'Files' { 'Its settings are in files of the GPO that the console does not read.' }
            'Directory' { 'Its settings are in objects of the directory under the GPO, which the console does not read.' }
            default { 'An extension the console does not know: its settings may be in files or in objects of the directory it does not read.' }
        }
        $row.Options = $text + [Environment]::NewLine + $extension.Guid
        $row.IsExtra = $true
        $row.Key = "Extension|$($extension.Guid)"
        $row
    }
    foreach ($name in $Files.Keys) {
        if ($name -eq 'GPT.INI' -or $Known.Contains($name) -or (Test-PSGPOInertFile -Path $name)) { continue }
        $bytes = [byte[]]$Files[$name]
        $row = [AvaloniaSettingRow]::new()
        $row.Path = 'Files of the GPO'
        $row.Name = $name
        $row.State = "$($bytes.Length) bytes"
        $row.Options = "SHA-256 $((Get-PSGPOFileHash -Bytes $bytes).Substring(0, 12))"
        $row.IsExtra = $true
        $row.Key = "File|$name"
        $row
    }
}
