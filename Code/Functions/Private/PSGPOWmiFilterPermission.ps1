<#
    Delegation of the WMI filters, as the Delegation tabs of GPMC show and change it: on the WMI
    Filters container (CN=SOM,CN=WMIPolicy,CN=System), who creates filters; on a filter, who
    changes it. The ACEs are those the GPMC API writes (recorded on a Windows domain):

      Container  WmiCreate        Creator owner: creates filters,     (A;;CCLCRPWPRC)        0x00020035
                                  changes those it created (CREATOR
                                  OWNER of the container)
                 WmiFullControl   Full control: creates filters and   (A;;CCDCLCRPWPRC)      0x00020037
                                  changes all of them                 + (A;CIIO;GA...)       0x100F01FF
      Filter     WmiEdit          Edit                                (A;;LCRPWPRC)          0x00020034
                 WmiFullControl   Full control                        (A;;LCRPWPDTSDRCWD)    0x00070074
                 WmiCustom        other rights, or a deny ACE

    An account is at a level when its ACEs give at least these rights (the administrators of the
    domain have more). The accounts that only read are not listed, as in GPMC. The inherited ACEs
    are shown, not changed.
#>

$script:PSGPOWmiFilterMask = @{
    WmiCreate = [uint32]0x00020035
    WmiContainerFullControl = [uint32]0x00020037
    WmiChildFullControl = [uint32]0x100F01FF
    WmiEdit = [uint32]0x00020034
    WmiFullControl = [uint32]0x00070074
}
# Create child, and the rights a GA (generic all) gives on an object of the directory.
$script:PSGPOCreateChild = [uint32]0x1
$script:PSGPOGenericAll = [uint32]0x10000000
$script:PSGPOAllRights = [uint32]0x000F01FF
# Write property, delete tree, delete, write DACL, write owner: a right that changes something.
$script:PSGPOWriteRights = [uint32]0x000D0060

# The text of a level of the delegation of the WMI filters, as GPMC shows it.
function Get-PSGPOWmiFilterPermissionText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Permission)

    switch ($Permission) {
        'WmiCreate' { 'Creator owner' }
        'WmiEdit' { 'Edit' }
        'WmiFullControl' { 'Full control' }
        default { 'Custom' }
    }
}

# The level the rights of an account give on the WMI Filters container (-Container) or on a filter;
# $null when they only let it read.
function Get-PSGPOWmiFilterPermissionLevel {
    [CmdletBinding()]
    param([uint32]$Mask, [bool]$Children, [bool]$Denied, [switch]$Container)

    if ($Container) {
        if (-not ($Mask -band $script:PSGPOCreateChild)) { return $null }
        if ($Denied) { return 'WmiCustom' }
        if ($Children -or ($Mask -band $script:PSGPOAllRights) -eq $script:PSGPOAllRights) { return 'WmiFullControl' }
        return 'WmiCreate'
    }
    if ($Denied -and ($Mask -band $script:PSGPOWriteRights)) { return 'WmiCustom' }
    if (($Mask -band $script:PSGPOWmiFilterMask.WmiFullControl) -eq $script:PSGPOWmiFilterMask.WmiFullControl) { return 'WmiFullControl' }
    if (($Mask -band $script:PSGPOWmiFilterMask.WmiEdit) -eq $script:PSGPOWmiFilterMask.WmiEdit) { return 'WmiEdit' }
    if ($Mask -band $script:PSGPOWriteRights) { return 'WmiCustom' }
    $null
}

# The accounts of the DACL of the WMI Filters container (-Container) or of a filter with their
# level, as GPMC lists them: one row for each account, the level of all its rights; Inherited when
# its inherited ACEs alone give it, Explicit when it has ACEs of its own there (those a change
# replaces). In the order of the DACL, the inherited ones last.
function Get-PSGPOWmiFilterPermissionFromDescriptor {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor, [switch]$Container)

    $accounts = [ordered]@{}
    foreach ($ace in @($Descriptor.Dacl)) {
        if (-not $ace.IsKnown()) { continue }
        if (-not $accounts.Contains($ace.Sid)) { $accounts[$ace.Sid] = @{ Sid = $ace.Sid; Explicit = [uint32]0; Inherited = [uint32]0; HasExplicit = $false; Children = $false; InheritedChildren = $false; Denied = $false } }
        $account = $accounts[$ace.Sid]
        $inherited = [bool]($ace.Flags -band [GPOToolsAce]::Inherited)
        if (-not $inherited) { $account.HasExplicit = $true }
        $mask = [uint32]$ace.Mask
        if ($mask -band $script:PSGPOGenericAll) { $mask = $mask -bor $script:PSGPOAllRights }
        if ($ace.IsDeny()) { $account.Denied = $true; continue }
        if ($ace.Flags -band [GPOToolsAce]::InheritOnly) {
            # What the filters of the container inherit: full control on each of them.
            if (($ace.Flags -band [GPOToolsAce]::ContainerInherit) -and ($mask -band $script:PSGPOAllRights) -eq $script:PSGPOAllRights) {
                if ($inherited) { $account.InheritedChildren = $true } else { $account.Children = $true }
            }
            continue
        }
        # An object ACE: create child of a class counts as create child; another right of one
        # property or extended right only does not.
        if ($ace.IsObjectAce() -and $ace.ObjectType -ne [guid]::Empty) { $mask = $mask -band $script:PSGPOCreateChild }
        if ($inherited) { $account.Inherited = $account.Inherited -bor $mask } else { $account.Explicit = $account.Explicit -bor $mask }
    }
    $rows = foreach ($account in $accounts.Values) {
        $level = Get-PSGPOWmiFilterPermissionLevel -Mask ($account.Explicit -bor $account.Inherited) -Children ($account.Children -or $account.InheritedChildren) -Denied $account.Denied -Container:$Container
        if (-not $level) { continue }
        $fromInherited = Get-PSGPOWmiFilterPermissionLevel -Mask $account.Inherited -Children $account.InheritedChildren -Denied $false -Container:$Container
        [pscustomobject]@{
            Sid = $account.Sid
            Permission = $level
            Inherited = $fromInherited -eq $level
            Explicit = $account.HasExplicit
            Denied = $account.Denied
        }
    }
    @($rows | Where-Object { -not $_.Inherited }) + @($rows | Where-Object Inherited)
}

