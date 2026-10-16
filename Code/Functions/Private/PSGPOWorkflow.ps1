<#
    Approval workflow of the GPOs (Workflow of the configuration of the domain), with the rights
    of the domain only: nothing to trust on the computer of the technician.

    - Roles: the approvers (Tier 0) and the creators (Tier 1) are groups of the domain, named in
      the configuration of the domain; the role of the account is read in its groups
      (tokenGroups).
    - Delegation (Initialize-PSGPOWorkflow, by an approver): the creators create GPOs with the
      right to create groupPolicyContainer objects in CN=Policies, and to create folders in the
      Policies folder of SYSVOL (CREATOR OWNER gets full control of what it creates there), not
      with Group Policy Creator Owners.
    - Pending GPO: its creator owns it (CREATOR OWNER of the groupPolicyContainer class: full
      control). The console removes "Apply Group Policy" from it, so that it applies to nobody
      even linked, and lets the groups of creators of the creator edit its settings.
    - Approval: the owner of the GPO becomes the owner of the approved GPOs, in the directory
      (its container and the containers it holds) and in SYSVOL (its folder and every file and
      folder in it): an owner can always change the permissions, so the creator would give
      itself its rights back otherwise. The ACEs of the creator and of the creators are removed;
      the groups of creators keep editing its settings (EditSettings) or only read it
      (ReadOnly); it applies to the group the approver chooses.

    A GPO is pending when its owner is none of the owners an approved GPO has (the owner of the
    approved GPOs, the approvers, Domain Admins, Enterprise Admins, Administrators, SYSTEM).
#>

# The class of the GPOs (schemaIDGUID of groupPolicyContainer).
$script:PSGPOGroupPolicyContainerClass = [guid]'f30e3bc2-9ff0-11d1-b603-0000f80367c1'
# Rights of the directory: create child objects, and GPMC "Edit settings" on a GPO (read, write,
# create and delete child objects: RP WP CC DC LC LO RC).
$script:PSGPOCreateChildMask = [uint32]0x00000001
$script:PSGPOEditSettingsMask = [uint32]0x000200B7
# Rights of the files: read and execute with create folders (this folder only), full control.
$script:PSGPOCreateFolderMask = [uint32]0x001200AD
$script:PSGPOFullFileMask = [uint32]0x001F01FF

# The workflow of the configuration in use, its lists of groups split.
function Get-PSGPOWorkflowSetting {
    [CmdletBinding()]
    param()

    $workflow = (Get-PSGPOConfigurationData).Workflow
    $split = { param($Text) @("$Text" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    [pscustomobject]@{
        Enabled = [bool]$workflow.Enabled
        Approvers = [string[]](& $split $workflow.Approvers)
        Creators = [string[]](& $split $workflow.Creators)
        ApprovedOwner = "$($workflow.ApprovedOwner)".Trim()
        CreatorRights = "$($workflow.CreatorRights)"
    }
}

# A value in an LDAP filter (RFC 4515).
function ConvertTo-PSGPOLdapFilterValue {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Value)

    $text = [System.Text.StringBuilder]::new()
    foreach ($char in $Value.ToCharArray()) {
        switch ($char) {
            '\' { [void]$text.Append('\5c') }
            '*' { [void]$text.Append('\2a') }
            '(' { [void]$text.Append('\28') }
            ')' { [void]$text.Append('\29') }
            ([char]0) { [void]$text.Append('\00') }
            default { [void]$text.Append($char) }
        }
    }
    $text.ToString()
}

# Entries of a search with their binary attributes: DistinguishedName, and Values by attribute
# (byte arrays).
function Invoke-PSGPOLdapBinarySearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$SearchBase,
        [ValidateSet('Base', 'OneLevel', 'Subtree')] [string]$Scope = 'Subtree',
        [string]$Filter = '(objectClass=*)',
        [Parameter(Mandatory)] [string[]]$Attribute,
        # The security descriptor parts of nTSecurityDescriptor
        [System.DirectoryServices.Protocols.SecurityMasks]$SecurityMasks = 'None'
    )

    $request = [System.DirectoryServices.Protocols.SearchRequest]::new($SearchBase, $Filter, $Scope, $Attribute)
    if ($SecurityMasks -ne 'None') { [void]$request.Controls.Add([System.DirectoryServices.Protocols.SecurityDescriptorFlagControl]::new($SecurityMasks)) }
    $page = $null
    if ($Scope -ne 'Base') { $page = [System.DirectoryServices.Protocols.PageResultRequestControl]::new(500); [void]$request.Controls.Add($page) }
    do {
        $response = $Connection.SendRequest($request)
        foreach ($entry in $response.Entries) {
            $values = @{}
            foreach ($name in $entry.Attributes.AttributeNames) { $values[$name] = @($entry.Attributes[$name].GetValues([byte[]])) }
            [pscustomobject]@{ DistinguishedName = $entry.DistinguishedName; Values = $values }
        }
        $cookie = $null
        if ($page) {
            $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] } | Select-Object -First 1).Cookie
            $page.Cookie = $cookie
        }
    } while ($cookie -and $cookie.Length)
}

