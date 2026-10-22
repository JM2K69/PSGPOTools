#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# What the account of the console manages (RBAC), from the delegations of the domain: the
# attributes it may write (allowedAttributesEffective) on the domain, the OUs and the GPOs, and
# the classes it may create in CN=Policies. Every account sees the whole domain, as GPMC; what it
# does not manage is greyed and offers no action.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
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

    Describe 'What an account without delegation sees' {
        BeforeAll {
            $Set = Get-TestLdapEntrySet
            $Policies = New-TestLdapEntry "CN=Policies,CN=System,$TestLdapDomainDN" @{ allowedChildClassesEffective = @('container') }
            $Directory = ConvertTo-PSGPOLdapDirectory -Server 'dc.hardenbox.labo' -VendorName 'Samba Team' -DomainEntry $Set.Domain `
                -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos -PoliciesEntry $Policies -EffectiveRights 3>$null
            $Directory.Account = 'HARDENBOX\test.user'
            $Directory.CanCreateWmiFilter = $false
        }

        It 'Reads the whole domain, greyed, and says it changes nothing' {
            $Directory.HasDelegation() | Should -BeFalse
            $Roots = New-PSGPODirectoryTree -Directory $Directory
            @((Get-Node $Roots 'Group Policy Objects').Children.Tag) | Should -Be @($Directory.Gpos)
            Get-Node $Roots 'Lyon', 'Workstations' | Should -Not -BeNullOrEmpty
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Directory.Domain
            Get-Row $Detail 'Delegation' | Should -BeLike 'None: *reads the domain only'
            Get-Row $Detail 'Your rights' | Should -Be 'Read only'
            $Item = @(Get-PSGPOStatusBarItem -Platform ([GPOToolsPlatform]@{ OperatingSystem = 'Linux' }) -Directory $Directory) | Where-Object Text -Like 'Connected as*'
            $Item.Text | Should -Be 'Connected as HARDENBOX\test.user (read only)'
        }

        It 'Reads the rights on the WMI filters, and refuses the changes they do not give' {
            Mock Invoke-PSGPOLdapSearch -ParameterFilter { $Scope -eq 'Base' } {
                New-TestLdapEntry "CN=SOM,CN=WMIPolicy,CN=System,$TestLdapDomainDN" @{ allowedChildClassesEffective = @('container') }
            }
            Mock Invoke-PSGPOLdapSearch -ParameterFilter { $Scope -eq 'OneLevel' } {
                New-TestLdapEntry "CN={6C5B8B5E-3F5A-4C3E-9D4B-2A1B3C4D5E6F},CN=SOM,CN=WMIPolicy,CN=System,$TestLdapDomainDN" @{
                    'msWMI-ID' = '{6C5B8B5E-3F5A-4C3E-9D4B-2A1B3C4D5E6F}'; 'msWMI-Name' = 'Laptops'; 'msWMI-Parm2' = '1;3;10;27;WQL;root\CIMv2;SELECT * FROM Win32_Battery;'
                    allowedAttributesEffective = @('description') }
                New-TestLdapEntry "CN={7C5B8B5E-3F5A-4C3E-9D4B-2A1B3C4D5E6F},CN=SOM,CN=WMIPolicy,CN=System,$TestLdapDomainDN" @{
                    'msWMI-ID' = '{7C5B8B5E-3F5A-4C3E-9D4B-2A1B3C4D5E6F}'; 'msWMI-Name' = 'Servers'; 'msWMI-Parm2' = '1;3;10;57;WQL;root\CIMv2;SELECT * FROM Win32_OperatingSystem WHERE ProductType = 3;'
                    allowedAttributesEffective = @('msWMI-Name', 'msWMI-Parm1', 'msWMI-Parm2') }
            }
            Read-PSGPODomainWmiFilter -Connection ([pscustomobject]@{}) -Directory $Directory
            $Directory.CanCreateWmiFilter | Should -BeFalse
            $Directory.FindWmiFilter('Laptops').CanEdit | Should -BeFalse
            $Directory.FindWmiFilter('Servers').CanEdit | Should -BeTrue
            { $Directory.NewWmiFilter('Other', '', @([pscustomobject]@{ Query = 'SELECT * FROM Win32_Battery' })) } | Should -Throw -ExpectedMessage '*cannot create WMI filters*'
            $Laptops = $Directory.FindWmiFilter('Laptops')
            { $Directory.EditWmiFilter($Laptops, 'Portables', '', $Laptops.Queries) } | Should -Throw -ExpectedMessage "*cannot change the WMI filter 'Laptops'*"
            { $Directory.RemoveWmiFilter($Laptops) } | Should -Throw -ExpectedMessage "*cannot delete the WMI filter 'Laptops'*"
            $Directory.WmiFilters.Clear()
        }
    }

    Describe 'What a delegated account sees' {
        BeforeAll {
            $Directory = New-DelegatedDirectory
            $Roots = New-PSGPODirectoryTree -Directory $Directory
        }

        It 'Shows every OU and its links, those it does not manage greyed' {
            $Domain = @($Roots)[0]
            $Full = New-PSGPODirectoryTree -Directory (New-TestLdapDirectory)
            @($Domain.Children.Header) | Should -Be @(@($Full)[0].Children.Header) -Because 'it sees the domain as an account that manages everything'
            $Domain.IconBrush | Should -Be '#8A8886'
            @($Domain.Children | Where-Object { $_.Tag -is [GPOToolsGpoLink] }).IconBrush | Sort-Object -Unique | Should -Be '#8A8886'
            $Lyon = Get-Node $Roots 'Lyon'
            $Lyon.IconBrush | Should -Be '#8A8886' -Because 'it does not link GPOs there'
            Get-Node $Roots 'Domain Controllers' | Should -Not -BeNullOrEmpty
            $Workstations = Get-Node $Roots 'Lyon', 'Workstations'
            $Workstations.IconBrush | Should -Not -Be '#8A8886'
            @($Workstations.Children | Where-Object { $_.Tag -is [GPOToolsGpoLink] }).Count | Should -Be 2 -Because 'its links are shown'
            @($Workstations.Children | Where-Object { $_.Tag -is [GPOToolsGpoLink] }).IconBrush |
                Should -Be @((Get-Node $Full 'Lyon', 'Workstations').Children | Where-Object { $_.Tag -is [GPOToolsGpoLink] }).IconBrush -Because 'it manages them'
            Get-Node $Roots 'Lyon', 'Workstations', 'Laptops' | Should -Not -BeNullOrEmpty
        }

        It 'Shows every GPO, those it does not edit greyed' {
            $Gpos = (Get-Node $Roots 'Group Policy Objects').Children
            @($Gpos.Tag) | Should -Be @($Directory.Gpos)
            @($Gpos | Where-Object { $_.Tag.CanEdit }).IconBrush | Should -Not -Be '#8A8886'
            @($Gpos | Where-Object { -not $_.Tag.CanEdit -and $_.Tag.ApprovalState -ne 'Pending' }).IconBrush | Sort-Object -Unique | Should -Be '#8A8886'
            @((Get-PSGPODirectoryDetail -Directory $Directory -Item 'GroupPolicyObjects').Properties.Key) | Should -Be @($Directory.Gpos.DisplayName)
        }

        It 'Says with which account and which rights' {
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Directory.Domain
            Get-Row $Detail 'Connected as' | Should -Be 'HARDENBOX\tier2'
            Get-Row $Detail 'Delegation' | Should -BeLike 'Limited*'
            @($Detail.Links).Count | Should -Be @($Directory.Domain.Links).Count -Because 'it reads the links of the domain'
            Get-Row (Get-PSGPODirectoryDetail -Directory $Directory -Item $Directory.FindSom("OU=Lyon,$TestLdapDomainDN")) 'Your rights' | Should -Be 'Read only'
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
            Mock Set-PSGPODomainGpoStatus { throw 'the domain was asked' }
            $ReadOnly = $Directory.Gpos | Where-Object { -not $_.CanEdit } | Select-Object -First 1
            { $Directory.SetGpoStatus($ReadOnly, 1) } | Should -Throw -ExpectedMessage "*HARDENBOX\tier2 cannot edit the GPO*"
            Should -Invoke Add-PSGPODomainGpLink -Times 0 -Exactly
            Should -Invoke New-PSGPODomainGpo -Times 0 -Exactly
            Should -Invoke Set-PSGPODomainGpoStatus -Times 0 -Exactly
        }
    }
}
