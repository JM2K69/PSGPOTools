<#
    Active Directory side of the console, as GPMC shows it: the domain and its OUs (scopes of
    management, SOM), the GPOs and the links between them.

    GPOToolsDirectory keeps the directory in memory: read from JSON (Import-PSGPODirectory), its
    changes stay in memory. GPOToolsLdapDirectory is read from a domain over LDAP
    (Get-PSGPODirectory, Windows AD or Samba AD) and writes its changes to the domain through
    the hidden Save* methods, which run before the in-memory change.

    gPLink (MS-GPOL 2.2.2): [LDAP://<GPO DN>;<options>]... with options bit 0 = link disabled and
    bit 1 = enforced. The last entry is link order 1 (highest precedence): GPMC and samba-tool gpo
    setlink put a new link, of lowest precedence, first.
#>

enum GPOToolsSomKind {
    Domain
    OrganizationalUnit
}

class GPOToolsGpo {
    [guid]$Id
    [string]$DisplayName
    [string]$DistinguishedName
    # gPCFileSysPath: the GPO folder in SYSVOL (\\<domain>\SysVol\<domain>\Policies\{GUID})
    [string]$FileSysPath
    # versionNumber: user version in the high word, computer version in the low word
    [int]$Version
    # flags: 1 = user settings disabled, 2 = computer settings disabled
    [int]$Flags
    # Security filtering, as GPMC lists it: who applies the GPO (Authenticated Users for a new
    # GPO) and who is denied it, by name; $null when it could not be read
    [string[]]$SecurityFiltering = @('Authenticated Users')
    [string[]]$DeniedTo = @()
    # The account of the console can edit the GPO (write of its group policy container)
    [bool]$CanEdit = $true
    # Last change of the GPO in the directory (whenChanged, UTC); $null when not read
    [Nullable[datetime]]$Modified
    # Client-side extensions of the GPO (gPCMachineExtensionNames, gPCUserExtensionNames)
    [string]$MachineExtensionNames
    [string]$UserExtensionNames
    # Owner of the GPO (its group policy container): SID and name; $null when not read
    [string]$OwnerSid
    [string]$Owner
    # Approval workflow (Workflow of the configuration): 'Pending' (created by a creator, it
    # applies to nobody until approved) or 'Approved'; $null without the workflow
    [string]$ApprovalState
    # The permissions its approval removed that neither its creator nor the creators had (SDDL):
    # someone added them while it was pending
    [string[]]$RemovedAtApproval = @()
    # The content the approver reviewed (Get-PSGPOReviewStamp), for its approval: refused when the
    # GPO changed since; $null when not given
    [string]$ReviewStamp
    # WMI filter of the GPO (gPCWQLFilter): the Id of a msWMI-Som object; $null without one
    [Nullable[guid]]$WmiFilterId

    # -band: -shr keeps the sign, a user version of 0x8000 or more would be negative.
    [int] GetUserVersion() { return ($this.Version -shr 16) -band 0xFFFF }
    [int] GetComputerVersion() { return $this.Version -band 0xFFFF }

    # A pending GPO someone gave "Apply Group Policy" back to: its creator owns it, and can change
    # its permissions outside the console. It applies before its approval.
    [bool] AppliesWhilePending() {
        return $this.ApprovalState -eq 'Pending' -and $this.SecurityFiltering.Count -gt 0
    }

    [string] GetStatus() {
        switch ($this.Flags -band 3) {
            1 { return 'User configuration settings disabled' }
            2 { return 'Computer configuration settings disabled' }
            3 { return 'All settings disabled' }
        }
        return 'Enabled'
    }

    [string] ToString() { return $this.DisplayName }
}

# A WMI filter of the domain (msWMI-Som in CN=SOM,CN=WMIPolicy,CN=System): the computers apply the
# GPOs linked to it only when each of its queries returns something.
class GPOToolsWmiFilter {
    [guid]$Id
    [string]$Name
    [string]$Description
    [string]$DistinguishedName
    # Its WQL queries: Namespace (root\CIMv2) and Query, as msWMI-Parm2 holds them
    [object[]]$Queries = @()
    # The account can change and delete it (allowedAttributesEffective holds msWMI-Parm2)
    [bool]$CanEdit = $true
    # Who created it and when, when it changed last (msWMI-Author, msWMI-CreationDate,
    # msWMI-ChangeDate: yyyyMMddHHmmss.ffffff-000, UTC), as a .mof export keeps them
    [string]$Author
    [string]$CreationDate
    [string]$ChangeDate

    # The date of a WMI filter (msWMI-CreationDate, msWMI-ChangeDate) now.
    static [string] GetDate() { return [datetime]::UtcNow.ToString('yyyyMMddHHmmss.ffffff-000', [cultureinfo]::InvariantCulture) }

    [string] GetQueryText() {
        return (@($this.Queries | ForEach-Object { "$($_.Namespace): $($_.Query)" }) -join '; ')
    }

    [string] ToString() { return $this.Name }
}

class GPOToolsGpoLink {
    [string]$GpoDistinguishedName
    # $null when the GPO is not in the directory (deleted GPO, GPO of another domain)
    [GPOToolsGpo]$Gpo
    [bool]$Enabled = $true
    [bool]$Enforced
    # Link order: 1 is the highest precedence
    [int]$Order

    [string] GetDisplayName() {
        if ($this.Gpo) { return $this.Gpo.DisplayName }
        return "GPO not found ($($this.GpoDistinguishedName))"
    }

    [string] GetStatus() {
        if ($this.Gpo) { return $this.Gpo.GetStatus() }
        return 'GPO not found'
    }

    # gPLink options of the link: bit 0 link disabled, bit 1 enforced.
    [int] GetOptions() {
        $Options = 0
        if (-not $this.Enabled) { $Options = $Options -bor 1 }
        if ($this.Enforced) { $Options = $Options -bor 2 }
        return $Options
    }

    # gPLink value of links: the highest link order first, link order 1 last.
    static [string] Format([GPOToolsGpoLink[]]$Links) {
        $Text = [System.Text.StringBuilder]::new()
        foreach ($Link in @($Links | Sort-Object Order -Descending)) {
            [void]$Text.AppendFormat('[LDAP://{0};{1}]', $Link.GpoDistinguishedName, $Link.GetOptions())
        }
        return $Text.ToString()
    }

    # Links of a gPLink value, by link order; the directory resolves their GPO.
    static [System.Collections.Generic.List[GPOToolsGpoLink]] Parse([string]$GpLink) {
        $Links = [System.Collections.Generic.List[GPOToolsGpoLink]]::new()
        if ([string]::IsNullOrWhiteSpace($GpLink)) { return $Links }
        $Found = [regex]::Matches($GpLink, '\[LDAP://([^;\]]+);(\d+)\]', 'IgnoreCase')
        for ($i = $Found.Count - 1; $i -ge 0; $i--) {
            $Options = [int]$Found[$i].Groups[2].Value
            $Link = [GPOToolsGpoLink]::new()
            $Link.GpoDistinguishedName = $Found[$i].Groups[1].Value
            $Link.Enabled = ($Options -band 1) -eq 0
            $Link.Enforced = ($Options -band 2) -eq 2
            $Link.Order = $Links.Count + 1
            $Links.Add($Link)
        }
        return $Links
    }
}

# Scope of management: the domain or an OU, where GPOs are linked.
class GPOToolsSom {
    [string]$Name
    [string]$DistinguishedName
    [GPOToolsSomKind]$Kind
    [bool]$BlockInheritance
    [System.Collections.Generic.List[GPOToolsGpoLink]]$Links
    [System.Collections.Generic.List[GPOToolsSom]]$Children
    [GPOToolsSom]$Parent
    # The account of the console can link GPOs here (write of gPLink), as the GPMC delegation
    # "Link GPOs"
    [bool]$CanLink = $true

    GPOToolsSom() {
        $this.Links = [System.Collections.Generic.List[GPOToolsGpoLink]]::new()
        $this.Children = [System.Collections.Generic.List[GPOToolsSom]]::new()
    }

    [string] ToString() { return $this.Name }
}

class GPOToolsDirectory {
    [string]$DomainName
    [GPOToolsSom]$Domain
    [System.Collections.Generic.List[GPOToolsGpo]]$Gpos
    # Where the directory comes from, shown by the window
    [string]$Source = 'in memory'
    # NewGpo and NewLink are refused while writing to the source is not implemented
    [bool]$IsReadOnly
    # Sample data shown because no domain was discovered (Show-GPOManagerAvalonia)
    [bool]$IsDemonstration
    # Container of the users and groups (wellKnownObjects of the domain); CN=Users when not read
    [string]$UsersContainer
    # Account the directory was read with (NetBIOS domain and user name); $null in memory
    [string]$Account
    # The account can create GPOs (groupPolicyContainer objects in CN=Policies)
    [bool]$CanCreateGpo = $true
    # The account can create WMI filters (msWMI-Som objects in CN=SOM,CN=WMIPolicy,CN=System)
    [bool]$CanCreateWmiFilter = $true
    # The account is an administrator of the domain (Domain Admins, Enterprise Admins,
    # Administrators): it changes the configuration of HGPM for the domain. In memory, the
    # directory is the one of its user.
    [bool]$IsDomainAdministrator = $true
    # The tier of the account in the central audit log (Audit.Path, Audit.Tiers) and backups
    # (Backup.Path, Tier 0 only): Tier0, Tier1, Tier2 or Unassigned; empty without them
    [string]$AuditTier = ''
    # WMI filters of the domain
    [System.Collections.Generic.List[GPOToolsWmiFilter]]$WmiFilters
    # Approval workflow of the domain (Update-PSGPODomainWorkflow): Enabled, IsApprover,
    # IsCreator, the SIDs and names of the groups, the owner of the approved GPOs; $null without it
    [pscustomobject]$Workflow

    GPOToolsDirectory([string]$DomainName) {
        if ([string]::IsNullOrWhiteSpace($DomainName)) { throw 'The domain name is required.' }
        $this.DomainName = $DomainName
        $this.Gpos = [System.Collections.Generic.List[GPOToolsGpo]]::new()
        $this.WmiFilters = [System.Collections.Generic.List[GPOToolsWmiFilter]]::new()
        $this.Domain = [GPOToolsSom]::new()
        $this.Domain.Name = $DomainName
        $this.Domain.DistinguishedName = (($DomainName.Split('.') | ForEach-Object { "DC=$_" }) -join ',')
        $this.Domain.Kind = [GPOToolsSomKind]::Domain
    }

    [GPOToolsGpo] FindGpo([string]$DisplayName) {
        foreach ($Gpo in $this.Gpos) {
            if ([string]::Equals($Gpo.DisplayName, $DisplayName, [System.StringComparison]::OrdinalIgnoreCase)) { return $Gpo }
        }
        return $null
    }

    [GPOToolsGpo] FindGpoByDistinguishedName([string]$DistinguishedName) {
        foreach ($Gpo in $this.Gpos) {
            if ([string]::Equals($Gpo.DistinguishedName, $DistinguishedName, [System.StringComparison]::OrdinalIgnoreCase)) { return $Gpo }
        }
        return $null
    }

    [GPOToolsSom] FindSom([string]$DistinguishedName) {
        $Stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        $Stack.Push($this.Domain)
        while ($Stack.Count) {
            $Som = $Stack.Pop()
            if ([string]::Equals($Som.DistinguishedName, $DistinguishedName, [System.StringComparison]::OrdinalIgnoreCase)) { return $Som }
            foreach ($Child in $Som.Children) { $Stack.Push($Child) }
        }
        return $null
    }

    # Parent DN: what follows the first comma that is not escaped.
    static [string] GetParentDistinguishedName([string]$DistinguishedName) {
        $Match = [regex]::Match($DistinguishedName, '(?<!\\),')
        if ($Match.Success) { return $DistinguishedName.Substring($Match.Index + 1) }
        return $null
    }

    [GPOToolsSom] AddOrganizationalUnit([GPOToolsSom]$ParentSom, [string]$Name) {
        $DistinguishedName = 'OU={0},{1}' -f ($Name -replace '([,\\#+<>;"=])', '\$1'), $ParentSom.DistinguishedName
        return $this.AddOrganizationalUnit($ParentSom, $Name, $DistinguishedName)
    }

    [GPOToolsSom] AddOrganizationalUnit([GPOToolsSom]$ParentSom, [string]$Name, [string]$DistinguishedName) {
        $Som = [GPOToolsSom]::new()
        $Som.Name = $Name
        $Som.DistinguishedName = $DistinguishedName
        $Som.Kind = [GPOToolsSomKind]::OrganizationalUnit
        $Som.Parent = $ParentSom
        $ParentSom.Children.Add($Som)
        return $Som
    }

    # Sets the links of a SOM from its gPLink, resolving their GPO in the directory.
    [void] SetLinks([GPOToolsSom]$Som, [string]$GpLink) {
        $Som.Links = [GPOToolsGpoLink]::Parse($GpLink)
        foreach ($Link in $Som.Links) { $Link.Gpo = $this.FindGpoByDistinguishedName($Link.GpoDistinguishedName) }
    }

    # The same, the GPOs found in $GpoByDistinguishedName (a hashtable, case-insensitive): reading
    # a domain, a search of the list for each link would be quadratic.
    [void] SetLinks([GPOToolsSom]$Som, [string]$GpLink, [hashtable]$GpoByDistinguishedName) {
        $Som.Links = [GPOToolsGpoLink]::Parse($GpLink)
        foreach ($Link in $Som.Links) { $Link.Gpo = $GpoByDistinguishedName[$Link.GpoDistinguishedName] }
    }

    # Adds a GPO read from a directory: unlike AddGpo, its name may be empty or already used. The
    # list is not sorted: SortGpos once every GPO is added (sorting at each one is quadratic).
    [GPOToolsGpo] AddExistingGpo([GPOToolsGpo]$Gpo) {
        if (-not $Gpo.DistinguishedName) {
            $Gpo.DistinguishedName = 'CN={{{0}}},CN=Policies,CN=System,{1}' -f $Gpo.Id.ToString().ToUpperInvariant(), $this.Domain.DistinguishedName
        }
        $this.Gpos.Add($Gpo)
        return $Gpo
    }

    # Takes everything $Read has (the domain read again, of the same type): what holds this
    # directory (the window, its handlers) sees the domain as it is now.
    [void] ReplaceWith([GPOToolsDirectory]$Read) {
        if ($Read.GetType() -ne $this.GetType()) { throw "The directory read again is a $($Read.GetType().Name), not a $($this.GetType().Name)." }
        foreach ($Property in $this.GetType().GetProperties([System.Reflection.BindingFlags]'Instance, Public')) {
            if ($Property.CanWrite) { $Property.SetValue($this, $Property.GetValue($Read)) }
        }
    }

    # The GPOs by name, as GPMC lists them.
    [void] SortGpos() {
        $Sorted = [System.Linq.Enumerable]::ToList([System.Linq.Enumerable]::OrderBy($this.Gpos, [Func[GPOToolsGpo, string]] { param($Gpo) "$($Gpo.DisplayName)" }, [System.StringComparer]::OrdinalIgnoreCase))
        $this.Gpos.Clear()
        $this.Gpos.AddRange($Sorted)
    }

    # Adds an existing GPO; $Id is generated when empty.
    [GPOToolsGpo] AddGpo([string]$DisplayName, [guid]$Id) {
        $Name = "$DisplayName".Trim()
        if (-not $Name) { throw 'The GPO name is required.' }
        if ($this.FindGpo($Name)) { throw "A GPO named '$Name' already exists in $($this.DomainName)." }
        $Gpo = [GPOToolsGpo]::new()
        $Gpo.Id = if ($Id -eq [guid]::Empty) { [guid]::NewGuid() } else { $Id }
        $Gpo.DisplayName = $Name
        $Gpo.DistinguishedName = 'CN={{{0}}},CN=Policies,CN=System,{1}' -f $Gpo.Id.ToString().ToUpperInvariant(), $this.Domain.DistinguishedName
        $Gpo.FileSysPath = $this.GetCanonicalFileSysPath($Gpo)
        $this.Gpos.Add($Gpo)
        $this.Gpos.Sort([System.Comparison[GPOToolsGpo]] { param($a, $b) [string]::Compare($a.DisplayName, $b.DisplayName, $true) })
        return $Gpo
    }

    # Creates a GPO, like GPMC "New GPO".
    [GPOToolsGpo] NewGpo([string]$DisplayName) {
        $this.AssertWritable()
        if (-not $this.CanCreateGpo) { throw "The account $($this.Account) cannot create GPOs in $($this.DomainName)." }
        $Gpo = $this.AddGpo($DisplayName, [guid]::Empty)
        try { $this.SaveNewGpo($Gpo) } catch { [void]$this.Gpos.Remove($Gpo); throw }
        # The approval workflow: a GPO of a creator applies to nobody until it is approved. If it
        # cannot be made so, it is deleted rather than left applying to everyone.
        if ($this.IsWorkflowCreator()) {
            try {
                $this.SavePendingGpo($Gpo)
                $Gpo.ApprovalState = 'Pending'
            } catch {
                $Reason = $_.Exception.GetBaseException().Message
                try { $this.SaveRemovedGpo($Gpo); [void]$this.Gpos.Remove($Gpo) } catch { throw "The GPO '$($Gpo.DisplayName)' is created but cannot wait for its approval ($Reason), and cannot be deleted: delete it, it applies to everyone. $($_.Exception.GetBaseException().Message)" }
                throw "The GPO '$($Gpo.DisplayName)' is not created: it cannot wait for its approval ($Reason)."
            }
        } elseif ($this.Workflow -and $this.Workflow.Enabled) {
            $Gpo.ApprovalState = 'Approved'
        }
        return $Gpo
    }

    # The folder of a GPO in SYSVOL, as the domain gives it: \\<domain>\SysVol\<domain>\Policies\{GUID}.
    [string] GetCanonicalFileSysPath([GPOToolsGpo]$Gpo) {
        return '\\{0}\SysVol\{0}\Policies\{{{1}}}' -f $this.DomainName, $Gpo.Id.ToString().ToUpperInvariant()
    }

    # A GPO whose gPCFileSysPath is not its folder in SYSVOL: whoever writes the GPO (its creator
    # owns it while it waits) can point it at another share or folder, which the computers then
    # read its settings from, and which an approver would give its permissions to. The console
    # neither reads nor writes such a GPO, nor approves it. The case is not checked (Windows and
    # Samba compare paths without it).
    [bool] IsGpoRedirected([GPOToolsGpo]$Gpo) {
        if ([string]::IsNullOrWhiteSpace($Gpo.FileSysPath)) { return $false }
        return -not [string]::Equals($Gpo.FileSysPath.TrimEnd('\'), $this.GetCanonicalFileSysPath($Gpo), [System.StringComparison]::OrdinalIgnoreCase)
    }

    # Why the console does not use a redirected GPO, empty when it is not.
    [string] GetRedirectedProblem([GPOToolsGpo]$Gpo) {
        if (-not $this.IsGpoRedirected($Gpo)) { return '' }
        return "The GPO '$($Gpo.DisplayName)' is redirected: its gPCFileSysPath is '$($Gpo.FileSysPath)', not its folder '$($this.GetCanonicalFileSysPath($Gpo))'. Someone who can write the GPO changed it, and the computers read its settings from there. The console neither reads, writes nor approves it: an administrator of the domain deletes it, or sets its gPCFileSysPath back."
    }

    # The account creates GPOs that wait for an approval: a creator of the workflow, not an approver.
    [bool] IsWorkflowCreator() {
        return $this.Workflow -and $this.Workflow.Enabled -and $this.Workflow.IsCreator -and -not $this.Workflow.IsApprover
    }

    # A GPO waiting for its approval, as the account follows it: every one for an approver (it
    # approves them) or any other account; only its own for a creator, the ones it edits, not the
    # ones of the other tiers.
    [bool] IsPendingFollowed([GPOToolsGpo]$Gpo) {
        if ($Gpo.ApprovalState -ne 'Pending') { return $false }
        return $Gpo.CanEdit -or -not $this.IsWorkflowCreator()
    }

    # Approves a GPO waiting for its approval: its owner becomes the owner of the approved GPOs,
    # in the directory and in SYSVOL; the creators keep reading it (ReadOnly) or editing its
    # settings (EditSettings); it applies to $ApplyToSid (with its name $ApplyToName).
    [void] ApproveGpo([GPOToolsGpo]$Gpo, [string]$CreatorRights, [string]$ApplyToSid, [string]$ApplyToName) {
        $this.ApproveGpo($Gpo, $CreatorRights, $ApplyToSid, $ApplyToName, $null, $null)
    }

    # The same, the GPO also denied to $DenyToSid (with its name $DenyToName).
    [void] ApproveGpo([GPOToolsGpo]$Gpo, [string]$CreatorRights, [string]$ApplyToSid, [string]$ApplyToName, [string]$DenyToSid, [string]$DenyToName) {
        $this.AssertWritable()
        if (-not ($this.Workflow -and $this.Workflow.Enabled)) { throw 'The approval workflow is not enabled for this domain (Workflow.Enabled).' }
        if (-not $this.Workflow.IsApprover) { throw "The account $($this.Account) is not an approver of the GPOs (Workflow.Approvers)." }
        if ($CreatorRights -notin 'ReadOnly', 'EditSettings') { throw "Unknown rights of the creators: '$CreatorRights' (ReadOnly or EditSettings)." }
        if (-not $ApplyToSid) { throw 'The approved GPO applies to someone: give the group (or Authenticated Users).' }
        $Redirected = $this.GetRedirectedProblem($Gpo)
        if ($Redirected) { throw "$Redirected It is not approved." }
        $this.SaveApprovedGpo($Gpo, $CreatorRights, $ApplyToSid, $DenyToSid)
        $Gpo.ApprovalState = 'Approved'
        $Gpo.OwnerSid = $this.Workflow.ApprovedOwnerSid
        $Gpo.Owner = $this.Workflow.ApprovedOwner
        $Gpo.SecurityFiltering = @($ApplyToName)
        # Not "= if (...)": the output of if unrolls an empty list into $null.
        $Gpo.DeniedTo = @()
        if ($DenyToSid) { $Gpo.DeniedTo = @($DenyToName) }
    }

    # The security filtering groups of a GPO waiting for its approval, created by an approver in
    # $Container (the configuration when empty): APPLY_<GPO> and DENY_<GPO>, without setting its
    # security filtering, which its approval sets. Returns the two groups (Name, DistinguishedName, Sid).
    [object[]] NewApprovalGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        $this.AssertWritable()
        if (-not ($this.Workflow -and $this.Workflow.Enabled -and $this.Workflow.IsApprover)) { throw "The account $($this.Account) is not an approver of the GPOs (Workflow.Approvers)." }
        # A path below the domain (OU=Groups,OU=Tier 1) is made a distinguished name.
        if ([string]::IsNullOrWhiteSpace($Container)) { $Container = (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups.Container }
        return $this.SaveApprovalGroups($Gpo, (Resolve-PSGPOGroupContainer -Directory $this -Container $Container))
    }

    # Configuration of HGPM for the domain (Use-PSGPODomainConfiguration): Configuration.psd1
    # in SYSVOL\<domain>\PSGPOTools; its bytes, $null when the domain has none.
    [byte[]] ReadConfigurationFile() {
        return $this.LoadConfigurationFile()
    }

    # Writes the configuration of the domain; $null or no byte removes it.
    [void] WriteConfigurationFile([byte[]]$Bytes) {
        $this.AssertWritable()
        $this.SaveConfigurationFile($Bytes)
    }

    # Where the configuration of the domain is, as shown to the user.
    [string] GetConfigurationPath() {
        return "SYSVOL\$($this.DomainName)\PSGPOTools\Configuration.psd1 ($($this.Source))"
    }

    # The Default Domain Policy and the Default Domain Controllers Policy: never deleted.
    static [guid[]] $DefaultGpoIds = @([guid]'31B2F340-016D-11D2-945F-00C04FB984F9', [guid]'6AC1786C-016F-11D2-945F-00C04FB984F9')

    # Deletes a GPO, like GPMC "Delete": its links in the domain first (refused when the account
    # cannot delete one of them), then the GPO, its container and its folder in SYSVOL.
    [void] RemoveGpo([GPOToolsGpo]$Gpo) {
        $this.AssertWritable()
        if (-not $this.Gpos.Contains($Gpo)) { throw "The GPO '$($Gpo.DisplayName)' is not in $($this.DomainName)." }
        if ([GPOToolsDirectory]::DefaultGpoIds -contains $Gpo.Id) {
            throw "The GPO '$($Gpo.DisplayName)' is a default GPO of the domain: it is not deleted (change its settings instead)."
        }
        if (-not $Gpo.CanEdit) { throw "The account $($this.Account) cannot delete the GPO '$($Gpo.DisplayName)'." }
        $Links = @($this.GetLinksOf($Gpo))
        $Refused = @($Links | Where-Object { -not $_.Som.CanLink } | ForEach-Object { $_.Som.Name })
        if ($Refused.Count) {
            throw "The account $($this.Account) cannot delete the links of the GPO '$($Gpo.DisplayName)' to $($Refused -join ', '): the GPO is not deleted."
        }
        foreach ($Pair in $Links) { $this.RemoveLink($Pair.Som, $Pair.Link) }
        $this.SaveRemovedGpo($Gpo)
        [void]$this.Gpos.Remove($Gpo)
    }

    # Rights of the account, as the delegations of the domain give them (RBAC): a technician
    # changes the OUs where it links GPOs and the GPOs it edits; it reads the others.
    [bool] IsLimited() {
        if (-not $this.CanCreateGpo) { return $true }
        foreach ($Gpo in $this.Gpos) { if (-not $Gpo.CanEdit) { return $true } }
        $Stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        $Stack.Push($this.Domain)
        while ($Stack.Count) {
            $Som = $Stack.Pop()
            if (-not $Som.CanLink) { return $true }
            foreach ($Child in $Som.Children) { $Stack.Push($Child) }
        }
        return $false
    }

    # The account manages something: it links GPOs somewhere, edits or creates GPOs, creates or
    # changes WMI filters. Without it, the console only reads.
    [bool] HasDelegation() {
        if ($this.CanCreateGpo -or $this.CanCreateWmiFilter) { return $true }
        foreach ($Gpo in $this.Gpos) { if ($Gpo.CanEdit) { return $true } }
        foreach ($Filter in $this.WmiFilters) { if ($Filter.CanEdit) { return $true } }
        $Stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        $Stack.Push($this.Domain)
        while ($Stack.Count) {
            $Som = $Stack.Pop()
            if ($Som.CanLink) { return $true }
            foreach ($Child in $Som.Children) { $Stack.Push($Child) }
        }
        return $false
    }

    # A SOM the account manages, or the path to one.
    [bool] IsSomVisible([GPOToolsSom]$Som) {
        if ($Som.CanLink) { return $true }
        foreach ($Child in $Som.Children) { if ($this.IsSomVisible($Child)) { return $true } }
        return $false
    }

    # A GPO the account edits, or linked to a SOM it manages.
    [bool] IsGpoVisible([GPOToolsGpo]$Gpo) {
        if ($Gpo.CanEdit) { return $true }
        foreach ($Pair in $this.GetLinksOf($Gpo)) { if ($Pair.Som.CanLink) { return $true } }
        return $false
    }

    # The GPOs IsGpoVisible shows, in their order, in one pass over the tree: IsGpoVisible for
    # each GPO would walk the whole tree for each one.
    [GPOToolsGpo[]] GetVisibleGpos() {
        $Linked = [System.Collections.Generic.HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
        $Stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        $Stack.Push($this.Domain)
        while ($Stack.Count) {
            $Som = $Stack.Pop()
            if ($Som.CanLink) { foreach ($Link in $Som.Links) { if ($Link.Gpo) { [void]$Linked.Add($Link.Gpo) } } }
            foreach ($Child in $Som.Children) { $Stack.Push($Child) }
        }
        $Visible = [System.Collections.Generic.List[GPOToolsGpo]]::new()
        foreach ($Gpo in $this.Gpos) { if ($Gpo.CanEdit -or $Linked.Contains($Gpo)) { $Visible.Add($Gpo) } }
        return $Visible.ToArray()
    }

    # Links a GPO to a SOM with the lowest precedence (the last link order), like GPMC.
    [GPOToolsGpoLink] NewLink([GPOToolsSom]$Som, [GPOToolsGpo]$Gpo) {
        $this.AssertWritable()
        $this.AssertCanLink($Som)
        foreach ($Existing in $Som.Links) {
            if ([object]::ReferenceEquals($Existing.Gpo, $Gpo)) {
                throw "The GPO '$($Gpo.DisplayName)' is already linked to $($Som.Name)."
            }
        }
        $Link = [GPOToolsGpoLink]::new()
        $Link.GpoDistinguishedName = $Gpo.DistinguishedName
        $Link.Gpo = $Gpo
        $Link.Order = $Som.Links.Count + 1
        $Som.Links.Add($Link)
        try { $this.SaveNewLink($Som, $Link) } catch { [void]$Som.Links.Remove($Link); throw }
        return $Link
    }

    # GPO status, like GPMC: 0 enabled, 1 user configuration settings disabled, 2 computer
    # configuration settings disabled, 3 all settings disabled.
    [void] SetGpoStatus([GPOToolsGpo]$Gpo, [int]$Flags) {
        $this.AssertWritable()
        if ($Flags -lt 0 -or $Flags -gt 3) { throw "Unknown GPO status flags: $Flags (0 to 3)." }
        if (-not $Gpo.CanEdit) { throw "The account $($this.Account) cannot edit the GPO '$($Gpo.DisplayName)'." }
        $this.SaveGpoStatus($Gpo, $Flags)
        $Gpo.Flags = $Flags
    }

    # Renames a GPO, as GPMC "Rename": its display name only. Its GUID, so its folder in SYSVOL,
    # its links, its backups and its security filtering groups do not change.
    [void] RenameGpo([GPOToolsGpo]$Gpo, [string]$DisplayName) {
        $this.AssertWritable()
        if (-not $this.Gpos.Contains($Gpo)) { throw "The GPO '$($Gpo.DisplayName)' is not in $($this.DomainName)." }
        if (-not $Gpo.CanEdit) { throw "The account $($this.Account) cannot rename the GPO '$($Gpo.DisplayName)'." }
        $Name = "$DisplayName".Trim()
        if (-not $Name) { throw 'The GPO name is required.' }
        if ($Name -ceq $Gpo.DisplayName) { return }
        $Other = $this.FindGpo($Name)
        if ($Other -and $Other -ne $Gpo) { throw "A GPO named '$Name' already exists in $($this.DomainName)." }
        $this.SaveRenamedGpo($Gpo, $Name)
        $Gpo.DisplayName = $Name
        $this.SortGpos()
    }

    # Security filtering groups of a GPO, created in $Container: APPLY_<GPO>, whose members alone
    # apply it, and DENY_<GPO>, whose members never apply it. Returns the two groups (Name,
    # DistinguishedName, Sid).
    [object[]] NewFilteringGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        $this.AssertWritable()
        # It would apply to the members of the group before its approval.
        if ($Gpo.ApprovalState -eq 'Pending') { throw "The GPO '$($Gpo.DisplayName)' waits for its approval: its security filtering is set when it is approved." }
        # By default where the configuration says, else the users container.
        if ([string]::IsNullOrWhiteSpace($Container)) {
            $Container = Resolve-PSGPOGroupContainer -Directory $this -Container (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups.Container
        }
        $Created = $this.SaveFilteringGroups($Gpo, $Container)
        $Gpo.SecurityFiltering = @($Created[0].Name)
        $Gpo.DeniedTo = @($Created[1].Name)
        return $Created
    }

    # The WMI filter of a GPO; $null without one, or when it is not in the domain anymore.
    [GPOToolsWmiFilter] GetWmiFilter([GPOToolsGpo]$Gpo) {
        if ($null -eq $Gpo.WmiFilterId) { return $null }
        foreach ($Filter in $this.WmiFilters) { if ($Filter.Id -eq $Gpo.WmiFilterId) { return $Filter } }
        return $null
    }

    # A WMI filter by name (case-insensitive) or Id.
    [GPOToolsWmiFilter] FindWmiFilter([string]$NameOrId) {
        $Id = [guid]::Empty
        $IsId = [guid]::TryParse($NameOrId.Trim('{', '}', ' '), [ref]$Id)
        foreach ($Filter in $this.WmiFilters) {
            if (($IsId -and $Filter.Id -eq $Id) -or [string]::Equals($Filter.Name, $NameOrId, [System.StringComparison]::OrdinalIgnoreCase)) { return $Filter }
        }
        return $null
    }

    # Links a GPO to a WMI filter ($null: none), as the WMI Filtering of the Scope tab of GPMC.
    [void] SetWmiFilter([GPOToolsGpo]$Gpo, [GPOToolsWmiFilter]$Filter) {
        $this.AssertWritable()
        if (-not $Gpo.CanEdit) { throw "The account $($this.Account) cannot edit the GPO '$($Gpo.DisplayName)'." }
        if ($Filter -and -not $this.WmiFilters.Contains($Filter)) { throw "The WMI filter '$($Filter.Name)' is not a filter of $($this.DomainName)." }
        $this.SaveWmiFilter($Gpo, $Filter)
        $Gpo.WmiFilterId = if ($Filter) { $Filter.Id } else { $null }
    }

    # Permissions of a GPO, as the Delegation tab of GPMC (PSGPOPermission.ps1): one row per account,
    # Sid, Name, Permission (GpoRead, GpoApply, GpoEdit, GpoEditDeleteModifySecurity, GpoCustom),
    # Inherited, Applies, Denied.
    [object[]] GetGpoPermissions([GPOToolsGpo]$Gpo) {
        $Rows = @(Get-PSGPOPermissionFromDescriptor -Descriptor $this.LoadGpoDescriptor($Gpo))
        $Names = $this.ResolveSidNames([string[]]@($Rows | ForEach-Object Sid))
        foreach ($Row in $Rows) { $Row | Add-Member -NotePropertyName Name -NotePropertyValue $Names[$Row.Sid] -Force }
        return $Rows
    }

    # Gives an account ($Sid) one level of GPMC on a GPO, None removing it, as the Delegation tab.
    [void] SetGpoPermission([GPOToolsGpo]$Gpo, [string]$Sid, [string]$Permission) {
        $Levels = 'GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity', 'None'
        if ($Levels -notcontains $Permission) { throw "Unknown permission '$Permission': $($Levels -join ', ')." }
        $this.AssertCanChangePermissions($Gpo)
        $this.UpdateSecurityFiltering($Gpo, $this.SaveGpoPermissions($Gpo, 'Permission', $Sid, $Permission))
    }

    # Adds an account to the security filtering of a GPO ($Apply), or removes it, as the Scope tab.
    [void] SetGpoSecurityFiltering([GPOToolsGpo]$Gpo, [string]$Sid, [bool]$Apply) {
        $this.AssertCanChangePermissions($Gpo)
        $this.UpdateSecurityFiltering($Gpo, $this.SaveGpoPermissions($Gpo, 'Filtering', $Sid, "$Apply"))
    }

    # Names of SIDs, as the directory knows them; a SID it does not know keeps its string form.
    [hashtable] ResolveSidNames([string[]]$Sids) {
        $Names = @{}
        foreach ($Sid in @($Sids)) {
            $Names[$Sid] = if ([GPOToolsSecurityDescriptor]::WellKnownNames.ContainsKey($Sid)) { [GPOToolsSecurityDescriptor]::WellKnownNames[$Sid] } else { $Sid }
        }
        return $Names
    }

    hidden [void] AssertCanChangePermissions([GPOToolsGpo]$Gpo) {
        $this.AssertWritable()
        if (-not $Gpo.CanEdit) { throw "The account $($this.Account) cannot edit the GPO '$($Gpo.DisplayName)'." }
        # Its permissions are rebuilt when it is approved: a change now would be lost, or would make it apply.
        if ($Gpo.ApprovalState -eq 'Pending') { throw "The GPO '$($Gpo.DisplayName)' waits for its approval: its permissions are set when it is approved." }
    }

    # The security filtering of the GPO, from the descriptor written.
    hidden [void] UpdateSecurityFiltering([GPOToolsGpo]$Gpo, [GPOToolsSecurityDescriptor]$Descriptor) {
        $Filtering = $Descriptor.GetSecurityFiltering()
        $Names = $this.ResolveSidNames([string[]]@(@($Filtering.Apply) + @($Filtering.Deny)))
        $Gpo.SecurityFiltering = @($Filtering.Apply | ForEach-Object { $Names[$_] })
        $Gpo.DeniedTo = @($Filtering.Deny | ForEach-Object { $Names[$_] })
    }

    # Creates a WMI filter: its queries are WQL queries of a namespace (root\CIMv2).
    [GPOToolsWmiFilter] NewWmiFilter([string]$Name, [string]$Description, [object[]]$Queries) {
        $this.AssertWritable()
        if (-not $this.CanCreateWmiFilter) { throw "The account $($this.Account) cannot create WMI filters in $($this.DomainName)." }
        $Name = "$Name".Trim()
        if (-not $Name) { throw 'The name of the WMI filter is required.' }
        if ($this.FindWmiFilter($Name)) { throw "A WMI filter named '$Name' already exists in $($this.DomainName)." }
        if (-not @($Queries).Count) { throw 'A WMI filter has at least one query.' }
        $Filter = [GPOToolsWmiFilter]::new()
        $Filter.Id = [guid]::NewGuid()
        $Filter.Name = $Name
        $Filter.Description = $Description
        $Filter.Queries = @($Queries | ForEach-Object { [pscustomobject]@{ Namespace = $(if ($_.Namespace) { $_.Namespace } else { 'root\CIMv2' }); Query = "$($_.Query)" } })
        $Filter.DistinguishedName = 'CN={{{0}}},CN=SOM,CN=WMIPolicy,CN=System,{1}' -f $Filter.Id.ToString().ToUpperInvariant(), $this.Domain.DistinguishedName
        $Filter.Author = if ($this.Account) { $this.Account } else { [Environment]::UserName }
        $Filter.CreationDate = [GPOToolsWmiFilter]::GetDate()
        $Filter.ChangeDate = $Filter.CreationDate
        $this.SaveNewWmiFilter($Filter)
        $this.WmiFilters.Add($Filter)
        # By name, as the domain gives them.
        $this.WmiFilters.Sort([System.Comparison[GPOToolsWmiFilter]] { param($a, $b) [string]::Compare($a.Name, $b.Name, $true) })
        return $Filter
    }

    # Changes the name, description and queries of a WMI filter, as GPMC edits a filter: the GPOs
    # linked to it keep it (its Id does not change) and apply with its new queries.
    [void] EditWmiFilter([GPOToolsWmiFilter]$Filter, [string]$Name, [string]$Description, [object[]]$Queries) {
        $this.AssertWritable()
        if (-not $this.WmiFilters.Contains($Filter)) { throw "The WMI filter '$($Filter.Name)' is not a filter of $($this.DomainName)." }
        if (-not $Filter.CanEdit) { throw "The account $($this.Account) cannot change the WMI filter '$($Filter.Name)'." }
        $Name = "$Name".Trim()
        if (-not $Name) { throw 'The name of the WMI filter is required.' }
        $Other = $this.FindWmiFilter($Name)
        if ($Other -and $Other -ne $Filter) { throw "A WMI filter named '$Name' already exists in $($this.DomainName)." }
        if (-not @($Queries).Count) { throw 'A WMI filter has at least one query.' }
        $Changed = [GPOToolsWmiFilter]::new()
        $Changed.Id = $Filter.Id
        $Changed.DistinguishedName = $Filter.DistinguishedName
        $Changed.Name = $Name
        $Changed.Description = "$Description".Trim()
        $Changed.Queries = @($Queries | ForEach-Object { [pscustomobject]@{ Namespace = $(if ($_.Namespace) { "$($_.Namespace)".Trim() } else { 'root\CIMv2' }); Query = "$($_.Query)".Trim() } })
        if ($Changed.Name -ceq $Filter.Name -and $Changed.Description -ceq "$($Filter.Description)" -and $Changed.GetQueryText() -ceq $Filter.GetQueryText()) { return }
        $Changed.ChangeDate = [GPOToolsWmiFilter]::GetDate()
        $this.SaveEditedWmiFilter($Filter, $Changed)
        $Filter.ChangeDate = $Changed.ChangeDate
        $Filter.Name = $Changed.Name
        $Filter.Description = $Changed.Description
        $Filter.Queries = $Changed.Queries
        $this.WmiFilters.Sort([System.Comparison[GPOToolsWmiFilter]] { param($a, $b) [string]::Compare($a.Name, $b.Name, $true) })
    }

    # The container of the WMI filters of the domain.
    [string] GetWmiFilterContainer() { return "CN=SOM,CN=WMIPolicy,CN=System,$($this.Domain.DistinguishedName)" }

    # Delegation of the WMI filters, as the Delegation tabs of GPMC (PSGPOWmiFilterPermission.ps1):
    # one row for each account, Sid, Name, Permission, Inherited, Explicit. A filter: who changes
    # it (WmiEdit, WmiFullControl); $null: the WMI Filters container, who creates filters
    # (WmiCreate, WmiFullControl).
    [object[]] GetWmiFilterPermissions([GPOToolsWmiFilter]$Filter) {
        $Rows = @(Get-PSGPOWmiFilterPermissionFromDescriptor -Descriptor $this.LoadWmiFilterDescriptor($Filter) -Container:($null -eq $Filter))
        $Names = $this.ResolveSidNames([string[]]@($Rows | ForEach-Object Sid))
        foreach ($Row in $Rows) { $Row | Add-Member -NotePropertyName Name -NotePropertyValue $Names[$Row.Sid] -Force }
        return $Rows
    }

    # Gives an account ($Sid) one level on a filter, or on the container ($null), None removing it.
    [void] SetWmiFilterPermission([GPOToolsWmiFilter]$Filter, [string]$Sid, [string]$Permission) {
        $this.AssertWritable()
        if ($Filter) {
            if (-not $this.WmiFilters.Contains($Filter)) { throw "The WMI filter '$($Filter.Name)' is not a filter of $($this.DomainName)." }
            if (-not $Filter.CanEdit) { throw "The account $($this.Account) cannot change the permissions of the WMI filter '$($Filter.Name)'." }
        }
        $this.SaveWmiFilterPermission($Filter, $Sid, $Permission)
    }

    # Deletes a WMI filter no GPO is linked to, as GPMC does.
    [void] RemoveWmiFilter([GPOToolsWmiFilter]$Filter) {
        $this.AssertWritable()
        if (-not $Filter.CanEdit) { throw "The account $($this.Account) cannot delete the WMI filter '$($Filter.Name)'." }
        $Linked = @($this.Gpos | Where-Object { $_.WmiFilterId -eq $Filter.Id } | ForEach-Object DisplayName)
        if ($Linked.Count) { throw "The WMI filter '$($Filter.Name)' is used by $($Linked -join ', '): it is not deleted." }
        $this.SaveRemovedWmiFilter($Filter)
        [void]$this.WmiFilters.Remove($Filter)
    }

    # Enables or disables a link, enforces it or not, like the Link Enabled and Enforced items of
    # GPMC.
    [void] SetLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link, [bool]$Enabled, [bool]$Enforced) {
        $this.AssertWritable()
        $this.AssertCanLink($Som)
        if (-not $Som.Links.Contains($Link)) { throw "This link is not a link of $($Som.Name) anymore." }
        # Only what changes: another console may have changed the other option meanwhile.
        [Nullable[bool]]$NewEnabled = $null
        [Nullable[bool]]$NewEnforced = $null
        if ($Enabled -ne $Link.Enabled) { $NewEnabled = $Enabled }
        if ($Enforced -ne $Link.Enforced) { $NewEnforced = $Enforced }
        if ($null -eq $NewEnabled -and $null -eq $NewEnforced) { return }
        $this.SaveLink($Som, $Link, $NewEnabled, $NewEnforced, 0)
        if ($null -ne $NewEnabled) { $Link.Enabled = $Enabled }
        if ($null -ne $NewEnforced) { $Link.Enforced = $Enforced }
    }

    # Moves a link to the link order $Order (1 is the highest precedence), the others following
    # in their order, like the arrows of the Linked Group Policy Objects tab of GPMC.
    [void] MoveLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link, [int]$Order) {
        $this.AssertWritable()
        $this.AssertCanLink($Som)
        if (-not $Som.Links.Contains($Link)) { throw "This link is not a link of $($Som.Name) anymore." }
        if ($Order -lt 1 -or $Order -gt $Som.Links.Count) { throw "Link order ${Order}: $($Som.Name) has $($Som.Links.Count) link$(if ($Som.Links.Count -ne 1) { 's' }) (1 to $($Som.Links.Count))." }
        $this.SaveLink($Som, $Link, $null, $null, $Order)
        # As the domain has them: the same order whether the links were read again or not.
        $Others = @($Som.Links | Where-Object { -not [object]::ReferenceEquals($_, $Link) } | Sort-Object Order)
        $Position = 1
        foreach ($Other in $Others) {
            if ($Position -eq $Order) { $Position++ }
            $Other.Order = $Position++
        }
        $Link.Order = $Order
    }

    # Blocks the inheritance of a SOM or not, like GPMC "Block Inheritance": the GPOs linked to its
    # parents no longer apply there, but for the enforced links.
    [void] SetBlockInheritance([GPOToolsSom]$Som, [bool]$Blocked) {
        $this.AssertWritable()
        $this.AssertCanLink($Som)
        $this.SaveBlockInheritance($Som, $Blocked)
        $Som.BlockInheritance = $Blocked
    }

    # Deletes a link of a SOM, like GPMC "Delete" on a link: the GPO itself is kept, the links
    # after it move up one link order.
    [void] RemoveLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {
        $this.AssertWritable()
        $this.AssertCanLink($Som)
        if (-not $Som.Links.Contains($Link)) { throw "This link is not a link of $($Som.Name) anymore." }
        $this.SaveRemovedLink($Som, $Link)
        if ($Som.Links.Contains($Link)) {
            [void]$Som.Links.Remove($Link)
            $Order = 1
            foreach ($Remaining in @($Som.Links | Sort-Object Order)) { $Remaining.Order = $Order++ }
        }
    }

    [string] GetUsersContainer() {
        if ($this.UsersContainer) { return $this.UsersContainer }
        return "CN=Users,$($this.Domain.DistinguishedName)"
    }

    # Where a GPO is linked, as (Som, Link) pairs.
    [object[]] GetLinksOf([GPOToolsGpo]$Gpo) {
        $Found = [System.Collections.Generic.List[object]]::new()
        $Stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        $Stack.Push($this.Domain)
        while ($Stack.Count) {
            $Som = $Stack.Pop()
            foreach ($Link in $Som.Links) {
                if ([object]::ReferenceEquals($Link.Gpo, $Gpo)) { $Found.Add([pscustomobject]@{ Som = $Som; Link = $Link }) }
            }
            foreach ($Child in $Som.Children) { $Stack.Push($Child) }
        }
        return $Found.ToArray()
    }

    # Client-side extensions declared by a GPO (gPC*ExtensionNames) for its files, with the tool
    # of the editor: Registry (Registry.pol, administrative templates of the computer / user)
    # and Security (GptTmpl.inf, security settings).
    static [string] $RegistryExtension = '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'
    static [hashtable] $RegistryTool = @{ Machine = '{D02B1F72-3407-48AE-BA88-E8213C6761F1}'; User = '{D02B1F73-3407-48AE-BA88-E8213C6761F1}' }
    static [string] $SecurityExtension = '{827D319E-6EAC-11D2-A4EA-00C04F79F83A}'
    static [string] $SecurityTool = '{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}'
    # Security template of a GPO, in its folder
    static [string] $SecurityTemplatePath = 'Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf'

    # Registry.pol of a GPO for a scope (Machine or User): its bytes, $null when the GPO has none.
    [byte[]] ReadPolicyFile([GPOToolsGpo]$Gpo, [string]$Scope) {
        return $this.LoadGpoFile($Gpo, "$([GPOToolsDirectory]::GetScopeFolder($Scope))\Registry.pol")
    }

    # Writes the Registry.pol of a GPO for a scope, and increases the version of the GPO for that
    # scope so that the computers apply it.
    [void] WritePolicyFile([GPOToolsGpo]$Gpo, [string]$Scope, [byte[]]$Bytes) {
        $this.AssertWritable()
        $Folder = [GPOToolsDirectory]::GetScopeFolder($Scope)
        $this.SaveGpoFile($Gpo, "$Folder\Registry.pol", $Bytes, $Folder, [GPOToolsDirectory]::RegistryExtension, [GPOToolsDirectory]::RegistryTool[$Folder])
    }

    # Every file of the folder of a GPO, by path in the folder (Machine\Registry.pol): for a backup.
    [System.Collections.Specialized.OrderedDictionary] ReadGpoFolder([GPOToolsGpo]$Gpo) {
        return $this.LoadGpoFolder($Gpo)
    }

    # The GPO as the directory has it now (version, status, last change): before a backup, as
    # it may have changed since it was read.
    [void] RefreshGpo([GPOToolsGpo]$Gpo) {
        $this.LoadGpoState($Gpo)
    }

    # Puts a GPO back as a backup has it, like GPMC Restore-GPO: the files of its folder (those
    # the backup does not have are deleted), its status and client-side extensions; its version
    # increases so that the computers apply it again. Its links and permissions do not change.
    [void] RestoreGpo([GPOToolsGpo]$Gpo, [System.Collections.IDictionary]$Files, [int]$Flags, [string]$MachineExtensionNames, [string]$UserExtensionNames) {
        $this.AssertWritable()
        if (-not $Gpo.CanEdit) { throw "The account $($this.Account) cannot edit the GPO '$($Gpo.DisplayName)'." }
        $this.SaveRestoredGpo($Gpo, $Files, $Flags, $MachineExtensionNames, $UserExtensionNames)
    }

    # Preferences of a GPO ([MS-GPPREF]): the XML file of a preference type for a scope, by its
    # path in Preferences (Registry\Registry.xml); $null when the GPO has none.
    [byte[]] ReadPreferenceFile([GPOToolsGpo]$Gpo, [string]$Scope, [string]$Path) {
        return $this.LoadGpoFile($Gpo, "$([GPOToolsDirectory]::GetScopeFolder($Scope))\Preferences\$Path")
    }

    # Writes the XML file of a preference type, increases the version of the scope and declares
    # the client-side extension of the type with its tool, and the tool under the null extension
    # as GPMC does for the preferences.
    [void] WritePreferenceFile([GPOToolsGpo]$Gpo, [string]$Scope, [string]$Path, [byte[]]$Bytes, [string]$Extension, [string]$Tool) {
        $this.AssertWritable()
        $Folder = [GPOToolsDirectory]::GetScopeFolder($Scope)
        $this.SaveGpoFile($Gpo, "$Folder\Preferences\$Path", $Bytes, $Folder, @([GPOToolsDirectory]::PreferenceToolsExtension, $Extension), $Tool)
    }

    # The null GUID under which GPMC lists the tools of the preferences.
    static [string] $PreferenceToolsExtension = '{00000000-0000-0000-0000-000000000000}'

    # GptTmpl.inf of a GPO (its security settings): its bytes, $null when the GPO has none.
    [byte[]] ReadSecurityTemplate([GPOToolsGpo]$Gpo) {
        return $this.LoadGpoFile($Gpo, [GPOToolsDirectory]::SecurityTemplatePath)
    }

    # Writes the GptTmpl.inf of a GPO, and increases its computer version.
    [void] WriteSecurityTemplate([GPOToolsGpo]$Gpo, [byte[]]$Bytes) {
        $this.AssertWritable()
        $this.SaveGpoFile($Gpo, [GPOToolsDirectory]::SecurityTemplatePath, $Bytes, 'Machine', [GPOToolsDirectory]::SecurityExtension, [GPOToolsDirectory]::SecurityTool)
    }

    # Advanced audit policy of a GPO ([MS-GPAC]): its audit.csv, its client-side extension
    # (Audit Policy Configuration) and the tool of the editor.
    static [string] $AuditPolicyPath = 'Machine\Microsoft\Windows NT\Audit\audit.csv'
    static [string] $AuditPolicyExtension = '{F3CCC681-B74C-4060-9F26-CD84525DCA2A}'
    static [string] $AuditPolicyTool = '{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}'

    # The audit.csv of a GPO: its bytes, $null when the GPO has none.
    [byte[]] ReadAuditPolicyFile([GPOToolsGpo]$Gpo) {
        return $this.LoadGpoFile($Gpo, [GPOToolsDirectory]::AuditPolicyPath)
    }

    # Writes the audit.csv of a GPO, increases its computer version and declares the extension of
    # the advanced audit policy.
    [void] WriteAuditPolicyFile([GPOToolsGpo]$Gpo, [byte[]]$Bytes) {
        $this.AssertWritable()
        $this.SaveGpoFile($Gpo, [GPOToolsDirectory]::AuditPolicyPath, $Bytes, 'Machine', [GPOToolsDirectory]::AuditPolicyExtension, [GPOToolsDirectory]::AuditPolicyTool)
    }

    # Public key policies: the Registry.pol of the scope, declared with the tool of the
    # certificates (Public Key Policies of the editor) under the Registry extension, and under the
    # extension of the EFS recovery policy when the GPO has recovery agents, as GPMC does.
    static [string] $PublicKeyTool = '{53D6AB1D-2488-11D1-A28C-00C04FB94F17}'
    static [string] $EfsRecoveryExtension = '{B1BE8D72-6EAC-11D2-A4EA-00C04F79F83A}'

    [void] WritePublicKeyPolicyFile([GPOToolsGpo]$Gpo, [string]$Scope, [byte[]]$Bytes, [bool]$Efs) {
        $this.AssertWritable()
        $Folder = [GPOToolsDirectory]::GetScopeFolder($Scope)
        $Extensions = @([GPOToolsDirectory]::RegistryExtension) + @(if ($Efs) { [GPOToolsDirectory]::EfsRecoveryExtension })
        $this.SaveGpoFile($Gpo, "$Folder\Registry.pol", $Bytes, $Folder, $Extensions, [GPOToolsDirectory]::PublicKeyTool)
    }

    # Folder of a scope in the GPO: Machine (HKLM) or User (HKCU).
    static [string] GetScopeFolder([string]$Scope) {
        switch ($Scope) {
            'Machine' { return 'Machine' }
            'User' { return 'User' }
        }
        throw "Unknown policy scope: '$Scope' (Machine or User)."
    }

    # Version of a GPO once a scope changed: the computer version in the low word, the user one in the high word.
    static [int] GetNextVersion([int]$Version, [string]$Folder) {
        $Computer = $Version -band 0xFFFF
        $User = ($Version -shr 16) -band 0xFFFF
        if ($Folder -eq 'Machine') { $Computer = ($Computer + 1) -band 0xFFFF } else { $User = ($User + 1) -band 0xFFFF }
        return ($User -shl 16) -bor $Computer
    }

    hidden [void] AssertWritable() {
        if ($this.IsReadOnly) { throw "The directory $($this.DomainName) is read-only ($($this.Source))." }
    }

    hidden [void] AssertCanLink([GPOToolsSom]$Som) {
        if (-not $Som.CanLink) { throw "The account $($this.Account) cannot link GPOs to $($Som.Name): no delegation there." }
    }

    # Persistence of a change, once validated: nothing to do in memory. A failure undoes the change.
    # SaveNewGpo may give the GPO the identity the domain chose (Id, DistinguishedName, FileSysPath).
    hidden [void] SaveNewGpo([GPOToolsGpo]$Gpo) {}
    # SaveNewLink may set the links of the SOM again from the domain (link added by someone else).
    hidden [void] SaveNewLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {}
    hidden [void] SaveGpoStatus([GPOToolsGpo]$Gpo, [int]$Flags) {}
    # $Gpo still has the name the domain has.
    hidden [void] SaveRenamedGpo([GPOToolsGpo]$Gpo, [string]$DisplayName) {}
    # SaveRemovedLink may set the links of the SOM again from the domain.
    hidden [void] SaveRemovedLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {}
    # SaveLink may set the links of the SOM again from the domain; $null keeps an option, $Order 0
    # the link order.
    hidden [void] SaveLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link, [Nullable[bool]]$Enabled, [Nullable[bool]]$Enforced, [int]$Order) {}
    hidden [void] SaveBlockInheritance([GPOToolsSom]$Som, [bool]$Blocked) {}
    hidden [void] SaveWmiFilter([GPOToolsGpo]$Gpo, [GPOToolsWmiFilter]$Filter) {}
    # The permissions of the GPOs in memory, from the default ones of a new GPO.
    hidden [hashtable]$GpoDescriptors = @{}
    hidden [GPOToolsSecurityDescriptor] LoadGpoDescriptor([GPOToolsGpo]$Gpo) {
        $Key = "$($Gpo.Id)"
        if (-not $this.GpoDescriptors.ContainsKey($Key)) { $this.GpoDescriptors[$Key] = New-PSGPODefaultDescriptor -Gpo $Gpo }
        return $this.GpoDescriptors[$Key]
    }
    # Changes the permissions of the GPO (Invoke-PSGPOPermissionChange) and returns its descriptor.
    hidden [GPOToolsSecurityDescriptor] SaveGpoPermissions([GPOToolsGpo]$Gpo, [string]$Operation, [string]$Sid, [string]$Value) {
        $Descriptor = $this.LoadGpoDescriptor($Gpo)
        Invoke-PSGPOPermissionChange -Descriptor $Descriptor -Operation $Operation -Sid $Sid -Value $Value
        return $Descriptor
    }
    hidden [void] SaveNewWmiFilter([GPOToolsWmiFilter]$Filter) {}
    # The delegation of the WMI filters in memory: the explicit ACEs of the container ('Container')
    # and of each filter (its Id); a filter inherits what the container gives its filters.
    hidden [hashtable]$WmiFilterDescriptors = @{}
    hidden [GPOToolsSecurityDescriptor] LoadWmiFilterDescriptor([GPOToolsWmiFilter]$Filter) {
        if (-not $this.WmiFilterDescriptors.ContainsKey('Container')) { $this.WmiFilterDescriptors['Container'] = New-PSGPOWmiFilterDefaultDescriptor -Container }
        if (-not $Filter) { return $this.WmiFilterDescriptors['Container'] }
        $Key = "$($Filter.Id)"
        if (-not $this.WmiFilterDescriptors.ContainsKey($Key)) { $this.WmiFilterDescriptors[$Key] = New-PSGPOWmiFilterDefaultDescriptor }
        # A copy, not through its bytes: in memory an account may be a name, not a SID.
        $Stored = $this.WmiFilterDescriptors[$Key]
        $Descriptor = [GPOToolsSecurityDescriptor]::new()
        $Descriptor.Owner = $Stored.Owner
        $Descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
        foreach ($Ace in @($Stored.Dacl)) { $Descriptor.Dacl.Add([GPOToolsAce]::new($Ace.Type, $Ace.Flags, $Ace.Mask, $Ace.Sid, $Ace.ObjectType)) }
        foreach ($Ace in @($this.WmiFilterDescriptors['Container'].Dacl)) {
            if ($Ace.IsKnown() -and ($Ace.Flags -band [GPOToolsAce]::ContainerInherit)) {
                $Descriptor.Dacl.Add([GPOToolsAce]::new($Ace.Type, [GPOToolsAce]::Inherited, $Ace.Mask, $Ace.Sid, $Ace.ObjectType))
            }
        }
        return $Descriptor
    }
    hidden [void] SaveWmiFilterPermission([GPOToolsWmiFilter]$Filter, [string]$Sid, [string]$Permission) {
        $null = $this.LoadWmiFilterDescriptor($Filter)
        $Descriptor = $this.WmiFilterDescriptors[$(if ($Filter) { "$($Filter.Id)" } else { 'Container' })]
        Set-PSGPOWmiFilterPermissionAce -Descriptor $Descriptor -Sid $Sid -Permission $Permission -Container:($null -eq $Filter)
    }
    # $Changed: the filter as it becomes, $Filter still as the domain has it.
    hidden [void] SaveEditedWmiFilter([GPOToolsWmiFilter]$Filter, [GPOToolsWmiFilter]$Changed) {}
    hidden [void] SaveRemovedWmiFilter([GPOToolsWmiFilter]$Filter) {}
    # A GPO of a creator, made to wait for its approval: it applies to nobody.
    hidden [void] SavePendingGpo([GPOToolsGpo]$Gpo) {
        $Gpo.SecurityFiltering = @()
        $Gpo.Owner = $this.Account
    }
    hidden [void] SaveApprovedGpo([GPOToolsGpo]$Gpo, [string]$CreatorRights, [string]$ApplyToSid, [string]$DenyToSid) {}
    hidden [object[]] SaveApprovalGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        $Created = foreach ($Role in 'Apply', 'Deny') {
            $Name = Get-PSGPOFilteringGroupName -Role $Role -GpoName $Gpo.DisplayName
            $DistinguishedName = 'CN={0},{1}' -f ($Name -replace '([,\\#+<>;"=])', '\$1'), $Container
            if ($this.Groups.ContainsKey($DistinguishedName)) { throw "The group $DistinguishedName already exists." }
            [pscustomobject]@{ Name = $Name; DistinguishedName = $DistinguishedName; Sid = $Name }
        }
        foreach ($Group in $Created) { $this.Groups[$Group.DistinguishedName] = $Group }
        return $Created
    }
    hidden [void] SaveRemovedGpo([GPOToolsGpo]$Gpo) {
        $Prefix = "$($Gpo.Id)\"
        foreach ($Key in @($this.GpoFiles.Keys | Where-Object { $_.StartsWith($Prefix) })) { $this.GpoFiles.Remove($Key) }
    }

    # Groups created in memory, by distinguished name.
    hidden [hashtable]$Groups = @{}
    hidden [object[]] SaveFilteringGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        $Created = foreach ($Role in 'Apply', 'Deny') {
            $Name = Get-PSGPOFilteringGroupName -Role $Role -GpoName $Gpo.DisplayName
            $DistinguishedName = 'CN={0},{1}' -f ($Name -replace '([,\\#+<>;"=])', '\$1'), $Container
            if ($this.Groups.ContainsKey($DistinguishedName)) { throw "The group $DistinguishedName already exists." }
            [pscustomobject]@{ Name = $Name; DistinguishedName = $DistinguishedName; Sid = $null }
        }
        foreach ($Group in $Created) { $this.Groups[$Group.DistinguishedName] = $Group }
        return $Created
    }

    # The configuration of the domain kept in memory.
    hidden [byte[]]$ConfigurationBytes
    hidden [byte[]] LoadConfigurationFile() { return $this.ConfigurationBytes }
    hidden [void] SaveConfigurationFile([byte[]]$Bytes) { $this.ConfigurationBytes = if ($Bytes -and $Bytes.Length) { $Bytes } else { $null } }

    # Files of the GPOs kept in memory, by GPO and path in its folder.
    hidden [hashtable]$GpoFiles = @{}
    hidden [byte[]] LoadGpoFile([GPOToolsGpo]$Gpo, [string]$Path) {
        return $this.GpoFiles["$($Gpo.Id)\$Path"]
    }
    hidden [System.Collections.Specialized.OrderedDictionary] LoadGpoFolder([GPOToolsGpo]$Gpo) {
        $Files = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Prefix = "$($Gpo.Id)\"
        foreach ($Key in @($this.GpoFiles.Keys | Where-Object { $_.StartsWith($Prefix) } | Sort-Object)) {
            $Files[$Key.Substring($Prefix.Length)] = $this.GpoFiles[$Key]
        }
        return $Files
    }
    hidden [void] LoadGpoState([GPOToolsGpo]$Gpo) {}
    hidden [void] SaveRestoredGpo([GPOToolsGpo]$Gpo, [System.Collections.IDictionary]$Files, [int]$Flags, [string]$MachineExtensionNames, [string]$UserExtensionNames) {
        $Prefix = "$($Gpo.Id)\"
        foreach ($Key in @($this.GpoFiles.Keys | Where-Object { $_.StartsWith($Prefix) })) { $this.GpoFiles.Remove($Key) }
        foreach ($Name in $Files.Keys) { if ($Name -ne 'GPT.INI') { $this.GpoFiles["$Prefix$Name"] = [byte[]]$Files[$Name] } }
        $Gpo.Version = [GPOToolsDirectory]::GetNextVersion([GPOToolsDirectory]::GetNextVersion($Gpo.Version, 'Machine'), 'User')
        $Gpo.Flags = $Flags
        $Gpo.MachineExtensionNames = $MachineExtensionNames
        $Gpo.UserExtensionNames = $UserExtensionNames
        $Gpo.Modified = [datetime]::UtcNow
    }
    # Saves a file of the GPO, then increases the version of the scope ($Folder) and declares the
    # client-side extension that applies it.
    hidden [void] SaveGpoFile([GPOToolsGpo]$Gpo, [string]$Path, [byte[]]$Bytes, [string]$Folder, [string[]]$Extension, [string]$Tool) {
        $this.GpoFiles["$($Gpo.Id)\$Path"] = $Bytes
        $Gpo.Version = [GPOToolsDirectory]::GetNextVersion($Gpo.Version, $Folder)
        $Gpo.Modified = [datetime]::UtcNow
        foreach ($Guid in $Extension) {
            if ($Folder -eq 'Machine') { $Gpo.MachineExtensionNames = Add-PSGPOExtensionName -Current $Gpo.MachineExtensionNames -Extension $Guid -Tool $Tool }
            else { $Gpo.UserExtensionNames = Add-PSGPOExtensionName -Current $Gpo.UserExtensionNames -Extension $Guid -Tool $Tool }
        }
    }
}