# The accounts of the domain named in the configuration (sAMAccountName, DOMAIN\name or a SID):
# Name and Sid. An unknown name stops the workflow: it would give the wrong rights.
function Find-PSGPODomainAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DomainDistinguishedName,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Name
    )

    foreach ($item in $Name) {
        if ($item -match '^S-1-\d+(-\d+)+$') { [pscustomobject]@{ Name = $item; Sid = $item }; continue }
        $account = ($item -split '\\')[-1]
        $entry = @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $DomainDistinguishedName `
                -Filter "(sAMAccountName=$(ConvertTo-PSGPOLdapFilterValue $account))" -Attribute 'objectSid') | Select-Object -First 1
        if (-not $entry -or -not $entry.Values['objectSid']) { throw "No account named '$item' in the domain." }
        [pscustomobject]@{ Name = $account; Sid = ConvertFrom-PSGPOSidBytes -Bytes ([byte[]]$entry.Values['objectSid'][0]) }
    }
}

# SIDs of an account and of its groups, nested ones included (tokenGroups), by its name
# (DOMAIN\user) or its SID.
function Get-PSGPOAccountGroupSid {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DomainDistinguishedName,
        [string]$Account,
        [string]$Sid
    )

    $filter = if ($Sid) { "(objectSid=$(ConvertTo-PSGPOLdapBinaryFilter -Bytes ([GPOToolsSecurityDescriptor]::ConvertSidToBytes($Sid))))" }
        else { "(sAMAccountName=$(ConvertTo-PSGPOLdapFilterValue (($Account -split '\\')[-1])))" }
    $entry = @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $DomainDistinguishedName -Filter $filter -Attribute 'objectSid') | Select-Object -First 1
    if (-not $entry) { return [string[]]@() }
    $sids = [System.Collections.Generic.List[string]]::new()
    $sids.Add((ConvertFrom-PSGPOSidBytes -Bytes ([byte[]]$entry.Values['objectSid'][0])))
    $token = @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $entry.DistinguishedName -Scope Base -Attribute 'tokenGroups') | Select-Object -First 1
    foreach ($value in @($token.Values['tokenGroups'])) { if ($value) { $sids.Add((ConvertFrom-PSGPOSidBytes -Bytes ([byte[]]$value))) } }
    , [string[]]$sids
}

# The owners an approved GPO may have: the owner of the approved GPOs, the approvers, Domain
# Admins, Enterprise Admins, Administrators, SYSTEM.
function Get-PSGPOApprovedOwnerSid {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [pscustomobject]$Workflow, [Parameter(Mandatory)] [string]$DomainSid)

    , [string[]](@($Workflow.ApprovedOwnerSid) + @($Workflow.ApproverSids) + @("$DomainSid-512", "$DomainSid-519", 'S-1-5-32-544', 'S-1-5-18') | Select-Object -Unique)
}

# The workflow of the directory (GPOToolsDirectory.Workflow) and the approval state of its GPOs,
# from the configuration of the domain, the groups of the account and the owners of the GPOs.
# A workflow that cannot be read stops the creation of GPOs: a GPO of a creator would apply
# before its approval.
function Update-PSGPODomainWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory
    )

    $setting = Get-PSGPOWorkflowSetting
    if (-not $setting.Enabled) {
        $Directory.Workflow = $null
        foreach ($gpo in $Directory.Gpos) { $gpo.ApprovalState = $null }
        return
    }
    $domainDN = $Directory.Domain.DistinguishedName
    try {
        $approvers = @(Find-PSGPODomainAccount -Connection $Connection -DomainDistinguishedName $domainDN -Name $setting.Approvers)
        $creators = @(Find-PSGPODomainAccount -Connection $Connection -DomainDistinguishedName $domainDN -Name $setting.Creators)
        $owner = @(Find-PSGPODomainAccount -Connection $Connection -DomainDistinguishedName $domainDN -Name $setting.ApprovedOwner)[0]
        # Not @(...): the function returns its array as one object.
        $token = Get-PSGPOAccountGroupSid -Connection $Connection -DomainDistinguishedName $domainDN -Account $Directory.Account
    } catch {
        $Directory.Workflow = [pscustomobject]@{ Enabled = $true; Problem = $_.Exception.Message; IsApprover = $false; IsCreator = $false }
        $Directory.CanCreateGpo = $false
        Write-Warning "The approval workflow of $($Directory.DomainName) cannot be read, no GPO can be created until it is fixed: $($_.Exception.Message)"
        return
    }
    $Directory.Workflow = [pscustomobject]@{
        Enabled = $true
        Problem = $null
        IsApprover = [bool]@($approvers | Where-Object { $token -contains $_.Sid }).Count
        IsCreator = [bool]@($creators | Where-Object { $token -contains $_.Sid }).Count
        Approvers = [string[]]@($approvers.Name)
        ApproverSids = [string[]]@($approvers.Sid)
        Creators = [string[]]@($creators.Name)
        CreatorSids = [string[]]@($creators.Sid)
        # The groups of creators the account is in: they edit the GPOs it creates
        AccountCreatorSids = [string[]]@($creators | Where-Object { $token -contains $_.Sid } | ForEach-Object Sid)
        ApprovedOwner = $owner.Name
        ApprovedOwnerSid = $owner.Sid
        CreatorRights = $setting.CreatorRights
    }

    # The owners of the GPOs: their approval state.
    $owners = @{}
    foreach ($entry in @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase "CN=Policies,CN=System,$domainDN" -Scope OneLevel `
                -Filter '(objectClass=groupPolicyContainer)' -Attribute 'nTSecurityDescriptor' -SecurityMasks Owner)) {
        if ($entry.Values['nTSecurityDescriptor']) {
            $owners[$entry.DistinguishedName.ToLowerInvariant()] = [GPOToolsSecurityDescriptor]::Parse([byte[]]$entry.Values['nTSecurityDescriptor'][0]).Owner
        }
    }
    $names = Resolve-PSGPODomainSid -Connection $Connection -DomainDistinguishedName $domainDN -Sid @($owners.Values | Where-Object { $_ })
    $domainSid = ($owner.Sid -replace '-\d+$', '')
    $approved = Get-PSGPOApprovedOwnerSid -Workflow $Directory.Workflow -DomainSid $domainSid
    foreach ($gpo in $Directory.Gpos) {
        $sid = $owners["$($gpo.DistinguishedName)".ToLowerInvariant()]
        $gpo.OwnerSid = $sid
        $gpo.Owner = if ($sid) { $names[$sid] }
        $gpo.ApprovalState = if (-not $sid) { $null } elseif ($approved -contains $sid) { 'Approved' } else { 'Pending' }
    }
}

