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
# gPCFileSysPath (schemaIDGUID) and the right to write a property: the groups of creators that
# keep editing an approved GPO are denied writing it, or they would redirect the GPO to a folder
# they own (IsGpoRedirected).
$script:PSGPOFileSysPathAttribute = [guid]'f30e3bc1-9ff0-11d1-b603-0000f80367c1'
$script:PSGPOWritePropertyMask = [uint32]0x00000020
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
        [pscustomobject]@{ Name = $account; Sid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entry.Values['objectSid'][0]) }
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

    $entry = if (-not $Sid -and $Account -match '^[A-Za-z]+=.+,(?i:DC)=') {
        # A distinguished name: a "Who am I?" answer in the dn: form.
        @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $Account -Scope Base -Attribute 'objectSid') | Select-Object -First 1
    } else {
        $filter = if ($Sid) { "(objectSid=$(ConvertTo-PSGPOLdapBinaryFilter -Bytes ([GPOToolsSecurityDescriptor]::ConvertSidToBytes($Sid))))" }
            else { "(sAMAccountName=$(ConvertTo-PSGPOLdapFilterValue (($Account -split '\\')[-1])))" }
        @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $DomainDistinguishedName -Filter $filter -Attribute 'objectSid') | Select-Object -First 1
    }
    if (-not $entry) { return [string[]]@() }
    $sids = [System.Collections.Generic.List[string]]::new()
    $sids.Add((ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entry.Values['objectSid'][0])))
    $token = @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $entry.DistinguishedName -Scope Base -Attribute 'tokenGroups') | Select-Object -First 1
    foreach ($value in @($token.Values['tokenGroups'])) { if ($value) { $sids.Add((ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$value))) } }
    , [string[]]$sids
}

# What is wrong with the roles of the workflow, by their SIDs (the names of the configuration
# found in the domain): a group of every account (Everyone, Authenticated Users, Domain Users...)
# as approvers or creators, an account in both roles (it would approve its own GPOs: an approver
# creates GPOs approved at once), an owner of the approved GPOs that is neither an approver nor an
# administrator of the domain (it could change the permissions of every approved GPO).
function Test-PSGPOWorkflowRole {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Approvers,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Creators,
        [Parameter(Mandatory)] [object]$Owner,
        [Parameter(Mandatory)] [string]$DomainSid
    )

    # Everyone, Anonymous, Authenticated Users, Users, Guests; Domain Users, Domain Guests, Domain Computers.
    $everyone = @('S-1-1-0', 'S-1-5-7', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-32-546', "$DomainSid-513", "$DomainSid-514", "$DomainSid-515")
    foreach ($role in @(@{ Name = 'Approvers'; Accounts = $Approvers }, @{ Name = 'Creators'; Accounts = $Creators })) {
        foreach ($account in @($role.Accounts | Where-Object { $everyone -contains $_.Sid })) {
            "Workflow.$($role.Name) names $($account.Name), a group of every account."
        }
    }
    foreach ($account in @($Creators | Where-Object { @($Approvers.Sid) -contains $_.Sid })) {
        "$($account.Name) is in Workflow.Approvers and Workflow.Creators: an approver's GPOs are approved at once, so its creators would approve their own GPOs."
    }
    $admins = @("$DomainSid-512", "$DomainSid-519", 'S-1-5-32-544')
    if ($Owner -and @($Approvers.Sid) -notcontains $Owner.Sid -and $admins -notcontains $Owner.Sid) {
        "Workflow.ApprovedOwner ($($Owner.Name)) is neither a group of the approvers nor of the administrators of the domain: it would own, and could change, every approved GPO."
    }
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
# The domain delegates the creation of GPOs to groups that are not its administrators (Initialize-
# PSGPOWorkflow gives the creators the right to create groupPolicyContainer objects in
# CN=Policies): the approval workflow is deployed. Group Policy Creator Owners, which the domain
# gives this right, does not count. $false when the permissions of CN=Policies cannot be read.
function Test-PSGPODomainCreationDelegated {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DomainDistinguishedName
    )

    try {
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $Connection -DistinguishedName "CN=Policies,CN=System,$DomainDistinguishedName"
    } catch {
        Write-Verbose "The permissions of CN=Policies cannot be read: $($_.Exception.Message)"
        return $false
    }
    # Domain Admins, Enterprise Admins, Group Policy Creator Owners, Administrators, SYSTEM.
    $admins = '-512$', '-519$', '-520$', '^S-1-5-32-544$', '^S-1-5-18$'
    foreach ($ace in @($descriptor.Dacl)) {
        if (-not $ace.IsKnown() -or $ace.IsDeny() -or -not ($ace.Mask -band $script:PSGPOCreateChildMask)) { continue }
        if ($ace.IsObjectAce() -and $ace.ObjectType -ne [guid]::Empty -and $ace.ObjectType -ne $script:PSGPOGroupPolicyContainerClass) { continue }
        if (@($admins | Where-Object { $ace.Sid -match $_ }).Count) { continue }
        return $true
    }
    $false
}

