#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Language of the interface: every text of the code has its translation in each file of
# Resources/Strings, with the same values ({0}...), and the windows parse once translated.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    # Evaluated during discovery, here: the variables of BeforeDiscovery are not visible in InModuleScope.
    $Languages = @(Get-ChildItem (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Resources' 'Strings') -Filter '*.psd1' | ForEach-Object { @{ Language = $_.BaseName; File = $_.FullName } })

    Describe 'Texts of the interface' {
        BeforeAll {
            . (Join-Path $PSScriptRoot 'PSGPOTextKey.ps1')
            $Keys = Get-PSGPOTextKey -Path (Join-Path $PSScriptRoot '..' '..' 'Code' 'Functions')
            # The keys the code gives by a value (Get-PSGPOText $state).
            foreach ($Key in 'Enabled', 'Disabled', 'NotConfigured', 'Added', 'Changed', 'Removed', 'Category', 'Value', 'Range', 'Values', 'User', 'Machine',
                'User configuration settings disabled', 'Computer configuration settings disabled', 'All settings disabled',
                'Continue processing the other items of this type after an error', "Run in the logged-on user's security context", 'Remove this item when it is no longer applied',
                'Read', 'Read and apply', 'Edit settings', 'Edit settings, delete, modify security', 'Custom', 'Creator owner', 'Edit', 'Full control',
                'True', 'False', 'Create', 'Replace', 'Update', 'Delete',
                'Number', 'Boolean', 'Accounts', 'Audit', 'Text', 'Choice', 'MultiText', 'Bitmask', 'RegistryValue') {
                [void]$Keys.Add($Key)
            }
        }
        AfterAll { $null = Set-PSGPOLanguage -Language 'en-US' }

        It 'Has a translation of every text in <Language>' -ForEach $Languages {
            $Texts = Import-PowerShellDataFile -LiteralPath $File -SkipLimitCheck
            @($Keys | Where-Object { -not $Texts.ContainsKey($_) } | Sort-Object) | Should -BeNullOrEmpty
            @($Texts.Keys | Where-Object { -not $Texts[$_] }) | Should -BeNullOrEmpty -Because 'an empty text would hide the English one'
        }

        It 'Keeps the values of each text in <Language>' -ForEach $Languages {
            $Texts = Import-PowerShellDataFile -LiteralPath $File -SkipLimitCheck
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
            foreach ($Xaml in (Get-PSGPOManagerWindowXaml), (Get-PSGPOPasswordPolicyWindowXaml), (Get-PSGPOPasswordPolicyEditorXaml), (Get-PSGPOLauncherWindowXaml), (Get-PSGPOWmiFilterCreatorWindowXaml), (Get-PSGPOPolicyAnalyzerWindowXaml)) {
                { [xml](ConvertTo-PSGPOLocalizedXaml -Xaml $Xaml) } | Should -Not -Throw
            }
        }
    }

    # The names the console shows of the catalogs: Resources/Strings/Catalogs/<language>.psd1.
    $Catalogs = @(Get-ChildItem (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Resources' 'Strings' 'Catalogs') -Filter '*.psd1' | ForEach-Object { @{ Language = $_.BaseName; File = $_.FullName } })

    Describe 'Names of the catalogs' {
        BeforeAll {
            $Names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Setting in @(Get-PSGPOSecuritySetting)) {
                foreach ($Name in @($Setting.Name) + @($Setting.Path) + @($Setting.Unit) + @($Setting.Choices | ForEach-Object Text)) { if ($Name) { [void]$Names.Add($Name) } }
            }
            foreach ($Extension in @(Get-PSGPOPreferenceCatalog)) {
                foreach ($Name in @($Extension.Name, $Extension.Group) + @($Extension.Items.Label) + @($Extension.Items.Properties | ForEach-Object { $_.Label; $_.Hint })) { if ($Name) { [void]$Names.Add($Name) } }
            }
            foreach ($Setting in @(Get-PSGPOConfigurationSetting -Override @{})) { if ($Setting.Description) { [void]$Names.Add($Setting.Description) } }
            # The WMI filter creator: its classes, their properties and values, its ready-made queries.
            $Wmi = Get-PSGPOWmiCatalog
            foreach ($Class in $Wmi.Classes) {
                foreach ($Name in @($Class.Description, $Class.Warning) + @($Class.Properties.Description) + @($Class.Properties.Values | ForEach-Object Text)) { if ($Name) { [void]$Names.Add($Name) } }
            }
            foreach ($Template in $Wmi.Templates) {
                foreach ($Name in @($Template.Category, $Template.Name, $Template.Description, $Template.Note) + @($Template.Parameters | ForEach-Object { $_.Label; $_.Hint; $_.Choices.Text })) { if ($Name) { [void]$Names.Add($Name) } }
            }
        }

        It 'Has a translation of every name in <Language>, and no other' -ForEach $Catalogs {
            $Texts = Import-PowerShellDataFile -LiteralPath $File -SkipLimitCheck
            @($Names | Where-Object { -not $Texts.ContainsKey($_) } | Sort-Object) | Should -BeNullOrEmpty
            @($Texts.Keys | Where-Object { -not $Names.Contains($_) } | Sort-Object) | Should -BeNullOrEmpty -Because 'a name no catalog has anymore is left over'
            @($Texts.Keys | Where-Object { -not $Texts[$_] -or $Texts[$_] -ne $Texts[$_].Trim() }) | Should -BeNullOrEmpty
        }

        It 'Keeps the values of each name in <Language>' -ForEach $Catalogs {
            $Texts = Import-PowerShellDataFile -LiteralPath $File -SkipLimitCheck
            @(foreach ($Key in $Texts.Keys) {
                    if ((@([regex]::Matches($Key, '\{\d+\}').Value) -join ',') -ne (@([regex]::Matches($Texts[$Key], '\{\d+\}').Value) -join ',')) { $Key }
                }) | Should -BeNullOrEmpty
        }

        It 'Shows the names of the catalogs in the language of the interface, the texts of the interface first' {
            $null = Set-PSGPOLanguage -Language 'fr-FR'
            Get-PSGPOText 'Minimum password length' | Should -Be 'Longueur minimale du mot de passe'
            Get-PSGPOText 'Registry Item' | Should -Be 'Élément Registre'
            Get-PSGPOText 'Refresh' | Should -Be 'Actualiser'
            $null = Set-PSGPOLanguage -Language 'en-US'
            Get-PSGPOText 'Minimum password length' | Should -Be 'Minimum password length'
        }
    }

    Describe 'Reports shown in the language of the interface' {
        AfterEach { $null = Set-PSGPOLanguage -Language 'en-US' }

        It 'Translates a path, a value and its unit, a list, a label and its value, a note' {
            $null = Set-PSGPOLanguage -Language 'fr-FR'
            ConvertTo-PSGPODisplayText 'Policies > Windows Settings > Security Settings > Account Policies > Password Policy' |
                Should -Be 'Stratégies > Paramètres Windows > Paramètres de sécurité > Stratégies de comptes > Stratégie de mot de passe'
            ConvertTo-PSGPODisplayText '8 hours' | Should -Be '8 heures'
            ConvertTo-PSGPODisplayText 'Success, Failure' | Should -Be 'Réussite, Échec'
            ConvertTo-PSGPODisplayText 'Update (disabled)' | Should -Be 'Mettre à jour (désactivé)'
            ConvertTo-PSGPODisplayText "Enabled`nGPO status: All settings disabled" | Should -Be "Activé$([Environment]::NewLine)État GPO : Tous les paramètres désactivés"
            ConvertTo-PSGPODisplayText 'T1 - Servers - Baseline' | Should -Be 'T1 - Servers - Baseline' -Because 'a name stays as it is'
            ConvertTo-PSGPODisplayText 'HKLM\Software, a value' | Should -Be 'HKLM\Software, a value'
        }

        It 'Leaves the report in English without a language' {
            ConvertTo-PSGPODisplayText '8 hours' | Should -Be '8 hours'
            ConvertTo-PSGPODisplayText '' | Should -Be ''
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
