#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The sites of the forest and their links, as GPMC shows them under Sites (PSGPOSite.ps1): read from
# the directory or the JSON description, never changed; in the tree, the details, the search, and
# when a GPO linked to a site is deleted. The sites of a real forest are tested in
# PSGPOTools.Ldap.tests.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
    }

    Describe 'Sites of a directory' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.IsReadOnly = $false
            $Paris = $Directory.FindSite('Paris-Site')
        }

        It 'Reads the sites of the JSON description, by name, with their links by link order' {
            @($Directory.Sites.Name) | Should -Be @('Default-First-Site-Name', 'Lyon-Site', 'Paris-Site')
            $Paris.Kind | Should -Be ([GPOToolsSomKind]::Site)
            $Paris.CanLink | Should -BeFalse
            $Paris.DistinguishedName | Should -Be 'CN=Paris-Site,CN=Sites,CN=Configuration,DC=corp,DC=contoso,DC=com'
            @($Paris.Links | ForEach-Object { $_.Gpo.DisplayName }) | Should -Be @('U - Paris - Printers', 'C - Workstations - Windows Update Ring Pilot')
            $Paris.Links[1].Enabled | Should -BeFalse
            $Directory.FindSite($Paris.DistinguishedName.ToLowerInvariant()) | Should -Be $Paris
            $Directory.FindSite('Marseille-Site') | Should -BeNullOrEmpty
        }

        It 'Changes no link of a site: they are changed with GPMC' {
            $Gpo = $Directory.FindGpo('U - Lyon - Printers')
            { $Directory.NewLink($Paris, $Gpo) } | Should -Throw '*read, not changed*'
            { $Directory.RemoveLink($Paris, $Paris.Links[0]) } | Should -Throw '*read, not changed*'
            { $Directory.MoveLink($Paris, $Paris.Links[1], 1) } | Should -Throw '*read, not changed*'
            { $Directory.SetBlockInheritance($Paris, $true) } | Should -Throw '*read, not changed*'
            { $Directory.SetLink($Paris, $Paris.Links[0], $true, $true) } | Should -Throw '*read, not changed*'
            $Paris.Links.Count | Should -Be 2
        }

        It 'Gives the links of a GPO in the sites, apart from those of the domain' {
            $Gpo = $Directory.FindGpo('U - Paris - Printers')
            @($Directory.GetSiteLinksOf($Gpo).Som) | Should -Be @($Paris)
            @($Directory.GetLinksOf($Gpo).Som.Kind) | Should -Not -Contain ([GPOToolsSomKind]::Site)
        }

        It 'Keeps the links of the sites to a GPO deleted, to a GPO not found, and says so' {
            $Gpo = $Directory.FindGpo('U - Paris - Printers')
            Remove-PSGPO -Directory $Directory -Name 'U - Paris - Printers' -NoBackup -Confirm:$false -WarningVariable Warnings 3>$null
            $Directory.FindGpo('U - Paris - Printers') | Should -BeNullOrEmpty
            $Paris.Links.Count | Should -Be 2
            $Paris.Links[0].Gpo | Should -BeNullOrEmpty
            $Paris.Links[0].GpoDistinguishedName | Should -Be $Gpo.DistinguishedName
            "$Warnings" | Should -BeLike '*the sites Paris-Site keep their link to it*'
        }

        It 'Refuses a site without a name in the JSON description' {
            $Path = Join-Path $TestDrive 'site.json'
            Set-Content -LiteralPath $Path -Value '{ "domain": "corp.contoso.com", "gpos": [ { "name": "A" } ], "sites": [ { "links": [ "A" ] } ] }'
            { Import-PSGPODirectory -Path $Path } | Should -Throw "*every site needs a 'name'*"
            Set-Content -LiteralPath $Path -Value '{ "domain": "corp.contoso.com", "sites": [ { "name": "S", "links": [ "B" ] } ] }'
            { Import-PSGPODirectory -Path $Path } | Should -Throw "*the site S is linked to 'B'*"
        }
    }

    Describe 'Sites read from a directory' {
        It 'Resolves the links of the sites in the GPOs of the domain, whatever the case; a GPO of another domain is not found' {
            $Set = Get-TestLdapEntrySet
            $Directory = ConvertTo-PSGPOLdapDirectory -Server 'dc.hardenbox.labo' -VendorName 'Samba Team' -DomainEntry $Set.Domain -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos 3>$null
            $Other = 'cn={11111111-2222-3333-4444-555555555555},cn=policies,cn=system,DC=child,DC=hardenbox,DC=labo'
            $Entries = @(
                New-TestLdapEntry "CN=Default-First-Site-Name,CN=Sites,CN=Configuration,$TestLdapDomainDN" @{ cn = 'Default-First-Site-Name'; gPLink = "[LDAP://$(Get-TestLdapGpoDN $TestLdapWorkstationsPolicy);2][LDAP://$Other;0]" }
                New-TestLdapEntry "CN=Branch,CN=Sites,CN=Configuration,$TestLdapDomainDN" @{ name = 'Branch' }
            )
            Add-PSGPOSiteEntry -Directory $Directory -SiteEntry $Entries
            @($Directory.Sites.Name) | Should -Be @('Branch', 'Default-First-Site-Name')
            $Site = $Directory.FindSite('Default-First-Site-Name')
            $Site.Links[0].GpoDistinguishedName | Should -Be $Other -Because 'link order 1 is the last of the gPLink'
            $Site.Links[0].Gpo | Should -BeNullOrEmpty
            $Site.Links[1].Gpo.Id | Should -Be ([guid]$TestLdapWorkstationsPolicy)
            $Site.Links[1].Enforced | Should -BeTrue
            $Directory.FindSite('Branch').Links.Count | Should -Be 0
        }
    }

    Describe 'Sites in the tree, the details and the search' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Paris = $Directory.FindSite('Paris-Site')
        }

        It 'Shows the sites beside the domain, with their links, never greyed' {
            $Roots = New-PSGPODirectoryTree -Directory $Directory -ShowUnmanaged $false
            $Roots.Count | Should -Be 2
            $Roots[1].Header | Should -Be 'Sites'
            $Roots[1].Tag | Should -Be 'Sites'
            Get-PSGPODirectoryNodeKey $Roots[1] | Should -Be 'SITES'
            @($Roots[1].Children.Header) | Should -Be @('Default-First-Site-Name', 'Lyon-Site', 'Paris-Site')
            $Node = $Roots[1].Children[2]
            $Node.Tag | Should -Be $Paris
            $Node.Parent | Should -Be $Roots[1]
            @($Node.Children.Header) | Should -Be @('U - Paris - Printers', 'C - Workstations - Windows Update Ring Pilot (link disabled)')
            $Node.IconBrush | Should -Not -Be '#8A8886'
            Get-PSGPODirectoryNodeKey $Node | Should -Be "SOM:$($Paris.DistinguishedName)"
        }

        It 'Has no Sites node when the forest has none' {
            $Directory.Sites.Clear()
            (New-PSGPODirectoryTree -Directory $Directory).Count | Should -Be 1
        }

        It 'Details a site, the sites, and the links of a GPO in the sites' {
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Paris
            $Detail.Title | Should -Be 'Paris-Site'
            @($Detail.Properties.Key) | Should -Be @('Type', 'Distinguished name', 'Your rights')
            $Detail.Properties[0].Value | Should -Be 'Site'
            $Detail.LinksHeader | Should -Be 'Linked Group Policy Objects (2)'
            @($Detail.Links.Name) | Should -Be @('U - Paris - Printers', 'C - Workstations - Windows Update Ring Pilot')

            $All = Get-PSGPODirectoryDetail -Directory $Directory -Item 'Sites'
            $All.Title | Should -Be 'Sites of the forest'
            @($All.Properties.Key)[0..2] | Should -Be @('Default-First-Site-Name', 'Lyon-Site', 'Paris-Site')
            $All.Properties[2].Value | Should -Be '2 linked GPO(s)'

            $Gpo = Get-PSGPODirectoryDetail -Directory $Directory -Item $Directory.FindGpo('U - Paris - Printers')
            @($Gpo.Links.Name) | Should -Contain 'Paris-Site'
            @($Gpo.Links | Where-Object Name -EQ 'Paris-Site').Location | Should -Be $Paris.DistinguishedName
        }

        It 'Finds the GPOs linked to a site, and counts a link to a site as a link' {
            @(Find-PSGPO -Directory $Directory -LinkedTo 'Paris-Site').DisplayName | Sort-Object | Should -Be @('C - Workstations - Windows Update Ring Pilot', 'U - Paris - Printers')
            @(Find-PSGPO -Directory $Directory -LinkedTo $Paris.DistinguishedName).Count | Should -Be 2
            { Find-PSGPO -Directory $Directory -LinkedTo 'Marseille-Site' } | Should -Throw "*No domain or OU named 'Marseille-Site'*"
            $Directory.IsReadOnly = $false
            $Only = $Directory.NewGpo('C - Paris - Proxy')
            $Link = [GPOToolsGpoLink]::new()
            $Link.GpoDistinguishedName = $Only.DistinguishedName
            $Link.Gpo = $Only
            $Link.Order = 3
            $Paris.Links.Add($Link)
            @(Find-PSGPO -Directory $Directory -Linked) | Should -Contain $Only
            @(Find-PSGPO -Directory $Directory -NotLinked) | Should -Not -Contain $Only
        }
    }
}
