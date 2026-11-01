#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The search of GPOs (Find-PSGPO, PSGPOSearch.ps1), as the Search of GPMC: each criterion, and
# several at once, on the sample directory changed in memory.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        function Get-FoundName { param([object[]]$Gpo) @($Gpo | ForEach-Object DisplayName | Sort-Object) }
    }

    Describe 'Find-PSGPO' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.IsReadOnly = $false
        }

        It 'Finds the GPOs by a part of their name, or a pattern' {
            Get-FoundName (Find-PSGPO -Directory $Directory -Name 'printers') | Should -Be @('U - Lyon - Printers', 'U - Paris - Printers')
            Get-FoundName (Find-PSGPO -Directory $Directory -Name 'C - Workstations - *') | Should -Be @(
                'C - Workstations - BitLocker', 'C - Workstations - Security Baseline Windows 11', 'C - Workstations - Windows Update Ring Broad', 'C - Workstations - Windows Update Ring Pilot')
            Find-PSGPO -Directory $Directory -Name 'nothing like it' | Should -BeNullOrEmpty
        }

        It 'Finds a GPO by its unique ID' {
            $Gpo = $Directory.FindGpo('U - Lyon - Printers')
            @(Find-PSGPO -Directory $Directory -Id $Gpo.Id) | Should -Be @($Gpo)
        }

        It 'Finds the GPOs linked to the domain or an OU, by its name or its distinguished name' {
            Get-FoundName (Find-PSGPO -Directory $Directory -LinkedTo 'Pilot') | Should -Be @('C - Workstations - Windows Update Ring Pilot', 'TEST - Edge Policies')
            Get-FoundName (Find-PSGPO -Directory $Directory -LinkedTo 'corp.contoso.com') | Should -Be @('C - All - Defender Antivirus', 'C - All - LAPS', 'C - All - Windows Firewall', 'Default Domain Policy')
            { Find-PSGPO -Directory $Directory -LinkedTo 'No such OU' } | Should -Throw "*No domain or OU named 'No such OU'*"
        }

        It 'Finds the GPOs linked nowhere, and those linked somewhere' {
            $New = $Directory.NewGpo('C - Kiosks - Not linked yet')
            @(Find-PSGPO -Directory $Directory -NotLinked) | Should -Be @($New)
            @(Find-PSGPO -Directory $Directory -Linked) | Should -Not -Contain $New
            @(Find-PSGPO -Directory $Directory -Linked).Count | Should -Be ($Directory.Gpos.Count - 1)
        }

        It 'Finds the GPOs by their status, and by their approval' {
            Get-FoundName (Find-PSGPO -Directory $Directory -Status Disabled) | Should -Be @('OLD - Windows 10 Baseline')
            @(Find-PSGPO -Directory $Directory -Status UserOnly).DisplayName | Should -BeLike 'U - *'
            $Gpo = $Directory.FindGpo('TEST - Edge Policies')
            $Gpo.ApprovalState = 'Pending'
            @(Find-PSGPO -Directory $Directory -ApprovalState Pending) | Should -Be @($Gpo)
        }

        It 'Finds the GPOs of a WMI filter, and refuses a filter the domain does not have' {
            $Filter = $Directory.NewWmiFilter('Laptops', 'Computers with a battery', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            $Gpo = $Directory.FindGpo('C - Laptops - Power Management')
            $Directory.SetWmiFilter($Gpo, $Filter)
            @(Find-PSGPO -Directory $Directory -WmiFilter 'Laptops') | Should -Be @($Gpo)
            { Find-PSGPO -Directory $Directory -WmiFilter 'Desktops' } | Should -Throw "*No WMI filter named 'Desktops'*"
        }

        It 'Finds the GPOs by a client-side extension they declare, and by a text of their settings' {
            $Gpo = $Directory.FindGpo('C - Kiosks - Assigned Access')
            $Pol = [GPOToolsRegistryPol]::new()
            $Pol.Entries.Add([GPOToolsPolEntry]::new('Software\Policies\Contoso\Kiosk', 'ShowClock', [GPOToolsPolType]::DWord, [BitConverter]::GetBytes([uint32]1)))
            $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
            @(Find-PSGPO -Directory $Directory -Extension 'Registry') | Should -Be @($Gpo)
            @(Find-PSGPO -Directory $Directory -Extension '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}') | Should -Be @($Gpo)
            @(Find-PSGPO -Directory $Directory -Setting 'showclock') | Should -Be @($Gpo)
            @(Find-PSGPO -Directory $Directory -Setting 'Contoso\Kiosk') | Should -Be @($Gpo)
            Find-PSGPO -Directory $Directory -Setting 'Not a setting of any GPO' | Should -BeNullOrEmpty
        }

        It 'Finds the GPOs an account has a permission on, by its SID or its name, which permission said or not' {
            $Gpo = $Directory.FindGpo('U - Lyon - Printers')
            $Directory.SetGpoPermission($Gpo, 'S-1-5-21-1-2-3-1500', 'GpoEdit')
            @(Find-PSGPO -Directory $Directory -Account 'S-1-5-21-1-2-3-1500') | Should -Be @($Gpo)
            @(Find-PSGPO -Directory $Directory -Account 'S-1-5-21-1-2-3-1500' -Permission GpoEdit) | Should -Be @($Gpo)
            Find-PSGPO -Directory $Directory -Account 'S-1-5-21-1-2-3-1500' -Permission GpoApply | Should -BeNullOrEmpty
            @(Find-PSGPO -Directory $Directory -Account 'Authenticated Users' -Permission GpoApply).Count | Should -Be $Directory.Gpos.Count
            { Find-PSGPO -Directory $Directory -Permission GpoApply } | Should -Throw '*Give -Account with -Permission*'
        }

        It 'Finds the GPOs by a text of their comment' {
            $Gpo = $Directory.FindGpo('C - Kiosks - Assigned Access')
            $Directory.WriteGpoComment($Gpo, "Kiosks of the halls`nCHG-2041")
            @(Find-PSGPO -Directory $Directory -Comment 'chg-2041') | Should -Be @($Gpo)
            Find-PSGPO -Directory $Directory -Comment 'CHG-9999' | Should -BeNullOrEmpty
        }

        It 'Gives the GPOs that match every criterion given' {
            # Several OUs are named Workstations: by its distinguished name.
            $Workstations = @($Directory.GetLinksOf($Directory.FindGpo('OLD - Windows 10 Baseline')))[0].Som.DistinguishedName
            Get-FoundName (Find-PSGPO -Directory $Directory -LinkedTo $Workstations -Status Disabled) | Should -Be @('OLD - Windows 10 Baseline')
            { Find-PSGPO -Directory $Directory -LinkedTo 'Workstations' } | Should -Throw '*Several OUs are named*'
            Get-FoundName (Find-PSGPO -Directory $Directory -Name 'Windows Update' -LinkedTo 'Servers') | Should -Be @('C - Servers - Windows Update')
            Find-PSGPO -Directory $Directory -Name 'Printers' -Status Disabled | Should -BeNullOrEmpty
        }
    }
}