# ACEs that give "Apply Group Policy" (or every extended right), not inherited: who applies the GPO.
function Test-PSGPOApplyAce {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [GPOToolsAce]$Ace)

    $Ace.IsKnown() -and -not $Ace.IsDeny() -and -not ($Ace.Flags -band [GPOToolsAce]::Inherited) -and ($Ace.Mask -band [GPOToolsSecurityDescriptor]::ControlAccess) -and
        (-not $Ace.IsObjectAce() -or $Ace.ObjectType -eq [guid]::Empty -or $Ace.ObjectType -eq [GPOToolsSecurityDescriptor]::ApplyGroupPolicy)
}

# The DACL of a GPO waiting for its approval: nobody applies it ("Apply Group Policy" removed
# from every ACE, the other rights kept), and the groups $EditSids edit its settings.
function ConvertTo-PSGPOPendingDescriptor {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [AllowEmptyCollection()] [string[]]$EditSids = @()
    )

    $pending = [GPOToolsSecurityDescriptor]::Parse($Descriptor.ToBytes())
    Remove-PSGPOApplyRight -Descriptor $pending
    foreach ($sid in $EditSids) { Add-PSGPOEditSettingsAce -Descriptor $pending -Sid $sid }
    $pending
}

# Removes "Apply Group Policy" from the ACEs that give it: the ACE goes, or keeps its other rights.
function Remove-PSGPOApplyRight {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor)

    for ($i = $Descriptor.Dacl.Count - 1; $i -ge 0; $i--) {
        $ace = $Descriptor.Dacl[$i]
        if (-not (Test-PSGPOApplyAce -Ace $ace)) { continue }
        $ace.Mask = $ace.Mask -band (-bnot [GPOToolsSecurityDescriptor]::ControlAccess)
        if (-not $ace.Mask) { $Descriptor.Dacl.RemoveAt($i) }
    }
}

