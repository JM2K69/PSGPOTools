<#
    Restricted groups of a GPO, as the Group Policy editor shows them under Computer
    Configuration > Policies > Windows Settings > Security Settings > Restricted Groups: the
    section [Group Membership] of GptTmpl.inf ([MS-GPSB] 2.2.6), two keys per group:

      *S-1-5-32-544__Members = *S-1-5-21-...-512,CONTOSO\Helpdesk
      *S-1-5-32-544__Memberof = *S-1-5-32-555

    A group is a name (DOMAIN\name) or a SID prefixed with *. Members: when the key is there, the
    computers give the group these members only, and remove the others (an empty list: no member
    at all); without the key, its members do not change. Member of: the groups the computers add
    it to (they do not remove it from the others).
#>

$script:PSGPORestrictedGroupSection = 'Group Membership'

# The restricted groups of the template: Group, Members and MemberOf (the accounts; $null when
# the key is not defined), in their order in the file.
function Get-PSGPORestrictedGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsSecurityTemplate]$Template)

    $groups = [ordered]@{}
    foreach ($key in $Template.GetKeys($script:PSGPORestrictedGroupSection)) {
        if ($key -notmatch '^(.+)__(Members|Memberof)$') { continue }
        $name = $Matches[1]
        $kind = if ($Matches[2] -eq 'Members') { 'Members' } else { 'MemberOf' }
        $found = @($groups.Keys | Where-Object { $_ -ieq $name })
        if (-not $found.Count) { $groups[$name] = [pscustomobject]@{ Group = $name; Members = $null; MemberOf = $null } } else { $name = $found[0] }
        $accounts = @("$($Template.GetValue($script:PSGPORestrictedGroupSection, $key))" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $groups[$name].$kind = [string[]]$accounts
    }
    $groups.Values
}

# Sets a restricted group: its members ($null: not defined, @(): no member) and the groups it is
# a member of ($null or @(): none). A group that was there under another case of its name is
# replaced.
function Set-PSGPORestrictedGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityTemplate]$Template,
        [Parameter(Mandatory)] [string]$Group,
        [AllowNull()] [string[]]$Members,
        [AllowNull()] [string[]]$MemberOf
    )

    $Group = $Group.Trim()
    if (-not $Group) { throw (Get-PSGPOText 'Give the group: DOMAIN\name, or its SID prefixed with * (*S-1-5-32-544).') }
    if ($Group.Contains(',') -or $Group.Contains('=')) { throw (Get-PSGPOText "'{0}' is not a group name." $Group) }
    Remove-PSGPORestrictedGroup -Template $Template -Group $Group
    $Template.AddPreamble()
    $clean = { param($Accounts) (@($Accounts) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Unique) -join ',' }
    # Both keys, as the Group Policy editor writes them: Memberof first, Members then.
    $Template.SetValue($script:PSGPORestrictedGroupSection, "$($Group)__Memberof", (& $clean $MemberOf))
    if ($null -ne $Members) { $Template.SetValue($script:PSGPORestrictedGroupSection, "$($Group)__Members", (& $clean $Members)) }
}

# Removes a restricted group from the template.
function Remove-PSGPORestrictedGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityTemplate]$Template,
        [Parameter(Mandatory)] [string]$Group
    )

    foreach ($key in @($Template.GetKeys($script:PSGPORestrictedGroupSection))) {
        if ($key -ieq "$($Group.Trim())__Members" -or $key -ieq "$($Group.Trim())__Memberof") { $Template.SetValue($script:PSGPORestrictedGroupSection, $key, $null) }
    }
}

# A group or an account as the editor shows it: its name, a well-known SID by its name.
function Format-PSGPORestrictedAccount {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string]$Account)

    $name = [GPOToolsSecuritySetting]::FormatAccount($Account)
    if ($Account.StartsWith('*') -and $name -ne $Account.Substring(1)) { "$name ($Account)" } else { $name }
}

# The restricted groups as the Settings tab of GPMC lists them: the group, its members, and the
# groups it is a member of.
function Get-PSGPOConfiguredRestrictedGroup {
    [CmdletBinding()]
    [OutputType([AvaloniaSettingRow])]
    param([Parameter(Mandatory)] [GPOToolsSecurityTemplate]$Template)

    foreach ($group in @(Get-PSGPORestrictedGroup -Template $Template)) {
        $row = [AvaloniaSettingRow]::new()
        $row.Path = 'Policies > Windows Settings > Security Settings > Restricted Groups'
        $row.Name = Format-PSGPORestrictedAccount $group.Group
        $row.State = if ($null -eq $group.Members) { 'Members: not defined' }
            elseif (-not $group.Members.Count) { 'Members: none (the computers remove every member)' }
            else { "Members: $(@($group.Members | ForEach-Object { Format-PSGPORestrictedAccount $_ }) -join ', ')" }
        $row.Options = if ($group.MemberOf.Count) { "Member of: $(@($group.MemberOf | ForEach-Object { Format-PSGPORestrictedAccount $_ }) -join ', ')" }
        $row
    }
}
