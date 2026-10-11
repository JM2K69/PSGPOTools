#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Group Policy Management model (proof of concept): the domain read from JSON by
# Import-PSGPODirectory, GPO creation and links, the tree and the details of the view.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Samples' 'Directory.sample.json'

        function Find-Som {
            param([GPOToolsDirectory]$Directory, [string]$DistinguishedName)
            $Stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
            $Stack.Push($Directory.Domain)
            while ($Stack.Count) {
                $Som = $Stack.Pop()
                if ($Som.DistinguishedName -eq $DistinguishedName) { return $Som }
                foreach ($Child in $Som.Children) { $Stack.Push($Child) }
            }
        }

        function Write-TestJson {
            param([string]$Json)
            $File = Join-Path $TestDrive 'directory.json'
            Set-Content -LiteralPath $File -Value $Json -Encoding utf8
            $File
        }
    }

    Describe 'Import-PSGPODirectory' {
        BeforeAll {
            $Directory = Import-PSGPODirectory -Path $SamplePath
        }

        It 'Reads the domain and its well-known GPOs' {
            $Directory | Should -BeOfType ([GPOToolsDirectory])
            $Directory.DomainName | Should -Be 'corp.contoso.com'
            $Directory.Domain.DistinguishedName | Should -Be 'DC=corp,DC=contoso,DC=com'
            $Directory.Domain.Kind | Should -Be ([GPOToolsSomKind]::Domain)
            $Directory.Gpos.Count | Should -Be 29
            $Default = $Directory.FindGpo('default domain policy')
            $Default.Id | Should -Be ([guid]'31B2F340-016D-11D2-945F-00C04FB984F9')
            $Default.DistinguishedName | Should -Be 'CN={31B2F340-016D-11D2-945F-00C04FB984F9},CN=Policies,CN=System,DC=corp,DC=contoso,DC=com'
        }

        It 'Keeps the GPOs sorted by name' {
            $Names = @($Directory.Gpos.DisplayName)
            $Names | Should -Be @($Names | Sort-Object)
        }

        It 'Reads the GPO versions and status' {
            $Gpo = $Directory.FindGpo('C - RDS - Session Hosts')
            $Gpo.GetComputerVersion() | Should -Be 10
            $Gpo.GetUserVersion() | Should -Be 3
            $Gpo.GetStatus() | Should -Be 'Enabled'
            $Directory.FindGpo('U - All - Office Settings').GetStatus() | Should -Be 'Computer configuration settings disabled'
            $Directory.FindGpo('C - All - LAPS').GetStatus() | Should -Be 'User configuration settings disabled'
            $Directory.FindGpo('OLD - Windows 10 Baseline').GetStatus() | Should -Be 'All settings disabled'
        }

        It 'Builds the OU hierarchy with the distinguished names' {
            @($Directory.Domain.Children.Name) | Should -Be @('Domain Controllers', 'Tier 0', 'Servers', 'Sites', 'Staging', 'Disabled Objects')
            $Laptops = Find-Som $Directory 'OU=Laptops,OU=Workstations,OU=Paris,OU=Sites,DC=corp,DC=contoso,DC=com'
            $Laptops.Kind | Should -Be ([GPOToolsSomKind]::OrganizationalUnit)
            $Laptops.Parent.Name | Should -Be 'Workstations'
            $Laptops.Parent.Parent.Name | Should -Be 'Paris'
        }

        It 'Reads the links by link order, with their options' {
            $Workstations = Find-Som $Directory 'OU=Workstations,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com'
            @($Workstations.Links.Order) | Should -Be @(1, 2, 3, 4)
            $Workstations.Links[0].Gpo.DisplayName | Should -Be 'C - Workstations - Security Baseline Windows 11'
            $Workstations.Links[0].Enforced | Should -BeTrue
            $Workstations.Links[1].Enforced | Should -BeFalse
            $Workstations.Links[3].Enabled | Should -BeFalse
            $Workstations.Links[2].Enabled | Should -BeTrue
        }

        It 'Reads the blocked inheritance' {
            (Find-Som $Directory 'OU=Tier 0,DC=corp,DC=contoso,DC=com').BlockInheritance | Should -BeTrue
            (Find-Som $Directory 'OU=Servers,DC=corp,DC=contoso,DC=com').BlockInheritance | Should -BeFalse
        }

        It 'Finds every link of a GPO' {
            $Links = @($Directory.GetLinksOf($Directory.FindGpo('C - Workstations - BitLocker')))
            $Links.Count | Should -Be 2
            @($Links.Som.Parent.Name | Sort-Object) | Should -Be @('Lyon', 'Paris')
            @($Directory.GetLinksOf($Directory.FindGpo('TEST - Edge Policies'))).Count | Should -Be 1
        }

        It 'Rejects <Case>' -ForEach @(
            @{ Case = 'a file without domain'; Json = '{ "gpos": [] }'; Message = "*'domain' property is required*" }
            @{ Case = 'a GPO without name'; Json = '{ "domain": "a.b", "gpos": [ { "id": "31B2F340-016D-11D2-945F-00C04FB984F9" } ] }'; Message = "*every GPO needs a 'name'*" }
            @{ Case = 'two GPOs with the same name'; Json = '{ "domain": "a.b", "gpos": [ { "name": "X" }, { "name": "x" } ] }'; Message = "*already exists*" }
            @{ Case = 'a link to an unknown GPO'; Json = '{ "domain": "a.b", "organizationalUnits": [ { "name": "OU1", "links": [ "Missing" ] } ] }'; Message = "*OU1 is linked to 'Missing'*" }
            @{ Case = 'an OU without name'; Json = '{ "domain": "a.b", "organizationalUnits": [ { } ] }'; Message = "*every organizational unit needs a 'name'*" }
        ) {
            { Import-PSGPODirectory -Path (Write-TestJson $Json) } | Should -Throw -ExpectedMessage $Message
        }

        It 'Escapes the special characters of an OU name in its distinguished name' {
            $Directory = Import-PSGPODirectory -Path (Write-TestJson '{ "domain": "a.b", "organizationalUnits": [ { "name": "Sales, Paris" } ] }')
            $Directory.Domain.Children[0].DistinguishedName | Should -Be 'OU=Sales\, Paris,DC=a,DC=b'
            $Directory.Domain.Children[0].Name | Should -Be 'Sales, Paris'
        }
    }

    Describe 'GPO creation and links' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Paris = Find-Som $Directory 'OU=Paris,OU=Sites,DC=corp,DC=contoso,DC=com'
        }

        It 'Creates a GPO with a new GUID and no setting' {
            $Gpo = $Directory.NewGpo('  C - Paris - Proxy  ')
            $Gpo.DisplayName | Should -Be 'C - Paris - Proxy'
            $Gpo.Id | Should -Not -Be ([guid]::Empty)
            $Gpo.Version | Should -Be 0
            $Gpo.GetStatus() | Should -Be 'Enabled'
            $Gpo.DistinguishedName | Should -BeLike 'CN={*},CN=Policies,CN=System,DC=corp,DC=contoso,DC=com'
            $Directory.FindGpo('C - Paris - Proxy') | Should -Be $Gpo
            $Directory.Gpos.Count | Should -Be 30
        }

        It 'Refuses an empty name or the name of an existing GPO, whatever the case' {
            { $Directory.NewGpo('   ') } | Should -Throw -ExpectedMessage '*name is required*'
            { $Directory.NewGpo('default domain POLICY') } | Should -Throw -ExpectedMessage "*'default domain POLICY' already exists in corp.contoso.com*"
            $Directory.Gpos.Count | Should -Be 29
        }

        It 'Links a GPO with the lowest precedence' {
            $Gpo = $Directory.NewGpo('U - Paris - Proxy')
            $Paris.Links.Count | Should -Be 0
            $Link = $Directory.NewLink($Paris, $Gpo)
            $Link.Order | Should -Be 1
            $Link.Enabled | Should -BeTrue
            $Link.Enforced | Should -BeFalse

            $Users = Find-Som $Directory 'OU=Users,OU=Paris,OU=Sites,DC=corp,DC=contoso,DC=com'
            $Directory.NewLink($Users, $Gpo).Order | Should -Be 5
            @($Directory.GetLinksOf($Gpo)).Count | Should -Be 2
        }

        It 'Refuses to link the same GPO twice to an OU' {
            $Gpo = $Directory.FindGpo('Default Domain Policy')
            { $Directory.NewLink($Directory.Domain, $Gpo) } | Should -Throw -ExpectedMessage "*already linked to corp.contoso.com*"
            $Directory.Domain.Links.Count | Should -Be 4
        }

        It 'Undoes the change when it cannot be saved' {
            # A directory whose persistence fails, as a real domain could. Defined at run time:
            # the module classes are unknown when this file is parsed.
            $Failing = Invoke-Expression @'
class FailingDirectory : GPOToolsDirectory {
    FailingDirectory() : base('fail.test') {}
    hidden [void] SaveNewGpo([GPOToolsGpo]$Gpo) { throw 'Access denied' }
    hidden [void] SaveLinks([GPOToolsSom]$Som) { throw 'Access denied' }
}
[FailingDirectory]::new()
'@
            { $Failing.NewGpo('X') } | Should -Throw -ExpectedMessage '*Access denied*'
            $Failing.Gpos.Count | Should -Be 0

            $Gpo = $Failing.AddGpo('Y', [guid]::Empty)
            { $Failing.NewLink($Failing.Domain, $Gpo) } | Should -Throw -ExpectedMessage '*Access denied*'
            $Failing.Domain.Links.Count | Should -Be 0
        }
    }

    Describe 'Group Policy Management tree' {
        BeforeAll {
            $Directory = Import-PSGPODirectory -Path $SamplePath
        }

        It 'Shows the domain links, its OUs then the Group Policy Objects container' {
            $Roots = New-PSGPODirectoryTree -Directory $Directory
            $Roots.Count | Should -Be 1
            $Roots[0].Header | Should -Be 'corp.contoso.com'
            $Roots[0].IsExpanded | Should -BeTrue
            @($Roots[0].Children.Header) | Should -Be @(
                'Default Domain Policy', 'C - All - LAPS (enforced)', 'C - All - Defender Antivirus', 'C - All - Windows Firewall',
                'Domain Controllers', 'Tier 0 (blocks inheritance)', 'Servers', 'Sites', 'Staging (blocks inheritance)', 'Disabled Objects',
                'Group Policy Objects')
            @($Roots[0].Children[-1].Children.Tag) | Should -Be @($Directory.Gpos)
        }

        It 'Marks the enforced and disabled links' {
            $Roots = New-PSGPODirectoryTree -Directory $Directory
            $Sites = $Roots[0].Children | Where-Object Header -EQ 'Sites'
            $Lyon = $Sites.Children | Where-Object Header -EQ 'Lyon'
            $Workstations = $Lyon.Children | Where-Object Header -EQ 'Workstations'
            @($Workstations.Children.Header) | Should -Be @(
                'C - Workstations - Security Baseline Windows 11 (enforced)', 'C - Workstations - BitLocker',
                'C - Workstations - Windows Update Ring Broad', 'OLD - Windows 10 Baseline (link disabled)', 'Laptops')
            $Workstations.Children[0].Tag | Should -BeOfType ([GPOToolsGpoLink])
            $Workstations.Children[0].Parent | Should -Be $Workstations
        }

        It 'Expands the nodes of the given keys' {
            $Keys = [System.Collections.Generic.HashSet[string]]::new([string[]]@('SOM:OU=Sites,DC=corp,DC=contoso,DC=com', 'GPOS:DC=corp,DC=contoso,DC=com'))
            $Roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $Keys
            ($Roots[0].Children | Where-Object Header -EQ 'Sites').IsExpanded | Should -BeTrue
            ($Roots[0].Children | Where-Object Header -EQ 'Servers').IsExpanded | Should -BeFalse
            $Roots[0].Children[-1].IsExpanded | Should -BeTrue
            Get-PSGPODirectoryNodeKey $Roots[0].Children[-1] | Should -Be 'GPOS:DC=corp,DC=contoso,DC=com'
            Get-PSGPODirectoryNodeKey $Roots[0].Children[0] | Should -BeNullOrEmpty
        }
    }

    Describe 'Group Policy Management details' {
        BeforeAll {
            $Directory = Import-PSGPODirectory -Path $SamplePath
        }

        It 'Shows an OU with its links' {
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item (Find-Som $Directory 'OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com')
            $Detail.Title | Should -Be 'Users'
            ($Detail.Properties | Where-Object Key -EQ 'Type').Value | Should -Be 'Organizational unit'
            ($Detail.Properties | Where-Object Key -EQ 'Distinguished name').Value | Should -Be 'OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com'
            $Detail.LinksHeader | Should -Be 'Linked Group Policy Objects (4)'
            @($Detail.Links.Name) | Should -Be @('U - All - Desktop Restrictions', 'U - All - Office Settings', 'U - Lyon - Drive Mappings', 'U - Lyon - Printers')
            $Detail.Links[0].Status | Should -Be 'Computer configuration settings disabled'
            $Detail.Gpo | Should -BeNullOrEmpty
        }

        It 'Shows a GPO from its link, with all its links' {
            $Link = (Find-Som $Directory 'OU=RDS,OU=Servers,DC=corp,DC=contoso,DC=com').Links[1]
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Link
            $Detail.Gpo.DisplayName | Should -Be 'C - Servers - Remote Desktop'
            $Detail.Title | Should -Be 'C - Servers - Remote Desktop'
            ($Detail.Properties | Where-Object Key -EQ 'Unique ID').Value | Should -Be '{8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E21}'
            ($Detail.Properties | Where-Object Key -EQ 'Computer version').Value | Should -Be '4'
            $Detail.LinksHeader | Should -Be 'Links (2)'
            @($Detail.Links.Location) | Should -Be @('OU=RDS,OU=Servers,DC=corp,DC=contoso,DC=com', 'OU=SQL Servers,OU=Servers,DC=corp,DC=contoso,DC=com')
            @($Detail.Links.Enforced) | Should -Be @('Enforced: No', 'Enforced: No')
        }

        It 'Lists the GPOs of the Group Policy Objects container' {
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item 'GroupPolicyObjects'
            $Detail.Title | Should -Be 'Group Policy Objects in corp.contoso.com'
            $Detail.Properties.Count | Should -Be 29
            $Detail.LinksHeader | Should -BeNullOrEmpty
        }
    }

    Describe 'Icons' {
        It 'Ships every icon the code uses, under the MIT license of Fluent UI System Icons' {
            $IconFolder = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Resources' 'Icons'
            Get-Content (Join-Path $IconFolder 'LICENSE') -TotalCount 1 | Should -Be 'MIT License'
            $Shipped = @(Get-PSGPOIconName)
            $Code = Get-ChildItem (Join-Path $PSScriptRoot '..' '..' 'Code') -Recurse -Filter *.ps1 | Get-Content -Raw
            $Used = @([regex]::Matches($Code -join "`n", "Icon\.([a-z-]+)\}|-Name '([a-z-]+)'|'(folder|document|person|desktop|weather-sunny|weather-moon)'") |
                ForEach-Object { $_.Groups[1..3].Value } | Where-Object { $_ } | Sort-Object -Unique)
            $Used.Count | Should -BeGreaterThan 15
            foreach ($Name in $Used) { $Shipped | Should -Contain $Name -Because "the code uses the icon '$Name'" }
        }

        It 'Reads each icon as path data with the non-zero fill rule' {
            foreach ($Name in Get-PSGPOIconName) {
                Get-PSGPOIconData -Name $Name | Should -Match '^F1 M[\d.]' -Because "$Name.svg must hold a path"
            }
            { Get-PSGPOIconData -Name 'no-such-icon' } | Should -Throw -ExpectedMessage 'Icon not found*'
        }

        It 'Gives the tree nodes an icon by kind, with a colour' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Roots = New-PSGPODirectoryTree -Directory $Directory
            $Domain = $Roots[0]
            $Domain.Icon | Should -Be 'globe'
            $Domain.IconData | Should -Be (Get-PSGPOIconData -Name 'globe')
            $Domain.IconBrush | Should -Match '^#[0-9A-F]{6}$'
            ($Domain.Children | Where-Object Header -EQ 'Servers').Icon | Should -Be 'folder'
            ($Domain.Children | Where-Object Header -EQ 'Tier 0 (blocks inheritance)').Icon | Should -Be 'folder-prohibited'
            ($Domain.Children | Where-Object Header -EQ 'Default Domain Policy').Icon | Should -Be 'link'
            ($Domain.Children | Where-Object Header -EQ 'C - All - LAPS (enforced)').Icon | Should -Be 'lock-closed'
            $Domain.Children[-1].Icon | Should -Be 'library'
            $Domain.Children[-1].Children[0].Icon | Should -Be 'document-settings'
            $Lyon = ($Domain.Children | Where-Object Header -EQ 'Sites').Children | Where-Object Header -EQ 'Lyon'
            (($Lyon.Children | Where-Object Header -EQ 'Workstations').Children | Where-Object Header -Like '*(link disabled)').Icon | Should -Be 'link-dismiss'
        }
    }
}
