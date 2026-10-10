<#
    Active Directory side of the console, as GPMC shows it: the domain and its OUs (scopes of
    management, SOM), the GPOs and the links between them.

    Proof of concept: the directory is read from a JSON description (Import-PSGPODirectory) and
    kept in memory. Reading a real domain (LDAP, Samba AD included) will come later, in a class
    deriving from GPOToolsDirectory that overrides the hidden Save* methods.
#>

enum GPOToolsSomKind {
    Domain
    OrganizationalUnit
}

class GPOToolsGpo {
    [guid]$Id
    [string]$DisplayName
    [string]$DistinguishedName
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
    [GPOToolsGpo]$Gpo
    [bool]$Enabled = $true
    [bool]$Enforced
    # Link order: 1 is the highest precedence
    [int]$Order
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

    [GPOToolsSom] AddOrganizationalUnit([GPOToolsSom]$ParentSom, [string]$Name) {
        $Som = [GPOToolsSom]::new()
        $Som.Name = $Name
        $Som.DistinguishedName = 'OU={0},{1}' -f ($Name -replace '([,\\#+<>;"=])', '\$1'), $ParentSom.DistinguishedName
        $Som.Kind = [GPOToolsSomKind]::OrganizationalUnit
        $Som.Parent = $ParentSom
        $ParentSom.Children.Add($Som)
        return $Som
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
        $this.Gpos.Add($Gpo)
        $this.Gpos.Sort([System.Comparison[GPOToolsGpo]] { param($a, $b) [string]::Compare($a.DisplayName, $b.DisplayName, $true) })
        return $Gpo
    }

    # Creates a GPO, like GPMC "New GPO".
    [GPOToolsGpo] NewGpo([string]$DisplayName) {
        $Gpo = $this.AddGpo($DisplayName, [guid]::Empty)
        try { $this.SaveNewGpo($Gpo) } catch { [void]$this.Gpos.Remove($Gpo); throw }
        return $Gpo
    }

    # Links a GPO to a SOM with the lowest precedence (the last link order), like GPMC.
    [GPOToolsGpoLink] NewLink([GPOToolsSom]$Som, [GPOToolsGpo]$Gpo) {
        foreach ($Existing in $Som.Links) {
            if ([object]::ReferenceEquals($Existing.Gpo, $Gpo)) {
                throw "The GPO '$($Gpo.DisplayName)' is already linked to $($Som.Name)."
            }
        }
        $Link = [GPOToolsGpoLink]::new()
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

    # Persistence of a change, once validated: nothing to do in memory. A failure undoes the change.
    hidden [void] SaveNewGpo([GPOToolsGpo]$Gpo) {}
    hidden [void] SaveLinks([GPOToolsSom]$Som) {}
}
