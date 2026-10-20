#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Fine-grained password policies (PSO): the values of the directory, the checks of the settings,
# the PSO that applies to an account and why, the commands and the texts of Show-PSOManagerAvalonia;
# on the sample policies, in memory (PSGPOTools.Ldap.tests.ps1 writes them to a domain controller).
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'PasswordPolicy.sample.json'
        # A binary search entry, as Invoke-PSGPOLdapBinarySearch returns it.
        function New-BinaryEntry {
            param([string]$DistinguishedName, [hashtable]$Text, [hashtable]$Binary = @{})
            $values = @{}
            foreach ($name in $Text.Keys) { $values[$name] = @(foreach ($value in @($Text[$name])) { , [System.Text.Encoding]::UTF8.GetBytes([string]$value) }) }
            foreach ($name in $Binary.Keys) { $values[$name] = @(, [byte[]]$Binary[$name]) }
            [pscustomobject]@{ DistinguishedName = $DistinguishedName; Values = $values }
        }
    }

    Describe 'Values of the directory' {
        It 'Reads and writes the durations, "never" included' {
            ConvertFrom-PSGPODirectoryInterval '-864000000000' | Should -Be ([TimeSpan]::FromDays(1))
            ConvertFrom-PSGPODirectoryInterval '-9223372036854775808' | Should -Be ([TimeSpan]::Zero)
            ConvertFrom-PSGPODirectoryInterval '0' | Should -Be ([TimeSpan]::Zero)
            ConvertFrom-PSGPODirectoryInterval '' | Should -Be ([TimeSpan]::Zero)
            ConvertTo-PSGPODirectoryInterval -Value ([TimeSpan]::FromMinutes(30)) | Should -Be '-18000000000'
            ConvertTo-PSGPODirectoryInterval -Value ([TimeSpan]::Zero) | Should -Be '0'
            ConvertTo-PSGPODirectoryInterval -Value ([TimeSpan]::Zero) -ZeroIsNever | Should -Be '-9223372036854775808'
        }

        It 'Escapes a name in a distinguished name' {
            ConvertTo-PSGPODistinguishedNameValue -Value 'PSO, Tier 1' | Should -Be 'PSO\, Tier 1'
            ConvertTo-PSGPODistinguishedNameValue -Value '#1 ' | Should -Be '\#1\ '
            ConvertTo-PSGPODistinguishedNameValue -Value 'a+b=c' | Should -Be 'a\+b\=c'
        }

        It 'Gives the values a PSO is written with' {
            $Policy = [GPOToolsPasswordPolicy]::NewDefault()
            $Policy.Precedence = 20
            $Policy.MaxPasswordAge = [TimeSpan]::Zero
            $Policy.AppliesTo.Add('CN=G,DC=x')
            $Values = Get-PSGPOPasswordPolicyValue -Policy $Policy
            $Values['msDS-PasswordSettingsPrecedence'] | Should -Be '20'
            $Values['msDS-PasswordComplexityEnabled'] | Should -Be 'TRUE'
            $Values['msDS-PasswordReversibleEncryptionEnabled'] | Should -Be 'FALSE'
            $Values['msDS-MaximumPasswordAge'] | Should -Be '-9223372036854775808'
            $Values['msDS-MinimumPasswordAge'] | Should -Be '-864000000000'
            $Values['msDS-PSOAppliesTo'] | Should -Be @('CN=G,DC=x')
        }

        It 'Reads a PSO of the directory: its settings, rights, subjects and protection' {
            $Descriptor = [GPOToolsSecurityDescriptor]::new()
            $Descriptor.Owner = 'S-1-5-32-544'
            $Descriptor.Group = 'S-1-5-32-544'
            $Descriptor.Control = [GPOToolsSecurityDescriptor]::DaclPresent -bor [GPOToolsSecurityDescriptor]::SelfRelative
            $Descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, 0, 0xF01FF, 'S-1-5-32-544', [guid]::Empty))
            $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDenied, 0, 0x10040, 'S-1-1-0', [guid]::Empty))
            $Id = [guid]'0a6f3c51-7d2e-4b8a-9c41-1f0e2d3c4b99'
            $Entry = New-BinaryEntry -DistinguishedName 'CN=PSO - T1,CN=Password Settings Container,CN=System,DC=contoso,DC=com' -Text @{
                name = 'PSO - T1'; 'msDS-PasswordSettingsPrecedence' = '20'; 'msDS-MinimumPasswordLength' = '16'; 'msDS-PasswordHistoryLength' = '24'
                'msDS-PasswordComplexityEnabled' = 'TRUE'; 'msDS-PasswordReversibleEncryptionEnabled' = 'FALSE'; 'msDS-MinimumPasswordAge' = '-864000000000'
                'msDS-MaximumPasswordAge' = '-9223372036854775808'; 'msDS-LockoutThreshold' = '10'; 'msDS-LockoutDuration' = '-9223372036854775808'
                'msDS-LockoutObservationWindow' = '-18000000000'; description = 'Servers'
                'msDS-PSOAppliesTo' = @('CN=A,DC=contoso,DC=com', 'CN=B,DC=contoso,DC=com')
                allowedAttributesEffective = @('description', 'msDS-PasswordSettingsPrecedence'); whenChanged = '20261020101500.0Z'
            } -Binary @{ objectGUID = $Id.ToByteArray(); nTSecurityDescriptor = $Descriptor.ToBytes() }
            $Policy = ConvertTo-PSGPOPasswordPolicy -Entry $Entry -EffectiveRights
            $Policy.Name | Should -Be 'PSO - T1'
            $Policy.Id | Should -Be $Id
            $Policy.Precedence | Should -Be 20
            $Policy.MinPasswordLength | Should -Be 16
            $Policy.MaxPasswordAge | Should -Be ([TimeSpan]::Zero) -Because 'the passwords never expire'
            $Policy.LockoutDuration | Should -Be ([TimeSpan]::Zero) -Because 'locked out until an administrator unlocks the account'
            $Policy.LockoutObservationWindow | Should -Be ([TimeSpan]::FromMinutes(30))
            $Policy.AppliesTo | Should -Be @('CN=A,DC=contoso,DC=com', 'CN=B,DC=contoso,DC=com')
            $Policy.CanEdit | Should -BeTrue
            $Policy.ProtectedFromAccidentalDeletion | Should -BeTrue
            $Policy.Modified | Should -Be ([datetime]::new(2026, 10, 20, 10, 15, 0, [System.DateTimeKind]::Utc))
            $Policy.DirectoryValues['msDS-MaximumPasswordAge'] | Should -Be '-9223372036854775808' -Because 'a change removes the value read'

            $Entry.Values['allowedAttributesEffective'] = @(, [System.Text.Encoding]::UTF8.GetBytes('description'))
            $Entry.Values.Remove('nTSecurityDescriptor')
            $Read = ConvertTo-PSGPOPasswordPolicy -Entry $Entry -EffectiveRights
            $Read.CanEdit | Should -BeFalse
            $Read.ProtectedFromAccidentalDeletion | Should -BeFalse
        }

        It 'Reads the password policy of the domain from its domain object' {
            $Entry = [pscustomobject]@{ DistinguishedName = 'DC=contoso,DC=com'; Attributes = @{
                    minPwdLength = @('14'); pwdHistoryLength = @('24'); pwdProperties = @('17'); minPwdAge = @('-864000000000'); maxPwdAge = @('-311040000000000')
                    lockoutThreshold = @('0'); lockoutDuration = @('-18000000000'); lockOutObservationWindow = @('-18000000000') } }
            $Policy = ConvertTo-PSGPODomainPasswordPolicy -Entry $Entry
            $Policy.IsDefault | Should -BeTrue
            $Policy.MinPasswordLength | Should -Be 14
            $Policy.ComplexityEnabled | Should -BeTrue
            $Policy.ReversibleEncryptionEnabled | Should -BeTrue
            $Policy.MaxPasswordAge | Should -Be ([TimeSpan]::FromDays(360))
        }
    }

    Describe 'Checks of the settings' {
        BeforeEach {
            $Policy = [GPOToolsPasswordPolicy]::NewDefault()
            $Policy.Name = 'PSO'
            $Policy.Precedence = 1
        }

        It 'Accepts the settings of a new PSO of the Administrative Center' {
            @(Test-PSGPOPasswordPolicy -Policy $Policy) | Should -BeNullOrEmpty
        }

        It 'Refuses <Case>' -ForEach @(
            @{ Case = 'a PSO without name'; Change = { $Policy.Name = ' ' }; Message = 'The name is required.' }
            @{ Case = 'a precedence of 0'; Change = { $Policy.Precedence = 0 }; Message = 'The precedence is a number of 1 or more.' }
            @{ Case = 'a length of 256'; Change = { $Policy.MinPasswordLength = 256 }; Message = 'The minimum password length is between 0 and 255 characters.' }
            @{ Case = 'a history of 1025'; Change = { $Policy.PasswordHistoryCount = 1025 }; Message = 'The password history is between 0 and 1024 passwords.' }
            @{ Case = 'a minimum age as long as the maximum'; Change = { $Policy.MinPasswordAge = $Policy.MaxPasswordAge }; Message = 'The minimum password age is shorter than the maximum password age.' }
            @{ Case = 'a reset after more than the lockout'; Change = { $Policy.LockoutThreshold = 5; $Policy.LockoutObservationWindow = [TimeSpan]::FromMinutes(60) }; Message = 'The failed logon attempts count is reset after a time no longer than the lockout duration.' }
            @{ Case = 'a lockout without reset'; Change = { $Policy.LockoutThreshold = 5; $Policy.LockoutObservationWindow = [TimeSpan]::Zero }; Message = 'With a lockout, the failed logon attempts count is reset after one minute or more.' }
            @{ Case = 'a negative duration'; Change = { $Policy.MinPasswordAge = [TimeSpan]::FromDays(-1) }; Message = 'A duration cannot be negative.' }
        ) {
            & $Change
            @(Test-PSGPOPasswordPolicy -Policy $Policy) | Should -Contain $Message
        }

        It 'Accepts a password that never expires, and a lockout until an administrator unlocks the account' {
            $Policy.MaxPasswordAge = [TimeSpan]::Zero
            $Policy.MinPasswordAge = [TimeSpan]::FromDays(5)
            $Policy.LockoutThreshold = 5
            $Policy.LockoutDuration = [TimeSpan]::Zero
            $Policy.LockoutObservationWindow = [TimeSpan]::FromDays(1)
            @(Test-PSGPOPasswordPolicy -Policy $Policy) | Should -BeNullOrEmpty
        }

        It 'Says it in the language of the interface' {
            $Policy.Name = ''
            try {
                $null = Set-PSGPOLanguage -Language 'fr-FR'
                @(Test-PSGPOPasswordPolicy -Policy $Policy -Localized) | Should -Be @('Le nom est obligatoire.')
            } finally { $null = Set-PSGPOLanguage -Language 'en-US' }
        }
    }

    Describe 'The PSO that applies' {
        BeforeEach { $Store = Import-PSGPOPasswordPolicyStore -Path $SamplePath }

        It 'Applies the PSO of the group of a user' {
            $Result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('amartin')
            $Result.AppliedPolicy | Should -Be 'PSO - Tier 0 Admins'
            $Result.Source | Should -Be 'Computed' -Because 'no domain controller to ask in memory'
            $Result.Settings.MinPasswordLength | Should -Be 20
            $Result.Candidates.Name | Should -Be @('PSO - Tier 0 Admins', 'Default domain password policy')
            $Result.Candidates.Status | Should -Be @('Applied', 'LowerPriority')
        }

        It 'Takes the lowest precedence, through nested groups too' {
            $Result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('bdurand')
            $Result.AppliedPolicy | Should -Be 'PSO - Tier 1 Admins'
            $It50 = $Result.Candidates | Where-Object Name -EQ 'PSO - IT Staff'
            $It50.AppliesThrough | Should -Be @('Tier 1 Admins > IT Staff')
            $It50.Status | Should -Be 'LowerPriority'
        }

        It 'Ignores a domain local group, whatever its precedence (Windows)' {
            $Result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('jdupont')
            $Result.AppliedPolicy | Should -Be 'Default domain password policy'
            $Vpn = $Result.Candidates | Where-Object Name -EQ 'PSO - VPN Users'
            $Vpn.Status | Should -Be 'GroupIgnored'
            $Vpn.IgnoredGroups | Should -Be @('VPN Users')
            $Vpn.Reason | Should -BeLike '*only global security groups do*'
        }

        It 'Lets a domain local group pass its PSO on with Samba AD' {
            $Store.GroupRule = 'Security'
            $Result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('jdupont')
            $Result.AppliedPolicy | Should -Be 'PSO - VPN Users'
            (Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('bdurand')).AppliedPolicy | Should -Be 'PSO - VPN Users' -Because 'precedence 5 wins once its group counts'
        }

        It 'Prefers a PSO applied directly to the user to those of its groups' {
            $Result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('svc-backup')
            $Result.AppliedPolicy | Should -Be 'PSO - Backup account'
            ($Result.Candidates | Where-Object Name -EQ 'PSO - Service Accounts').Status | Should -Be 'DirectWins'
            ($Result.Candidates | Where-Object Name -EQ 'PSO - Backup account').AppliesThrough | Should -Be @('Direct')
        }

        It 'Breaks a tie of precedence with the smallest GUID' {
            $T1 = $Store.FindPolicy('PSO - Tier 1 Admins')
            $It = $Store.FindPolicy('PSO - IT Staff')
            $It.Precedence = $T1.Precedence
            $Store.SortPolicies()
            (Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('bdurand')).AppliedPolicy | Should -Be 'PSO - Tier 1 Admins' -Because '...4b02 is smaller than ...4b05'
            $It.Id = [guid]'00000000-0000-0000-0000-000000000001'
            (Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('bdurand')).AppliedPolicy | Should -Be 'PSO - IT Staff'
        }

        It 'Gives a group the PSO its members get through it' {
            $Result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('T1-Admins')
            $Result.Kind | Should -Be 'Group'
            $Result.AppliedPolicy | Should -Be 'PSO - Tier 1 Admins'
            ($Result.Candidates | Where-Object Name -EQ 'PSO - IT Staff').Status | Should -Be 'LowerPriority' -Because 'for its members, both reach them through groups'
            (Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('VPN-Users')).AppliedPolicy | Should -Be 'Default domain password policy'
        }

        It 'Keeps the answer of the domain controller, and says when it differs' {
            $Account = $Store.ResolveAccount('amartin')
            $Other = $Store.FindPolicy('PSO - IT Staff')
            $Store | Add-Member -MemberType ScriptMethod -Name GetServerResultant -Value { param($Account) 'CN=PSO - IT Staff,CN=Password Settings Container,CN=System,DC=corp,DC=contoso,DC=com' } -Force
            $Result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Account
            $Result.Source | Should -Be 'DomainController'
            $Result.AppliedPolicy | Should -Be $Other.Name
            $Result.ComputedPolicy | Should -Be 'PSO - Tier 0 Admins'
            $Result.Differs | Should -BeTrue
        }
    }

    Describe 'Policies of a store in memory' {
        BeforeEach { $Store = Import-PSGPOPasswordPolicyStore -Path $SamplePath }

        It 'Creates a PSO in the container, once checked, with a name of its own' {
            $Policy = [GPOToolsPasswordPolicy]::NewDefault()
            $Policy.Name = 'PSO, new'
            $Policy.Precedence = 1
            $New = $Store.NewPolicy($Policy)
            $New.DistinguishedName | Should -Be 'CN=PSO\, new,CN=Password Settings Container,CN=System,DC=corp,DC=contoso,DC=com'
            $New.Id | Should -Not -Be ([guid]::Empty)
            $Store.Policies[0].Name | Should -Be 'PSO, new' -Because 'the list is by order of priority'
            { $Store.NewPolicy($Policy) } | Should -Throw -ExpectedMessage '*already exists*'
            $Policy.Name = 'Other'; $Policy.Precedence = 0
            { $Store.NewPolicy($Policy) } | Should -Throw -ExpectedMessage '*precedence*'
            $Store.CanCreate = $false
            $Policy.Precedence = 3
            { $Store.NewPolicy($Policy) } | Should -Throw -ExpectedMessage '*cannot create*'
        }

        It 'Changes, renames and applies a PSO, and keeps one protected from deletion' {
            $Policy = $Store.FindPolicy('PSO - Tier 0 Admins')
            $Changed = $Policy.Clone()
            $Changed.Name = 'PSO - T0'
            $Changed.MinPasswordLength = 24
            $null = $Store.SetPolicy($Policy, $Changed)
            $Policy.Name | Should -Be 'PSO - T0'
            $Policy.DistinguishedName | Should -BeLike 'CN=PSO - T0,CN=Password Settings Container,*'
            $Store.AddSubject($Policy, $Store.ResolveAccount('jdupont'))
            $Policy.AppliesTo.Count | Should -Be 2
            $Store.RemoveSubject($Policy, $Store.ResolveAccount('T0-Admins').DistinguishedName)
            $Policy.AppliesTo | Should -Be @($Store.ResolveAccount('jdupont').DistinguishedName)
            { $Store.RemovePolicy($Policy) } | Should -Throw -ExpectedMessage '*protected from accidental deletion*'
            $Unprotected = $Policy.Clone(); $Unprotected.ProtectedFromAccidentalDeletion = $false
            $null = $Store.SetPolicy($Policy, $Unprotected)
            $Store.RemovePolicy($Policy)
            $Store.FindPolicy('PSO - T0') | Should -BeNullOrEmpty
        }

        It 'Finds a user or a group by name, account name or distinguished name' {
            $Store.ResolveAccount('CORP\amartin').Name | Should -Be 'Alice Martin'
            $Store.ResolveAccount('Alice Martin').SamAccountName | Should -Be 'amartin'
            $Store.ResolveAccount($Store.ResolveAccount('IT-Staff').DistinguishedName).Name | Should -Be 'IT Staff'
            { $Store.ResolveAccount('nobody') } | Should -Throw -ExpectedMessage "*No user or group named 'nobody'*"
            @($Store.FindAccounts('Tier')).Count | Should -Be 3
        }

        It 'Keeps in the audit log what a change changed' {
            $Policy = $Store.FindPolicy('PSO - Tier 2 Admins')
            $Changed = $Policy.Clone()
            $Changed.MinPasswordLength = 15
            $Changed.AppliesTo.Add('CN=X,DC=corp')
            $Details = Get-PSGPOPasswordPolicyAuditDetail -Policy $Changed -Before $Policy
            $Details.Keys | Should -Be @('Name', 'MinPasswordLength', 'AddedSubjects')
            $Details.MinPasswordLength.Before | Should -Be 14
            $Details.MinPasswordLength.After | Should -Be 15
        }
    }

    Describe 'Commands' {
        BeforeEach {
            $script:Store = Import-PSGPOPasswordPolicyStore -Path $SamplePath
            Mock Connect-PSGPOPasswordPolicyStore { $script:Store }
        }

        It 'Lists the PSOs by order of priority, and the password policy of the domain' {
            $All = @(Get-PSGPOFineGrainedPasswordPolicy)
            $All.Count | Should -Be 7
            $All[0].Name | Should -Be 'PSO - VPN Users'
            $All[0].PSObject.TypeNames[0] | Should -Be 'PSGPOTools.FineGrainedPasswordPolicy'
            @(Get-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier*').Count | Should -Be 3
            $Default = Get-PSGPODefaultPasswordPolicy
            $Default.MinPasswordLength | Should -Be 7
            $Default.PSObject.Properties.Name | Should -Not -Contain 'Precedence'
        }

        It 'Creates a PSO with the settings of the Administrative Center, and applies it' {
            $New = New-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Helpdesk' -Precedence 25 -MinPasswordLength 12 -MaxPasswordAge 90.00:00:00 -AppliesTo 'jdupont', 'IT-Staff' -Confirm:$false
            $New.PasswordHistoryCount | Should -Be 24
            $New.ComplexityEnabled | Should -BeTrue
            $New.ProtectedFromAccidentalDeletion | Should -BeTrue
            $New.MaxPasswordAge | Should -Be ([TimeSpan]::FromDays(90))
            $New.AppliesTo.Count | Should -Be 2
            (Get-PSGPOResultantPasswordPolicy -Identity jdupont).AppliedPolicy | Should -Be 'PSO - Helpdesk'
        }

        It 'Changes only what -WhatIf does not stop' {
            $null = Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 2 Admins' -MinPasswordLength 18 -WhatIf
            $script:Store.FindPolicy('PSO - Tier 2 Admins').MinPasswordLength | Should -Be 14
            $null = New-PSGPOFineGrainedPasswordPolicy -Name 'X' -Precedence 1 -WhatIf
            $script:Store.FindPolicy('X') | Should -BeNullOrEmpty
        }

        It 'Changes, renames, applies and deletes PSOs' {
            $Set = Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 2 Admins' -NewName 'PSO - T2' -LockoutDuration 0 -ProtectedFromAccidentalDeletion $false -Confirm:$false
            $Set.Name | Should -Be 'PSO - T2'
            $Set.LockoutDuration | Should -Be ([TimeSpan]::Zero)
            $Set.LockoutThreshold | Should -Be 10 -Because 'what is not given does not change'
            (Add-PSGPOFineGrainedPasswordPolicySubject -Name 'PSO - T2' -Subject 'jdupont' -Confirm:$false).AppliesTo.Count | Should -Be 2
            (Remove-PSGPOFineGrainedPasswordPolicySubject -Name 'PSO - T2' -Subject 'T2-Admins' -Confirm:$false).AppliesTo.Count | Should -Be 1
            Remove-PSGPOFineGrainedPasswordPolicy -Name 'PSO - T2' -Confirm:$false
            $script:Store.FindPolicy('PSO - T2') | Should -BeNullOrEmpty
            Remove-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 0 Admins' -Confirm:$false -ErrorVariable Problem -ErrorAction SilentlyContinue
            "$Problem" | Should -BeLike '*protected from accidental deletion*'
            Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Nothing' -MinPasswordLength 1 -Confirm:$false -ErrorVariable Missing -ErrorAction SilentlyContinue
            "$Missing" | Should -BeLike "*No password settings object named 'PSO - Nothing'*"
        }

        It 'Tells which PSO applies to a user, and why the others do not' {
            $Result = Get-PSGPOResultantPasswordPolicy -Identity bdurand
            $Result.PSObject.TypeNames[0] | Should -Be 'PSGPOTools.ResultantPasswordPolicy'
            $Result.AppliedPolicy | Should -Be 'PSO - Tier 1 Admins'
            $Result.Settings.MinPasswordLength | Should -Be 16
            $Result.Candidates.Status | Should -Be @('GroupIgnored', 'Applied', 'LowerPriority', 'LowerPriority')
            $Result.Candidates[0].PSObject.Properties.Name | Should -Not -Contain 'Policy'
            Get-PSGPOResultantPasswordPolicy -Identity nobody -ErrorVariable Problem -ErrorAction SilentlyContinue
            "$Problem" | Should -BeLike '*No user or group*'
        }
    }

    Describe 'Texts of the PSO Manager' {
        AfterEach { $null = Set-PSGPOLanguage -Language 'en-US' }

        It 'Shows the settings of a PSO, singular and "never" included' {
            $Policy = [GPOToolsPasswordPolicy]::NewDefault()
            $Policy.Precedence = 3
            $Policy.MaxPasswordAge = [TimeSpan]::Zero
            $Policy.LockoutThreshold = 5
            $Policy.LockoutDuration = [TimeSpan]::Zero
            $Rows = @(Get-PSGPOPasswordPolicySettingRow -Policy $Policy)
            ($Rows | Where-Object Key -EQ 'Minimum password age').Value | Should -Be '1 day'
            ($Rows | Where-Object Key -EQ 'Maximum password age').Value | Should -Be 'The password never expires'
            ($Rows | Where-Object Key -EQ 'Account will be locked out').Value | Should -Be 'Until an administrator manually unlocks the account'
            Get-PSGPOPasswordPolicySummary -Policy $Policy | Should -Be '7 characters, history 24, never expires, locked out after 5 attempts'
            $null = Set-PSGPOLanguage -Language 'fr-FR'
            $Rows = @(Get-PSGPOPasswordPolicySettingRow -Policy $Policy)
            ($Rows | Where-Object Key -EQ 'Longueur minimale du mot de passe').Value | Should -Be '7 caractères'
            ($Rows | Where-Object Key -EQ 'Priorité').Value | Should -Be '3'
        }

        It 'Says what a group is, and why a PSO does not apply' {
            $Store = Import-PSGPOPasswordPolicyStore -Path $SamplePath
            Get-PSGPOPasswordAccountKindText -Account $Store.ResolveAccount('VPN-Users') | Should -Be 'Domain local security group'
            Get-PSGPOPasswordAccountKindText -Account $Store.ResolveAccount('amartin') | Should -Be 'User'
            $Result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Store.ResolveAccount('bdurand')
            $Rows = @(foreach ($Candidate in $Result.Candidates) { ConvertTo-PSGPOPasswordCandidateRow -Candidate $Candidate -Result $Result -Store $Store })
            $Rows[0].Status | Should -Be 'Ignored'
            $Rows[0].Through | Should -Be 'Through VPN Users'
            $Rows[1].IsApplied | Should -BeTrue
            $Rows[2].Reason | Should -Be 'Not applied: PSO - Tier 1 Admins comes first (a lower precedence, or the same one and a smaller GUID).'
            $Rows[3].Name | Should -Be 'Default domain password policy'
            $null = Set-PSGPOLanguage -Language 'fr-FR'
            (ConvertTo-PSGPOPasswordCandidateRow -Candidate $Result.Candidates[0] -Result $Result -Store $Store).Reason |
                Should -Be 'Non appliqué : VPN Users ne transmet pas de paramètres de mot de passe. Seuls les groupes de sécurité globaux le font.'
        }
    }
}
