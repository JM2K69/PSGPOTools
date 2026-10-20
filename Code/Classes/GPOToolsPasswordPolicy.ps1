<#
    Fine-grained password policies of a domain (password settings objects, PSO), as the Active
    Directory Administrative Center manages them: msDS-PasswordSettings objects of
    CN=Password Settings Container,CN=System,<domain>, each with its precedence, its settings and
    the users and groups it directly applies to (msDS-PSOAppliesTo). An account no PSO applies to
    has the password policy of the domain (the attributes of the domain object). Windows and Samba
    AD (4.9 and later, functional level 2008 or more) have the same schema: the PSOs are read and
    written over LDAP, from Windows and Linux.

    GPOToolsPasswordPolicyStore holds them in memory (sample data, tests);
    GPOToolsLdapPasswordPolicyStore reads them from a domain controller and writes the changes
    there, as GPOToolsDirectory and GPOToolsLdapDirectory do for the GPOs.
#>

class GPOToolsPasswordPolicy {
    [string]$Name
    [string]$DistinguishedName
    # objectGUID: of two PSOs with the same precedence, the smaller one wins
    [guid]$Id
    # The PSO with the lowest precedence wins; 0 for the password policy of the domain
    [int]$Precedence
    [int]$MinPasswordLength
    [int]$PasswordHistoryCount
    [bool]$ComplexityEnabled
    [bool]$ReversibleEncryptionEnabled
    [TimeSpan]$MinPasswordAge
    # Zero: the passwords never expire
    [TimeSpan]$MaxPasswordAge
    # 0: the accounts are never locked out
    [int]$LockoutThreshold
    # Zero: locked out until an administrator unlocks the account
    [TimeSpan]$LockoutDuration
    [TimeSpan]$LockoutObservationWindow
    [string]$Description
    [bool]$ProtectedFromAccidentalDeletion
    # Distinguished names of the users and groups it directly applies to
    [System.Collections.Generic.List[string]]$AppliesTo
    # The password policy of the domain, not a PSO
    [bool]$IsDefault
    # The account of the console can change it (allowedAttributesEffective)
    [bool]$CanEdit = $true
    [Nullable[datetime]]$Modified
    # The values of its attributes as the domain has them: a change removes them, and is refused
    # when another console changed them meanwhile
    hidden [hashtable]$DirectoryValues

    GPOToolsPasswordPolicy() {
        $this.AppliesTo = [System.Collections.Generic.List[string]]::new()
    }

    # The settings of a new PSO in the Active Directory Administrative Center.
    static [GPOToolsPasswordPolicy] NewDefault() {
        $Policy = [GPOToolsPasswordPolicy]::new()
        $Policy.MinPasswordLength = 7
        $Policy.PasswordHistoryCount = 24
        $Policy.ComplexityEnabled = $true
        $Policy.MinPasswordAge = [TimeSpan]::FromDays(1)
        $Policy.MaxPasswordAge = [TimeSpan]::FromDays(42)
        $Policy.LockoutDuration = [TimeSpan]::FromMinutes(30)
        $Policy.LockoutObservationWindow = [TimeSpan]::FromMinutes(30)
        return $Policy
    }

    [GPOToolsPasswordPolicy] Clone() {
        $Copy = [GPOToolsPasswordPolicy]::new()
        foreach ($Property in $this.PSObject.Properties) {
            if ($Property.Name -ne 'AppliesTo') { $Copy.($Property.Name) = $Property.Value }
        }
        $Copy.AppliesTo.AddRange([string[]]@($this.AppliesTo))
        return $Copy
    }

    # The order of priority of the domain controllers: the lowest precedence, then the smallest
    # objectGUID.
    static [int] Compare([GPOToolsPasswordPolicy]$A, [GPOToolsPasswordPolicy]$B) {
        $Result = $A.Precedence.CompareTo($B.Precedence)
        if ($Result -eq 0) { $Result = $A.Id.CompareTo($B.Id) }
        return $Result
    }

