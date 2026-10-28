#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The well-known accounts (GPOToolsWellKnownSid): one table for the names shown and the names typed,
# in English and French; the accounts resolved by their name, *SID or SID, a well-known account of
# the domain by its RID when the domain names it in another language; the suggestions while typing
# and the completion of the parameters that take an account.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')
        $DomainSid = 'S-1-5-21-1111-2222-3333'
    }

    Describe 'Table of the well-known accounts' {
        It 'Has each SID once, and each name once for its authority' {
            $All = [GPOToolsWellKnownSid]::All
            @($All.Sid | Select-Object -Unique).Count | Should -Be $All.Count
            @($All | ForEach-Object { "$($_.Authority)\$($_.Name)" } | Select-Object -Unique).Count | Should -Be $All.Count
            foreach ($Entry in $All) {
                $Entry.Sid | Should -Match '^(S-1-\d+(-\d+)+|-\d+)$'
                $Entry.FrenchName | Should -Not -BeNullOrEmpty
            }
        }

        It 'Has the accounts every domain has, Key Admins and the RODC groups included' {
            foreach ($Rid in '-498', '-500', '-512', '-513', '-515', '-516', '-518', '-519', '-520', '-521', '-522', '-525', '-526', '-527', '-553', '-571', '-572') {
                [GPOToolsWellKnownSid]::All.Sid | Should -Contain $Rid
            }
        }

        It 'Names a SID as before: <Sid> is <Name>' -ForEach @(
            @{ Sid = '*S-1-5-32-544'; Name = 'BUILTIN\Administrators' }
            @{ Sid = '*S-1-5-11'; Name = 'NT AUTHORITY\Authenticated Users' }
            @{ Sid = '*S-1-1-0'; Name = 'Everyone' }
            @{ Sid = '*S-1-5-17'; Name = 'NT AUTHORITY\IUSR' }
            @{ Sid = '*S-1-5-80-0'; Name = 'NT SERVICE\ALL SERVICES' }
            @{ Sid = '*S-1-15-2-1'; Name = 'APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES' }
            @{ Sid = '*S-1-5-21-1111-2222-3333-512'; Name = 'Domain Admins' }
            @{ Sid = '*S-1-5-21-1111-2222-3333-526'; Name = 'Key Admins' }
            @{ Sid = '*S-1-5-21-1111-2222-3333-1105'; Name = 'S-1-5-21-1111-2222-3333-1105' }
            @{ Sid = 'CONTOSO\Tier1-Admins'; Name = 'CONTOSO\Tier1-Admins' }
        ) {
            [GPOToolsSecuritySetting]::FormatAccount($Sid) | Should -Be $Name
        }

        It 'Names the accounts of an ACL by their short name, and the migration tables the same' {
            [GPOToolsSecurityDescriptor]::WellKnownNames['S-1-5-11'] | Should -Be 'Authenticated Users'
            [GPOToolsSecurityDescriptor]::WellKnownNames['S-1-5-9'] | Should -Be 'ENTERPRISE DOMAIN CONTROLLERS'
            [GPOToolsSecurityDescriptor]::WellKnownNames.ContainsKey('-512') | Should -BeFalse
            $script:PSGPOWellKnownAccounts['S-1-5-32-555'] | Should -Be 'Remote Desktop Users'
            $script:PSGPOWellKnownAccounts['S-1-5-90-0'] | Should -Be 'Window Manager Group'
        }

        It 'Finds <Name> (domain accounts: <Domain>) as <Sid>' -ForEach @(
            @{ Name = 'Administrators'; Domain = $false; Sid = 'S-1-5-32-544' }
            @{ Name = 'BUILTIN\Administrateurs'; Domain = $false; Sid = 'S-1-5-32-544' }
            @{ Name = 'NT AUTHORITY\SYSTEM'; Domain = $false; Sid = 'S-1-5-18' }
            @{ Name = 'AUTORITE NT\Système'; Domain = $false; Sid = 'S-1-5-18' }
            @{ Name = 'utilisateurs authentifiés'; Domain = $false; Sid = 'S-1-5-11' }
            @{ Name = 'Tout le monde'; Domain = $false; Sid = 'S-1-1-0' }
            @{ Name = 'NT AUTHORITY\Users'; Domain = $false; Sid = $null }
            @{ Name = 'Domain Admins'; Domain = $false; Sid = $null }
            @{ Name = 'Domain Admins'; Domain = $true; Sid = '-512' }
            @{ Name = 'CONTOSO\Admins du domaine'; Domain = $true; Sid = '-512' }
            @{ Name = 'Contrôleurs de domaine'; Domain = $true; Sid = '-516' }
            @{ Name = 'Tier1-Admins'; Domain = $true; Sid = $null }
        ) {
            $Found = [GPOToolsWellKnownSid]::FindByName($Name, $Domain)
            if ($Sid) { $Found.Sid | Should -Be $Sid } else { $Found | Should -BeNullOrEmpty }
        }

        It 'Finds an account of a domain by its RID, and gives its SID in that domain' {
            $Found = [GPOToolsWellKnownSid]::FindBySid('*S-1-5-21-1111-2222-3333-519')
            $Found.Name | Should -Be 'Enterprise Admins'
            $Found.GetSid($DomainSid) | Should -Be "$DomainSid-519"
            $Found.GetSid($null) | Should -BeNullOrEmpty
            $Found.GetQualifiedName('CONTOSO') | Should -Be 'CONTOSO\Enterprise Admins'
            [GPOToolsWellKnownSid]::FindBySid('S-1-5-32-546').GetQualifiedName('CONTOSO') | Should -Be 'BUILTIN\Guests'
        }
    }

    Describe 'Accounts typed' {
        BeforeEach {
            $Directory = New-TestLdapDirectory
            Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
            # The domain names its groups in French: Domain Admins is not a sAMAccountName there. (The
            # SIDs written out: a mock does not see the variables of the tests.)
            Mock Invoke-PSGPOLdapBinarySearch {
                if ($Scope -eq 'Base') { return [pscustomobject]@{ DistinguishedName = $SearchBase; Values = @{ objectSid = @(, [GPOToolsSecurityDescriptor]::ConvertSidToBytes('S-1-5-21-1111-2222-3333')) } } }
                if ($Filter -eq '(sAMAccountName=Tier1-Admins)') { return [pscustomobject]@{ DistinguishedName = 'CN=Tier1-Admins'; Values = @{ objectSid = @(, [GPOToolsSecurityDescriptor]::ConvertSidToBytes('S-1-5-21-1111-2222-3333-1105')) } } }
            }
        }

        It 'Resolves <Name> to <Sid>' -ForEach @(
            @{ Name = 'Authenticated Users'; Sid = 'S-1-5-11'; Resolved = 'Authenticated Users' }
            @{ Name = 'Utilisateurs authentifiés'; Sid = 'S-1-5-11'; Resolved = 'Authenticated Users' }
            @{ Name = '*S-1-5-32-544'; Sid = 'S-1-5-32-544'; Resolved = 'Administrators' }
            @{ Name = 'CONTOSO\Tier1-Admins'; Sid = 'S-1-5-21-1111-2222-3333-1105'; Resolved = 'Tier1-Admins' }
            @{ Name = 'Domain Admins'; Sid = 'S-1-5-21-1111-2222-3333-512'; Resolved = 'Domain Admins' }
            @{ Name = '*S-1-5-21-1111-2222-3333-1105'; Sid = 'S-1-5-21-1111-2222-3333-1105'; Resolved = 'S-1-5-21-1111-2222-3333-1105' }
        ) {
            $Account = Resolve-PSGPOApplyTo -Directory $Directory -Name $Name
            $Account.Sid | Should -Be $Sid
            $Account.Name | Should -Be $Resolved
        }

        It 'Still refuses an account that is neither in the domain nor well known' {
            { Resolve-PSGPOApplyTo -Directory $Directory -Name 'Nobody' } | Should -Throw "No account named 'Nobody' in the domain."
        }
    }

    Describe 'Suggestions of the accounts' {
        AfterEach { $null = Set-PSGPOLanguage -Language 'en-US' }

        It 'Suggests the names that begin with the text first, written as their SID or their name' {
            $Rows = @(Get-PSGPOAccountSuggestion -Text 'admin' -Insert Sid -DomainSid $DomainSid)
            $Rows[0].Display | Should -Be 'BUILTIN\Administrators   S-1-5-32-544'
            @($Rows.Value) | Should -Contain '*S-1-5-32-544'
            @($Rows.Value) | Should -Contain "*$DomainSid-512"
            @(Get-PSGPOAccountSuggestion -Text 'S-1-5-32-55' -Insert Name).Value | Should -Be @('Print Operators', 'Backup Operators', 'Replicator', 'Pre-Windows 2000 Compatible Access', 'Remote Desktop Users', 'Network Configuration Operators', 'Incoming Forest Trust Builders', 'Performance Monitor Users', 'Performance Log Users')
        }

        It 'Suggests the groups of every computer only for a local group, as GPMC names them' {
            @(Get-PSGPOAccountSuggestion -Text 'admin' -Kind BuiltinGroup).Value | Should -Be @('Administrators (built-in)', 'Hyper-V Administrators (built-in)')
        }

        It 'Shows the names in the language of the interface, and finds the English ones too' {
            $null = Set-PSGPOLanguage -Language 'fr-FR'
            $Rows = @(Get-PSGPOAccountSuggestion -Text 'domain admins' -Insert Name -DomainSid $DomainSid)
            $Rows[0].Value | Should -Be 'Admins du domaine'
            $Rows[0].Display | Should -Be "Admins du domaine   $DomainSid-512"
        }

        It 'Adds the accounts of the domain, once' {
            $Directory = New-TestLdapDirectory
            Mock Find-PSGPOAccountSuggestion {
                [pscustomobject]@{ Name = 'Domain Admins'; Sid = "$DomainSid-512"; Kind = 'group' }
                [pscustomobject]@{ Name = 'Tier1-Admins'; Sid = "$DomainSid-1105"; Kind = 'group' }
            }
            $Rows = @(Get-PSGPOAccountSuggestion -Directory $Directory -Text 'ti' -Insert Sid -DomainSid $DomainSid)
            $Rows[-1].Display | Should -Be "HARDENBOX\Tier1-Admins   group, $DomainSid-1105"
            $Rows[-1].Value | Should -Be "*$DomainSid-1105"
            @($Rows | Where-Object Sid -EQ "$DomainSid-512").Count | Should -BeLessOrEqual 1
            Should -Invoke Find-PSGPOAccountSuggestion -Times 1 -Exactly
            # One character, or a SID: the domain is not searched.
            $null = @(Get-PSGPOAccountSuggestion -Directory $Directory -Text 't' -DomainSid $DomainSid)
            $null = @(Get-PSGPOAccountSuggestion -Directory $Directory -Text 'S-1-5-21' -DomainSid $DomainSid)
            Should -Invoke Find-PSGPOAccountSuggestion -Times 1 -Exactly
        }
    }

    Describe 'Completion of the parameters that take an account' {
        It 'Completes <Line> with <Expected>' -ForEach @(
            @{ Line = 'Approve-PSGPO -ApplyTo Auth'; Expected = "'Authenticated Users'" }
            @{ Line = 'Approve-PSGPO -DenyTo Domain'; Expected = "'Domain Admins'" }
            @{ Line = 'Set-PSGPOPermission -Account Admins'; Expected = "'Admins du domaine'" }
            @{ Line = "Set-PSGPOWmiFilterPermission -Account 'Tout"; Expected = "'Tout le monde'" }
        ) {
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            @($Completion.CompletionMatches.CompletionText) | Should -Contain $Expected
        }
    }
}