# Why the approval workflow of the domain is unknown, for an account that is not an administrator
# of the domain; $null when it is known. The configuration of the domain is not used (it cannot be
# read, holds a wrong value, or needs a newer console): the workflow it sets is unknown. It is
# missing on the domain controller read, while the domain delegates the creation of GPOs (a domain
# controller of Samba, which does not replicate SYSVOL, without it): the workflow was deployed. In
# both cases the defaults would let a creator make GPOs that apply at once.
function Get-PSGPOUnknownWorkflowProblem {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory
    )

    if ($Directory.IsDomainAdministrator) { return $null }
    $state = $script:PSGPOConfigurationState
    if ($state.Problem) {
        return "the configuration of the domain $($state.Path) is not used ($("$($state.Problem)".TrimEnd('.'))), and the approval workflow it sets is unknown."
    }
    if (-not $state.Exists -and (Test-PSGPODomainCreationDelegated -Connection $Connection -DomainDistinguishedName $Directory.Domain.DistinguishedName)) {
        return "the domain delegates the creation of GPOs (approval workflow), but $($Directory.Server) has no configuration of the domain ($($state.Path)): copy it there (Samba does not replicate SYSVOL; on Windows, check the replication of SYSVOL)."
    }
    $null
}

# A workflow that cannot be read stops the creation of GPOs: a GPO of a creator would apply
# before its approval.
function Update-PSGPODomainWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory
    )

    $setting = Get-PSGPOWorkflowSetting
    $domainDN = $Directory.Domain.DistinguishedName
    if (-not $setting.Enabled) {
        # The workflow the domain sets may be unknown: the configuration is not used, or missing
        # here while the domain delegates the creation of GPOs.
        $unknown = Get-PSGPOUnknownWorkflowProblem -Connection $Connection -Directory $Directory
        if ($unknown) {
            $Directory.Workflow = [pscustomobject]@{ Enabled = $true; Problem = $unknown; IsApprover = $false; IsCreator = $false }
            $Directory.CanCreateGpo = $false
            Write-Warning "The approval workflow of $($Directory.DomainName) is unknown, no GPO can be created until it is fixed: $unknown"
            return
        }
        $Directory.Workflow = $null
        foreach ($gpo in $Directory.Gpos) { $gpo.ApprovalState = $null }
        return
    }
    try {
        $approvers = @(Find-PSGPODomainAccount -Connection $Connection -DomainDistinguishedName $domainDN -Name $setting.Approvers)
        $creators = @(Find-PSGPODomainAccount -Connection $Connection -DomainDistinguishedName $domainDN -Name $setting.Creators)
        $owner = @(Find-PSGPODomainAccount -Connection $Connection -DomainDistinguishedName $domainDN -Name $setting.ApprovedOwner)[0]
        # Read, not taken from a SID of the configuration: the owner may be a builtin group.
        $domain = @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $domainDN -Scope Base -Attribute 'objectSid') | Select-Object -First 1
        if (-not $domain -or -not $domain.Values['objectSid']) { throw "the SID of the domain $domainDN cannot be read." }
        $domainSid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$domain.Values['objectSid'][0])
        $roles = @(Test-PSGPOWorkflowRole -Approvers $approvers -Creators $creators -Owner $owner -DomainSid $domainSid)
        if ($roles.Count) { throw ($roles -join ' ') }
        # The role of the account is read in its groups: an account that is not found would be
        # neither a creator nor an approver, and the GPOs it creates would be approved at once.
        if (-not $Directory.Account -or $Directory.Account -eq 'Anonymous') { throw 'the server does not say which account the console is connected with (LDAP "Who am I?").' }
        # Not @(...): the function returns its array as one object.
        $token = Get-PSGPOAccountGroupSid -Connection $Connection -DomainDistinguishedName $domainDN -Account $Directory.Account
        if (-not $token.Count) { throw "the account $($Directory.Account) is not found in the domain: its groups cannot be read." }
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
        AccountCreatorSids = [string[]]@($creators | Where-Object { $token -contains $_.Sid } | ForEach-Object { $_.Sid })
        ApprovedOwner = $owner.Name
        ApprovedOwnerSid = $owner.Sid
        CreatorRights = $setting.CreatorRights
        DomainSid = $domainSid
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

