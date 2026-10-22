<#
    Permissions of a GPO as the Delegation tab of GPMC shows and changes them: for each account of
    its DACL, one level of GPMC, from the access control entries of its group policy container.

      GpoRead                      Read                                    (A;CI;0x20094)
      GpoApply                     Read and apply                          read + (OA;CI;CR;Apply Group Policy)
                                   (GPMC: Read (from Security Filtering))
      GpoEdit                      Edit settings                           (A;CI;0x200BF)
      GpoEditDeleteModifySecurity  Edit settings, delete, modify security  (A;CI;0xF00FF)
      GpoCustom                    Custom: anything else, or a deny ACE

    The masks are those GPMC and Samba write (samba-tool gpo create, Set-GPPermission). The ACEs
    of CREATOR OWNER (inherit only) are not an account of the GPO, and the inherited ACEs come from
    CN=Policies: they are shown, not changed. The SYSVOL folder of the GPO takes the ACL of its
    container (Set-PSGPOGpoFolderAcl).
#>

$script:PSGPOPermissionMask = @{
    GpoRead = [uint32]0x00020094
    GpoEdit = [uint32]0x000200BF
    GpoEditDeleteModifySecurity = [uint32]0x000F00FF
}
# Edit settings as the approval workflow writes it (without the validated writes): still Edit settings.
$script:PSGPOEditSettingsMinimum = [uint32]0x000200B7

# The text of a level, as GPMC shows it.
function Get-PSGPOPermissionText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Permission)

    switch ($Permission) {
        'GpoRead' { 'Read' }
        'GpoApply' { 'Read and apply' }
        'GpoEdit' { 'Edit settings' }
        'GpoEditDeleteModifySecurity' { 'Edit settings, delete, modify security' }
        default { 'Custom' }
    }
}

# The level of an account from what its ACEs give: the union of its allow masks, whether it may
# apply the GPO, whether a deny ACE names it.
function Get-PSGPOPermissionLevel {
    [CmdletBinding()]
    [OutputType([string])]
    param([uint32]$Mask, [bool]$Applies, [bool]$Denied)

    $read = $script:PSGPOPermissionMask.GpoRead
    $full = $script:PSGPOPermissionMask.GpoEditDeleteModifySecurity
    if ($Denied) { return 'GpoCustom' }
    if (($Mask -band $full) -eq $full) { return 'GpoEditDeleteModifySecurity' }
    if (($Mask -band $script:PSGPOEditSettingsMinimum) -eq $script:PSGPOEditSettingsMinimum) { return 'GpoEdit' }
    $rest = $Mask -band (-bnot ($read -bor [GPOToolsSecurityDescriptor]::ControlAccess))
    if (($Mask -band $read) -eq $read -and -not $rest) { return $(if ($Applies) { 'GpoApply' } else { 'GpoRead' }) }
    'GpoCustom'
}

# The accounts of a DACL with their level: Sid, Permission, Inherited, Applies, Denied; the
# explicit ones first, in the order of the DACL, then the inherited ones.
function Get-PSGPOPermissionFromDescriptor {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor)

    $accounts = [ordered]@{}
    foreach ($ace in @($Descriptor.Dacl)) {
        if (-not $ace.IsKnown() -or ($ace.Flags -band [GPOToolsAce]::InheritOnly)) { continue }
        $inherited = [bool]($ace.Flags -band [GPOToolsAce]::Inherited)
        $key = "$inherited|$($ace.Sid)"
        if (-not $accounts.Contains($key)) { $accounts[$key] = @{ Sid = $ace.Sid; Inherited = $inherited; Mask = [uint32]0; Applies = $false; Denied = $false } }
        $account = $accounts[$key]
        $apply = ($ace.Mask -band [GPOToolsSecurityDescriptor]::ControlAccess) -and
            (-not $ace.IsObjectAce() -or $ace.ObjectType -eq [guid]::Empty -or $ace.ObjectType -eq [GPOToolsSecurityDescriptor]::ApplyGroupPolicy)
        if ($ace.IsDeny()) { $account.Denied = $true; continue }
        if ($apply) { $account.Applies = $true }
        # An object ACE gives its right on one property or extended right only.
        if (-not $ace.IsObjectAce() -or $ace.ObjectType -eq [guid]::Empty) { $account.Mask = $account.Mask -bor $ace.Mask }
    }
    $rows = foreach ($account in $accounts.Values) {
        [pscustomobject]@{
            Sid = $account.Sid
            Permission = Get-PSGPOPermissionLevel -Mask $account.Mask -Applies $account.Applies -Denied $account.Denied
            Mask = $account.Mask
            Inherited = $account.Inherited
            Applies = $account.Applies
            Denied = $account.Denied
        }
    }
    @($rows | Where-Object { -not $_.Inherited }) + @($rows | Where-Object Inherited)
}

