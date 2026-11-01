#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Group Policy Modeling (Get-PSGPOModeling, PSGPOModeling.ps1), as GPMC: the order of the links of the
# site, the domain and the OUs, the inheritance blocked, the security filtering of a token (MS16-072
# for a user GPO), the WMI filters, the parts disabled or empty, loopback processing. On the sample
# directory in memory, its containers; the accounts of a real domain are tested in
# PSGPOTools.Ldap.tests.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        $Domain = 'DC=corp,DC=contoso,DC=com'
        $Pilot = "OU=Pilot,OU=Workstations,OU=Paris,OU=Sites,$Domain"
        $ParisUsers = "OU=Users,OU=Paris,OU=Sites,$Domain"
        function Get-Row { param($Rows, [string]$Name) @($Rows | Where-Object Name -EQ $Name)[0] }
        # The computer GPO of the Pilot OU sets loopback processing: 1 Merge, 2 Replace.
        function Set-Loopback {
            param($Directory, [uint32]$Mode)
            $Pol = [GPOToolsRegistryPol]::new()
            $Pol.Entries.Add([GPOToolsPolEntry]::new('Software\Policies\Microsoft\Windows\System', 'UserPolicyMode', [GPOToolsPolType]::DWord, [BitConverter]::GetBytes($Mode)))
            $Directory.WritePolicyFile($Directory.FindGpo('TEST - Edge Policies'), 'Machine', $Pol.ToBytes())
        }
    }

    Describe 'Get-PSGPOModeling' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.IsReadOnly = $false
        }

        It 'Orders the links as Windows applies them: the enforced ones from the domain down, then the others from the OU up, the site last' {
            $Result = Get-PSGPOModeling -Directory $Directory -Computer $Pilot -Site 'Paris-Site'
            $Result.ComputerSom | Should -Be $Pilot
            $Result.Site | Should -Be 'Paris-Site'
            $Applied = @($Result.ComputerGpos | Where-Object Applied)
            @($Applied.Name) | Should -Be @(
                'C - All - LAPS', 'C - Workstations - Security Baseline Windows 11', 'C - Workstations - Windows Update Ring Pilot', 'TEST - Edge Policies',
                'C - Workstations - BitLocker', 'C - Workstations - Windows Update Ring Broad', 'Default Domain Policy', 'C - All - Defender Antivirus', 'C - All - Windows Firewall')
            @($Applied.Precedence) | Should -Be (1..9)
            (Get-Row $Result.ComputerGpos 'C - All - LAPS').Enforced | Should -BeTrue
            (Get-Row $Result.ComputerGpos 'U - Paris - Printers').Reason | Should -Be 'Disabled GPO' -Because 'its computer part is disabled'
            @($Result.ComputerGpos | Where-Object Name -EQ 'C - Workstations - Windows Update Ring Pilot').Count | Should -Be 1 -Because 'a GPO applied once is not listed again for its disabled link of the site'
        }

        It 'Stops at an OU that blocks the inheritance, but for the enforced links' {
            $Result = Get-PSGPOModeling -Directory $Directory -Computer "OU=PAW,OU=Tier 0,$Domain"
            @($Result.ComputerGpos | Where-Object Applied).Name | Should -Contain 'C - All - LAPS'
            @($Result.ComputerGpos.Name) | Should -Not -Contain 'Default Domain Policy'
            @($Result.ComputerGpos | Where-Object Applied).Name | Should -Contain 'C - PAW - Hardening'
        }

        It 'Denies a GPO the token does not apply, and applies it with the group of its security filtering' {
            $Gpo = $Directory.FindGpo('TEST - Edge Policies')
            $Directory.SetGpoSecurityFiltering($Gpo, 'S-1-5-11', $false)
            $Directory.SetGpoSecurityFiltering($Gpo, 'G-Pilot computers', $true)
            (Get-Row (Get-PSGPOModeling -Directory $Directory -Computer $Pilot).ComputerGpos 'TEST - Edge Policies').Reason | Should -Be 'Not applied (security filtering)'
            (Get-Row (Get-PSGPOModeling -Directory $Directory -Computer $Pilot -ComputerGroup 'G-Pilot computers').ComputerGpos 'TEST - Edge Policies').Reason | Should -Be 'Applied'
            $Descriptor = $Directory.LoadGpoDescriptor($Gpo)
            $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDeniedObject, [GPOToolsAce]::ContainerInherit, [GPOToolsSecurityDescriptor]::ControlAccess, 'G-Pilot computers', [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
            (Get-Row (Get-PSGPOModeling -Directory $Directory -Computer $Pilot -ComputerGroup 'G-Pilot computers').ComputerGpos 'TEST - Edge Policies').Reason | Should -Be 'Denied (security)'
        }

        It 'Says a user GPO the computer cannot read is inaccessible (MS16-072)' {
            $Gpo = $Directory.FindGpo('U - Paris - Printers')
            $Directory.SetGpoPermission($Gpo, 'S-1-5-11', 'None')
            $Directory.SetGpoSecurityFiltering($Gpo, 'G-Paris users', $true)
            (Get-Row (Get-PSGPOModeling -Directory $Directory -User $ParisUsers -UserGroup 'G-Paris users').UserGpos 'U - Paris - Printers').Reason | Should -Be 'Applied' -Because 'without the computer, nothing says it cannot read it'
            (Get-Row (Get-PSGPOModeling -Directory $Directory -Computer $Pilot -User $ParisUsers -UserGroup 'G-Paris users').UserGpos 'U - Paris - Printers').Reason | Should -BeLike 'Inaccessible*MS16-072*'
        }

        It 'Assumes the WMI filters true, but those said false, and denies a GPO whose filter is gone' {
            $Filter = $Directory.NewWmiFilter('Laptops', 'Computers with a battery', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            $Gpo = $Directory.FindGpo('C - Workstations - BitLocker')
            $Directory.SetWmiFilter($Gpo, $Filter)
            $Row = Get-Row (Get-PSGPOModeling -Directory $Directory -Computer $Pilot).ComputerGpos 'C - Workstations - BitLocker'
            $Row.Reason | Should -Be 'Applied'
            $Row.WmiFilter | Should -Be 'Laptops'
            (Get-Row (Get-PSGPOModeling -Directory $Directory -Computer $Pilot -FalseWmiFilter 'laptops').ComputerGpos 'C - Workstations - BitLocker').Reason | Should -Be 'WMI filter false'
            $Gpo.WmiFilterId = [guid]::NewGuid()
            (Get-Row (Get-PSGPOModeling -Directory $Directory -Computer $Pilot).ComputerGpos 'C - Workstations - BitLocker').Reason | Should -Be 'WMI filter not found'
        }

        It 'Says a disabled link, and a part without settings' {
            $Link = @($Directory.FindSom($Pilot).Links | Where-Object { $_.Gpo.DisplayName -eq 'TEST - Edge Policies' })[0]
            $Link.Enabled = $false
            (Get-Row (Get-PSGPOModeling -Directory $Directory -Computer $Pilot).ComputerGpos 'TEST - Edge Policies').Reason | Should -Be 'Disabled link'
            (Get-Row (Get-PSGPOModeling -Directory $Directory -User $ParisUsers).UserGpos 'Default Domain Policy').Reason | Should -Be 'Empty'
        }

        It 'Takes loopback processing from the computer GPOs: Replace the user GPOs by those of the computer, or Merge them after' {
            Set-Loopback $Directory 2
            $Replace = Get-PSGPOModeling -Directory $Directory -Computer $Pilot -User $ParisUsers
            $Replace.Loopback | Should -Be 'Replace'
            $Replace.LoopbackGpo | Should -Be 'TEST - Edge Policies'
            @($Replace.UserGpos.Name) | Should -Not -Contain 'U - Paris - Printers' -Because 'the GPOs of the OU of the user are replaced'
            @($Replace.UserGpos | Where-Object Applied).Name | Should -Contain 'TEST - Edge Policies'

            Set-Loopback $Directory 1
            $Merge = Get-PSGPOModeling -Directory $Directory -Computer $Pilot -User $ParisUsers
            $Merge.Loopback | Should -Be 'Merge'
            $Applied = @($Merge.UserGpos | Where-Object Applied).Name
            $Applied | Should -Contain 'U - Paris - Printers'
            [array]::IndexOf($Applied, 'TEST - Edge Policies') | Should -BeLessThan ([array]::IndexOf($Applied, 'U - Paris - Printers')) -Because 'the GPOs of the computer win'

            (Get-PSGPOModeling -Directory $Directory -Computer $Pilot -User $ParisUsers -Loopback None).Loopback | Should -Be 'None'
            (Get-PSGPOModeling -Directory $Directory -Computer $Pilot -User $ParisUsers -Loopback None).LoopbackGpo | Should -Be 'Given'
        }

        It 'Refuses what it cannot model' {
            { Get-PSGPOModeling -Directory $Directory } | Should -Throw '*Give -Computer, -User, or both*'
            { Get-PSGPOModeling -Directory $Directory -Computer 'PC-PARIS-01' } | Should -Throw '*has no accounts: give the domain or an OU*'
            { Get-PSGPOModeling -Directory $Directory -Computer $Pilot -Site 'Marseille-Site' } | Should -Throw "*No site named 'Marseille-Site'*"
            { Get-PSGPOModeling -Directory $Directory -User $ParisUsers -Loopback Merge } | Should -Throw '*give the computer too*'
        }

        It 'Says empty a part of a GPO of a domain that no client-side extension declares, whatever its version, as Windows' {
            . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')
            $Set = Get-TestLdapEntrySet
            $Read = ConvertTo-PSGPOLdapDirectory -Server 'dc.hardenbox.labo' -VendorName 'Samba Team' -DomainEntry $Set.Domain -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos 3>$null
            $Gpo = @($Read.Gpos)[0]
            $Gpo.Version = 0x00020004
            $Gpo.MachineExtensionNames = '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
            $Gpo.UserExtensionNames = ''
            Test-PSGPOModelingEmpty -Directory $Read -Gpo $Gpo -Scope Computer | Should -BeFalse
            Test-PSGPOModelingEmpty -Directory $Read -Gpo $Gpo -Scope User | Should -BeTrue -Because 'its user settings were removed: no extension'
            $Gpo.Version = 0x00000004
            Test-PSGPOModelingEmpty -Directory $Read -Gpo $Gpo -Scope User | Should -BeTrue -Because 'version 0'
            # A JSON description gives no extensions: the version alone.
            $Sample = $Directory.FindGpo('U - Paris - Printers')
            $Sample.UserExtensionNames | Should -BeNullOrEmpty
            Test-PSGPOModelingEmpty -Directory $Directory -Gpo $Sample -Scope User | Should -BeFalse
        }

        It 'Takes the domain as a container, and the objects of CN=Computers in the domain' {
            (Get-PSGPOModeling -Directory $Directory -Computer 'corp.contoso.com').ComputerSom | Should -Be $Domain
            (Find-PSGPOModelingSom -Directory $Directory -DistinguishedName "CN=PC-01,CN=Computers,$Domain").DistinguishedName | Should -Be $Domain
            (Find-PSGPOModelingSom -Directory $Directory -DistinguishedName "CN=PC-02,$Pilot").DistinguishedName | Should -Be $Pilot
        }
    }
}