# The ACE that denies writing the gPCFileSysPath of a GPO, as the approval writes it.
function Test-PSGPOFileSysPathDenyAce {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [GPOToolsAce]$Ace)

    $Ace.IsKnown() -and $Ace.Type -eq [GPOToolsAce]::AccessDeniedObject -and $Ace.ObjectType -eq $script:PSGPOFileSysPathAttribute -and
        $Ace.Mask -eq $script:PSGPOWritePropertyMask -and -not ($Ace.Flags -band [GPOToolsAce]::Inherited)
}

function Add-PSGPOFileSysPathDenyAce {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor, [Parameter(Mandatory)] [string]$Sid)

    $present = @($Descriptor.Dacl | Where-Object { $_.Sid -eq $Sid -and (Test-PSGPOFileSysPathDenyAce -Ace $_) }).Count
    if (-not $present) { $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDeniedObject, 0, $script:PSGPOWritePropertyMask, $Sid, $script:PSGPOFileSysPathAttribute)) }
}

function Add-PSGPOEditSettingsAce {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor, [Parameter(Mandatory)] [string]$Sid)

    $present = @($Descriptor.Dacl | Where-Object { $_.IsKnown() -and $_.Type -eq [GPOToolsAce]::AccessAllowed -and $_.Sid -eq $Sid -and
            -not ($_.Flags -band [GPOToolsAce]::Inherited) -and ($_.Mask -band $script:PSGPOEditSettingsMask) -eq $script:PSGPOEditSettingsMask }).Count
    if (-not $present) { $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, [GPOToolsAce]::ContainerInherit, $script:PSGPOEditSettingsMask, $Sid, [guid]::Empty)) }
}

# Accounts that only read an approved GPO: Authenticated Users (the computers must read every GPO,
# MS16-072) and ENTERPRISE DOMAIN CONTROLLERS.
$script:PSGPOReadOnlySids = @([GPOToolsSecurityDescriptor]::AuthenticatedUsers, 'S-1-5-9')

