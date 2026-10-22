#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

Describe 'Module manifest' {
    It 'Targets PowerShell 7.4+ Core' {
        $Manifest = Test-ModuleManifest -Path $ModuleManifest
        $Manifest.PowerShellVersion | Should -Be ([version]'7.4')
        $Manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'Exports only the public functions' {
        (Get-Module HGPM).ExportedCommands.Keys | Sort-Object |
            Should -Be @('Add-PSGPOFineGrainedPasswordPolicySubject', 'Approve-PSGPO', 'Backup-PSGPO', 'Compare-PSGPOBackup', 'Get-PSGPOAuditLog', 'Get-PSGPOBackup', 'Get-PSGPOCategory', 'Get-PSGPOConfiguration', 'Get-PSGPODefaultPasswordPolicy', 'Get-PSGPODirectory', 'Get-PSGPODrift', 'Get-PSGPOFineGrainedPasswordPolicy', 'Get-PSGPOGpmcBackup', 'Get-PSGPOMigrationEntry', 'Get-PSGPOMigrationTable', 'Get-PSGPOPermission', 'Get-PSGPOPolicy', 'Get-PSGPOResultantPasswordPolicy', 'Get-PSGPOSupportedOn', 'Get-PSGPOWmiFilter', 'Import-PSGPO', 'Import-PSGPODirectory', 'Initialize-PSGPOAdmx', 'Initialize-PSGPOWorkflow', 'Install-PSGPOAdmx', 'New-PSGPO', 'New-PSGPOFineGrainedPasswordPolicy', 'New-PSGPOLink', 'New-PSGPOMigrationTable', 'New-PSGPOWmiFilter', 'Remove-PSGPO', 'Remove-PSGPOFineGrainedPasswordPolicy', 'Remove-PSGPOFineGrainedPasswordPolicySubject', 'Remove-PSGPOLink', 'Remove-PSGPOWmiFilter', 'Restore-PSGPO', 'Set-PSGPO', 'Set-PSGPOBackup', 'Set-PSGPOFineGrainedPasswordPolicy', 'Set-PSGPOInheritance', 'Set-PSGPOLink', 'Set-PSGPOPermission', 'Show-GPOManagerAvalonia', 'Show-PSOManagerAvalonia', 'Test-PSGPOUpdate')
        (Get-Module HGPM).ExportedVariables.Count | Should -Be 0
    }

    It 'Points to this repository, its license and its changes' {
        $Data = (Import-PowerShellDataFile -Path $ModuleManifest).PrivateData.PSData
        $Data.ProjectUri | Should -Be 'https://jm2k69.github.io/PSGPOTools/' -Because 'the Project Site of the PowerShell Gallery is the documentation'
        $Data.IconUri | Should -Be 'https://raw.githubusercontent.com/JM2K69/PSGPOTools/master/docs/assets/logo/hgpm-85.png' -Because 'the logo of HGPM, in the repository'
        $Data.LicenseUri | Should -BeLike 'https://github.com/JM2K69/PSGPOTools/*LICENSE'
        $Data.ReleaseNotes | Should -Be 'https://jm2k69.github.io/PSGPOTools/en/changelog/' -Because 'the Changelog page of the site, made from CHANGELOG.md'
    }

    It 'Has a section of CHANGELOG.md for its version, which the release publishes' {
        $Data = Import-PowerShellDataFile -Path $ModuleManifest
        $Prerelease = "$($Data.PrivateData.PSData.Prerelease)".Trim()
        $Heading = '## {0}{1}' -f $Data.ModuleVersion, $(if ($Prerelease) { " - $Prerelease" })
        $Changelog = Join-Path (Split-Path -Path (Split-Path -Path $ModuleManifest -Parent) -Parent) 'CHANGELOG.md'
        @(Get-Content -LiteralPath $Changelog) | Should -Contain $Heading -Because 'CI/04_Publish.ps1 refuses a version without its notes'
    }
}

Describe 'Commands that write' {
    It '<Command> supports -WhatIf and -Confirm' -ForEach @(
        (Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1')).FunctionsToExport |
            Where-Object { $_ -match '^(New|Set|Remove|Restore|Approve|Backup|Install|Add|Initialize-PSGPOWorkflow)' } | ForEach-Object { @{ Command = $_ } }
    ) {
        # PSScriptAnalyzer leaves the private functions out of this rule: the commands ask.
        (Get-Command $Command).Parameters.Keys | Should -Contain 'WhatIf'
        (Get-Command $Command).Parameters.Keys | Should -Contain 'Confirm'
    }
}

Describe 'Help of the commands' {
    It '<Command> has a synopsis, an example and the help of each of its parameters' -ForEach @(
        # At discovery: the module is imported after it.
        (Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1')).FunctionsToExport | ForEach-Object { @{ Command = $_ } }
    ) {
        $Help = Get-Help -Name $Command -Full
        "$($Help.Synopsis)".Trim() | Should -Not -BeLike "$Command*" -Because 'a command without help shows its syntax as synopsis'
        @($Help.Examples.Example).Count | Should -BeGreaterThan 0
        $Common = [System.Management.Automation.Cmdlet]::CommonParameters + [System.Management.Automation.Cmdlet]::OptionalCommonParameters
        foreach ($Parameter in (Get-Command $Command).Parameters.Keys | Where-Object { $_ -notin $Common }) {
            $Text = @($Help.Parameters.Parameter | Where-Object Name -EQ $Parameter)[0].Description.Text
            "$Text".Trim() | Should -Not -BeNullOrEmpty -Because "-$Parameter of $Command is described"
        }
    }

    It '<Command> opens its page of the documentation site with Get-Help -Online' -ForEach @(
        (Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1')).FunctionsToExport | ForEach-Object { @{ Command = $_ } }
    ) {
        # Get-Help -Online opens the first link of the help.
        @((Get-Help -Name $Command -Full).relatedLinks.navigationLink)[0].uri | Should -Be "https://jm2k69.github.io/PSGPOTools/en/reference/commands/$($Command.ToLowerInvariant())/"
    }

    It 'Has the page of each command on the documentation site, as its help is, in its menu and its table' {
        $Generated = Join-Path $TestDrive 'pages'
        $Script = Join-Path $PSScriptRoot '..' 'Update-CommandReference.ps1'
        # In another session: the script imports the module again.
        $null = pwsh -NoProfile -NonInteractive -File $Script -OutputPath $Generated
        $LASTEXITCODE | Should -Be 0
        $Commands = @((Get-Module HGPM).ExportedFunctions.Keys)
        foreach ($Language in 'en', 'fr') {
            $Pages = Join-Path $PSScriptRoot '..' '..' 'docs' $Language 'reference' 'commands'
            @(Get-ChildItem -LiteralPath $Pages -Filter '*.md').Count | Should -Be $Commands.Count
            $Menu = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' '..' $(if ($Language -eq 'en') { 'zensical.toml' } else { 'zensical.fr.toml' }))
            $Table = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' '..' 'docs' $Language 'reference' 'commands.md')
            foreach ($Command in $Commands) {
                $Page = "$($Command.ToLowerInvariant()).md"
                ((Get-Content -Raw -LiteralPath (Join-Path $Pages $Page)) -replace "`r") | Should -Be ((Get-Content -Raw -LiteralPath (Join-Path $Generated $Language $Page)) -replace "`r") -Because "the page of $Command is its help: run CI/Update-CommandReference.ps1 after a change of the help"
                $Menu | Should -BeLike "*""reference/commands/$Page""*"
                $Table.Contains("[``$Command``](commands/$Page)") | Should -BeTrue -Because "the table links $Command to its page"
            }
        }
    }
}

Describe 'Before Initialize-PSGPOAdmx' {
    BeforeAll {
        InModuleScope HGPM { [GPOToolsUtility]::RemoveAll() }
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
        # TerminalServer.admx (Windows 11 26H2) puts AutoSubscription in a category AutoSubscription
        # that no ADMX defines: it has none, and the editor shows it under its scope.
        @($AllPolicies | Where-Object { $null -eq $_.Category } | ForEach-Object ID | Sort-Object -Unique) | Should -Be @('AutoSubscription')
        @($AllPolicies | Where-Object { $_.Path -notlike "$($_.Scope)\*" }).Count | Should -Be 0
    }

    It 'Category names are unique per namespace' {
        # Not per prefix: GroupPolicyPreferencesLogging.admx and grouppolicypreferences.admx both
        # use the prefix pref, for two namespaces, and both define CSE_Logging.
        @(Get-PSGPOCategory | Group-Object Name, { $_.target.namespace } | Where-Object Count -GT 1).Count | Should -Be 0
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
        It 'Places every policy under its own category, in Policies > Administrative Templates' {
            InModuleScope HGPM {
                $Roots = New-PSGPOPolicyTree
                $Roots.Header | Should -Be @('Computer Configuration', 'User Configuration')
                # As the Group Policy editor: Policies (Windows Settings, Administrative Templates), then Preferences.
                @($Roots[0].Children.Header) | Should -Be @('Policies', 'Preferences')
                @($Roots[0].Children[0].Children.Header) | Should -Be @('Windows Settings', 'Administrative Templates')
                @($Roots[1].Children[0].Children.Header) | Should -Be @('Administrative Templates')

                $PolicyNodes = 0
                $Stack = [System.Collections.Generic.Stack[object]]::new()
                foreach ($Root in $Roots) { $Stack.Push($Root) }
                while ($Stack.Count) {
                    $Node = $Stack.Pop()
                    foreach ($Child in $Node.Children) { $Stack.Push($Child) }
                    if ($Node.Tag -is [GPOToolsPolicy]) {
                        $PolicyNodes++
                        # A policy without a category is under the Administrative Templates of its scope.
                        $Expected = if ($Node.Tag.Category) { $Node.Tag.Category } else { "AdministrativeTemplates:$($Node.Tag.Scope)" }
                        if ($Node.Tag.Category) { [object]::ReferenceEquals($Node.Parent.Tag, $Expected) | Should -BeTrue } else { $Node.Parent.Tag | Should -Be $Expected }
                    }
                }
                $PolicyNodes | Should -Be ([GPOToolsUtility]::Policies.Count)
            }
        }

        It 'Filters on the display name, case-insensitively and without wildcards' {
            InModuleScope HGPM {
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
