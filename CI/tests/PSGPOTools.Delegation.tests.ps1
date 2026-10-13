#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# What the account of the console manages (RBAC), from the delegations of the domain: the
# attributes it may write (allowedAttributesEffective) on the domain, the OUs and the GPOs, and
# the classes it may create in CN=Policies. A technician sees the OUs where it links GPOs, their
# parents as the path to them, and the GPOs it edits or that are linked to its OUs.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')

        # The domain of the fixture as a technician of Lyon\Workstations reads it: it links GPOs
        # to Workstations and Laptops below it, and edits no GPO but the second "Workstations".
        function New-DelegatedDirectory {
            param([switch]$CanCreateGpo)
            $Set = Get-TestLdapEntrySet
            $Rights = @{
                "OU=Workstations,OU=Lyon,$TestLdapDomainDN" = @('gPLink', 'gPOptions', 'description')
                "OU=Laptops,OU=Workstations,OU=Lyon,$TestLdapDomainDN" = @('gPLink', 'gPOptions')
                "OU=Lyon,$TestLdapDomainDN" = @('description')
                "CN={8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E31},CN=Policies,CN=System,$TestLdapDomainDN" = @('versionNumber', 'displayName')
            }
            foreach ($Entry in @($Set.Domain) + $Set.Ous + $Set.Gpos) {
                if ($Rights.ContainsKey($Entry.DistinguishedName)) { $Entry.Attributes['allowedattributeseffective'] = [string[]]$Rights[$Entry.DistinguishedName] }
            }
            $Classes = if ($CanCreateGpo) { @('groupPolicyContainer', 'container') } else { @('container') }
            $Policies = New-TestLdapEntry "CN=Policies,CN=System,$TestLdapDomainDN" @{ allowedChildClassesEffective = $Classes }
            $Directory = ConvertTo-PSGPOLdapDirectory -Server 'dc.hardenbox.labo' -VendorName 'Samba Team' -DomainEntry $Set.Domain `
                -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos -PoliciesEntry $Policies -EffectiveRights 3>$null
            $Directory.Account = 'HARDENBOX\tier2'
            $Directory
        }
        function Get-Node {
            param($Roots, [string[]]$Path)
            $Node = @($Roots)[0]
            foreach ($Header in $Path) {
                $Node = $Node.Children | Where-Object { $_.Header -eq $Header -or $_.Header -like "$Header (*" } | Select-Object -First 1
                if (-not $Node) { return $null }
            }
            $Node
        }
        function Get-Row { param($Detail, [string]$Key) ($Detail.Properties | Where-Object Key -EQ $Key).Value }
    }

    Describe 'Rights of the account read with the directory' {
        It 'Reads the rights from the attributes the account may write' {
            $Directory = New-DelegatedDirectory
            $Directory.Domain.CanLink | Should -BeFalse
            $Directory.FindSom("OU=Workstations,OU=Lyon,$TestLdapDomainDN").CanLink | Should -BeTrue
            $Directory.FindSom("OU=Laptops,OU=Workstations,OU=Lyon,$TestLdapDomainDN").CanLink | Should -BeTrue
            $Directory.FindSom("OU=Lyon,$TestLdapDomainDN").CanLink | Should -BeFalse -Because 'it may write its description, not its gPLink'
            $Directory.FindSom("OU=Domain Controllers,$TestLdapDomainDN").CanLink | Should -BeFalse
            @($Directory.Gpos | Where-Object CanEdit).Id | Should -Be @([guid]'8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E31')
            $Directory.CanCreateGpo | Should -BeFalse
            $Directory.IsLimited() | Should -BeTrue
            (New-DelegatedDirectory -CanCreateGpo).CanCreateGpo | Should -BeTrue
        }

        It 'Gives every right when the rights were not read' {
            $Directory = New-TestLdapDirectory
            $Directory.Domain.CanLink | Should -BeTrue
            @($Directory.Gpos | Where-Object { -not $_.CanEdit }) | Should -BeNullOrEmpty
            $Directory.CanCreateGpo | Should -BeTrue
            $Directory.IsLimited() | Should -BeFalse
        }

        It 'Names the account from the answer to "Who am I?"' {
            ConvertFrom-PSGPOLdapAuthzId -Value 'u:HARDENBOX\tier1' | Should -Be 'HARDENBOX\tier1'
            ConvertFrom-PSGPOLdapAuthzId -Value 'dn:CN=tier1,OU=Groups,OU=Tier 1,DC=hardenbox,DC=labo' | Should -Be 'CN=tier1,OU=Groups,OU=Tier 1,DC=hardenbox,DC=labo'
            ConvertFrom-PSGPOLdapAuthzId -Value '' | Should -Be 'Anonymous'
        }
    }

    Describe 'What a delegated account sees' {
        BeforeAll {
            $Directory = New-DelegatedDirectory
            $Roots = New-PSGPODirectoryTree -Directory $Directory
        }

        It 'Shows the OUs it manages with the path to them, and hides the others' {
            $Domain = @($Roots)[0]
            # The domain: no link shown, only the path to Lyon, and the GPO container.
            @($Domain.Children.Header) | Should -Be @('Lyon', 'Group Policy Objects')
            $Lyon = Get-Node $Roots 'Lyon'
            $Lyon.IconBrush | Should -Be '#8A8886' -Because 'it is only the path to the OUs it manages'
            @($Lyon.Children.Header) | Should -Be @('Workstations (blocks inheritance)')
            $Workstations = Get-Node $Roots 'Lyon', 'Workstations'
            $Workstations.IconBrush | Should -Not -Be '#8A8886'
            @($Workstations.Children | Where-Object { $_.Tag -is [GPOToolsGpoLink] }).Count | Should -Be 2 -Because 'its links are shown'
            Get-Node $Roots 'Lyon', 'Workstations', 'Laptops' | Should -Not -BeNullOrEmpty
        }

        It 'Shows the GPOs it edits or that are linked to its OUs' {
            $Gpos = (Get-Node $Roots 'Group Policy Objects').Children
            # The two "Workstations": the first is linked to Workstations, the second is edited.
            @($Gpos.Header) | Should -Be @('Workstations', 'Workstations')
            @($Gpos.Tag.CanEdit | Sort-Object) | Should -Be @($false, $true)
            @((Get-PSGPODirectoryDetail -Directory $Directory -Item 'GroupPolicyObjects').Properties.Key) | Should -Be @('Workstations', 'Workstations')
        }

        It 'Says with which account and which rights' {
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Directory.Domain
            Get-Row $Detail 'Connected as' | Should -Be 'HARDENBOX\tier2'
            Get-Row $Detail 'Delegation' | Should -BeLike 'Limited*'
            $Detail.LinksHeader | Should -BeLike '*not shown, no delegation here'
            $Detail.Links | Should -BeNullOrEmpty
            Get-Row (Get-PSGPODirectoryDetail -Directory $Directory -Item $Directory.FindSom("OU=Lyon,$TestLdapDomainDN")) 'Your rights' | Should -BeLike 'None*'
            Get-Row (Get-PSGPODirectoryDetail -Directory $Directory -Item $Directory.FindSom("OU=Workstations,OU=Lyon,$TestLdapDomainDN")) 'Your rights' | Should -Be 'Link GPOs'
            $ReadOnly = $Directory.Gpos | Where-Object { $_.DisplayName -eq 'Workstations' -and -not $_.CanEdit }
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $ReadOnly
            @($Detail.Properties.Key)[0..2] | Should -Be @('Unique ID', 'GPO status', 'Your rights')
            Get-Row $Detail 'Your rights' | Should -Be 'Read only'

            $Item = @(Get-PSGPOStatusBarItem -Platform ([GPOToolsPlatform]@{ OperatingSystem = 'Linux' }) -Directory $Directory) | Where-Object Text -Like 'Connected as*'
            $Item.Text | Should -Be 'Connected as HARDENBOX\tier2 (delegated rights)'
        }

        It 'Refuses what the account may not do, before asking the domain' {
            Mock Add-PSGPODomainGpLink { throw 'the domain was asked' }
            Mock New-PSGPODomainGpo { throw 'the domain was asked' }
            $Lyon = $Directory.FindSom("OU=Lyon,$TestLdapDomainDN")
            { $Directory.NewLink($Lyon, $Directory.Gpos[0]) } | Should -Throw -ExpectedMessage "*HARDENBOX\tier2 cannot link GPOs to Lyon*"
            { $Directory.NewGpo('T2 - New') } | Should -Throw -ExpectedMessage "*HARDENBOX\tier2 cannot create GPOs*"
            Should -Invoke Add-PSGPODomainGpLink -Times 0 -Exactly
            Should -Invoke New-PSGPODomainGpo -Times 0 -Exactly
        }
    }
}