# The descriptor of an approved GPO, or of an object it holds ($Container: the GPO itself), owned
# by $OwnerSid. Its DACL is rebuilt from what an approved GPO may hold, not from what the pending
# GPO holds: its creator owned it, and could add any ACE outside the console. The explicit ACEs
# kept are the allow ACEs of $TrustedSids (the owners an approved GPO may have) and of CREATOR
# OWNER, and the read rights of Authenticated Users and of the domain controllers; every other
# explicit ACE is removed, and those of an account other than $RemoveSids (the creator and the
# creators) are added to $Unexpected, as SDDL. The inherited ACEs stay: the directory computes
# them from the parent. On the GPO, Authenticated Users read it, the groups $EditSids edit its
# settings, $ApplySid applies it and $DenySid is denied it.
function ConvertTo-PSGPOApprovedDescriptor {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [Parameter(Mandatory)] [string]$OwnerSid,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$TrustedSids,
        [AllowEmptyCollection()] [string[]]$RemoveSids = @(),
        [AllowEmptyCollection()] [string[]]$EditSids = @(),
        [string]$ApplySid,
        [string]$DenySid,
        [System.Collections.Generic.List[string]]$Unexpected,
        [switch]$Container
    )

    $approved = [GPOToolsSecurityDescriptor]::Parse($Descriptor.ToBytes())
    $approved.Owner = $OwnerSid
    if ($null -eq $approved.Dacl) { $approved.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new() }
    $trusted = @($TrustedSids) + @([GPOToolsSecurityDescriptor]::CreatorOwner)
    for ($i = $approved.Dacl.Count - 1; $i -ge 0; $i--) {
        $ace = $approved.Dacl[$i]
        if ($ace.Flags -band [GPOToolsAce]::Inherited) { continue }
        $keep = $ace.IsKnown() -and -not $ace.IsDeny() -and $trusted -contains $ace.Sid
        if (-not $keep -and $ace.IsKnown() -and -not $ace.IsDeny() -and -not $ace.IsObjectAce() -and $script:PSGPOReadOnlySids -contains $ace.Sid) {
            # Read, nothing more ("Apply Group Policy" is set below, as the approver chooses).
            $read = $ace.Mask -band ([GPOToolsSecurityDescriptor]::ReadMask -bor [GPOToolsSecurityDescriptor]::ControlAccess)
            if ($read -ne $ace.Mask -and $null -ne $Unexpected -and $RemoveSids -notcontains $ace.Sid) { $Unexpected.Add($ace.ToSddl()) }
            $ace.Mask = $read
            $keep = [bool]$read
        }
        if ($keep) { continue }
        if ($null -ne $Unexpected -and -not ($ace.IsKnown() -and $RemoveSids -contains $ace.Sid)) {
            $Unexpected.Add($(if ($ace.IsKnown()) { $ace.ToSddl() } else { "(an access control entry of type $($ace.Type))" }))
        }
        $approved.Dacl.RemoveAt($i)
    }
    if ($Container) {
        Remove-PSGPOApplyRight -Descriptor $approved
        $read = @($approved.Dacl | Where-Object { $_.IsKnown() -and -not $_.IsDeny() -and -not $_.IsObjectAce() -and $_.Sid -eq [GPOToolsSecurityDescriptor]::AuthenticatedUsers -and
                ($_.Mask -band [GPOToolsSecurityDescriptor]::ReadMask) -eq [GPOToolsSecurityDescriptor]::ReadMask }).Count
        if (-not $read) {
            $approved.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, [GPOToolsAce]::ContainerInherit, [GPOToolsSecurityDescriptor]::ReadMask, [GPOToolsSecurityDescriptor]::AuthenticatedUsers, [guid]::Empty))
        }
        # The groups of creators edit its settings, never its folder (gPCFileSysPath).
        foreach ($sid in $EditSids) {
            Add-PSGPOEditSettingsAce -Descriptor $approved -Sid $sid
            Add-PSGPOFileSysPathDenyAce -Descriptor $approved -Sid $sid
        }
        if ($ApplySid) {
            $inherit = [GPOToolsAce]::ContainerInherit
            # Authenticated Users read every GPO already.
            if ($ApplySid -ne [GPOToolsSecurityDescriptor]::AuthenticatedUsers) {
                $approved.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, $inherit, [GPOToolsSecurityDescriptor]::ReadMask, $ApplySid, [guid]::Empty))
            }
            $approved.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowedObject, $inherit, [GPOToolsSecurityDescriptor]::ControlAccess, $ApplySid, [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
        }
        if ($DenySid) {
            $approved.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDeniedObject, [GPOToolsAce]::ContainerInherit, [GPOToolsSecurityDescriptor]::ControlAccess, $DenySid, [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
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

# Approves a GPO of the domain (GPOToolsDirectory.ApproveGpo): its SYSVOL folder and everything in
# it, then the containers it holds, then its container, owned by the owner of the approved GPOs.
# The container of the GPO is written last: its owner is what makes it approved, so a GPO whose
# SYSVOL folder or inner containers cannot be written stays pending, and can be approved again.
# Returns the permissions removed that belonged to neither the creator nor the creators (SDDL):
# someone added them while the GPO was pending.
function Approve-PSGPODomainGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [ValidateSet('ReadOnly', 'EditSettings')] [string]$CreatorRights,
        [Parameter(Mandatory)] [string]$ApplyToSid,
        [string]$DenyToSid
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
        $approvedOwners = Get-PSGPOApprovedOwnerSid -Workflow $workflow -DomainSid $workflow.DomainSid
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
        $unexpected = [System.Collections.Generic.List[string]]::new()
        $approved = ConvertTo-PSGPOApprovedDescriptor -Descriptor $descriptor -OwnerSid $ownerSid -TrustedSids $approvedOwners -RemoveSids $remove `
            -EditSids $edit -ApplySid $ApplyToSid -DenySid $DenyToSid -Unexpected $unexpected -Container
        $inner = @(foreach ($entry in @($entries | Where-Object { $_.DistinguishedName -ne $Gpo.DistinguishedName } | Sort-Object { $_.DistinguishedName.Length } -Descending)) {
                if (-not $entry.Values['nTSecurityDescriptor']) { continue }
                [pscustomobject]@{
                    DistinguishedName = $entry.DistinguishedName
                    Descriptor = ConvertTo-PSGPOApprovedDescriptor -Descriptor ([GPOToolsSecurityDescriptor]::Parse([byte[]]$entry.Values['nTSecurityDescriptor'][0])) `
                        -OwnerSid $ownerSid -TrustedSids $approvedOwners -RemoveSids $remove -Unexpected $unexpected
                }
            })

        # SYSVOL first, with the ACL the approved GPO will have; the GPO stays pending if it fails.
        try {
            Set-PSGPOGpoFolderAcl -Directory $Directory -Gpo $Gpo -Descriptor $approved -Owner
        } catch {
            throw "The GPO '$($Gpo.DisplayName)' is not approved, its SYSVOL folder cannot be given to $($workflow.ApprovedOwner): $($_.Exception.Message) It is still pending; approve it again once fixed."
        }
        # What the approver reviewed, compared now that its creator cannot write the folder.
        if ($Gpo.ReviewStamp -and (Get-PSGPOReviewStamp -Directory $Directory -Gpo $Gpo) -ne $Gpo.ReviewStamp) {
            throw "The GPO '$($Gpo.DisplayName)' is not approved: it changed since it was reviewed (its files or its attributes). It is still pending, its SYSVOL folder given to $($workflow.ApprovedOwner): review it again, then approve it."
        }
        # The containers it holds (User, Machine...), then the GPO.
        try {
            foreach ($item in $inner) {
                Set-PSGPODomainOwnerAndDacl -Connection $connection -DistinguishedName $item.DistinguishedName -Name $item.DistinguishedName -Descriptor $item.Descriptor
            }
            Set-PSGPODomainOwnerAndDacl -Connection $connection -DistinguishedName $Gpo.DistinguishedName -Name "the GPO '$($Gpo.DisplayName)'" -Descriptor $approved
        } catch {
            throw "The GPO '$($Gpo.DisplayName)' is not approved: $($_.Exception.Message) It is still pending; approve it again once fixed."
        }
    } finally {
        $connection.Dispose()
    }
    foreach ($ace in $unexpected) { Write-Warning "GPO '$($Gpo.DisplayName)': a permission nobody gives a pending GPO was removed at its approval: $ace" }
    Write-Verbose "GPO '$($Gpo.DisplayName)' approved: owned by $($workflow.ApprovedOwner), the creators $(if ($CreatorRights -eq 'EditSettings') { 'edit its settings' } else { 'read it' })."
    , [string[]]$unexpected
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
    # Windows: what the folder holds only inherits its ACL, its explicit ACEs removed (the creator
    # could have added some to a file).
    $inherit = [GPOToolsSecurityDescriptor]::new()
    $inherit.Owner = $folder.Owner
    $inherit.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
    foreach ($item in @(Get-PSGPOSysvolTree -Directory $Directory -Share $location.Share -Path $location.Path)) {
        $path = "$($location.Path)\$($item.Path)"
        $child = if ($IsWindows) { $inherit } else { $folder }
        Set-PSGPOSysvolItemAcl -Directory $Directory -Share $location.Share -Path $path -Descriptor $child -Owner:$Owner -Dacl
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
    # The well-known accounts (Authenticated Users, SYSTEM...), by name, NT AUTHORITY\name or SID.
    $short = ($Name -split '\\')[-1]
    foreach ($known in [GPOToolsSecurityDescriptor]::WellKnownNames.GetEnumerator()) {
        if ($Name -eq $known.Key -or $short -eq $known.Value) { return [pscustomobject]@{ Name = $known.Value; Sid = $known.Key } }
    }
    if ($Directory -isnot [GPOToolsLdapDirectory]) { return [pscustomobject]@{ Name = $Name; Sid = $Name } }
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        @(Find-PSGPODomainAccount -Connection $connection -DomainDistinguishedName $Directory.Domain.DistinguishedName -Name $Name)[0]
    } finally {
        $connection.Dispose()
    }
}