function Add-PSGPOEditSettingsAce {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor, [Parameter(Mandatory)] [string]$Sid)

    $present = @($Descriptor.Dacl | Where-Object { $_.IsKnown() -and $_.Type -eq [GPOToolsAce]::AccessAllowed -and $_.Sid -eq $Sid -and
            -not ($_.Flags -band [GPOToolsAce]::Inherited) -and ($_.Mask -band $script:PSGPOEditSettingsMask) -eq $script:PSGPOEditSettingsMask }).Count
    if (-not $present) { $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, [GPOToolsAce]::ContainerInherit, $script:PSGPOEditSettingsMask, $Sid, [guid]::Empty)) }
}

# The descriptor of an approved GPO, or of an object it holds ($Container: the GPO itself): owned
# by $OwnerSid, without the ACEs (not inherited) of $RemoveSids (the creator and the creators);
# on the GPO, the groups $EditSids edit its settings, and $ApplySid applies it.
function ConvertTo-PSGPOApprovedDescriptor {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [Parameter(Mandatory)] [string]$OwnerSid,
        [AllowEmptyCollection()] [string[]]$RemoveSids = @(),
        [AllowEmptyCollection()] [string[]]$EditSids = @(),
        [string]$ApplySid,
        [switch]$Container
    )

    $approved = [GPOToolsSecurityDescriptor]::Parse($Descriptor.ToBytes())
    $approved.Owner = $OwnerSid
    for ($i = $approved.Dacl.Count - 1; $i -ge 0; $i--) {
        $ace = $approved.Dacl[$i]
        if ($ace.IsKnown() -and -not ($ace.Flags -band [GPOToolsAce]::Inherited) -and $RemoveSids -contains $ace.Sid) { $approved.Dacl.RemoveAt($i) }
    }
    if ($Container) {
        Remove-PSGPOApplyRight -Descriptor $approved
        foreach ($sid in $EditSids) { Add-PSGPOEditSettingsAce -Descriptor $approved -Sid $sid }
        if ($ApplySid) {
            $inherit = [GPOToolsAce]::ContainerInherit
            # Authenticated Users read every GPO already.
            if ($ApplySid -ne [GPOToolsSecurityDescriptor]::AuthenticatedUsers) {
                $approved.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, $inherit, [GPOToolsSecurityDescriptor]::ReadMask, $ApplySid, [guid]::Empty))
            }
            $approved.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowedObject, $inherit, [GPOToolsSecurityDescriptor]::ControlAccess, $ApplySid, [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
        }
    }
    $approved
}