# Directory read from a domain over LDAP (Get-PSGPODirectory); its changes are written to the
# domain: GPOs created and deleted with RSAT (Windows) or samba-tool (Linux), links written over
# LDAP.
class GPOToolsLdapDirectory : GPOToolsDirectory {
    # Domain controller the directory was read from, and that the changes go to
    [string]$Server
    # Directory service of the domain controller: 'Samba AD' or 'Active Directory' (Windows)
    [string]$ServerType
    # How the directory was read, to connect again for the changes
    hidden [pscredential]$Credential
    hidden [bool]$UseSsl
    hidden [int]$Port

    GPOToolsLdapDirectory([string]$DomainName, [string]$DomainDistinguishedName, [string]$Server, [string]$ServerType) : base($DomainName) {
        $this.Domain.DistinguishedName = $DomainDistinguishedName
        $this.Server = $Server
        $this.ServerType = $ServerType
        $this.Source = "read over LDAP from $Server ($ServerType)"
    }

    hidden [void] SaveNewGpo([GPOToolsGpo]$Gpo) {
        New-PSGPODomainGpo -Directory $this -Gpo $Gpo
        Write-PSGPOAuditEntry -Directory $this -Action 'NewGpo' -Target $Gpo.DistinguishedName -Gpo $Gpo
    }

