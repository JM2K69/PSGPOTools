<#
    Active Directory side of the console, as GPMC shows it: the domain and its OUs (scopes of
    management, SOM), the GPOs and the links between them.

    GPOToolsDirectory keeps the directory in memory: read from JSON (Import-PSGPODirectory), its
    changes stay in memory. GPOToolsLdapDirectory is read from a domain over LDAP
    (Get-PSGPODirectory, Windows AD or Samba AD) and is read-only until writing is implemented;
    writing will override the hidden Save* methods, which run before the in-memory change.

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
        try { $this.SaveLinks($Som) } catch { [void]$Som.Links.Remove($Link); throw }
        return $Link
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

    hidden [void] AssertWritable() {
        if ($this.IsReadOnly) { throw "The directory $($this.DomainName) is read-only ($($this.Source))." }
    }

    # Persistence of a change, once validated: nothing to do in memory. A failure undoes the change.
    hidden [void] SaveNewGpo([GPOToolsGpo]$Gpo) {}
    hidden [void] SaveLinks([GPOToolsSom]$Som) {}
}

# Directory read from a domain over LDAP (Get-PSGPODirectory): read-only for now.
class GPOToolsLdapDirectory : GPOToolsDirectory {
    # Domain controller the directory was read from
    [string]$Server

    GPOToolsLdapDirectory([string]$DomainName, [string]$DomainDistinguishedName, [string]$Server) : base($DomainName) {
        $this.Domain.DistinguishedName = $DomainDistinguishedName
        $this.Server = $Server
        $this.Source = "read over LDAP from $Server, read-only"
        $this.IsReadOnly = $true
    }
}