# The descriptor without its inherited ACEs: the directory computes them again from the parent
# when the DACL is written.
function Get-PSGPOExplicitDescriptor {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor)

    $explicit = [GPOToolsSecurityDescriptor]::Parse($Descriptor.ToBytes())
    for ($i = $explicit.Dacl.Count - 1; $i -ge 0; $i--) {
        if ($explicit.Dacl[$i].Flags -band [GPOToolsAce]::Inherited) { $explicit.Dacl.RemoveAt($i) }
    }
    $explicit
}

# Writes the owner and the DACL of an object of the directory.
function Set-PSGPODomainOwnerAndDacl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DistinguishedName,
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [string]$Name = $DistinguishedName
    )

    $request = [System.DirectoryServices.Protocols.ModifyRequest]::new($DistinguishedName,
        [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Replace, 'nTSecurityDescriptor', [byte[]](Get-PSGPOExplicitDescriptor -Descriptor $Descriptor).ToBytes())
    [void]$request.Controls.Add([System.DirectoryServices.Protocols.SecurityDescriptorFlagControl]::new([System.DirectoryServices.Protocols.SecurityMasks]'Owner,Dacl'))
    try {
        [void]$Connection.SendRequest($request)
    } catch {
        $base = $_.Exception.GetBaseException()
        if ($base.PSObject.Properties['Response'] -and "$($base.Response.ResultCode)" -in 'InsufficientAccessRights', 'ConstraintViolation') {
            throw "The account cannot change the owner and the permissions of ${Name}: $($base.Message)"
        }
        throw
    }
}

# A GPO just created by a creator, made to wait for its approval: nobody applies it, the groups of
# creators of the creator edit it; in the directory, then its SYSVOL folder.
function Set-PSGPODomainPendingGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $Gpo.DistinguishedName
        $pending = ConvertTo-PSGPOPendingDescriptor -Descriptor $descriptor -EditSids $Directory.Workflow.AccountCreatorSids
        Set-PSGPODomainDacl -Connection $connection -DistinguishedName $Gpo.DistinguishedName -Descriptor $pending -Name "the GPO '$($Gpo.DisplayName)'"
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $Gpo.DistinguishedName
    } finally {
        $connection.Dispose()
    }
    # Every file and folder of the GPO, while the creator owns them: Samba sets the POSIX ACL of
    # a file only for its owner, and checks both; the groups of creators keep it once approved.
    Set-PSGPOGpoFolderAcl -Directory $Directory -Gpo $Gpo -Descriptor $descriptor
    $Gpo.OwnerSid = $descriptor.Owner
    $Gpo.Owner = $Directory.Account
    $Gpo.SecurityFiltering = @()
    $Gpo.DeniedTo = @()
    Write-Verbose "GPO '$($Gpo.DisplayName)' waits for its approval: it applies to nobody."
}