# The explicit ACEs of an account, removed; those of CREATOR OWNER-like inherit-only entries stay.
function Remove-PSGPOAccountAce {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor, [Parameter(Mandatory)] [string]$Sid)

    for ($i = $Descriptor.Dacl.Count - 1; $i -ge 0; $i--) {
        $ace = $Descriptor.Dacl[$i]
        if ($ace.IsKnown() -and $ace.Sid -eq $Sid -and -not ($ace.Flags -band ([GPOToolsAce]::Inherited -bor [GPOToolsAce]::InheritOnly))) { $Descriptor.Dacl.RemoveAt($i) }
    }
}

# Gives an account one level of GPMC on the GPO, in place of what it had (the explicit ACEs of the
# account are replaced; its inherited ones stay). The editors keep "Apply Group Policy" when they
# had it: the security filtering does not change with the delegation of the GPO.
function Set-PSGPOPermissionAce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [Parameter(Mandatory)] [string]$Sid,
        [Parameter(Mandatory)] [ValidateSet('GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity', 'None')] [string]$Permission
    )

    $before = @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor | Where-Object { $_.Sid -eq $Sid -and -not $_.Inherited }) | Select-Object -First 1
    $keepApply = $before -and $before.Applies -and $Permission -in 'GpoEdit', 'GpoEditDeleteModifySecurity'
    Remove-PSGPOAccountAce -Descriptor $Descriptor -Sid $Sid
    $inherit = [GPOToolsAce]::ContainerInherit
    switch ($Permission) {
        'None' { return }
        'GpoApply' { $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, $inherit, $script:PSGPOPermissionMask.GpoRead, $Sid, [guid]::Empty)) }
        default { $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, $inherit, $script:PSGPOPermissionMask[$Permission], $Sid, [guid]::Empty)) }
    }
    if ($Permission -eq 'GpoApply' -or $keepApply) {
        $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowedObject, $inherit, [GPOToolsSecurityDescriptor]::ControlAccess, $Sid, [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
    }
}

# Adds an account to the security filtering of the GPO (it reads and applies it, a deny of "Apply
# Group Policy" that named it removed), or removes it: it no longer applies the GPO, and no longer
# reads it when that was all it did, as GPMC does; Authenticated Users keeps reading it (the
# computers must read every GPO, MS16-072).
function Set-PSGPOFilteringAce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [Parameter(Mandatory)] [string]$Sid,
        [Parameter(Mandatory)] [bool]$Apply
    )

    $inherit = [GPOToolsAce]::ContainerInherit
    if ($Apply) {
        for ($i = $Descriptor.Dacl.Count - 1; $i -ge 0; $i--) {
            $ace = $Descriptor.Dacl[$i]
            if ($ace.IsKnown() -and $ace.IsDeny() -and $ace.Sid -eq $Sid -and -not ($ace.Flags -band [GPOToolsAce]::Inherited) -and
                ($ace.Mask -band [GPOToolsSecurityDescriptor]::ControlAccess)) { $Descriptor.Dacl.RemoveAt($i) }
        }
        $before = @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor | Where-Object { $_.Sid -eq $Sid -and -not $_.Inherited }) | Select-Object -First 1
        # Nothing yet, or read only: read and apply, as GPMC adds an account to the filtering.
        if (-not $before -or $before.Permission -eq 'GpoRead') { Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid $Sid -Permission 'GpoApply'; return }
        if ($before.Applies) { return }
        # An editor, or other rights: they stay, the account reads and applies the GPO too.
        if (($before.Mask -band $script:PSGPOPermissionMask.GpoRead) -ne $script:PSGPOPermissionMask.GpoRead) {
            $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, $inherit, $script:PSGPOPermissionMask.GpoRead, $Sid, [guid]::Empty))
        }
        $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowedObject, $inherit, [GPOToolsSecurityDescriptor]::ControlAccess, $Sid, [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
        return
    }
    $before = @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor | Where-Object { $_.Sid -eq $Sid -and -not $_.Inherited }) | Select-Object -First 1
    if (-not $before) { return }
    for ($i = $Descriptor.Dacl.Count - 1; $i -ge 0; $i--) {
        $ace = $Descriptor.Dacl[$i]
        if ($ace.Sid -ne $Sid -or -not (Test-PSGPOApplyAce -Ace $ace)) { continue }
        $ace.Mask = $ace.Mask -band (-bnot [GPOToolsSecurityDescriptor]::ControlAccess)
        if (-not $ace.Mask) { $Descriptor.Dacl.RemoveAt($i) }
    }
    if ($before.Permission -eq 'GpoApply' -and $Sid -ne [GPOToolsSecurityDescriptor]::AuthenticatedUsers) { Remove-PSGPOAccountAce -Descriptor $Descriptor -Sid $Sid }
}

# The computers can read the GPO: Authenticated Users, Domain Computers or Everyone read it
# (MS16-072: a GPO the computer cannot read is not applied, even to its users).
function Test-PSGPOComputerReadable {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyCollection()] [object[]]$Permission = @())

    [bool]@($Permission | Where-Object {
            ($_.Sid -in [GPOToolsSecurityDescriptor]::AuthenticatedUsers, 'S-1-1-0' -or $_.Sid -match '-515$' -or $_.Sid -eq 'Domain Computers') -and
            $_.Permission -ne 'GpoCustom' -and -not $_.Denied
        }).Count
}