    hidden [void] SaveNewLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {
        Add-PSGPODomainGpLink -Directory $this -Som $Som -Link $Link
        Write-PSGPOAuditEntry -Directory $this -Action 'NewLink' -Target $Som.DistinguishedName -Gpo $Link.Gpo -Details @{ Order = $Link.Order }
    }

    hidden [void] SaveGpoStatus([GPOToolsGpo]$Gpo, [int]$Flags) {
        Set-PSGPODomainGpoStatus -Directory $this -Gpo $Gpo -Flags $Flags
        Write-PSGPOAuditEntry -Directory $this -Action 'SetGpoStatus' -Target $Gpo.DistinguishedName -Gpo $Gpo -Details @{ Flags = $Flags }
    }

    hidden [void] SaveRenamedGpo([GPOToolsGpo]$Gpo, [string]$DisplayName) {
        Set-PSGPODomainGpoName -Directory $this -Gpo $Gpo -DisplayName $DisplayName
        Write-PSGPOAuditEntry -Directory $this -Action 'RenameGpo' -Target $Gpo.DistinguishedName -Gpo $Gpo -Details ([ordered]@{ Name = $DisplayName; OldName = $Gpo.DisplayName })
    }

    hidden [void] SaveRemovedLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {
        Remove-PSGPODomainGpLink -Directory $this -Som $Som -Link $Link
        Write-PSGPOAuditEntry -Directory $this -Action 'RemoveLink' -Target $Som.DistinguishedName -Gpo $Link.Gpo -Details @{ Gpo = $Link.GpoDistinguishedName }
    }

