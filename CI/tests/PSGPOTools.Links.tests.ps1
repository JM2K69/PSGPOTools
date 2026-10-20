#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Links and inheritance, as GPMC changes them: Enforced, Link Enabled, the link order, Block
# Inheritance, the status of a GPO; on a directory in memory, the gPLink a domain gets, and the
# commands.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        $Users = 'OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com'
        function Get-Order { param($Som) @($Som.Links | Sort-Object Order | ForEach-Object { $_.GetDisplayName() }) }
    }

    Describe 'gPLink of a changed link' {
        BeforeAll {
            # Link order 1 is the last entry.
            $Current = '[LDAP://cn={C},cn=policies;0][LDAP://cn={B},cn=policies;2][LDAP://cn={A},cn=policies;1]'
            function New-Link { param($Dn) $Link = [GPOToolsGpoLink]::new(); $Link.GpoDistinguishedName = $Dn; $Link }
        }

        It 'Enables, disables, enforces a link, the others written as they were' {
            Get-PSGPOChangedGpLink -Current $Current -Link (New-Link 'CN={A},CN=Policies') -Enabled $true |
                Should -BeExactly '[LDAP://cn={C},cn=policies;0][LDAP://cn={B},cn=policies;2][LDAP://cn={A},cn=policies;0]'
            Get-PSGPOChangedGpLink -Current $Current -Link (New-Link 'cn={C},cn=policies') -Enforced $true -Enabled $false |
                Should -BeExactly '[LDAP://cn={C},cn=policies;3][LDAP://cn={B},cn=policies;2][LDAP://cn={A},cn=policies;1]'
            Get-PSGPOChangedGpLink -Current $Current -Link (New-Link 'cn={B},cn=policies') -Enforced $false |
                Should -BeExactly '[LDAP://cn={C},cn=policies;0][LDAP://cn={B},cn=policies;0][LDAP://cn={A},cn=policies;1]'
        }

        It 'Moves a link to a link order' {
            # C (order 3) first: it is the last entry.
            Get-PSGPOChangedGpLink -Current $Current -Link (New-Link 'cn={C},cn=policies') -Order 1 |
                Should -BeExactly '[LDAP://cn={B},cn=policies;2][LDAP://cn={A},cn=policies;1][LDAP://cn={C},cn=policies;0]'
            Get-PSGPOChangedGpLink -Current $Current -Link (New-Link 'cn={A},cn=policies') -Order 2 |
                Should -BeExactly '[LDAP://cn={C},cn=policies;0][LDAP://cn={A},cn=policies;1][LDAP://cn={B},cn=policies;2]'
            Get-PSGPOChangedGpLink -Current $Current -Link (New-Link 'cn={A},cn=policies') -Order 9 |
                Should -BeExactly '[LDAP://cn={A},cn=policies;1][LDAP://cn={C},cn=policies;0][LDAP://cn={B},cn=policies;2]' -Because 'past the end is the end'
        }

        It 'Keeps the link objects of the SOM when its links are read back from the domain' {
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Som = $Directory.Domain
            $Directory.SetLinks($Som, $Current)
            $A = $Som.Links | Where-Object GpoDistinguishedName -EQ 'cn={A},cn=policies'
            $C = $Som.Links | Where-Object GpoDistinguishedName -EQ 'cn={C},cn=policies'
            Set-PSGPOSomLinkFromDomain -Directory $Directory -Som $Som -GpLink (Get-PSGPOChangedGpLink -Current $Current -Link $C -Enforced $true -Order 1)
            $Som.Links.Contains($A) | Should -BeTrue -Because 'a script holding the other link can still change it'
            $Som.Links.Contains($C) | Should -BeTrue
            $C.Order | Should -Be 1
            $C.Enforced | Should -BeTrue
            $A.Order | Should -Be 2
        }

        It 'Refuses a link that is not there anymore' {
            { Get-PSGPOChangedGpLink -Current $Current -Link (New-Link 'cn={D},cn=policies') -Enabled $false } | Should -Throw -ExpectedMessage '*not linked there anymore*'
        }
    }

    Describe 'Links of a directory in memory' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Som = $Directory.FindSom($Users)
            $Printers = $Som.Links | Where-Object { $_.GetDisplayName() -eq 'U - Lyon - Printers' }
        }

        It 'Enforces and disables a link' {
            $Directory.SetLink($Som, $Printers, $false, $true)
            $Printers.Enabled | Should -BeFalse
            $Printers.Enforced | Should -BeTrue
            [GPOToolsGpoLink]::Format($Som.Links) | Should -Match 'Printers|;3\]'
        }

        It 'Moves a link up and down, the others keeping their order' {
            $Directory.MoveLink($Som, $Printers, 1)
            Get-Order $Som | Should -Be @('U - Lyon - Printers', 'U - All - Desktop Restrictions', 'U - All - Office Settings', 'U - Lyon - Drive Mappings')
            $Directory.MoveLink($Som, $Printers, 3)
            Get-Order $Som | Should -Be @('U - All - Desktop Restrictions', 'U - All - Office Settings', 'U - Lyon - Printers', 'U - Lyon - Drive Mappings')
            @($Som.Links.Order | Sort-Object) | Should -Be @(1, 2, 3, 4)
            { $Directory.MoveLink($Som, $Printers, 5) } | Should -Throw -ExpectedMessage '*1 to 4*'
        }

        It 'Blocks the inheritance of an OU' {
            $Directory.SetBlockInheritance($Som, $true)
            $Som.BlockInheritance | Should -BeTrue
            $Directory.SetBlockInheritance($Som, $false)
            $Som.BlockInheritance | Should -BeFalse
        }

        It 'Refuses where the account cannot link' {
            $Som.CanLink = $false
            { $Directory.SetLink($Som, $Printers, $false, $false) } | Should -Throw -ExpectedMessage '*cannot link GPOs*'
            { $Directory.MoveLink($Som, $Printers, 1) } | Should -Throw -ExpectedMessage '*cannot link GPOs*'
            { $Directory.SetBlockInheritance($Som, $true) } | Should -Throw -ExpectedMessage '*cannot link GPOs*'
            $Printers.Enabled | Should -BeTrue
        }
    }

    Describe 'Commands of the links' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
        }

        It 'Links a GPO, enforced, by the name of an OU' {
            $Link = New-PSGPOLink -Directory $Directory -Name 'C - Servers - Remote Desktop' -Target 'File Servers' -Enforced
            $Link.Target | Should -Be 'OU=File Servers,OU=Servers,DC=corp,DC=contoso,DC=com'
            $Link.Order | Should -Be 2
            $Link.Enforced | Should -BeTrue
            $Link.Enabled | Should -BeTrue
        }

        It 'Changes a link and moves it, and deletes it' {
            $Link = Set-PSGPOLink -Directory $Directory -Name 'U - Lyon - Printers' -Target $Users -Enabled $false -Order 1
            $Link.Order | Should -Be 1
            $Link.Enabled | Should -BeFalse
            $Link.Enforced | Should -BeFalse -Because 'what is not given does not change'
            Remove-PSGPOLink -Directory $Directory -Name 'U - Lyon - Printers' -Target $Users -Confirm:$false
            Get-Order $Directory.FindSom($Users) | Should -Not -Contain 'U - Lyon - Printers'
        }

        It 'Says when an OU name is ambiguous, or a GPO is not linked there' {
            { Set-PSGPOLink -Directory $Directory -Name 'U - Lyon - Printers' -Target 'Users' -Enabled $false } | Should -Throw -ExpectedMessage '*Several OUs are named*'
            Set-PSGPOLink -Directory $Directory -Name 'C - PAW - Hardening' -Target $Users -Enabled $false -ErrorVariable Problem -ErrorAction SilentlyContinue
            "$Problem" | Should -BeLike '*is not linked to Users*'
            { Set-PSGPOLink -Directory $Directory -Name 'U - Lyon - Printers' -Target $Users } | Should -Throw -ExpectedMessage '*what changes*'
        }

        It 'Blocks the inheritance, and sets the status of a GPO' {
            Set-PSGPOInheritance -Directory $Directory -Target 'Servers' -Blocked $true -Confirm:$false
            $Directory.FindSom('OU=Servers,DC=corp,DC=contoso,DC=com').BlockInheritance | Should -BeTrue
            (Set-PSGPO -Directory $Directory -Name 'C - Servers - Windows Update' -Status ComputerOnly).GetStatus() | Should -Be 'User configuration settings disabled'
        }

        It 'Changes nothing with -WhatIf' {
            Set-PSGPOLink -Directory $Directory -Name 'U - Lyon - Printers' -Target $Users -Enforced $true -WhatIf
            ($Directory.FindSom($Users).Links | Where-Object { $_.GetDisplayName() -eq 'U - Lyon - Printers' }).Enforced | Should -BeFalse
        }
    }
}