    # It directly applies to this account (distinguished names compared as the directory does).
    [bool] AppliesDirectlyTo([string]$DistinguishedName) {
        foreach ($Subject in $this.AppliesTo) {
            if ([string]::Equals($Subject, $DistinguishedName, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }

    [string] ToString() { return $this.Name }
}

# A user or a group, as the fine-grained password policies see it.
class GPOToolsPasswordAccount {
    [string]$Name
    [string]$SamAccountName
    [string]$DistinguishedName
    # User or Group
    [string]$Kind
    [string]$Sid
    # Groups: Global, DomainLocal or Universal, security or distribution, built-in (groupType)
    [string]$GroupScope
    [bool]$IsSecurityGroup
    [bool]$IsBuiltin
    # Distinguished names of its groups (memberOf), its primary group apart
    [string[]]$MemberOf = @()
    [string]$PrimaryGroup

    # Scope and kind of a group from its groupType.
    [void] SetGroupType([int]$GroupType) {
        $this.GroupScope = if ($GroupType -band 0x2) { 'Global' } elseif ($GroupType -band 0x8) { 'Universal' } else { 'DomainLocal' }
        $this.IsSecurityGroup = ($GroupType -band 0x80000000) -ne 0
        $this.IsBuiltin = ($GroupType -band 0x1) -ne 0
    }

    [string] ToString() { return $this.Name }
}

class GPOToolsPasswordPolicyStore {
    [string]$DomainName
    [string]$DomainDistinguishedName
    # Where the policies come from, shown by the window
    [string]$Source = 'in memory'
    # Sample data shown because no domain was discovered (Show-PSOManagerAvalonia)
    [bool]$IsDemonstration
    # Account the domain was read with; $null in memory
    [string]$Account
    # The account can create PSOs (msDS-PasswordSettings objects in the Password Settings Container)
    [bool]$CanCreate = $true
    # By order of priority
    [System.Collections.Generic.List[GPOToolsPasswordPolicy]]$Policies
    # The password policy of the domain: the accounts no PSO applies to
    [GPOToolsPasswordPolicy]$DomainPolicy
    # The groups that pass a PSO on to their members: 'GlobalSecurity' as Windows domain controllers
    # (global security groups), 'Security' as Samba AD (security groups but the built-in ones)
    [string]$GroupRule = 'GlobalSecurity'
    # In memory: the users and groups, by distinguished name
    hidden [System.Collections.Generic.Dictionary[string, GPOToolsPasswordAccount]]$Accounts

    GPOToolsPasswordPolicyStore([string]$DomainName) {
        if ([string]::IsNullOrWhiteSpace($DomainName)) { throw 'The domain name is required.' }
        $this.DomainName = $DomainName
        $this.DomainDistinguishedName = (($DomainName.Split('.') | ForEach-Object { "DC=$_" }) -join ',')
        $this.Policies = [System.Collections.Generic.List[GPOToolsPasswordPolicy]]::new()
        $this.Accounts = [System.Collections.Generic.Dictionary[string, GPOToolsPasswordAccount]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $this.DomainPolicy = [GPOToolsPasswordPolicy]::NewDefault()
        $this.DomainPolicy.Name = 'Default domain password policy'
        $this.DomainPolicy.IsDefault = $true
        $this.DomainPolicy.CanEdit = $false
    }

    # A PSO applied to this group reaches its members.
    [bool] PassesPasswordPolicy([GPOToolsPasswordAccount]$Group) {
        if ($Group.Kind -ne 'Group' -or -not $Group.IsSecurityGroup) { return $false }
        if ($this.GroupRule -eq 'Security') { return -not $Group.IsBuiltin }
        return $Group.GroupScope -eq 'Global'
    }

    [string] GetContainer() {
        return "CN=Password Settings Container,CN=System,$($this.DomainDistinguishedName)"
    }

    [GPOToolsPasswordPolicy] FindPolicy([string]$Name) {
        foreach ($Policy in $this.Policies) {
            if ([string]::Equals($Policy.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) { return $Policy }
        }
        return $null
    }

    [void] SortPolicies() {
        $this.Policies.Sort([System.Comparison[GPOToolsPasswordPolicy]] { param($A, $B) [GPOToolsPasswordPolicy]::Compare($A, $B) })
    }

    # Reads the policies again from where they come from (nothing to read in memory).
    [void] Refresh() {}

    # Creates a PSO: its settings and the users and groups it applies to (AppliesTo).
    [GPOToolsPasswordPolicy] NewPolicy([GPOToolsPasswordPolicy]$Policy) {
        if (-not $this.CanCreate) { throw "The account $($this.Account) cannot create password settings objects in $($this.DomainName)." }
        $Problems = @(Test-PSGPOPasswordPolicy -Policy $Policy)
        if ($Problems.Count) { throw ($Problems -join ' ') }
        if ($this.FindPolicy($Policy.Name)) { throw "A password settings object named '$($Policy.Name)' already exists in $($this.DomainName)." }
        $New = $Policy.Clone()
        $New.IsDefault = $false
        $New.CanEdit = $true
        $New.DistinguishedName = 'CN={0},{1}' -f (ConvertTo-PSGPODistinguishedNameValue -Value $New.Name), $this.GetContainer()
        $this.SaveNewPolicy($New)
        $this.Policies.Add($New)
        $this.SortPolicies()
        return $New
    }

    # Changes a PSO to the settings, name and subjects of $Changed.
    [GPOToolsPasswordPolicy] SetPolicy([GPOToolsPasswordPolicy]$Policy, [GPOToolsPasswordPolicy]$Changed) {
        if (-not $Policy.CanEdit) { throw "The account $($this.Account) cannot change the password settings object '$($Policy.Name)'." }
        $Problems = @(Test-PSGPOPasswordPolicy -Policy $Changed)
        if ($Problems.Count) { throw ($Problems -join ' ') }
        $Other = $this.FindPolicy($Changed.Name)
        if ($Other -and -not [object]::ReferenceEquals($Other, $Policy)) { throw "A password settings object named '$($Changed.Name)' already exists in $($this.DomainName)." }
        $DistinguishedName = $this.SavePolicy($Policy, $Changed)
        foreach ($Name in 'Name', 'Precedence', 'MinPasswordLength', 'PasswordHistoryCount', 'ComplexityEnabled', 'ReversibleEncryptionEnabled', 'MinPasswordAge',
            'MaxPasswordAge', 'LockoutThreshold', 'LockoutDuration', 'LockoutObservationWindow', 'Description', 'ProtectedFromAccidentalDeletion') {
            $Policy.$Name = $Changed.$Name
        }
        $Policy.DistinguishedName = $DistinguishedName
        $Policy.AppliesTo.Clear()
        $Policy.AppliesTo.AddRange([string[]]@($Changed.AppliesTo))
        $Policy.Modified = [datetime]::UtcNow
        $this.SortPolicies()
        return $Policy
    }

    # Deletes a PSO; one protected from accidental deletion is kept.
    [void] RemovePolicy([GPOToolsPasswordPolicy]$Policy) {
        if ($Policy.ProtectedFromAccidentalDeletion) {
            throw "The password settings object '$($Policy.Name)' is protected from accidental deletion: clear its protection first."
        }
        if (-not $Policy.CanEdit) { throw "The account $($this.Account) cannot delete the password settings object '$($Policy.Name)'." }
        $this.SaveRemovedPolicy($Policy)
        [void]$this.Policies.Remove($Policy)
    }

    # Applies a PSO to a user or a group, or no longer.
    [void] AddSubject([GPOToolsPasswordPolicy]$Policy, [GPOToolsPasswordAccount]$Account) {
        if ($Policy.AppliesDirectlyTo($Account.DistinguishedName)) { return }
        $Changed = $Policy.Clone()
        $Changed.AppliesTo.Add($Account.DistinguishedName)
        $this.SetPolicy($Policy, $Changed)
    }

    [void] RemoveSubject([GPOToolsPasswordPolicy]$Policy, [string]$DistinguishedName) {
        if (-not $Policy.AppliesDirectlyTo($DistinguishedName)) { return }
        $Changed = $Policy.Clone()
        $Changed.AppliesTo.Clear()
        $Changed.AppliesTo.AddRange([string[]]@($Policy.AppliesTo | Where-Object { -not [string]::Equals($_, $DistinguishedName, [System.StringComparison]::OrdinalIgnoreCase) }))
        $this.SetPolicy($Policy, $Changed)
    }

    # The users and groups whose name, account name or display name starts with $Text (all of
    # them with an empty text), by name.
    [GPOToolsPasswordAccount[]] FindAccounts([string]$Text) {
        $Found = foreach ($Item in $this.Accounts.Values) {
            if (-not $Text -or $Item.Name -like "$Text*" -or $Item.SamAccountName -like "$Text*") { $Item }
        }
        return [GPOToolsPasswordAccount[]]@($Found | Sort-Object Name)
    }

    # A user or a group by its distinguished name; $null when the domain has none.
    [GPOToolsPasswordAccount] GetAccount([string]$DistinguishedName) {
        $Item = $null
        if ($this.Accounts.TryGetValue($DistinguishedName, [ref]$Item)) { return $Item }
        return $null
    }

    # A user or a group by its distinguished name, its account name (DOMAIN\name too) or its name.
    [GPOToolsPasswordAccount] ResolveAccount([string]$Identity) {
        if ($Identity -match '^[A-Za-z]+=.+,(?i:DC)=') {
            $Found = $this.GetAccount($Identity)
            if (-not $Found) { throw "No user or group $Identity in $($this.DomainName)." }
            return $Found
        }
        $Name = ($Identity -split '\\')[-1]
        $Matching = @($this.FindAccounts($Name) | Where-Object { $_.SamAccountName -eq $Name -or $_.Name -eq $Name })
        $Exact = @($Matching | Where-Object SamAccountName -EQ $Name)
        # Found by a search: read again with its groups.
        if ($Exact.Count -eq 1) { return $this.GetAccount($Exact[0].DistinguishedName) }
        if ($Matching.Count -eq 1) { return $this.GetAccount($Matching[0].DistinguishedName) }
        if ($Matching.Count -gt 1) { throw "Several users or groups are named '$Identity' in $($this.DomainName): give the distinguished name." }
        throw "No user or group named '$Identity' in $($this.DomainName)."
    }

    # The PSO the domain controller applies to a user (msDS-ResultantPSO): its distinguished name,
    # '' for the policy of the domain; $null when there is no domain controller to ask (an [object]:
    # a [string] method would turn $null into '').
    [object] GetServerResultant([GPOToolsPasswordAccount]$Account) { return $null }

    # Writes the changes where the policies come from: nothing to write in memory.
    hidden [void] SaveNewPolicy([GPOToolsPasswordPolicy]$Policy) {
        if ($Policy.Id -eq [guid]::Empty) { $Policy.Id = [guid]::NewGuid() }
        $Policy.Modified = [datetime]::UtcNow
    }
    # Returns the distinguished name of the PSO once renamed.
    hidden [string] SavePolicy([GPOToolsPasswordPolicy]$Policy, [GPOToolsPasswordPolicy]$Changed) {
        return 'CN={0},{1}' -f (ConvertTo-PSGPODistinguishedNameValue -Value $Changed.Name), $this.GetContainer()
    }
    hidden [void] SaveRemovedPolicy([GPOToolsPasswordPolicy]$Policy) {}
}

# Fine-grained password policies read from a domain controller over LDAP (Connect-
# PSGPOPasswordPolicyStore); the changes are written there, and to the audit log of HGPM.
class GPOToolsLdapPasswordPolicyStore : GPOToolsPasswordPolicyStore {
    # Domain controller the policies are read from, and that the changes go to
    [string]$Server
    # 'Samba AD' or 'Active Directory' (Windows)
    [string]$ServerType
    # How to connect again, and the domain of the audit log: a directory without its GPOs
    hidden [GPOToolsLdapDirectory]$Directory

    GPOToolsLdapPasswordPolicyStore([GPOToolsLdapDirectory]$Directory) : base($Directory.DomainName) {
        $this.Directory = $Directory
        $this.DomainDistinguishedName = $Directory.Domain.DistinguishedName
        $this.Server = $Directory.Server
        $this.ServerType = $Directory.ServerType
        $this.Account = $Directory.Account
        $this.Source = $Directory.Source
        $this.GroupRule = if ($Directory.ServerType -eq 'Samba AD') { 'Security' } else { 'GlobalSecurity' }
    }

    [void] Refresh() {
        Read-PSGPODomainPasswordPolicy -Store $this
    }

    hidden [void] SaveNewPolicy([GPOToolsPasswordPolicy]$Policy) {
        New-PSGPODomainPasswordPolicy -Directory $this.Directory -Policy $Policy
        Write-PSGPOAuditEntry -Directory $this.Directory -Action 'NewPasswordPolicy' -Target $Policy.DistinguishedName -Details (Get-PSGPOPasswordPolicyAuditDetail -Policy $Policy)
    }

    hidden [string] SavePolicy([GPOToolsPasswordPolicy]$Policy, [GPOToolsPasswordPolicy]$Changed) {
        $DistinguishedName = Set-PSGPODomainPasswordPolicy -Directory $this.Directory -Policy $Policy -Changed $Changed
        Write-PSGPOAuditEntry -Directory $this.Directory -Action 'SetPasswordPolicy' -Target $DistinguishedName -Details (Get-PSGPOPasswordPolicyAuditDetail -Policy $Changed -Before $Policy)
        return $DistinguishedName
    }

    hidden [void] SaveRemovedPolicy([GPOToolsPasswordPolicy]$Policy) {
        Remove-PSGPODomainPasswordPolicy -Directory $this.Directory -Policy $Policy
        Write-PSGPOAuditEntry -Directory $this.Directory -Action 'RemovePasswordPolicy' -Target $Policy.DistinguishedName -Details @{ Name = $Policy.Name }
    }

    [GPOToolsPasswordAccount[]] FindAccounts([string]$Text) {
        $Connection = New-PSGPODirectoryConnection -Directory $this.Directory
        try { return [GPOToolsPasswordAccount[]]@(Find-PSGPODomainPasswordAccount -Connection $Connection -DomainDistinguishedName $this.DomainDistinguishedName -Text $Text) }
        finally { $Connection.Dispose() }
    }

    [GPOToolsPasswordAccount] GetAccount([string]$DistinguishedName) {
        $Connection = New-PSGPODirectoryConnection -Directory $this.Directory
        try { return Get-PSGPODomainPasswordAccount -Connection $Connection -DistinguishedName $DistinguishedName }
        finally { $Connection.Dispose() }
    }

    [object] GetServerResultant([GPOToolsPasswordAccount]$Account) {
        if ($Account.Kind -ne 'User') { return $null }
        $Connection = New-PSGPODirectoryConnection -Directory $this.Directory
        try { return Get-PSGPODomainResultantPasswordPolicy -Connection $Connection -DistinguishedName $Account.DistinguishedName }
        finally { $Connection.Dispose() }
    }
}
