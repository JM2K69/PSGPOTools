#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Language of the interface: every text of the code has its translation in each file of
# Resources/Strings, with the same values ({0}...), and the windows parse once translated.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    # Evaluated during discovery, here: the variables of BeforeDiscovery are not visible in InModuleScope.
    $Languages = @(Get-ChildItem (Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Resources' 'Strings') -Filter '*.psd1' | ForEach-Object { @{ Language = $_.BaseName; File = $_.FullName } })

    Describe 'Texts of the interface' {
        BeforeAll {
            . (Join-Path $PSScriptRoot 'PSGPOTextKey.ps1')
            $Keys = Get-PSGPOTextKey -Path (Join-Path $PSScriptRoot '..' '..' 'Code' 'Functions')
            # The keys the code gives by a value (Get-PSGPOText $state).
            foreach ($Key in 'Enabled', 'Disabled', 'NotConfigured', 'Added', 'Changed', 'Removed', 'Category', 'Value', 'Range', 'Values', 'User', 'Machine',
                'User configuration settings disabled', 'Computer configuration settings disabled', 'All settings disabled',
                'Continue processing the other items of this type after an error', "Run in the logged-on user's security context", 'Remove this item when it is no longer applied',
                'Read', 'Read (from Security Filtering)', 'Edit settings', 'Edit settings, delete, modify security', 'Custom') {
                [void]$Keys.Add($Key)
            }
        }
        AfterAll { $null = Set-PSGPOLanguage -Language 'en-US' }

        It 'Has a translation of every text in <Language>' -ForEach $Languages {
            $Texts = Import-PowerShellDataFile -LiteralPath $File
            @($Keys | Where-Object { -not $Texts.ContainsKey($_) } | Sort-Object) | Should -BeNullOrEmpty
            @($Texts.Keys | Where-Object { -not $Texts[$_] }) | Should -BeNullOrEmpty -Because 'an empty text would hide the English one'
        }

        It 'Keeps the values of each text in <Language>' -ForEach $Languages {
            $Texts = Import-PowerShellDataFile -LiteralPath $File
            $Different = foreach ($Key in $Texts.Keys) {
                $Expected = @([regex]::Matches($Key, '\{\d+\}').Value | Sort-Object -Unique) -join ','
                $Actual = @([regex]::Matches($Texts[$Key], '\{\d+\}').Value | Sort-Object -Unique) -join ','
                if ($Expected -ne $Actual) { "$Key => $($Texts[$Key])" }
                else { try { $null = $Texts[$Key] -f @(0..9) } catch { "$Key => $($Texts[$Key]) (not a format)" } }
            }
            @($Different) | Should -BeNullOrEmpty
        }

        It 'Parses the windows once translated in <Language>' -ForEach $Languages {
            $null = Set-PSGPOLanguage -Language $Language
            foreach ($Xaml in (Get-PSGPOManagerWindowXaml)) {
                { [xml](ConvertTo-PSGPOLocalizedXaml -Xaml $Xaml) } | Should -Not -Throw
            }
        }
    }

    Describe 'Language of the interface' {
        AfterEach { $null = Set-PSGPOLanguage -Language 'en-US' }

        It 'Uses the file of the culture, else of its language, else English' {
            Set-PSGPOLanguage -Language 'fr-FR' | Should -Be 'fr-FR'
            Get-PSGPOText 'Refresh' | Should -Be 'Actualiser'
            Set-PSGPOLanguage -Language 'fr-CA' | Should -Be 'fr-FR'
            Set-PSGPOLanguage -Language 'de-DE' | Should -Be 'en-US'
            Get-PSGPOText 'Refresh' | Should -Be 'Refresh'
            Set-PSGPOLanguage -Language '' | Should -Be 'en-US'
            Set-PSGPOLanguage -Language 'not-a-culture' 3>$null | Should -Be 'en-US'
        }

        It 'Puts the values in the text, a 0 or an empty value too' {
            Get-PSGPOText 'Links ({0})' 0 | Should -Be 'Links (0)'
            Get-PSGPOText 'Domain {0}' '' | Should -Be 'Domain '
            $null = Set-PSGPOLanguage -Language 'fr-FR'
            Get-PSGPOText 'Links ({0})' 2 | Should -Be 'Liens (2)'
            Get-PSGPOText 'A text without translation' | Should -Be 'A text without translation'
            Get-PSGPOText 'GPO STATUS' | Should -Be 'État GPO' -Because 'the keys of a psd1 do not depend on the case'
        }

        It 'Translates the texts of the XAML, not the bindings, and escapes them' {
            $null = Set-PSGPOLanguage -Language 'fr-FR'
            $Xaml = ConvertTo-PSGPOLocalizedXaml -Xaml "<StackPanel><TextBlock Text='Refresh'/><TextBlock Text='{Binding Name}'/><Button Content='Block Inheritance'/></StackPanel>"
            $Document = [xml]$Xaml
            $Document.StackPanel.TextBlock[0].Text | Should -Be 'Actualiser'
            $Document.StackPanel.TextBlock[1].Text | Should -Be '{Binding Name}'
            $Document.StackPanel.Button.Content | Should -Be "Bloquer l'héritage"
        }
    }
}
