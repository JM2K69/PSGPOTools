#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# GUI tests: each test opens the real Show-GPOManagerAvalonia window (through the private
# Start-PSGPOManagerWindow -OnShown hook), drives its controls, then the window closes.
# They are skipped when the Avalonia runtime has not been staged with Get-AvaloniaBinaries.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..\..\PSGPOTools\PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force

    $Rid = & (Get-Module PSGPOTools) { Get-PSGPOAvaloniaRid }
    $AvaloniaMissing = -not (Test-Path (Join-Path $PSScriptRoot "..\..\PSGPOTools\Avalonia\bin\$Rid\Avalonia.dll"))
    if ($AvaloniaMissing) {
        Write-Warning "Avalonia runtime not staged for ${Rid}: GUI tests skipped (run PSGPOTools\Avalonia\Get-AvaloniaBinaries.ps1)."
    }
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..\..\sources\PolicyDefinitions')).Path
        Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null

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

                $Rows = @($Ui.registryValuesGrid.ItemsSource)
                ($Rows | Where-Object Key -EQ 'Enable').Value | Should -Be '1'
                ($Rows | Where-Object Key -EQ 'Disable').Value | Should -Be '0'

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
                $Ui.registryValuesGrid.ItemsSource | Should -BeNullOrEmpty
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
}