# The descriptor a GPO in memory starts with, as samba-tool gpo create and GPMC give it: the
# administrators and SYSTEM edit, delete and change its security, Authenticated Users read it,
# the domain controllers read it; its security filtering and denials from the GPO.
function New-PSGPODefaultDescriptor {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param([Parameter(Mandatory)] [GPOToolsGpo]$Gpo)

    # The well-known accounts by their SID; the other names stand for themselves in memory.
    $sids = @{}
    foreach ($known in [GPOToolsSecurityDescriptor]::WellKnownNames.GetEnumerator()) { $sids[$known.Value] = $known.Key }
    $descriptor = [GPOToolsSecurityDescriptor]::new()
    $descriptor.Owner = 'Domain Admins'
    $descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
    foreach ($admin in 'Domain Admins', 'Enterprise Admins', 'S-1-5-18') { Set-PSGPOPermissionAce -Descriptor $descriptor -Sid $admin -Permission 'GpoEditDeleteModifySecurity' }
    Set-PSGPOPermissionAce -Descriptor $descriptor -Sid ([GPOToolsSecurityDescriptor]::AuthenticatedUsers) -Permission 'GpoRead'
    Set-PSGPOPermissionAce -Descriptor $descriptor -Sid 'S-1-5-9' -Permission 'GpoRead'
    foreach ($name in @($Gpo.SecurityFiltering)) {
        $sid = if ($sids.ContainsKey($name)) { $sids[$name] } else { $name }
        Set-PSGPOFilteringAce -Descriptor $descriptor -Sid $sid -Apply $true
    }
    foreach ($name in @($Gpo.DeniedTo)) {
        $sid = if ($sids.ContainsKey($name)) { $sids[$name] } else { $name }
        $descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDeniedObject, [GPOToolsAce]::ContainerInherit, [GPOToolsSecurityDescriptor]::ControlAccess, $sid, [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
    }
    $descriptor
}

# One change of the permissions of a GPO: Permission (a level for $Sid, $Value) or Filtering
# ($Sid applies the GPO when $Value is True).
function Invoke-PSGPOPermissionChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [Parameter(Mandatory)] [ValidateSet('Permission', 'Filtering')] [string]$Operation,
        [Parameter(Mandatory)] [string]$Sid,
        [Parameter(Mandatory)] [string]$Value
    )

    if ($Operation -eq 'Permission') { Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid $Sid -Permission $Value }
    else { Set-PSGPOFilteringAce -Descriptor $Descriptor -Sid $Sid -Apply ($Value -eq 'True') }
}

# Changes the permissions of a GPO of the domain: its DACL read again (a change of another console
# is kept), changed, written; then the SYSVOL folder of the GPO and everything in it take the ACL
# of the DACL the domain stored, as GPMC does. Returns that descriptor.
function Set-PSGPODomainGpoPermission {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [string]$Operation,
        [Parameter(Mandatory)] [string]$Sid,
        [Parameter(Mandatory)] [string]$Value
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $Gpo.DistinguishedName
        Invoke-PSGPOPermissionChange -Descriptor $descriptor -Operation $Operation -Sid $Sid -Value $Value
        Set-PSGPODomainDacl -Connection $connection -DistinguishedName $Gpo.DistinguishedName -Descriptor (Get-PSGPOExplicitDescriptor -Descriptor $descriptor) -Name "the GPO '$($Gpo.DisplayName)'"
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $Gpo.DistinguishedName
    } finally {
        $connection.Dispose()
    }
    try {
        Set-PSGPOGpoFolderAcl -Directory $Directory -Gpo $Gpo -Descriptor $descriptor
    } catch {
        throw "The permissions of the GPO '$($Gpo.DisplayName)' are changed in the directory, not in SYSVOL: $($_.Exception.Message) Change them again once fixed: the computers read the folder with the ACL of the directory."
    }
    Write-Verbose "GPO '$($Gpo.DisplayName)': $Operation $Sid = $Value."
    $descriptor
}

# The permissions of a GPO as Get-PSGPOPermission gives them.
function Get-PSGPOPermissionRow {
    [CmdletBinding()]
    [OutputType('PSGPOTools.Permission')]
    param([Parameter(Mandatory)] [GPOToolsDirectory]$Directory, [Parameter(Mandatory)] [GPOToolsGpo]$Gpo)

    foreach ($row in @($Directory.GetGpoPermissions($Gpo))) {
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.Permission'
            GpoName = $Gpo.DisplayName
            GpoId = $Gpo.Id
            Trustee = $row.Name
            Sid = $row.Sid
            Permission = $row.Permission
            Inherited = $row.Inherited
            Denied = $row.Denied
        }
    }
}
