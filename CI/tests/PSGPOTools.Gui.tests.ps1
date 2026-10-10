#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# GUI tests: each test opens the real Show-GPOManagerAvalonia window (through the private
# Start-PSGPOManagerWindow -OnShown hook), drives its controls, then the window closes.
# They are skipped when the Avalonia runtime has not been staged with Get-AvaloniaBinaries.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force

    $Rid = & (Get-Module PSGPOTools) { Get-PSGPOAvaloniaRid }
    $AvaloniaMissing = -not (Test-Path (Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Avalonia' 'bin' $Rid 'Avalonia.dll'))
    if ($AvaloniaMissing) {
        Write-Warning "Avalonia runtime not staged for ${Rid}: GUI tests skipped (run PSGPOTools\Avalonia\Get-AvaloniaBinaries.ps1)."
    }
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path
        # Root BeforeAll also runs when every test is skipped: only load the ADMX for the GUI tests.
        $AvaloniaDll = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Avalonia' 'bin' (Get-PSGPOAvaloniaRid) 'Avalonia.dll'
        if (Test-Path $AvaloniaDll) {
            Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
        }

        # Depth-first search of the first tree node matching a condition.
        function Find-TreeNode {
            param($Roots, [scriptblock]$Where)
            $Stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($Root in $Roots) { $Stack.Push($Root) }
            while ($Stack.Count) {
                $Node = $Stack.Pop()
                if (& $Where $Node) { return $Node }
                foreach ($Child in $Node.Children) { $Stack.Push($Child) }
            }
        }

        function Get-TreePolicy {
            param($Roots)
            $Stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($Root in $Roots) { $Stack.Push($Root) }
            while ($Stack.Count) {
                $Node = $Stack.Pop()
                foreach ($Child in $Node.Children) { $Stack.Push($Child) }
                if ($Node.Tag -is [GPOToolsPolicy]) { $Node.Tag }
            }
        }

        function Invoke-Click {
            param($Control)
            $ClickEvent = if ($Control -is [Avalonia.Controls.MenuItem]) { [Avalonia.Controls.MenuItem]::ClickEvent } else { [Avalonia.Controls.Button]::ClickEvent }
            $Control.RaiseEvent([Avalonia.Interactivity.RoutedEventArgs]::new($ClickEvent))
        }

        $DefenderPolicy = [GPOToolsUtility]::Policies | Where-Object ID -EQ 'DisableAntiSpywareDefender'
    }

    Describe 'Show-GPOManagerAvalonia window' -Skip:$AvaloniaMissing {
        It 'Opens with the User and Machine scopes and the default breadcrumb' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Ui.Window.IsVisible | Should -BeTrue
                $Ui.treeView.ItemsSource.Header | Should -Be @('User', 'Machine')
                $Ui.breadcrumbTextBlock.Text | Should -Be 'Select a policy to see its path'
                @(Get-TreePolicy $Ui.treeView.ItemsSource).Count | Should -Be ([GPOToolsUtility]::Policies.Count)
            }
        }

        It 'Shows the details and breadcrumb of the selected policy' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) [object]::ReferenceEquals($n.Tag, $DefenderPolicy) }
                $Ui.treeView.SelectedItem = $Node

                $Ui.displayNameTextBox.Text | Should -Be $DefenderPolicy.DisplayName
                $Ui.descriptionTextBox.Text | Should -Be $DefenderPolicy.Description
                $Ui.scopeTextBox.Text | Should -Be 'Machine'
                $Ui.registryPathTextBox.Text | Should -Be 'HKLM:\Software\Policies\Microsoft\Windows Defender'
                $Ui.registryKeyTextBox.Text | Should -Be 'DisableAntiSpyware'

                $Rows = @($Ui.registryValuesList.ItemsSource)
                ($Rows | Where-Object Key -EQ 'Enabled').Value | Should -Be 'Software\Policies\Microsoft\Windows Defender\DisableAntiSpyware = 1 (DWord)'
                ($Rows | Where-Object Key -EQ 'Disabled').Value | Should -Be 'Software\Policies\Microsoft\Windows Defender\DisableAntiSpyware = 0 (DWord)'

                $Ui.breadcrumbTextBlock.Text | Should -BeLike "*Machine > Windows Components > *$($DefenderPolicy.Category.DisplayName) > $($DefenderPolicy.DisplayName)"
            }
        }

        It 'Clears the details when a category is selected' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) [object]::ReferenceEquals($n.Tag, $DefenderPolicy) }
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsCategory] }

                $Ui.displayNameTextBox.Text | Should -BeNullOrEmpty
                $Ui.registryPathTextBox.Text | Should -BeNullOrEmpty
                $Ui.registryValuesList.ItemsSource | Should -BeNullOrEmpty
            }
        }

        It 'Filters the tree with the search button and the Enter key' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Ui.searchTextBox.Text = 'BitLocker'
                Invoke-Click $Ui.searchButton
                $Found = @(Get-TreePolicy $Ui.treeView.ItemsSource)
                $Found.Count | Should -BeGreaterThan 0
                $Found | ForEach-Object { $_.DisplayName | Should -BeLike '*bitlocker*' }

                $Ui.searchTextBox.Text = ''
                $KeyArgs = [Avalonia.Input.KeyEventArgs]::new()
                $KeyArgs.RoutedEvent = [Avalonia.Input.InputElement]::KeyDownEvent
                $KeyArgs.Key = [Avalonia.Input.Key]::Enter
                $Ui.searchTextBox.RaiseEvent($KeyArgs)
                @(Get-TreePolicy $Ui.treeView.ItemsSource).Count | Should -Be ([GPOToolsUtility]::Policies.Count)
            }
        }

        It 'Toggles between the dark and light themes' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Before = $Ui.themeToggleButton.Content
                Invoke-Click $Ui.themeToggleButton
                $First = $Ui.Window.RequestedThemeVariant
                $Ui.themeToggleButton.Content | Should -Not -Be $Before

                Invoke-Click $Ui.themeToggleButton
                $Ui.Window.RequestedThemeVariant | Should -Not -Be $First
                $Ui.themeToggleButton.Content | Should -Be $Before

                # The label always offers the other theme than the one displayed.
                $Dark = [Avalonia.Styling.ThemeVariant]::Dark
                $Ui.themeToggleButton.Content | Should -BeLike $(if ($Ui.Window.RequestedThemeVariant -eq $Dark) { '*Light mode' } else { '*Dark mode' })
            }
        }

        It 'Copies the <Item> of the selected policy to the clipboard' -ForEach @(
            @{ Item = 'name'; MenuItem = 'copyNameMenuItem'; Expected = { $DefenderPolicy.DisplayName } }
            @{ Item = 'registry path'; MenuItem = 'copyRegistryMenuItem'; Expected = { $DefenderPolicy.Registry.Path } }
            @{ Item = 'PowerShell command'; MenuItem = 'copyCommandMenuItem'
               Expected = { "Get-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows Defender' -Name 'DisableAntiSpyware'" } }
        ) {
            $State = @{ Text = $null }
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) [object]::ReferenceEquals($n.Tag, $DefenderPolicy) }
                Invoke-Click $Ui[$MenuItem]
                $State.Text = $Ui.Window.Clipboard.GetTextAsync().GetAwaiter().GetResult()
            }
            $State.Text | Should -Be (& $Expected)
        }

        It 'Warns when no policy is loaded' {
            [GPOToolsUtility]::RemoveAll()
            try {
                Start-PSGPOManagerWindow -WarningVariable Warn 3>$null -OnShown {
                    param($Ui)
                    $Ui.treeView.ItemsSource | Should -BeNullOrEmpty
                    $Ui.breadcrumbTextBlock.Text | Should -BeLike 'No policy loaded*'
                }
                $Warn | Should -Not -BeNullOrEmpty
            } finally {
                Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
            }
        }
    }

    Describe 'Policy setting form' -Skip:$AvaloniaMissing {
        BeforeAll {
            function Select-TestPolicy {
                param($Ui, [string]$Id, [string]$Scope)
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource {
                    param($n) $n.Tag -is [GPOToolsPolicy] -and $n.Tag.ID -eq $Id -and (-not $Scope -or "$($n.Tag.Scope)" -eq $Scope)
                }.GetNewClosure()
            }
            function Get-PreviewLine {
                param($Ui)
                # 'Title | Key | Value name | Data' for each change of the preview list
                @($Ui.registryPreviewList.ItemsSource | ForEach-Object { '{0} | {1} | {2} | {3}' -f $_.Title, $_.Key, $_.ValueName, $_.Data })
            }
        }

        It 'Builds the options of AxISURLZonePolicies from the ADMX and ADML' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                Select-TestPolicy $Ui 'AxISURLZonePolicies'
                $Controls = $Ui.Editing.Editor.Controls

                $Combo = $Controls['InstallTrustedOCX']
                $Combo | Should -BeOfType ([Avalonia.Controls.ComboBox])
                @($Combo.ItemsSource) | Should -Be @("Don't install", 'Prompt the user', 'Silently install')
                $Combo.SelectedItem | Should -Be 'Silently install'
                $Controls['IgnoreUnknownCA'] | Should -BeOfType ([Avalonia.Controls.CheckBox])
                $Controls['IgnoreUnknownCA'].IsChecked | Should -BeFalse

                # Presentation order: three dropdowns, the free text, then the check boxes.
                $Boxes = @($Ui.optionsHost.Content.Children)
                $Boxes.Count | Should -Be 8
                $Boxes[3] | Should -BeOfType ([Avalonia.Controls.TextBlock])
                $Boxes[3].Text | Should -BeLike 'Permit connection to trusted sites*'
            }
        }

        It 'Enables the options and fills the preview only when the policy is enabled' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                Select-TestPolicy $Ui 'AxISURLZonePolicies'
                $Ui.notConfiguredRadio.IsChecked | Should -BeTrue
                $Ui.optionsHost.IsEnabled | Should -BeFalse
                $Ui.registryPreviewList.ItemsSource | Should -BeNullOrEmpty
                $Ui.previewEmptyTextBlock.IsVisible | Should -BeTrue
                $Ui.settingTitleTextBlock.Text | Should -Be 'Establish ActiveX installation policy for sites in Trusted zones'

                $Ui.enabledRadio.IsChecked = $true
                $Ui.previewEmptyTextBlock.IsVisible | Should -BeFalse
                $Ui.optionsHost.IsEnabled | Should -BeTrue
                Get-PreviewLine $Ui | Should -Contain 'Set REG_DWORD | HKLM\SOFTWARE\Policies\Microsoft\Windows\AxInstaller\AxISURLZonePolicies | InstallTrustedOCX | 2'

                # Editing an option updates the preview.
                $Ui.Editing.Editor.Controls['InstallTrustedOCX'].SelectedItem = "Don't install"
                $Ui.Editing.Editor.Controls['IgnoreUnknownCA'].IsChecked = $true
                $Lines = Get-PreviewLine $Ui
                $Lines | Should -Contain 'Set REG_DWORD | HKLM\SOFTWARE\Policies\Microsoft\Windows\AxInstaller\AxISURLZonePolicies | InstallTrustedOCX | 0'
                $Lines | Should -Contain 'Set REG_DWORD | HKLM\SOFTWARE\Policies\Microsoft\Windows\AxInstaller\AxISURLZonePolicies | IgnoreUnknownCA | 1'

                $Ui.disabledRadio.IsChecked = $true
                $Ui.optionsHost.IsEnabled | Should -BeFalse
                @(Get-PreviewLine $Ui | Where-Object { $_ -like 'Delete value (editor default) | HKLM\*' }).Count | Should -Be 7
            }
        }

        It 'Renders the preview rows on screen, with the key, at a 1333x750 window size' {
            # Regression: the former DataGrid kept its header height, so the rows were never visible.
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Ui.Window.Width = 1333
                $Ui.Window.Height = 750
                Select-TestPolicy $Ui 'Biometrics_EnableBio'
                $Ui.enabledRadio.IsChecked = $true
                $Ui.Window.UpdateLayout()

                Get-PreviewLine $Ui | Should -Be 'Set REG_DWORD | HKLM\SOFTWARE\Policies\Microsoft\Biometrics | Enabled | 1'
                $Row = $Ui.registryPreviewList.ContainerFromIndex(0)
                $Row | Should -Not -BeNullOrEmpty
                $Row.Bounds.Height | Should -BeGreaterThan 40
                # The row is inside the visible part of the Setting tab, without scrolling.
                $Origin = [Avalonia.VisualExtensions]::TranslatePoint($Row, [Avalonia.Point]::new(0, 0), $Ui.Window)
                $Origin.Value.Y + $Row.Bounds.Height | Should -BeLessThan $Ui.Window.Bounds.Height
            }
        }

        It 'Edits the free entries of the DisallowCpls list' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                Select-TestPolicy $Ui 'DisallowCpls'
                $Ui.enabledRadio.IsChecked = $true
                $List = $Ui.Editing.Editor.Controls['DisallowCplsList']
                foreach ($Entry in 'Microsoft.Mouse', 'Microsoft.System', 'Microsoft.Sound') {
                    $List.NameInput.Text = $Entry
                    Invoke-Click $List.Add
                }
                $List.ListBox.SelectedIndex = 1
                Invoke-Click $List.Remove
                @($List.Entries) | Should -Be @('Microsoft.Mouse', 'Microsoft.Sound')

                $Lines = Get-PreviewLine $Ui
                $Lines | Should -Contain 'Delete all values of the key (editor default) | HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl | (all values) | -'
                $Lines | Should -Contain 'Set REG_SZ | HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl | 1 | Microsoft.Mouse'
                $Lines | Should -Contain 'Set REG_SZ | HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl | 2 | Microsoft.Sound'
                $List.ValueInput.IsVisible | Should -BeFalse
            }
        }

        It 'Shows the validation error of a required text' {
            $Policy = [GPOToolsUtility]::Policies | Where-Object { $_.Elements.Count -eq 1 -and $_.Elements[0].Type -eq 'Text' -and $_.Elements[0].Required -and -not $_.Elements[0].DefaultValue } | Select-Object -First 1
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                Select-TestPolicy $Ui $Policy.ID "$($Policy.Scope)"
                $Ui.enabledRadio.IsChecked = $true
                $Ui.settingErrorTextBlock.Text | Should -BeLike '*is required.'
                $Ui.registryPreviewList.ItemsSource | Should -BeNullOrEmpty
                $Ui.previewEmptyTextBlock.Text | Should -BeLike 'Fix the options*'

                $Ui.Editing.Editor.Controls[$Policy.Elements[0].Id].Text = 'Contoso'
                # Avalonia posts TextChanged to the dispatcher: run it before checking.
                [Avalonia.Threading.Dispatcher]::UIThread.RunJobs()
                $Ui.settingErrorTextBlock.Text | Should -BeNullOrEmpty
                @(Get-PreviewLine $Ui)[-1] | Should -BeLike 'Set REG_*SZ | HKCU\* | * | Contoso'
            }
        }
    }
}
