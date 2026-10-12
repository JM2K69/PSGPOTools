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
        $Gpo = $this.AddGpo($DisplayName, [guid]::Empty)
        try { $this.SaveNewGpo($Gpo) } catch { [void]$this.Gpos.Remove($Gpo); throw }
        return $Gpo
    }

    # Links a GPO to a SOM with the lowest precedence (the last link order), like GPMC.
    [GPOToolsGpoLink] NewLink([GPOToolsSom]$Som, [GPOToolsGpo]$Gpo) {
        $this.AssertWritable()
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
        if ([string]::IsNullOrWhiteSpace($Container)) { $Container = $this.GetUsersContainer() }
        return $this.SaveFilteringGroups($Gpo, $Container)
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

    # Persistence of a change, once validated: nothing to do in memory. A failure undoes the change.
    # SaveNewGpo may give the GPO the identity the domain chose (Id, DistinguishedName, FileSysPath).
    hidden [void] SaveNewGpo([GPOToolsGpo]$Gpo) {}
    # SaveNewLink may set the links of the SOM again from the domain (link added by someone else).
    hidden [void] SaveNewLink([GPOToolsSom]$Som, [GPOToolsGpoLink]$Link) {}
    hidden [void] SaveGpoStatus([GPOToolsGpo]$Gpo, [int]$Flags) {}

    # Groups created in memory, by distinguished name.
    hidden [hashtable]$Groups = @{}
    hidden [object[]] SaveFilteringGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        $Created = foreach ($Prefix in 'APPLY', 'DENY') {
            $Name = Get-PSGPOFilteringGroupName -Prefix $Prefix -GpoName $Gpo.DisplayName
            $DistinguishedName = 'CN={0},{1}' -f ($Name -replace '([,\\#+<>;"=])', '\$1'), $Container
            if ($this.Groups.ContainsKey($DistinguishedName)) { throw "The group $DistinguishedName already exists." }
            [pscustomobject]@{ Name = $Name; DistinguishedName = $DistinguishedName; Sid = $null }
        }
        foreach ($Group in $Created) { $this.Groups[$Group.DistinguishedName] = $Group }
        return $Created
    }

    # Files of the GPOs kept in memory, by GPO and path in its folder.
    hidden [hashtable]$GpoFiles = @{}
    hidden [byte[]] LoadGpoFile([GPOToolsGpo]$Gpo, [string]$Path) {
        return $this.GpoFiles["$($Gpo.Id)\$Path"]
    }
    # Saves a file of the GPO, then increases the version of the scope ($Folder) and declares the
    # client-side extension that applies it.
    hidden [void] SaveGpoFile([GPOToolsGpo]$Gpo, [string]$Path, [byte[]]$Bytes, [string]$Folder, [string]$Extension, [string]$Tool) {
        $this.GpoFiles["$($Gpo.Id)\$Path"] = $Bytes
        $Gpo.Version = [GPOToolsDirectory]::GetNextVersion($Gpo.Version, $Folder)
    }
}

# Directory read from a domain over LDAP (Get-PSGPODirectory); its changes are written to the
# domain: GPOs created with samba-tool, links written over LDAP.
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

    hidden [object[]] SaveFilteringGroups([GPOToolsGpo]$Gpo, [string]$Container) {
        return New-PSGPODomainFilteringGroup -Directory $this -Gpo $Gpo -Container $Container
    }

    hidden [byte[]] LoadGpoFile([GPOToolsGpo]$Gpo, [string]$Path) {
        return Read-PSGPOSysvolFile -Directory $this -Gpo $Gpo -Path $Path
    }

    hidden [void] SaveGpoFile([GPOToolsGpo]$Gpo, [string]$Path, [byte[]]$Bytes, [string]$Folder, [string]$Extension, [string]$Tool) {
        Save-PSGPODomainGpoFile -Directory $this -Gpo $Gpo -Path $Path -Bytes $Bytes -Folder $Folder -Extension $Extension -Tool $Tool
    }

    # Directory service of a domain controller from the vendorName of its rootDSE: Samba sets it,
    # Windows domain controllers do not.
    static [string] GetServerType([string]$VendorName) {
        if ($VendorName -match 'Samba') { return 'Samba AD' }
        return 'Active Directory'
    }
}