# Approves a GPO of the domain (GPOToolsDirectory.ApproveGpo): its container and the containers
# it holds, then its SYSVOL folder and everything in it, owned by the owner of the approved GPOs.
function Approve-PSGPODomainGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [ValidateSet('ReadOnly', 'EditSettings')] [string]$CreatorRights,
        [Parameter(Mandatory)] [string]$ApplyToSid
    )

    $workflow = $Directory.Workflow
    $ownerSid = $workflow.ApprovedOwnerSid
    $domainDN = $Directory.Domain.DistinguishedName
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entries = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Subtree -Attribute 'nTSecurityDescriptor' -SecurityMasks 'Owner,Group,Dacl')
        $self = $entries | Where-Object { $_.DistinguishedName -eq $Gpo.DistinguishedName } | Select-Object -First 1
        if (-not $self -or -not $self.Values['nTSecurityDescriptor']) { throw "The permissions of the GPO '$($Gpo.DisplayName)' cannot be read." }
        $descriptor = [GPOToolsSecurityDescriptor]::Parse([byte[]]$self.Values['nTSecurityDescriptor'][0])

        # The creator (its owner, unless an approver owns it) and its groups of creators.
        $approvedOwners = Get-PSGPOApprovedOwnerSid -Workflow $workflow -DomainSid ($ownerSid -replace '-\d+$', '')
        $creator = if ($approvedOwners -notcontains $descriptor.Owner) { $descriptor.Owner }
        $creatorGroups = @()
        if ($creator) {
            $token = Get-PSGPOAccountGroupSid -Connection $connection -DomainDistinguishedName $domainDN -Sid $creator
            $creatorGroups = @($workflow.CreatorSids | Where-Object { $token -contains $_ })
        }
        if (-not $creatorGroups.Count) {
            # Created otherwise: the groups of creators the GPO gives rights to.
            $creatorGroups = @($workflow.CreatorSids | Where-Object { $sid = $_; @($descriptor.Dacl | Where-Object { $_.Sid -eq $sid }).Count })
        }
        $remove = @(@($creator) + @($workflow.CreatorSids) | Where-Object { $_ } | Select-Object -Unique)
        $edit = if ($CreatorRights -eq 'EditSettings') { $creatorGroups } else { @() }

        # The containers it holds first (User, Machine...), then the GPO.
        foreach ($entry in @($entries | Where-Object { $_.DistinguishedName -ne $Gpo.DistinguishedName } | Sort-Object { $_.DistinguishedName.Length } -Descending)) {
            if (-not $entry.Values['nTSecurityDescriptor']) { continue }
            $inner = [GPOToolsSecurityDescriptor]::Parse([byte[]]$entry.Values['nTSecurityDescriptor'][0])
            Set-PSGPODomainOwnerAndDacl -Connection $connection -DistinguishedName $entry.DistinguishedName -Name $entry.DistinguishedName `
                -Descriptor (ConvertTo-PSGPOApprovedDescriptor -Descriptor $inner -OwnerSid $ownerSid -RemoveSids $remove)
        }
        Set-PSGPODomainOwnerAndDacl -Connection $connection -DistinguishedName $Gpo.DistinguishedName -Name "the GPO '$($Gpo.DisplayName)'" `
            -Descriptor (ConvertTo-PSGPOApprovedDescriptor -Descriptor $descriptor -OwnerSid $ownerSid -RemoveSids $remove -EditSids $edit -ApplySid $ApplyToSid -Container)
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $Gpo.DistinguishedName
    } finally {
        $connection.Dispose()
    }
    Set-PSGPOGpoFolderAcl -Directory $Directory -Gpo $Gpo -Descriptor $descriptor -Owner
    Write-Verbose "GPO '$($Gpo.DisplayName)' approved: owned by $($workflow.ApprovedOwner), the creators $(if ($CreatorRights -eq 'EditSettings') { 'edit its settings' } else { 'read it' })."
}