# The content of a GPO as an approver reviews it, in one SHA-256 (hexadecimal): the attributes of
# its container that make it apply (version, status, client-side extensions, WMI filter, folder),
# read again from the domain, and every file of its SYSVOL folder (path and SHA-256 of its bytes).
# Its creator owns a pending GPO, and could change it between the review and the approval: the
# approval compares it again once the creator cannot write the folder anymore (Approve-PSGPODomainGpo).
function Get-PSGPOReviewStamp {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        # What the approver reviews, read once (Read-PSGPOReviewContent); read here when not given.
        $Content
    )

    if (-not $Content) { $Content = Read-PSGPOReviewContent -Directory $Directory -Gpo $Gpo }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Content.Attributes.Keys) { $lines.Add("$name=$($Content.Attributes[$name])") }
    foreach ($path in @($Content.Files.Keys | Sort-Object { "$_".ToUpperInvariant() })) {
        $lines.Add("$path=$([System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([byte[]]$Content.Files[$path])))")
    }
    [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($lines -join "`n")))
}

# What an approver reviews of a GPO, as the domain has it now: Attributes, those of its container
# that make it apply (read again from the domain), and Files, every file of its SYSVOL folder.
function Read-PSGPOReviewContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $names = 'versionNumber', 'flags', 'gPCMachineExtensionNames', 'gPCUserExtensionNames', 'gPCWQLFilter', 'gPCFileSysPath'
    $attributes = [ordered]@{}
    if ($Directory -is [GPOToolsLdapDirectory]) {
        $connection = New-PSGPODirectoryConnection -Directory $Directory
        try { $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Base -Attribute $names } finally { $connection.Dispose() }
        foreach ($name in $names) { $attributes[$name] = "$(Get-PSGPOLdapValue $entry $name)" }
    } else {
        $values = $Gpo.Version, $Gpo.Flags, $Gpo.MachineExtensionNames, $Gpo.UserExtensionNames, $Gpo.WmiFilterId, $Gpo.FileSysPath
        for ($i = 0; $i -lt $names.Count; $i++) { $attributes[$names[$i]] = "$($values[$i])" }
    }
    [pscustomobject]@{ Attributes = $attributes; Files = $Directory.ReadGpoFolder($Gpo) }
}

