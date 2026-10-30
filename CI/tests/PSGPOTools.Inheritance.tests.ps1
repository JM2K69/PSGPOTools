#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The links of a domain or OU and the GPOs that apply there by inheritance (Get-PSGPOInheritance),
# as the Linked Group Policy Objects and Group Policy Inheritance tabs of GPMC, on the sample
# directory.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    Describe 'Get-PSGPOInheritance' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json')
            $Domain = 'DC=corp,DC=contoso,DC=com'
            $Workstations = "OU=Workstations,OU=Lyon,OU=Sites,$Domain"
        }

        It 'Gives the links of an OU by link order, and the GPOs that apply there by precedence, as GPMC' {
            $Result = Get-PSGPOInheritance -Target $Workstations -Directory $Directory
            $Result.PSObject.TypeNames | Should -Contain 'PSGPOTools.GpoInheritance'
            $Result.Name | Should -Be 'Workstations'
            $Result.ContainerType | Should -Be 'OrganizationalUnit'
            $Result.Path | Should -Be $Workstations
            $Result.GpoInheritanceBlocked | Should -BeFalse
            @($Result.GpoLinks | ForEach-Object { '{0} {1} {2} {3}' -f $_.Order, $_.DisplayName, $_.Enforced, $_.Enabled }) | Should -Be @(
                '1 C - Workstations - Security Baseline Windows 11 True True'
                '2 C - Workstations - BitLocker False True'
                '3 C - Workstations - Windows Update Ring Broad False True'
                '4 OLD - Windows 10 Baseline False False'
            )
            # The enforced links first, from the domain down; then the others, from the OU up.
            @($Result.InheritedGpoLinks | ForEach-Object { '{0} {1} | {2}' -f $_.Precedence, $_.DisplayName, $_.Target }) | Should -Be @(
                "1 C - All - LAPS | $Domain"
                "2 C - Workstations - Security Baseline Windows 11 | $Workstations"
                "3 C - Workstations - BitLocker | $Workstations"
                "4 C - Workstations - Windows Update Ring Broad | $Workstations"
                "5 Default Domain Policy | $Domain"
                "6 C - All - Defender Antivirus | $Domain"
                "7 C - All - Windows Firewall | $Domain"
            ) -Because 'the disabled link of OLD - Windows 10 Baseline applies nowhere'
            @($Result.InheritedGpoLinks | Where-Object Enforced).DisplayName | Should -Be @('C - All - LAPS', 'C - Workstations - Security Baseline Windows 11')
        }

        It 'Lists a GPO whose settings are all disabled with its status, as GPMC; the analysis of what applies leaves it out' {
            $Directory.FindGpo('C - All - Defender Antivirus').Flags = 3
            $Inherited = (Get-PSGPOInheritance -Target $Workstations -Directory $Directory).InheritedGpoLinks
            ($Inherited | Where-Object DisplayName -EQ 'C - All - Defender Antivirus').Status | Should -Be 'All settings disabled'
            @(Get-PSGPOSomPrecedence -Som $Directory.FindSom($Workstations) | ForEach-Object { $_.Gpo.DisplayName }) | Should -Not -Contain 'C - All - Defender Antivirus'
        }

        It 'Says when an OU blocks the inheritance: the enforced links of its parents only, then its own' {
            $Result = Get-PSGPOInheritance -Target "OU=Kiosks,OU=Workstations,OU=Paris,OU=Sites,$Domain" -Directory $Directory
            $Result.GpoInheritanceBlocked | Should -BeTrue
            @($Result.InheritedGpoLinks.DisplayName) | Should -Be @('C - All - LAPS', 'C - Workstations - Security Baseline Windows 11', 'C - Kiosks - Assigned Access')
        }

        It 'Finds the domain by its name and several targets from the pipeline, and refuses one the domain does not have' {
            $Results = @(@('corp.contoso.com', $Workstations) | Get-PSGPOInheritance -Directory $Directory)
            $Results.Count | Should -Be 2
            $Results[0].ContainerType | Should -Be 'Domain'
            @($Results[0].GpoLinks).Count | Should -Be 4
            { Get-PSGPOInheritance -Target "OU=Nowhere,$Domain" -Directory $Directory } | Should -Throw
        }
    }
}