# The SYSVOL folder of a GPO, every file and every folder in it, with the ACL derived from the
# directory ($Descriptor of its container), and with its owner (-Owner). Windows propagates the
# ACL of the folder to what it holds. Samba does not, and checks (samba-tool ntacl sysvolcheck)
# that each of them has the ACL of the folder, as samba-tool ntacl sysvolreset sets it: the
# console does the same. Samba only changes the POSIX ACL of a file for its owner: the ACL the
# approval writes is kept as the ACL of Windows (NT), the POSIX ACL stays as the creator set it.
function Set-PSGPOGpoFolderAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [switch]$Owner
    )

    $location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
    $folder = $Descriptor.ConvertToFileSystem()
    $folder.Owner = $Descriptor.Owner
    Set-PSGPOSysvolItemAcl -Directory $Directory -Share $location.Share -Path $location.Path -Descriptor $folder -Owner:$Owner -Dacl
    foreach ($item in @(Get-PSGPOSysvolTree -Directory $Directory -Share $location.Share -Path $location.Path)) {
        $path = "$($location.Path)\$($item.Path)"
        if (-not $IsWindows) { Set-PSGPOSysvolItemAcl -Directory $Directory -Share $location.Share -Path $path -Descriptor $folder -Owner:$Owner -Dacl }
        elseif ($Owner) { Set-PSGPOSysvolItemAcl -Directory $Directory -Share $location.Share -Path $path -Descriptor $folder -Owner }
    }
}

# The delegation of the creation of GPOs to the groups of creators, without Group Policy Creator
# Owners: what it needs, what is there, what is added (-Apply). One row per right: Target, Account,
# Right, State (Present, Added or Missing).
function Set-PSGPODomainWorkflowDelegation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [switch]$Apply
    )

    $setting = Get-PSGPOWorkflowSetting
    $domainDN = $Directory.Domain.DistinguishedName
    $policies = "CN=Policies,CN=System,$domainDN"
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $creators = @(Find-PSGPODomainAccount -Connection $connection -DomainDistinguishedName $domainDN -Name $setting.Creators)
        if (-not $creators.Count) { throw 'No group of creators in the configuration of the domain (Workflow.Creators).' }
        $null = Find-PSGPODomainAccount -Connection $connection -DomainDistinguishedName $domainDN -Name (@($setting.Approvers) + $setting.ApprovedOwner)

        # The directory: create groupPolicyContainer objects in CN=Policies.
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $policies
        $changed = $false
        foreach ($group in $creators) {
            $present = @($descriptor.Dacl | Where-Object { $_.IsKnown() -and $_.Type -eq [GPOToolsAce]::AccessAllowedObject -and $_.Sid -eq $group.Sid -and
                    ($_.Mask -band $script:PSGPOCreateChildMask) -and $_.ObjectType -eq $script:PSGPOGroupPolicyContainerClass }).Count
            $state = if ($present) { 'Present' } elseif ($Apply) { 'Added' } else { 'Missing' }
            if (-not $present -and $Apply) {
                $descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowedObject, 0, $script:PSGPOCreateChildMask, $group.Sid, $script:PSGPOGroupPolicyContainerClass))
                $changed = $true
            }
            [pscustomobject]@{ Target = $policies; Account = $group.Name; Right = 'Create groupPolicyContainer objects'; State = $state }
        }
        if ($changed) { Set-PSGPODomainDacl -Connection $connection -DistinguishedName $policies -Descriptor (Get-PSGPOExplicitDescriptor -Descriptor $descriptor) -Name $policies }
    } finally {
        $connection.Dispose()
    }

    # SYSVOL: create folders in Policies, CREATOR OWNER full control of what it creates.
    $path = "$($Directory.DomainName)\Policies"
    $folder = Get-PSGPOSysvolItemAcl -Directory $Directory -Share 'SYSVOL' -Path $path
    $changed = $false
    $needed = @(foreach ($group in $creators) {
            @{ Account = $group.Name; Sid = $group.Sid; Flags = 0; Mask = $script:PSGPOCreateFolderMask; Right = 'List, read and create folders (this folder only)' }
        }) + @(@{ Account = 'CREATOR OWNER'; Sid = [GPOToolsSecurityDescriptor]::CreatorOwner; Flags = 0x0B; Mask = $script:PSGPOFullFileMask; Right = 'Full control of the folders and files it creates' })
    foreach ($right in $needed) {
        $present = @($folder.Dacl | Where-Object { $_.IsKnown() -and $_.Type -eq [GPOToolsAce]::AccessAllowed -and $_.Sid -eq $right.Sid -and
                ($_.Mask -band $right.Mask) -eq $right.Mask -and ($_.Flags -band 0x0B) -eq $right.Flags }).Count
        $state = if ($present) { 'Present' } elseif ($Apply) { 'Added' } else { 'Missing' }
        if (-not $present -and $Apply) {
            $folder.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, [byte]$right.Flags, $right.Mask, $right.Sid, [guid]::Empty))
            $changed = $true
        }
        [pscustomobject]@{ Target = "\\$($Directory.Server)\SYSVOL\$path"; Account = $right.Account; Right = $right.Right; State = $state }
    }
    if ($changed) { Set-PSGPOSysvolItemAcl -Directory $Directory -Share 'SYSVOL' -Path $path -Descriptor $folder -Dacl }
}

