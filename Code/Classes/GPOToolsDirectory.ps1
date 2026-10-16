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

    [int] GetUserVersion() { return $this.Version -shr 16 }
    [int] GetComputerVersion() { return $this.Version -band 0xFFFF }

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
    # Approval workflow of the domain (Update-PSGPODomainWorkflow): Enabled, IsApprover,
    # IsCreator, the SIDs and names of the groups, the owner of the approved GPOs; $null without it
    [pscustomobject]$Workflow

    GPOToolsDirectory([string]$DomainName) {
        if ([string]::IsNullOrWhiteSpace($DomainName)) { throw 'The domain name is required.' }
        $this.DomainName = $DomainName
        $this.Gpos = [System.Collections.Generic.List[GPOToolsGpo]]::new()
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

    # Adds a GPO read from a directory: unlike AddGpo, its name may be empty or already used.
    [GPOToolsGpo] AddExistingGpo([GPOToolsGpo]$Gpo) {
        if (-not $Gpo.DistinguishedName) {
            $Gpo.DistinguishedName = 'CN={{{0}}},CN=Policies,CN=System,{1}' -f $Gpo.Id.ToString().ToUpperInvariant(), $this.Domain.DistinguishedName
        }
        $this.Gpos.Add($Gpo)
        $this.Gpos.Sort([System.Comparison[GPOToolsGpo]] { param($a, $b) [string]::Compare($a.DisplayName, $b.DisplayName, $true) })
        return $Gpo
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
        $Gpo.FileSysPath = '\\{0}\SysVol\{0}\Policies\{{{1}}}' -f $this.DomainName, $Gpo.Id.ToString().ToUpperInvariant()
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

    # The account creates GPOs that wait for an approval: a creator of the workflow, not an approver.
    [bool] IsWorkflowCreator() {
        return $this.Workflow -and $this.Workflow.Enabled -and $this.Workflow.IsCreator -and -not $this.Workflow.IsApprover
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

    # Configuration of PSGPOTools for the domain (Use-PSGPODomainConfiguration): Configuration.psd1
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

    # Rights of the account, as the delegations of the domain give them (RBAC): a technician sees
    # the OUs where it links GPOs, with their parents as the path to them, and the GPOs it edits
    # or that are linked there.
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
        $this.SaveGpoStatus($Gpo, $Flags)
        $Gpo.Flags = $Flags
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
    # SaveRemovedLink may set the links of the SOM again from the domain.
    hidden [void] SaveRemovedLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {}
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
    }

    hidden [void] SaveNewLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {
        Add-PSGPODomainGpLink -Directory $this -Som $Som -Link $Link
    }

    hidden [void] SaveGpoStatus([GPOToolsGpo]$Gpo, [int]$Flags) {
        Set-PSGPODomainGpoFlags -Directory $this -Gpo $Gpo -Flags $Flags
    }

    hidden [void] SaveRemovedLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {
        Remove-PSGPODomainGpLink -Directory $this -Som $Som -Link $Link
    }

    hidden [void] SaveRemovedGpo([GPOToolsGpo]$Gpo) {
        Remove-PSGPODomainGpo -Directory $this -Gpo $Gpo
    }

    hidden [void] SavePendingGpo([GPOToolsGpo]$Gpo) {
        Set-PSGPODomainPendingGpo -Directory $this -Gpo $Gpo
    }

    hidden [void] SaveApprovedGpo([GPOToolsGpo]$Gpo, [string]$CreatorRights, [string]$ApplyToSid, [string]$DenyToSid) {
        Approve-PSGPODomainGpo -Directory $this -Gpo $Gpo -CreatorRights $CreatorRights -ApplyToSid $ApplyToSid -DenyToSid $DenyToSid
    }

    hidden [object[]] SaveApprovalGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        return New-PSGPODomainFilteringGroup -Directory $this -Gpo $Gpo -Container $Container -NoFiltering
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
    }

    hidden [object[]] SaveFilteringGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        return New-PSGPODomainFilteringGroup -Directory $this -Gpo $Gpo -Container $Container
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
    }

    hidden [void] SaveGpoFile([GPOToolsGpo]$Gpo, [string]$Path, [byte[]]$Bytes, [string]$Folder, [string[]]$Extension, [string]$Tool) {
        Save-PSGPODomainGpoFile -Directory $this -Gpo $Gpo -Path $Path -Bytes $Bytes -Folder $Folder -Extension $Extension -Tool $Tool
    }

    # Directory service of a domain controller from the vendorName of its rootDSE: Samba sets it,
    # Windows domain controllers do not.
    static [string] GetServerType([string]$VendorName) {
        if ($VendorName -match 'Samba') { return 'Samba AD' }
        return 'Active Directory'
    }
}