# What the console does not interpret in what an approver reviews (Read-PSGPOReviewContent): the
# rows of Get-PSGPOUninterpretedSetting, in English.
function Get-PSGPOReviewUninterpreted {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Content)

    $settings = Get-PSGPOFolderSetting -Files $Content.Files -MachineExtensionNames $Content.Attributes['gPCMachineExtensionNames'] -UserExtensionNames $Content.Attributes['gPCUserExtensionNames']
    $settings.Uninterpreted
}

# The security filtering groups a GPO already has (APPLY_<GPO> and DENY_<GPO>, the prefixes of the
# configuration), to propose them at its approval: Apply and Deny, each Name and Sid, or $null.
# A group an approver or an administrator of the domain does not own is not proposed, and Problem
# says why: a technician who can create groups may have made APPLY_<its GPO> before the approval,
# to choose where the GPO applies once approved (its members).
function Find-PSGPOFilteringGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $found = [ordered]@{ Apply = $null; Deny = $null; Problem = $null }
    $connection = if ($Directory -is [GPOToolsLdapDirectory]) { New-PSGPODirectoryConnection -Directory $Directory }
    try {
        foreach ($role in 'Apply', 'Deny') {
            $name = Get-PSGPOFilteringGroupName -Role $role -GpoName $Gpo.DisplayName
            if ($connection) {
                # Only a missing group is no group: any other error stops, rather than the GPO
                # being approved for Authenticated Users.
                $domainDN = $Directory.Domain.DistinguishedName
                $entry = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $domainDN -Filter "(sAMAccountName=$(ConvertTo-PSGPOLdapFilterValue $name))" `
                        -Attribute 'objectSid', 'nTSecurityDescriptor' -SecurityMasks Owner) | Select-Object -First 1
                if (-not $entry -or -not $entry.Values['objectSid']) { continue }
                $group = [pscustomobject]@{ Name = $name; Sid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entry.Values['objectSid'][0]) }
                $owner = if ($entry.Values['nTSecurityDescriptor']) { [GPOToolsSecurityDescriptor]::Parse([byte[]]$entry.Values['nTSecurityDescriptor'][0]).Owner }
                $trusted = if ($Directory.Workflow -and $Directory.Workflow.DomainSid) { Get-PSGPOApprovedOwnerSid -Workflow $Directory.Workflow -DomainSid $Directory.Workflow.DomainSid }
                if ($trusted -and $trusted -notcontains $owner) {
                    $ownerName = if ($owner) { (Resolve-PSGPODomainSid -Connection $connection -DomainDistinguishedName $domainDN -Sid $owner)[$owner] } else { 'nobody known' }
                    $text = Get-PSGPOText 'The group {0} exists, owned by {1}, not by an approver or an administrator of the domain: someone else may have made it to choose where the GPO applies. It is not proposed; check its members and its owner, or delete it.' $name $ownerName
                    $found.Problem = (@(@($found.Problem) + $text) | Where-Object { $_ }) -join ' '
                    continue
                }
                $found[$role] = $group
            } else {
                $group = @($Directory.Groups.Values | Where-Object Name -EQ $name)[0]
                if ($group) { $found[$role] = [pscustomobject]@{ Name = $group.Name; Sid = $(if ($group.Sid) { $group.Sid } else { $group.Name }) } }
            }
        }
    } finally {
        if ($connection) { $connection.Dispose() }
    }
    [pscustomobject]$found
}

# Approves a GPO (GPOToolsDirectory.ApproveGpo), then backs it up with the approved label in
# $BackupPath: its approved version, to which it is compared from then on (Get-PSGPODrift).
# -CreateFilteringGroups creates its groups APPLY_<GPO> and DENY_<GPO> first (in $GroupContainer,
# the configuration when empty), and the GPO applies to the first and is denied to the second; a
# GPO whose groups cannot be created is not approved.
function Invoke-PSGPOApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [ValidateSet('ReadOnly', 'EditSettings')] [string]$CreatorRights,
        [pscustomobject]$ApplyTo,
        [pscustomobject]$DenyTo,
        [switch]$CreateFilteringGroups,
        [string]$GroupContainer,
        [Parameter(Mandatory)] [string]$BackupPath,
        # What the approver reviewed (Get-PSGPOReviewStamp): the approval is refused if the GPO changed since.
        [string]$ReviewStamp
    )

    $created = @()
    if ($CreateFilteringGroups) {
        try {
            $created = @($Directory.NewApprovalGroups($Gpo, $GroupContainer))
        } catch {
            throw "The GPO '$($Gpo.DisplayName)' is not approved: its security filtering groups cannot be created ($($_.Exception.GetBaseException().Message))."
        }
        $ApplyTo = [pscustomobject]@{ Name = $created[0].Name; Sid = $created[0].Sid }
        $DenyTo = [pscustomobject]@{ Name = $created[1].Name; Sid = $created[1].Sid }
    }
    if (-not $ApplyTo) { throw 'The approved GPO applies to someone: give the group (or Authenticated Users).' }
    $creator = $Gpo.Owner
    $Gpo.RemovedAtApproval = @()
    $Gpo.ReviewStamp = $ReviewStamp
    try {
        $Directory.ApproveGpo($Gpo, $CreatorRights, $ApplyTo.Sid, $ApplyTo.Name, $(if ($DenyTo) { $DenyTo.Sid }), $(if ($DenyTo) { $DenyTo.Name }))
    } finally {
        $Gpo.ReviewStamp = $null
    }
    $by = if ($Directory.Account) { $Directory.Account } else { [Environment]::UserName }
    $rights = if ($CreatorRights -eq 'EditSettings') { 'edit its settings' } else { 'read it' }
    $backup = $null
    $problem = $null
    try {
        New-PSGPOFolder -Path $BackupPath
        $backup = Save-PSGPOBackup -Directory $Directory -Gpo $Gpo -Path $BackupPath -Label (Get-PSGPOApprovedLabel) `
            -Comment "Approved by $by$(if ($creator) { ", created by $creator" }): the creators $rights; applied by $($ApplyTo.Name)$(if ($DenyTo) { ", denied to $($DenyTo.Name)" }).$(if ($Gpo.RemovedAtApproval.Count) { " Permissions added while it was pending, removed: $($Gpo.RemovedAtApproval -join ' ')." })"
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
        DeniedTo = if ($DenyTo) { $DenyTo.Name }
        GroupsCreated = [string[]]@($created | ForEach-Object { $_.DistinguishedName })
        # Permissions someone added while it was pending (SDDL), removed by the approval
        RemovedPermissions = [string[]]@($Gpo.RemovedAtApproval)
        Backup = if ($backup) { $backup.Path }
        Problem = $problem
    }
}