    hidden [void] SaveLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link, [Nullable[bool]]$Enabled, [Nullable[bool]]$Enforced, [int]$Order) {
        Set-PSGPODomainGpLink -Directory $this -Som $Som -Link $Link -Enabled $Enabled -Enforced $Enforced -Order $Order
        $Changed = [ordered]@{}
        if ($null -ne $Enabled) { $Changed.Enabled = [bool]$Enabled }
        if ($null -ne $Enforced) { $Changed.Enforced = [bool]$Enforced }
        if ($Order) { $Changed.Order = $Order }
        Write-PSGPOAuditEntry -Directory $this -Action 'SetLink' -Target $Som.DistinguishedName -Gpo $Link.Gpo -Details $Changed
    }

    hidden [void] SaveBlockInheritance([GPOToolsSom]$Som, [bool]$Blocked) {
        $null = Set-PSGPODomainBlockInheritance -Directory $this -Som $Som -Blocked $Blocked
        Write-PSGPOAuditEntry -Directory $this -Action 'SetBlockInheritance' -Target $Som.DistinguishedName -Details @{ Blocked = $Blocked }
    }

    hidden [void] SaveWmiFilter([GPOToolsGpo]$Gpo, [GPOToolsWmiFilter]$Filter) {
        Set-PSGPODomainWmiFilterLink -Directory $this -Gpo $Gpo -Filter $Filter
        Write-PSGPOAuditEntry -Directory $this -Action 'SetWmiFilter' -Target $Gpo.DistinguishedName -Gpo $Gpo -Details @{ WmiFilter = $(if ($Filter) { $Filter.Name }); WmiFilterId = $(if ($Filter) { $Filter.Id.ToString() }) }
    }

    hidden [GPOToolsSecurityDescriptor] LoadGpoDescriptor([GPOToolsGpo]$Gpo) {
        $Connection = New-PSGPODirectoryConnection -Directory $this
        try { return Get-PSGPODomainSecurityDescriptor -Connection $Connection -DistinguishedName $Gpo.DistinguishedName }
        finally { $Connection.Dispose() }
    }

    hidden [GPOToolsSecurityDescriptor] SaveGpoPermissions([GPOToolsGpo]$Gpo, [string]$Operation, [string]$Sid, [string]$Value) {
        $Descriptor = Set-PSGPODomainGpoPermission -Directory $this -Gpo $Gpo -Operation $Operation -Sid $Sid -Value $Value
        $Name = $this.ResolveSidNames([string[]]@($Sid))[$Sid]
        Write-PSGPOAuditEntry -Directory $this -Action $(if ($Operation -eq 'Filtering') { 'SetGpoSecurityFiltering' } else { 'SetGpoPermission' }) -Target $Gpo.DistinguishedName -Gpo $Gpo `
            -Details ([ordered]@{ Account = $Name; Sid = $Sid; Value = $Value })
        return $Descriptor
    }

    [hashtable] ResolveSidNames([string[]]$Sids) {
        $Connection = New-PSGPODirectoryConnection -Directory $this
        try { return Resolve-PSGPODomainSid -Connection $Connection -DomainDistinguishedName $this.Domain.DistinguishedName -Sid @($Sids) }
        finally { $Connection.Dispose() }
    }

    hidden [void] SaveNewWmiFilter([GPOToolsWmiFilter]$Filter) {
        New-PSGPODomainWmiFilter -Directory $this -Filter $Filter
        Write-PSGPOAuditEntry -Directory $this -Action 'NewWmiFilter' -Target $Filter.DistinguishedName -Details ([ordered]@{ Name = $Filter.Name; Queries = $Filter.GetQueryText() })
    }

    hidden [void] SaveEditedWmiFilter([GPOToolsWmiFilter]$Filter, [GPOToolsWmiFilter]$Changed) {
        Set-PSGPODomainWmiFilter -Directory $this -Filter $Filter -Changed $Changed
        Write-PSGPOAuditEntry -Directory $this -Action 'EditWmiFilter' -Target $Filter.DistinguishedName `
            -Details ([ordered]@{ Name = $Changed.Name; OldName = $(if ($Filter.Name -cne $Changed.Name) { $Filter.Name }); Queries = $Changed.GetQueryText() })
    }

    hidden [GPOToolsSecurityDescriptor] LoadWmiFilterDescriptor([GPOToolsWmiFilter]$Filter) {
        $Connection = New-PSGPODirectoryConnection -Directory $this
        try { return Get-PSGPODomainSecurityDescriptor -Connection $Connection -DistinguishedName $(if ($Filter) { $Filter.DistinguishedName } else { $this.GetWmiFilterContainer() }) }
        finally { $Connection.Dispose() }
    }

    hidden [void] SaveWmiFilterPermission([GPOToolsWmiFilter]$Filter, [string]$Sid, [string]$Permission) {
        $Target = if ($Filter) { $Filter.DistinguishedName } else { $this.GetWmiFilterContainer() }
        $null = Set-PSGPODomainWmiFilterPermission -Directory $this -DistinguishedName $Target -Sid $Sid -Permission $Permission -Container:($null -eq $Filter) `
            -Name $(if ($Filter) { "the WMI filter '$($Filter.Name)'" } else { "the WMI filters of $($this.DomainName)" })
        $Name = $this.ResolveSidNames([string[]]@($Sid))[$Sid]
        Write-PSGPOAuditEntry -Directory $this -Action 'SetWmiFilterPermission' -Target $Target -Details ([ordered]@{ WmiFilter = $(if ($Filter) { $Filter.Name }); Account = $Name; Sid = $Sid; Value = $Permission })
    }

    hidden [void] SaveRemovedWmiFilter([GPOToolsWmiFilter]$Filter) {
        Remove-PSGPODomainWmiFilter -Directory $this -Filter $Filter
        Write-PSGPOAuditEntry -Directory $this -Action 'RemoveWmiFilter' -Target $Filter.DistinguishedName -Details @{ Name = $Filter.Name }
    }

    hidden [void] SaveRemovedGpo([GPOToolsGpo]$Gpo) {
        Remove-PSGPODomainGpo -Directory $this -Gpo $Gpo
        Write-PSGPOAuditEntry -Directory $this -Action 'RemoveGpo' -Target $Gpo.DistinguishedName -Gpo $Gpo
    }

    hidden [void] SavePendingGpo([GPOToolsGpo]$Gpo) {
        Set-PSGPODomainPendingGpo -Directory $this -Gpo $Gpo
        Write-PSGPOAuditEntry -Directory $this -Action 'PendingGpo' -Target $Gpo.DistinguishedName -Gpo $Gpo
    }

    hidden [void] SaveApprovedGpo([GPOToolsGpo]$Gpo, [string]$CreatorRights, [string]$ApplyToSid, [string]$DenyToSid) {
        $Gpo.RemovedAtApproval = Approve-PSGPODomainGpo -Directory $this -Gpo $Gpo -CreatorRights $CreatorRights -ApplyToSid $ApplyToSid -DenyToSid $DenyToSid
        Write-PSGPOAuditEntry -Directory $this -Action 'ApproveGpo' -Target $Gpo.DistinguishedName -Gpo $Gpo -Details ([ordered]@{
                CreatedBy = $Gpo.Owner; CreatorRights = $CreatorRights; ApplyTo = $ApplyToSid; DenyTo = $DenyToSid; RemovedPermissions = @($Gpo.RemovedAtApproval) })
    }

    hidden [object[]] SaveApprovalGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        $Created = New-PSGPODomainFilteringGroup -Directory $this -Gpo $Gpo -Container $Container -NoFiltering
        Write-PSGPOAuditEntry -Directory $this -Action 'NewFilteringGroups' -Target $Container -Gpo $Gpo -Details @{ Groups = @($Created | ForEach-Object DistinguishedName) }
        return $Created
    }

    # The configuration of the domain in the SYSVOL share of the domain controller.
    [string] GetConfigurationPath() {
        return "\\$($this.Server)\SYSVOL\$($this.DomainName)\PSGPOTools\Configuration.psd1"
    }

    hidden [byte[]] LoadConfigurationFile() {
        return Read-PSGPOSysvolItem -Directory $this -Share 'SYSVOL' -Path "$($this.DomainName)\PSGPOTools\Configuration.psd1"
    }

    hidden [void] SaveConfigurationFile([byte[]]$Bytes) {
        if ($Bytes -and $Bytes.Length) {
            Write-PSGPOSysvolItem -Directory $this -Share 'SYSVOL' -Base $this.DomainName -Path 'PSGPOTools\Configuration.psd1' -Bytes $Bytes
        } else {
            Remove-PSGPOSysvolItem -Directory $this -Share 'SYSVOL' -Path "$($this.DomainName)\PSGPOTools\Configuration.psd1"
        }
        Write-PSGPOAuditEntry -Directory $this -Action 'SaveConfiguration' -Target $this.GetConfigurationPath() -Details @{ Removed = -not ($Bytes -and $Bytes.Length) }
    }

    hidden [object[]] SaveFilteringGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        $Created = New-PSGPODomainFilteringGroup -Directory $this -Gpo $Gpo -Container $Container
        Write-PSGPOAuditEntry -Directory $this -Action 'NewFilteringGroups' -Target $Container -Gpo $Gpo -Details @{ Groups = @($Created | ForEach-Object DistinguishedName) }
        return $Created
    }

    hidden [byte[]] LoadGpoFile([GPOToolsGpo]$Gpo, [string]$Path) {
        return Read-PSGPOSysvolFile -Directory $this -Gpo $Gpo -Path $Path
    }

    hidden [System.Collections.Specialized.OrderedDictionary] LoadGpoFolder([GPOToolsGpo]$Gpo) {
        return Read-PSGPOSysvolFolder -Directory $this -Gpo $Gpo
    }

    hidden [void] LoadGpoState([GPOToolsGpo]$Gpo) {
        Update-PSGPODomainGpoState -Directory $this -Gpo $Gpo
    }

    hidden [void] SaveRestoredGpo([GPOToolsGpo]$Gpo, [System.Collections.IDictionary]$Files, [int]$Flags, [string]$MachineExtensionNames, [string]$UserExtensionNames) {
        Restore-PSGPODomainGpo -Directory $this -Gpo $Gpo -Files $Files -Flags $Flags -MachineExtensionNames $MachineExtensionNames -UserExtensionNames $UserExtensionNames
        Write-PSGPOAuditEntry -Directory $this -Action 'RestoreGpo' -Target $Gpo.DistinguishedName -Gpo $Gpo -Details @{ Files = @($Files.Keys); Version = $Gpo.Version }
    }

    hidden [void] SaveGpoFile([GPOToolsGpo]$Gpo, [string]$Path, [byte[]]$Bytes, [string]$Folder, [string[]]$Extension, [string]$Tool) {
        Save-PSGPODomainGpoFile -Directory $this -Gpo $Gpo -Path $Path -Bytes $Bytes -Folder $Folder -Extension $Extension -Tool $Tool
        Write-PSGPOAuditEntry -Directory $this -Action 'SaveGpoFile' -Target $Gpo.DistinguishedName -Gpo $Gpo -Details ([ordered]@{
                Path = $Path; Size = $Bytes.Length; Sha256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)); Version = $Gpo.Version })
    }

    # Directory service of a domain controller from the vendorName of its rootDSE: Samba sets it,
    # Windows domain controllers do not.
    static [string] GetServerType([string]$VendorName) {
        if ($VendorName -match 'Samba') { return 'Samba AD' }
        return 'Active Directory'
    }
}