# The group an approved GPO applies to: Name and Sid (Authenticated Users, or a group of the
# domain); in memory, its name.
function Resolve-PSGPOApplyTo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Name
    )

    $Name = $Name.Trim()
    if ($Name -in 'Authenticated Users', 'NT AUTHORITY\Authenticated Users', [GPOToolsSecurityDescriptor]::AuthenticatedUsers) {
        return [pscustomobject]@{ Name = 'Authenticated Users'; Sid = [GPOToolsSecurityDescriptor]::AuthenticatedUsers }
    }
    if ($Directory -isnot [GPOToolsLdapDirectory]) { return [pscustomobject]@{ Name = $Name; Sid = $Name } }
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        @(Find-PSGPODomainAccount -Connection $connection -DomainDistinguishedName $Directory.Domain.DistinguishedName -Name $Name)[0]
    } finally {
        $connection.Dispose()
    }
}

# Approves a GPO (GPOToolsDirectory.ApproveGpo), then backs it up with the approved label in
# $BackupPath: its approved version, to which it is compared from then on (Get-PSGPODrift).
function Invoke-PSGPOApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [ValidateSet('ReadOnly', 'EditSettings')] [string]$CreatorRights,
        [Parameter(Mandatory)] [pscustomobject]$ApplyTo,
        [Parameter(Mandatory)] [string]$BackupPath
    )

    $creator = $Gpo.Owner
    $Directory.ApproveGpo($Gpo, $CreatorRights, $ApplyTo.Sid, $ApplyTo.Name)
    $by = if ($Directory.Account) { $Directory.Account } else { [Environment]::UserName }
    $rights = if ($CreatorRights -eq 'EditSettings') { 'edit its settings' } else { 'read it' }
    $backup = $null
    $problem = $null
    try {
        $null = New-Item -ItemType Directory -Path $BackupPath -Force -ErrorAction Stop
        $backup = Save-PSGPOBackup -Directory $Directory -Gpo $Gpo -Path $BackupPath -Label (Get-PSGPOApprovedLabel) `
            -Comment "Approved by $by$(if ($creator) { ", created by $creator" }): the creators $rights; applied by $($ApplyTo.Name)."
    } catch {
        $problem = "It is approved, but not backed up: $($_.Exception.GetBaseException().Message)"
    }
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Approval'
        DisplayName = $Gpo.DisplayName
        Owner = $Gpo.Owner
        CreatedBy = $creator
        CreatorRights = $CreatorRights
        AppliedBy = $ApplyTo.Name
        Backup = if ($backup) { $backup.Path }
        Problem = $problem
    }
}
