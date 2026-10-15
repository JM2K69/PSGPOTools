#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

Describe 'Module manifest' {
    It 'Targets PowerShell 7.4+ Core' {
        $Manifest = Test-ModuleManifest -Path $ModuleManifest
        $Manifest.PowerShellVersion | Should -Be ([version]'7.4')
        $Manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'Exports only the public functions' {
        (Get-Module PSGPOTools).ExportedCommands.Keys | Sort-Object |
            Should -Be @('Backup-PSGPO', 'Compare-PSGPOBackup', 'Get-PSGPOBackup', 'Get-PSGPOCategory', 'Get-PSGPOConfiguration', 'Get-PSGPODirectory', 'Get-PSGPOPolicy', 'Get-PSGPOSupportedOn', 'Import-PSGPODirectory', 'Initialize-PSGPOAdmx', 'Restore-PSGPO', 'Show-GPOManagerAvalonia')
        (Get-Module PSGPOTools).ExportedVariables.Count | Should -Be 0
    }
}

Describe 'Before Initialize-PSGPOAdmx' {
    BeforeAll {
        InModuleScope PSGPOTools { [GPOToolsUtility]::RemoveAll() }
    }

    It '<Command> warns that nothing is loaded' -ForEach @(
        @{ Command = 'Get-PSGPOPolicy' }
        @{ Command = 'Get-PSGPOCategory' }
        @{ Command = 'Get-PSGPOSupportedOn' }
    ) {
        $Result = & $Command -WarningVariable Warn 3>$null
        $Result | Should -BeNullOrEmpty
        $Warn | Should -Not -BeNullOrEmpty
    }
}

Describe 'After Initialize-PSGPOAdmx' {
    BeforeAll {
        Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
        $AllPolicies = @(Get-PSGPOPolicy)
    }

    It 'Loads policies, categories and SupportedOn definitions' {
        $AllPolicies.Count | Should -BeGreaterThan 3000
        @(Get-PSGPOCategory).Count | Should -BeGreaterThan 400
        @(Get-PSGPOSupportedOn).Count | Should -BeGreaterThan 0
    }

    It 'Get-PSGPOPolicy without -Scope returns every scope' {
        $User = @(Get-PSGPOPolicy -Scope User)
        $Machine = @(Get-PSGPOPolicy -Scope Machine)
        $User.Count | Should -BeGreaterThan 0
        $Machine.Count | Should -BeGreaterThan 0
        $AllPolicies.Count | Should -Be ($User.Count + $Machine.Count)
        $User.Scope | Sort-Object -Unique | Should -Be 'User'
        $Machine.Scope | Sort-Object -Unique | Should -Be 'Machine'
    }

    It 'Every policy has a category and a path under its scope' {
        @($AllPolicies | Where-Object { $null -eq $_.Category }).Count | Should -Be 0
        @($AllPolicies | Where-Object { $_.Path -notlike "$($_.Scope)\*" }).Count | Should -Be 0
    }

    It 'Category names are unique per prefix' {
        @(Get-PSGPOCategory | Group-Object Name, { $_.target.prefix } | Where-Object Count -GT 1).Count | Should -Be 0
    }

    It 'Resolves the parent of <Category> (<Case>)' -ForEach @(
        # netcon:NetworkConnections, where NetworkConnections.admx declares the prefix networkconnections
        @{ Category = 'WF_Category'; Parent = 'NetworkConnections'; Case = 'prefix alias resolved through using' }
        @{ Category = 'MMC_Preferences'; Parent = 'MMC_GroupPolicy'; Case = 'prefix alias resolved through using' }
        # backup:Backup, where the using namespace has no file: fall back to the prefix rule
        @{ Category = 'BackupServer'; Parent = 'Backup'; Case = 'using namespace not available' }
    ) {
        (Get-PSGPOCategory | Where-Object Name -EQ $Category).ParentCategory.Name | Should -Be $Parent
    }

    It 'Resolves a known policy' {
        $Policy = $AllPolicies | Where-Object ID -EQ 'DisableAntiSpywareDefender'
        $Policy | Should -Not -BeNullOrEmpty
        $Policy.Scope | Should -Be 'Machine'
        $Policy.Registry.Path | Should -Be 'HKLM:\Software\Policies\Microsoft\Windows Defender'
        $Policy.Registry.Key | Should -Be 'DisableAntiSpyware'
    }

    It 'Reinitializing does not duplicate objects' {
        Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
        @(Get-PSGPOPolicy).Count | Should -Be $AllPolicies.Count
    }

    Context 'GUI policy tree (New-PSGPOPolicyTree)' {
        It 'Places every policy under its own category' {
            InModuleScope PSGPOTools {
                $Roots = New-PSGPOPolicyTree
                $Roots.Header | Should -Be @('User', 'Machine')

                $PolicyNodes = 0
                $Stack = [System.Collections.Generic.Stack[object]]::new()
                foreach ($Root in $Roots) { $Stack.Push($Root) }
                while ($Stack.Count) {
                    $Node = $Stack.Pop()
                    foreach ($Child in $Node.Children) { $Stack.Push($Child) }
                    if ($Node.Tag -is [GPOToolsPolicy]) {
                        $PolicyNodes++
                        [object]::ReferenceEquals($Node.Parent.Tag, $Node.Tag.Category) | Should -BeTrue
                    }
                }
                $PolicyNodes | Should -Be ([GPOToolsUtility]::Policies.Count)
            }
        }

        It 'Filters on the display name, case-insensitively and without wildcards' {
            InModuleScope PSGPOTools {
                $Expected = @([GPOToolsUtility]::Policies | Where-Object { $_.DisplayName -like '*bitlocker*' }).Count
                $Expected | Should -BeGreaterThan 0

                $Count = 0
                $Stack = [System.Collections.Generic.Stack[object]]::new()
                foreach ($Root in (New-PSGPOPolicyTree -Filter 'BITLOCKER')) { $Stack.Push($Root) }
                while ($Stack.Count) {
                    $Node = $Stack.Pop()
                    foreach ($Child in $Node.Children) { $Stack.Push($Child) }
                    if ($Node.Tag -is [GPOToolsPolicy]) { $Count++ }
                }
                $Count | Should -Be $Expected

                { New-PSGPOPolicyTree -Filter '[' } | Should -Not -Throw
                (New-PSGPOPolicyTree -Filter 'no policy has this name').Count | Should -Be 0
            }
        }
    }
}