# Gives an account one level on the WMI Filters container (-Container: WmiCreate, WmiFullControl)
# or on a filter (WmiEdit, WmiFullControl), in place of what it had: its explicit ACEs there,
# inherit-only ones included, are replaced; None removes them.
function Set-PSGPOWmiFilterPermissionAce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [Parameter(Mandatory)] [string]$Sid,
        [Parameter(Mandatory)] [string]$Permission,
        [switch]$Container
    )

    $levels = if ($Container) { 'WmiCreate', 'WmiFullControl', 'None' } else { 'WmiEdit', 'WmiFullControl', 'None' }
    if ($levels -notcontains $Permission) { throw "Unknown permission on $(if ($Container) { 'the WMI Filters container' } else { 'a WMI filter' }): '$Permission' ($($levels -join ', '))." }
    for ($i = $Descriptor.Dacl.Count - 1; $i -ge 0; $i--) {
        $ace = $Descriptor.Dacl[$i]
        if ($ace.IsKnown() -and $ace.Sid -eq $Sid -and -not ($ace.Flags -band [GPOToolsAce]::Inherited)) { $Descriptor.Dacl.RemoveAt($i) }
    }
    $allow = [GPOToolsAce]::AccessAllowed
    switch ($Permission) {
        'None' { return }
        'WmiCreate' { $Descriptor.AddAce([GPOToolsAce]::new($allow, 0, $script:PSGPOWmiFilterMask.WmiCreate, $Sid, [guid]::Empty)) }
        'WmiEdit' { $Descriptor.AddAce([GPOToolsAce]::new($allow, 0, $script:PSGPOWmiFilterMask.WmiEdit, $Sid, [guid]::Empty)) }
        'WmiFullControl' {
            if ($Container) {
                $Descriptor.AddAce([GPOToolsAce]::new($allow, 0, $script:PSGPOWmiFilterMask.WmiContainerFullControl, $Sid, [guid]::Empty))
                $Descriptor.AddAce([GPOToolsAce]::new($allow, [GPOToolsAce]::ContainerInherit -bor [GPOToolsAce]::InheritOnly, $script:PSGPOWmiFilterMask.WmiChildFullControl, $Sid, [guid]::Empty))
            } else {
                $Descriptor.AddAce([GPOToolsAce]::new($allow, 0, $script:PSGPOWmiFilterMask.WmiFullControl, $Sid, [guid]::Empty))
            }
        }
    }
}

# The descriptors in memory, as a domain gives them: the WMI Filters container (-Container) where
# the administrators of the domain have full control and Administrators and Group Policy Creator
# Owners create filters; a filter, read by Authenticated Users (the rest it inherits from the
# container: GPOToolsDirectory.LoadWmiFilterDescriptor).
function New-PSGPOWmiFilterDefaultDescriptor {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param([switch]$Container)

    $descriptor = [GPOToolsSecurityDescriptor]::new()
    $descriptor.Owner = 'Domain Admins'
    $descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
    $read = [uint32]0x00020094
    if ($Container) {
        foreach ($admin in 'Domain Admins', 'Enterprise Admins') { Set-PSGPOWmiFilterPermissionAce -Descriptor $descriptor -Sid $admin -Permission 'WmiFullControl' -Container }
        foreach ($creator in 'S-1-5-32-544', 'Group Policy Creator Owners') { Set-PSGPOWmiFilterPermissionAce -Descriptor $descriptor -Sid $creator -Permission 'WmiCreate' -Container }
        $descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, [GPOToolsAce]::ContainerInherit, $read, [GPOToolsSecurityDescriptor]::AuthenticatedUsers, [guid]::Empty))
    } else {
        $descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, 0, $read, [GPOToolsSecurityDescriptor]::AuthenticatedUsers, [guid]::Empty))
    }
    $descriptor
}

# Changes the delegation of the WMI Filters container or of a filter in the domain: its DACL read
# again (a change of another console is kept), changed, written without its inherited ACEs (the
# domain computes them, and gives the filters what the container gives them). Returns the
# descriptor the domain stored.
function Set-PSGPODomainWmiFilterPermission {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$DistinguishedName,
        [Parameter(Mandatory)] [string]$Sid,
        [Parameter(Mandatory)] [string]$Permission,
        [switch]$Container,
        [string]$Name = $DistinguishedName
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $DistinguishedName
        Set-PSGPOWmiFilterPermissionAce -Descriptor $descriptor -Sid $Sid -Permission $Permission -Container:$Container
        Set-PSGPODomainDacl -Connection $connection -DistinguishedName $DistinguishedName -Descriptor (Get-PSGPOExplicitDescriptor -Descriptor $descriptor) -Name $Name
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $DistinguishedName
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "${Name}: $Sid = $Permission."
    $descriptor
}
