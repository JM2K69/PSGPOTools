#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# GUI tests: each test opens the real Show-GPOManagerAvalonia window (through the private
# Start-PSGPOManagerWindow -OnShown hook), drives its controls, then the window closes.
# They are skipped when the Avalonia runtime has not been staged with Get-AvaloniaBinaries.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    # Evaluated during discovery, here and not in BeforeDiscovery: InModuleScope runs this block
    # in the module scope, where the variables of the test file are not visible (-Skip:$null).
    $Rid = Get-PSGPOAvaloniaRid
    $AvaloniaMissing = -not (Test-Path (Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Avalonia' 'bin' $Rid 'Avalonia.dll'))
    if ($AvaloniaMissing) {
        Write-Warning "Avalonia runtime not staged for ${Rid}: GUI tests skipped (run PSGPOTools/Avalonia/Get-AvaloniaBinaries.ps1)."
    }

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

        # Runs the Avalonia loop (platform events included) until $Until is true or the timeout,
        # instead of blocking the UI thread: the X11 clipboard answers through window messages.
        function Invoke-UiLoop {
            param([scriptblock]$Until = { $false }, [int]$TimeoutMilliseconds = 5000)
            $Frame = [Avalonia.Threading.DispatcherFrame]::new()
            $Timer = [Avalonia.Threading.DispatcherTimer]::new()
            $Timer.Interval = [TimeSpan]::FromMilliseconds(20)
            $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
            $Timer.Add_Tick({
                if ((& $Until) -or [DateTime]::UtcNow -gt $Deadline) {
                    $Timer.Stop()
                    $Frame.Continue = $false
                }
            }.GetNewClosure())
            $Timer.Start()
            [Avalonia.Threading.Dispatcher]::UIThread.PushFrame($Frame)
        }

        function Wait-UiTask {
            param([System.Threading.Tasks.Task]$Task)
            # Not a closure: it must see $Task through this function scope.
            Invoke-UiLoop -Until { $Task.IsCompleted }
            if (-not $Task.IsCompleted) { throw 'The UI task did not complete within 5 seconds.' }
            $Task.GetAwaiter().GetResult()
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
                $Before = $Ui.themeToggleText.Text
                $BeforeIcon = $Ui.themeToggleIcon.Data
                Invoke-Click $Ui.themeToggleButton
                $First = $Ui.Window.RequestedThemeVariant
                $Ui.themeToggleText.Text | Should -Not -Be $Before
                $Ui.themeToggleIcon.Data | Should -Not -Be $BeforeIcon

                Invoke-Click $Ui.themeToggleButton
                $Ui.Window.RequestedThemeVariant | Should -Not -Be $First
                $Ui.themeToggleText.Text | Should -Be $Before

                # The label always offers the other theme than the one displayed.
                $Dark = [Avalonia.Styling.ThemeVariant]::Dark
                $Ui.themeToggleText.Text | Should -Be $(if ($Ui.Window.RequestedThemeVariant -eq $Dark) { 'Light mode' } else { 'Dark mode' })
            }
        }

        It 'Copies the <Item> of the selected policy to the clipboard' -ForEach @(
            @{ Item = 'name'; MenuItem = 'copyNameMenuItem'; Expected = { $DefenderPolicy.DisplayName } }
            @{ Item = 'registry path'; MenuItem = 'copyRegistryMenuItem'; Expected = { $DefenderPolicy.Registry.Path } }
            @{ Item = 'PowerShell command'; MenuItem = 'copyCommandMenuItem'
               Expected = { "Get-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows Defender' -Name 'DisableAntiSpyware'" } }
        ) {
            $State = @{ Copied = $null; ReadBack = $null }
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) [object]::ReferenceEquals($n.Tag, $DefenderPolicy) }
                Invoke-Click $Ui[$MenuItem]

                # Our part: the right text is handed to the clipboard and the copy completes.
                $Copy = $Ui.Clipboard
                if ($Copy.Error) { throw "SetTextAsync threw $($Copy.Error.GetType().FullName): $($Copy.Error.Message)" }
                $Copy.Task | Should -Not -BeNullOrEmpty -Because 'the menu item must start a copy'
                try { Wait-UiTask $Copy.Task } catch {
                    throw "SetTextAsync failed: $($_.Exception.GetBaseException().GetType().FullName): $($_.Exception.GetBaseException().Message)"
                }
                $State.Copied = $Copy.Text

                # The platform part: read the system clipboard back.
                try { $State.ReadBack = Wait-UiTask $Ui.Window.Clipboard.GetTextAsync() } catch {
                    throw "GetTextAsync failed: $($_.Exception.GetBaseException().GetType().FullName): $($_.Exception.GetBaseException().Message)"
                }
            }
            $State.Copied | Should -Be (& $Expected) -Because 'the menu item must copy this text'

            # Under Xvfb (Linux CI) the X11 clipboard reads back $null although the copy succeeded:
            # report it as inconclusive rather than pass without proof, until checked on a Linux desktop.
            if (-not $IsWindows -and $null -eq $State.ReadBack) {
                Set-ItResult -Inconclusive -Because 'the X11 clipboard returned nothing under Xvfb; the read back is only checked on Windows so far'
                return
            }
            $State.ReadBack | Should -Be (& $Expected) -Because 'the system clipboard must hold the copied text'
        }

        It 'Shows the security settings and warns when no ADMX policy is loaded' {
            [GPOToolsUtility]::RemoveAll()
            try {
                Start-PSGPOManagerWindow -WarningVariable Warn 3>$null -OnShown {
                    param($Ui)
                    # The security settings do not come from the ADMX files (Linux without ADMX).
                    # The preferences do not either: both scopes have them.
                    $Ui.treeView.ItemsSource.Header | Should -Be @('User', 'Machine')
                    @($Ui.treeView.ItemsSource)[0].Children.Header | Should -Be @('Preferences')
                    @($Ui.treeView.ItemsSource)[1].Children.Header | Should -Be @('Windows Settings', 'Preferences')
                    $Ui.breadcrumbTextBlock.Text | Should -BeLike 'No ADMX policy loaded*'
                    $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsSecuritySetting] -and $n.Tag.Key -eq 'MinimumPasswordLength' }
                    $Ui.settingTitleTextBlock.Text | Should -Be 'Minimum password length'
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
            Start-PSGPOManagerWindow -StartView Editor -OnShown {
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
                # TranslatePoint gives $null when it cannot place the row: the check would pass without proof.
                $Origin | Should -Not -BeNullOrEmpty
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

    Describe 'Group Policy Management view' -Skip:$AvaloniaMissing {
        BeforeAll {
            $SamplePath = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Samples' 'Directory.sample.json'
            . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')

            # Node of the domain tree at a path of headers, from the domain.
            function Get-DomainNode {
                param($Ui, [string[]]$Path)
                $Node = @($Ui.domainTreeView.ItemsSource)[0]
                foreach ($Header in $Path) {
                    $Node = $Node.Children | Where-Object Header -EQ $Header | Select-Object -First 1
                    if (-not $Node) { throw "No node '$Header' in the domain tree." }
                }
                $Node
            }
        }
        BeforeEach {
            # Each test changes the directory: start again from the sample.
            $Directory = Import-PSGPODirectory -Path $SamplePath
        }
        BeforeAll {
            function Get-PreviewLine {
                param($Ui)
                @($Ui.registryPreviewList.ItemsSource | ForEach-Object { '{0} | {1} | {2} | {3}' -f $_.Title, $_.Key, $_.ValueName, $_.Data })
            }
            function Select-GuiPolicy {
                param($Ui, [string]$Id)
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsPolicy] -and $n.Tag.ID -eq $Id }.GetNewClosure()
            }
        }

        It 'Opens on the domain tree, the domain expanded' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.managementView.IsVisible | Should -BeTrue
                $Ui.editorView.IsVisible | Should -BeFalse
                $Ui.searchPanel.IsVisible | Should -BeFalse
                $Ui.managementButton.IsVisible | Should -BeFalse
                $Ui.browseAdmxButton.IsVisible | Should -BeTrue
                $Ui.directoryEmptyTextBlock.IsVisible | Should -BeFalse
                $Ui.subtitleTextBlock.Text | Should -Be 'Group Policy Management - corp.contoso.com'

                $Domain = @($Ui.domainTreeView.ItemsSource)[0]
                $Domain.Header | Should -Be 'corp.contoso.com'
                $Domain.Children[-3].Header | Should -Be 'Group Policy Objects'
                $Domain.Children[-2].Header | Should -Be 'WMI Filters'
                $Domain.Children[-1].Header | Should -Be 'Deleted GPOs' -Because 'the recycle bin of the GPOs, from their backups'
                # The IsExpanded binding reaches the tree view item.
                $Ui.Window.UpdateLayout()
                $DomainItem = $Ui.domainTreeView.ContainerFromItem($Domain)
                $DomainItem.IsExpanded | Should -BeTrue
                # The icon of the node is drawn from the shipped SVG, in its colour (no emoji: Linux has no font for them).
                $Icon = [Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($DomainItem) | Where-Object { $_ -is [Avalonia.Controls.PathIcon] } | Select-Object -First 1
                $Icon.Data | Should -BeOfType ([Avalonia.Media.StreamGeometry])
                $Icon.Data.Bounds.Width | Should -BeGreaterThan 10
                "$($Icon.Foreground)" | Should -Be '#ff0f6cbd'
            }
        }

        It 'Shows the links of the selected OU and only its context menu items' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Paris', 'Workstations'
                $Ui.directoryTitleTextBlock.Text | Should -Be 'Workstations'
                $Ui.directoryBreadcrumbTextBlock.Text | Should -Be 'corp.contoso.com > Sites > Paris > Workstations'
                $Ui.linksHeaderTextBlock.Text | Should -Be 'Linked Group Policy Objects (3)'
                @($Ui.linksList.ItemsSource.Name) | Should -Be @(
                    'C - Workstations - Security Baseline Windows 11', 'C - Workstations - BitLocker', 'C - Workstations - Windows Update Ring Broad')
                $Ui.createLinkedGpoMenuItem.IsVisible | Should -BeTrue
                $Ui.newGpoMenuItem.IsVisible | Should -BeFalse
                $Ui.editGpoMenuItem.IsVisible | Should -BeFalse
                $Ui.editGpoButton.IsVisible | Should -BeFalse

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Paris', 'Workstations', 'C - Workstations - BitLocker'
                $Ui.directoryTitleTextBlock.Text | Should -Be 'C - Workstations - BitLocker'
                $Ui.linksHeaderTextBlock.Text | Should -Be 'Links (2)'
                $Ui.createLinkedGpoMenuItem.IsVisible | Should -BeFalse
                $Ui.editGpoMenuItem.IsVisible | Should -BeTrue
                $Ui.editGpoButton.IsVisible | Should -BeTrue

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.newGpoMenuItem.IsVisible | Should -BeTrue
                $Ui.createLinkedGpoMenuItem.IsVisible | Should -BeFalse
                $Ui.editGpoMenuItem.IsVisible | Should -BeFalse
            }
        }

        It 'Creates a GPO linked to the selected OU from the context menu' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users'
                Invoke-Click $Ui.createLinkedGpoMenuItem
                $Ui.newGpoPanel.IsVisible | Should -BeTrue
                $Ui.newGpoTitleTextBlock.Text | Should -Be 'New GPO in corp.contoso.com, linked to Users'
                $Ui.newGpoNameTextBox.Text | Should -Be 'New Group Policy Object'

                $Ui.newGpoNameTextBox.Text = 'U - Lyon - Proxy'
                Invoke-Click $Ui.newGpoCreateButton

                $Ui.newGpoPanel.IsVisible | Should -BeFalse
                $Gpo = $Ui.Directory.FindGpo('U - Lyon - Proxy')
                $Gpo | Should -Not -BeNullOrEmpty
                $Users = $Ui.Directory.Domain.Children | Where-Object Name -EQ 'Sites' | ForEach-Object Children | Where-Object Name -EQ 'Lyon' | ForEach-Object Children | Where-Object Name -EQ 'Users'
                $Users.Links[-1].Gpo | Should -Be $Gpo
                $Users.Links[-1].Order | Should -Be 5

                # The new link is selected, its OU expanded, and shown in the tree after the other links.
                $Selected = $Ui.domainTreeView.SelectedItem
                $Selected.Tag | Should -Be $Users.Links[-1]
                $Selected.Parent.IsExpanded | Should -BeTrue
                $Selected.Parent.Parent.IsExpanded | Should -BeTrue
                $Selected.Parent.Children[4].Header | Should -Be 'U - Lyon - Proxy'
                $Ui.directoryTitleTextBlock.Text | Should -Be 'U - Lyon - Proxy'
                (Get-DomainNode $Ui 'Group Policy Objects').Children.Header | Should -Contain 'U - Lyon - Proxy'
            }
        }

        It 'Creates a GPO with its status and its security filtering groups' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users'
                Invoke-Click $Ui.createLinkedGpoMenuItem
                $Ui.newGpoStatusComboBox.SelectedIndex | Should -Be 0
                $Ui.newGpoGroupsCheckBox.IsChecked | Should -BeFalse
                $Ui.newGpoGroupsPanel.IsVisible | Should -BeFalse

                $Ui.newGpoNameTextBox.Text = 'U - Lyon - Proxy'
                $Ui.newGpoStatusComboBox.SelectedIndex = 2
                $Ui.newGpoGroupsCheckBox.IsChecked = $true
                $Ui.newGpoGroupsPanel.IsVisible | Should -BeTrue
                $Ui.newGpoGroupsTextBlock.Text | Should -BeLike 'APPLY_U - Lyon - Proxy: only its members apply the GPO*DENY_U - Lyon - Proxy: its members never apply it*'
                # The users container first, then the OUs of the domain.
                $Containers = @($Ui.newGpoGroupsContainerComboBox.ItemsSource)
                $Containers[0] | Should -Be 'CN=Users,DC=corp,DC=contoso,DC=com'
                $Containers | Should -Contain 'OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com'
                $Ui.newGpoGroupsContainerComboBox.SelectedItem = 'OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com'
                Invoke-Click $Ui.newGpoCreateButton

                $Gpo = $Ui.Directory.FindGpo('U - Lyon - Proxy')
                $Gpo.GetStatus() | Should -Be 'Computer configuration settings disabled'
                $Ui.Directory.GetLinksOf($Gpo).Count | Should -Be 1
                $Ui.directoryResultTextBlock.Text -split '\r?\n' | Should -Be @(
                    "GPO 'U - Lyon - Proxy' created."
                    'GPO status: Computer configuration settings disabled.'
                    'Security filtering groups APPLY_U - Lyon - Proxy and DENY_U - Lyon - Proxy created in OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com.'
                    'Linked to Users.')
                $Ui.directoryResultTextBlock.IsVisible | Should -BeTrue
                # Another selection: the result goes away.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites'
                $Ui.directoryResultTextBlock.IsVisible | Should -BeFalse
            }
        }

        It 'Shows a delegated account its name, and only what it may do' {
            # The fixture domain as a technician of Lyon\Workstations reads it (see PSGPOTools.Delegation.tests.ps1).
            $Set = Get-TestLdapEntrySet
            foreach ($Entry in $Set.Ous) {
                if ($Entry.DistinguishedName -like 'OU=Workstations,OU=Lyon,*') { $Entry.Attributes['allowedattributeseffective'] = [string[]]@('gPLink', 'gPOptions') }
            }
            $Policies = New-TestLdapEntry "CN=Policies,CN=System,$TestLdapDomainDN" @{ allowedChildClassesEffective = 'groupPolicyContainer' }
            $Delegated = ConvertTo-PSGPOLdapDirectory -Server 'dc.hardenbox.labo' -VendorName 'Samba Team' -DomainEntry $Set.Domain `
                -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos -PoliciesEntry $Policies -EffectiveRights 3>$null
            $Delegated.Account = 'HARDENBOX\tier2'
            Start-PSGPOManagerWindow -Directory $Delegated -OnShown {
                param($Ui)
                $Ui.subtitleTextBlock.Text | Should -Be 'Group Policy Management - hardenbox.labo (Samba AD) - connected as HARDENBOX\tier2'
                @($Ui.statusBarList.ItemsSource.Text) | Should -Contain 'Connected as HARDENBOX\tier2 (delegated rights)'

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon'
                $Ui.createLinkedGpoMenuItem.IsVisible | Should -BeFalse -Because 'Lyon is only the path to Workstations'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon', 'Workstations (blocks inheritance)'
                $Ui.createLinkedGpoMenuItem.IsVisible | Should -BeTrue

                # A GPO linked to its OU that it cannot edit: the link can go, the GPO is read only.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon', 'Workstations (blocks inheritance)', 'Workstations (enforced)'
                $Ui.editGpoMenuItem.IsVisible | Should -BeFalse
                $Ui.editGpoButton.IsVisible | Should -BeFalse
                $Ui.deleteLinkMenuItem.IsVisible | Should -BeTrue
                ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Your rights').Value | Should -Be 'Read only'
            }
        }

        It 'Shows the backups of a GPO as a timeline, what changed at each one, and backs it up' {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $Root = Join-Path $TestDrive "history-$([guid]::NewGuid())"
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Set-PSGPOUserSetting -Values @{ BackupPath = $Root }
            try {
                $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
                $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
                Start-Sleep -Milliseconds 1100
                $Pol = [GPOToolsRegistryPol]::new()
                Set-PSGPOPolicyState -Policy ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'Biometrics_EnableBio' | Select-Object -First 1) -Pol $Pol -State Enabled
                $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
                $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
                # Not backed up yet: the current state.
                $Directory.SetGpoStatus($Gpo, 0)

                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Servers - Security Baseline'
                    $Ui.historyTab.IsVisible | Should -BeTrue
                    $Ui.directoryTabs.SelectedItem = $Ui.historyTab
                    $Ui.historyPathTextBox.Text | Should -Be $Root

                    # Oldest first, the current state last; the newest node selected.
                    $Nodes = @($Ui.historyTimelineList.ItemsSource)
                    @($Nodes.Summary) | Should -Be @('first backup', '+1  ~0  -0', '+0  ~1  -0, not backed up')
                    $Nodes[2].IsCurrent | Should -BeTrue
                    $Ui.historyTimelineList.SelectedIndex | Should -Be 2
                    $Ui.historyStatusTextBlock.Text | Should -BeLike '2 backups in*The GPO changed since the last one (Now).'
                    $Ui.historyCompareTextBlock.Text | Should -BeLike 'Changes since the backup of*not backed up yet'
                    $Row = @($Ui.historyChangesList.ItemsSource)[0]
                    "$($Row.Change) | $($Row.Location) | $($Row.Name) | $($Row.Before) | $($Row.After)" |
                        Should -Be 'Changed | GPO > Properties | GPO status | User configuration settings disabled | Enabled'

                    $Ui.historyTimelineList.SelectedIndex = 1
                    $Ui.historyCompareTextBlock.Text | Should -BeLike 'Changes from * to *'
                    @($Ui.historyChangesList.ItemsSource).Name | Should -Be @('Allow the use of biometrics')
                    @($Ui.historyChangesList.ItemsSource)[0].ChangeBrush | Should -Be '#107C10'
                    $Ui.historyTimelineList.SelectedIndex = 0
                    $Ui.historyCompareTextBlock.Text | Should -BeLike 'First backup, *: the settings of the GPO then'

                    # Back up now: the current state becomes the newest backup.
                    Invoke-Click $Ui.historyBackupButton
                    $Ui.historyStatusTextBlock.Text | Should -Be "Backed up in $Root."
                    @($Ui.historyTimelineList.ItemsSource).Count | Should -Be 3
                    @($Ui.historyTimelineList.ItemsSource | Where-Object IsCurrent).Count | Should -Be 0
                    Invoke-Click $Ui.historyBackupButton
                    $Ui.historyStatusTextBlock.Text | Should -BeLike 'Not backed up again*'

                    # Restore the first backup, once confirmed.
                    $Ui.historyTimelineList.SelectedIndex = 0
                    $Ui.historyRestoreButton.IsVisible | Should -BeTrue
                    Invoke-Click $Ui.historyRestoreButton
                    $Ui.historyRestorePanel.IsVisible | Should -BeTrue
                    $Ui.historyRestoreTextBlock.Text | Should -BeLike "Restore the GPO 'C - Servers - Security Baseline' as it was on *backed up first."
                    Invoke-Click $Ui.historyRestoreCancelButton
                    $Ui.historyRestorePanel.IsVisible | Should -BeFalse
                    Invoke-Click $Ui.historyRestoreButton
                    Invoke-Click $Ui.historyRestoreConfirmButton
                    $Ui.historyStatusTextBlock.Text | Should -BeLike 'GPO restored as it was on * (version *); its state before was backed up.'
                    $Ui.Directory.ReadPolicyFile($Gpo, 'Machine') | Should -BeNullOrEmpty -Because 'the first backup had no Registry.pol'
                    $Gpo.GetStatus() | Should -Be 'User configuration settings disabled'
                    $Ui.directoryTabs.SelectedItem | Should -Be $Ui.historyTab
                    # Its state before the restore was backed up: the restore shows as the change of Now.
                    $Nodes = @($Ui.historyTimelineList.ItemsSource)
                    $Nodes[-1].IsCurrent | Should -BeTrue
                    $Ui.historyRestoreButton.IsVisible | Should -BeFalse -Because 'Now is not a backup'
                }
                @(Get-PSGPOBackup -Path $Root).Count | Should -Be 3 -Because "the state before the restore was the newest backup already"
            } finally {
                $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
            }
        }

        It 'Backs up with a comment, keeps the notes of a backup, and shows the changes since the approved version' {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $Root = Join-Path $TestDrive "notes-$([guid]::NewGuid())"
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Set-PSGPOUserSetting -Values @{ BackupPath = $Root }
            try {
                $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
                $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName

                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Servers - Security Baseline'
                    $Ui.directoryTabs.SelectedItem = $Ui.historyTab
                    $Ui.historyDriftBorder.IsVisible | Should -BeTrue
                    $Ui.historyDriftTextBlock.Text | Should -BeLike "No approved version yet: check 'Approved'*"
                    $Ui.historyDriftButton.IsVisible | Should -BeFalse

                    # The notes of the selected backup: approve it.
                    $Ui.historyNotesPanel.IsVisible | Should -BeTrue
                    $Ui.historyNotesApprovedCheckBox.Content | Should -Be 'Approved version'
                    $Ui.historyNotesInfoTextBlock.Text | Should -BeLike 'Backed up on *.'
                    $Ui.historyNotesCommentTextBox.Text = 'Baseline reviewed'
                    $Ui.historyNotesLabelsTextBox.Text = 'Q4, Approved, ,q4'
                    $Ui.historyNotesApprovedCheckBox.IsChecked = $true
                    Invoke-Click $Ui.historyNotesSaveButton
                    $Ui.historyStatusTextBlock.Text | Should -BeLike 'Notes of the backup of * saved.'
                    $Node = @($Ui.historyTimelineList.ItemsSource)[0]
                    $Node.IsApproved | Should -BeTrue
                    $Node.NodeFill | Should -Be '#107C10'
                    $Node.LabelsText | Should -Be 'Q4, Approved'
                    $Node.Comment | Should -Be 'Baseline reviewed'
                    $Ui.historyTimelineList.SelectedItem | Should -Be $Node -Because 'the saved backup stays selected'
                    $Ui.historyNotesLabelsTextBox.Text | Should -Be 'Q4' -Because 'the approved label is the check box'
                    $Ui.historyDriftTextBlock.Text | Should -BeLike 'The GPO is its approved version of *'

                    # Changed outside the console: drifted.
                    $Pol = [GPOToolsRegistryPol]::new()
                    Set-PSGPOPolicyState -Policy ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'Biometrics_EnableBio' | Select-Object -First 1) -Pol $Pol -State Enabled
                    $Ui.Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
                    $Ui.directoryTabs.SelectedIndex = 0
                    $Ui.directoryTabs.SelectedItem = $Ui.historyTab
                    $Ui.historyDriftTextBlock.Text | Should -BeLike 'Changed since its approved version of * (+1  ~0  -0).'
                    $Ui.historyDriftBorder.BorderBrush.Color.ToString() | Should -Be '#ffca5010'
                    $Ui.historyDriftButton.IsVisible | Should -BeTrue
                    $Ui.historyNotesPanel.IsVisible | Should -BeFalse -Because 'Now is not a backup'

                    # Backed up with a comment: still not the approved version.
                    $Ui.historyCommentTextBox.Text = 'CHG-1024: biometrics'
                    Invoke-Click $Ui.historyBackupButton
                    $Ui.historyCommentTextBox.Text | Should -Be '' -Because 'the comment went with the backup'
                    $Nodes = @($Ui.historyTimelineList.ItemsSource)
                    $Nodes.Count | Should -Be 2
                    $Nodes[1].Comment | Should -Be 'CHG-1024: biometrics'
                    $Nodes[1].IsApproved | Should -BeFalse
                    $Ui.historyDriftButton.IsVisible | Should -BeTrue
                    Invoke-Click $Ui.historyDriftButton
                    $Ui.historyCompareTextBlock.Text | Should -BeLike 'Changes since the approved version of *'
                    @($Ui.historyChangesList.ItemsSource).Name | Should -Be @('Allow the use of biometrics')
                    $Ui.historyRestoreButton.IsVisible | Should -BeFalse
                }
                (Get-PSGPOBackup -Path $Root | Select-Object -First 1).BackedUpBy | Should -Be $Directory.Account
            } finally {
                $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
            }
        }

        It 'Creates, changes and removes the settings of the configuration of the domain in its window' {
            try {
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    Invoke-Click $Ui.configurationButton
                    $Settings = $Ui.Configuration.Ui
                    $Settings.Window.IsVisible | Should -BeTrue
                    $C = $Settings.Controls
                    $C.pathTextBlock.Text | Should -BeLike 'Configuration of the domain corp.contoso.com, for every console of the domain: SYSVOL\corp.contoso.com\PSGPOTools\Configuration.psd1*(not created yet)*'
                    $C.saveButton.IsEnabled | Should -BeTrue
                    $Rows = @($C.settingsList.ItemsSource)
                    $Rows.Count | Should -Be 17
                    @($Rows | Where-Object Source -EQ 'Default').Count | Should -Be 17
                    ($Rows | Where-Object Key -EQ 'NewGpo.SecurityFilteringGroups.ApplyPrefix').Default | Should -BeLike 'Default: APPLY_ - Names of the groups*'

                    # Create: a choice, a boolean, a text.
                    $C.keyComboBox.SelectedItem = 'NewGpo.SecurityFilteringGroups.Scope'
                    @($C.valueComboBox.ItemsSource) | Should -Be @('Global', 'DomainLocal', 'Universal')
                    $C.valueTextBox.IsVisible | Should -BeFalse
                    $C.valueComboBox.SelectedItem = 'DomainLocal'
                    Invoke-Click $C.setButton
                    $C.keyComboBox.SelectedItem = 'NewGpo.SecurityFilteringGroups.Create'
                    @($C.valueComboBox.ItemsSource) | Should -Be @('True', 'False')
                    $C.valueComboBox.SelectedItem = 'True'
                    Invoke-Click $C.setButton
                    $C.keyComboBox.SelectedItem = 'NewGpo.SecurityFilteringGroups.Container'
                    $C.valueTextBox.Text = 'OU=Servers'
                    Invoke-Click $C.setButton
                    $Row = @($C.settingsList.ItemsSource) | Where-Object Key -EQ 'NewGpo.SecurityFilteringGroups.Container'
                    "$($Row.Value) | $($Row.Source)" | Should -Be 'Value: OU=Servers | Set for the domain'
                    $C.statusTextBlock.Text | Should -BeLike '*not saved yet.'

                    # A wrong value is refused with the reason.
                    $C.keyComboBox.SelectedItem = 'NewGpo.SecurityFilteringGroups.ApplyPrefix'
                    $C.valueTextBox.Text = 'GPO:A'
                    Invoke-Click $C.setButton
                    $C.statusTextBlock.Text | Should -BeLike '*ApplyPrefix must not be empty, nor hold*'
                    (@($C.settingsList.ItemsSource) | Where-Object Key -EQ 'NewGpo.SecurityFilteringGroups.ApplyPrefix').Source | Should -Be 'Default'

                    # Update, then delete (back to the default).
                    $C.keyComboBox.SelectedItem = 'NewGpo.SecurityFilteringGroups.Scope'
                    $C.valueComboBox.SelectedItem = 'Universal'
                    Invoke-Click $C.setButton
                    Invoke-Click $C.removeButton
                    (@($C.settingsList.ItemsSource) | Where-Object Key -EQ 'NewGpo.SecurityFilteringGroups.Scope').Source | Should -Be 'Default'

                    # Closing asks once when the changes are not saved; Save writes them.
                    Invoke-Click $C.closeButton
                    $Settings.Window.IsVisible | Should -BeTrue
                    $C.statusTextBlock.Text | Should -BeLike 'Your changes are not saved*'
                    Invoke-Click $C.saveButton
                    $C.statusTextBlock.Text | Should -BeLike 'Saved:*'
                    Invoke-Click $C.closeButton
                    $Settings.Window.IsVisible | Should -BeFalse

                    # The new GPO form takes the configuration.
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users'
                    Invoke-Click $Ui.createLinkedGpoMenuItem
                    $Ui.newGpoGroupsCheckBox.IsChecked | Should -BeTrue
                    $Ui.newGpoGroupsPanel.IsVisible | Should -BeTrue
                    @($Ui.newGpoGroupsContainerComboBox.ItemsSource)[0] | Should -Be 'OU=Servers,DC=corp,DC=contoso,DC=com'
                    $Ui.newGpoGroupsContainerComboBox.SelectedIndex | Should -Be 0
                }
                $Saved = ConvertFrom-PSGPOConfigurationByte -Bytes $Directory.ReadConfigurationFile()
                $Saved.NewGpo.SecurityFilteringGroups.Create | Should -BeTrue
                $Saved.NewGpo.SecurityFilteringGroups.Container | Should -Be 'OU=Servers'
                $Saved.NewGpo.SecurityFilteringGroups.ContainsKey('Scope') | Should -BeFalse -Because 'it was removed'
            } finally {
                Use-PSGPODomainConfiguration -Directory $null
            }
        }

        It 'Shows the configuration without saving it for a directory that cannot be written' {
            $Directory.IsReadOnly = $true
            try {
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    Invoke-Click $Ui.configurationButton
                    $C = $Ui.Configuration.Ui.Controls
                    $C.saveButton.IsEnabled | Should -BeFalse
                    $C.pathTextBlock.Text | Should -BeLike '*cannot be written: the configuration is shown, not saved*'
                    $Ui.Configuration.Ui.Window.Close()
                }
            } finally {
                Use-PSGPODomainConfiguration -Directory $null
            }
        }

        It 'Proposes the name, status and groups of the configuration of the domain for a new GPO' {
            $Directory.WriteConfigurationFile([System.Text.Encoding]::UTF8.GetBytes("@{ NewGpo = @{ DefaultName = 'C - New'; Status = 'ComputerOnly'; SecurityFilteringGroups = @{ ApplyPrefix = 'GPO-A-'; DenyPrefix = 'GPO-D-' } } }"))
            try {
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users'
                    Invoke-Click $Ui.createLinkedGpoMenuItem
                    $Ui.newGpoNameTextBox.Text | Should -Be 'C - New'
                    $Ui.newGpoStatusComboBox.SelectedIndex | Should -Be 1
                    $Ui.newGpoGroupsCheckBox.IsChecked | Should -BeFalse
                    $Ui.newGpoGroupsTextBlock.Text | Should -BeLike 'GPO-A-C - New: only its members apply the GPO*GPO-D-C - New: its members never apply it*'
                }
            } finally {
                Use-PSGPODomainConfiguration -Directory $null
            }
        }

        It 'Creates, edits, moves and deletes the preference items of a GPO' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                function Select-Preference {
                    param([string]$Scope, [string]$Group, [string]$Name)
                    $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource {
                        param($n) $n.Tag -is [GPOToolsPreferenceNode] -and $n.Tag.Scope -eq $Scope -and $n.Tag.Extension.Name -eq $Name
                    }.GetNewClosure()
                }
                # Outside a GPO: the type, no item.
                Invoke-Click $Ui.browseAdmxButton
                Select-Preference Machine 'Windows Settings' 'Registry'
                $Ui.preferencesPanel.IsVisible | Should -BeTrue
                $Ui.detailsTabs.IsVisible | Should -BeFalse
                $Ui.detailsTitleTextBlock.Text | Should -Be 'Preference Items'
                $Ui.preferencesEmptyTextBlock.Text | Should -BeLike 'Edit a GPO*'
                $Ui.preferencesNewButton.IsEnabled | Should -BeFalse

                Invoke-Click $Ui.managementButton
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                Select-Preference Machine 'Windows Settings' 'Registry'
                $Ui.preferencesTitleTextBlock.Text | Should -Be 'Registry (Computer Configuration)'
                $Ui.preferencesEmptyTextBlock.Text | Should -Be 'This GPO has no Registry item for the computers.'
                @($Ui.preferencesNewTypeComboBox.ItemsSource) | Should -Be @('Registry Item')

                # New item.
                Invoke-Click $Ui.preferencesNewButton
                $Ui.preferencesFormBorder.IsVisible | Should -BeTrue
                $Ui.preferencesFormTitleTextBlock.Text | Should -Be 'New Registry Item'
                $Controls = $Ui.preferencesFormHost.Content.Children
                $Text = { param($Label) $Index = [array]::IndexOf(@($Controls | ForEach-Object { "$($_.Text)" }), $Label); $Controls[$Index + 1] }
                (& $Text 'Key path *').Text = 'SOFTWARE\Contoso'
                (& $Text 'Value name (empty: the key only)').Text = 'Mode'
                (& $Text 'Value data').Text = 'on'
                Invoke-Click $Ui.preferencesSaveButton
                $Ui.preferencesFormBorder.IsVisible | Should -BeFalse
                $Ui.preferencesStatusTextBlock.Text | Should -BeLike 'Registry Item created in Preferences\Registry\Registry.xml (Machine version *).'
                @($Ui.preferencesList.ItemsSource).Name | Should -Be @('Mode')
                @($Ui.preferencesList.ItemsSource)[0].Summary | Should -BeLike 'Update - Hive: HKEY_LOCAL_MACHINE - Key path: SOFTWARE\Contoso*'
                $Ui.preferencesList.SelectedItem.Name | Should -Be 'Mode'

                # A required value missing: the form says so, nothing is written.
                Invoke-Click $Ui.preferencesNewButton
                Invoke-Click $Ui.preferencesSaveButton
                $Ui.preferencesFormErrorTextBlock.Text | Should -Be 'Key path is required.'
                Invoke-Click $Ui.preferencesCancelButton

                # Edit, then a second item moved before it, then delete.
                Invoke-Click $Ui.preferencesEditButton
                $Controls = $Ui.preferencesFormHost.Content.Children
                (& $Text 'Value data').Text = 'off'
                Invoke-Click $Ui.preferencesSaveButton
                @($Ui.preferencesList.ItemsSource)[0].Summary | Should -BeLike '*Value data: off*'
                Invoke-Click $Ui.preferencesNewButton
                $Controls = $Ui.preferencesFormHost.Content.Children
                (& $Text 'Key path *').Text = 'SOFTWARE\Contoso\Agent'
                (& $Text 'Value name (empty: the key only)').Text = ''
                Invoke-Click $Ui.preferencesSaveButton
                @($Ui.preferencesList.ItemsSource).Name | Should -Be @('Mode', 'Agent')
                Invoke-Click $Ui.preferencesUpButton
                @($Ui.preferencesList.ItemsSource).Name | Should -Be @('Agent', 'Mode')
                $Ui.preferencesList.SelectedItem.Name | Should -Be 'Agent'
                Invoke-Click $Ui.preferencesDeleteButton
                $Ui.preferencesDeletePanel.IsVisible | Should -BeTrue
                Invoke-Click $Ui.preferencesDeleteConfirmButton
                @($Ui.preferencesList.ItemsSource).Name | Should -Be @('Mode')
                $Ui.preferencesStatusTextBlock.Text | Should -BeLike "'Agent' deleted*"

                # Only the configured settings: the Registry preferences of the computers.
                $Ui.configuredOnlyCheckBox.IsChecked = $true
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsPreferenceNode] }
                "$($Node.Tag)" | Should -Be 'Registry (Machine)'
                @(Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsPreferenceNode] -and $n.Tag.Scope -eq 'User' }) | Should -BeNullOrEmpty

                # The Settings tab lists the item.
                Invoke-Click $Ui.managementButton
                $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                $Row = @($Ui.computerSettingsList.ItemsSource) | Where-Object Path -EQ 'Policies > Preferences > Windows Settings > Registry'
                $Row.Name | Should -Be 'Mode'
                $Row.State | Should -Be 'Update'
            }
            $Gpo.MachineExtensionNames | Should -Match ([regex]::Escape('{B087BE9D-ED37-454F-AF9C-04291E351182}{BEE07A6A-EC9F-4659-B8C9-0B1937907C83}'))
        }

        It 'Edits the task definition of an immediate task, and warns of a stored password' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Tasks = Get-PSGPOPreferenceExtension -Id ScheduledTasks
            $File = [GPOToolsPreferenceFile]::Parse([System.Text.Encoding]::UTF8.GetBytes(@'
<?xml version="1.0" encoding="utf-8"?>
<ScheduledTasks clsid="{CC63F200-7309-4ba0-B154-A71CD118DBCC}"><ImmediateTaskV2 clsid="{9756B581-76EC-4169-9AFC-0CA8D43ADB5F}" name="Inventory" image="0" changed="2021-01-01 00:00:00" uid="{11111111-2222-3333-4444-555555555555}"><Properties action="C" name="Inventory" runAs="NT AUTHORITY\System" logonType="S4U" cpassword="xyz"><Task version="1.3"/></Properties></ImmediateTaskV2></ScheduledTasks>
'@))
            $Directory.WritePreferenceFile($Gpo, 'Machine', $Tasks.Path, $File.ToBytes(), $Tasks.Cse, $Tasks.Tool)
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsPreferenceNode] -and $n.Tag.Scope -eq 'Machine' -and $n.Tag.Extension.Id -eq 'ScheduledTasks' }
                $Ui.preferencesNewButton.IsVisible | Should -BeTrue
                @($Ui.preferencesNewTypeComboBox.ItemsSource) | Should -Contain 'Immediate Task (Windows 7 and later)'
                $Row = @($Ui.preferencesList.ItemsSource)[0]
                $Row.Name | Should -Be 'Inventory'
                $Row.Flags | Should -Be 'Stores a password readable by any user of the domain (MS14-025)'
                $Ui.preferencesList.SelectedItem = $Row
                $Ui.preferencesEditButton.IsEnabled | Should -BeTrue
                Invoke-Click $Ui.preferencesEditButton
                $Controls = @($Ui.preferencesFormHost.Content.Children)
                # The warning of the password, and the task definition as XML.
                @($Controls | Where-Object { "$($_.Text)" -like 'A password is stored*' }).Count | Should -Be 1
                $Box = $Controls | Where-Object { $_ -is [Avalonia.Controls.TextBox] -and "$($_.Text)" -like '<Task*' }
                $Box.Text | Should -Be '<Task version="1.3" />'
                $Box.Text = '<Task version="1.3"><Actions'
                Invoke-Click $Ui.preferencesSaveButton
                $Ui.preferencesFormErrorTextBlock.Text | Should -BeLike '*the XML is not valid*'
                $Box.Text = '<Task version="1.3"><Actions Context="Author"><Exec><Command>inventory.exe</Command></Exec></Actions></Task>'
                Invoke-Click $Ui.preferencesSaveButton
                $Ui.preferencesFormBorder.IsVisible | Should -BeFalse
                $Saved = [GPOToolsPreferenceFile]::Parse($Ui.Directory.ReadPreferenceFile($Gpo, 'Machine', $Tasks.Path))
                $Saved.Document.SelectSingleNode('//Exec/Command').InnerText | Should -Be 'inventory.exe'
                $Saved.Document.SelectSingleNode('//Properties').GetAttribute('cpassword') | Should -Be 'xyz' -Because 'the stored password is kept as it is'
                $Ui.preferencesDeleteButton.IsEnabled | Should -BeTrue
            }
        }

        It 'Deletes a link from the context menu once confirmed, keeping the GPO' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'U - Lyon - Printers'
                $Ui.deleteLinkMenuItem.IsVisible | Should -BeFalse -Because 'a GPO is not a link'
                ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Security filtering').Value | Should -Be 'Authenticated Users'

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users', 'U - Lyon - Printers'
                $Ui.deleteLinkMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.deleteLinkMenuItem
                $Ui.deleteLinkPanel.IsVisible | Should -BeTrue
                $Ui.deleteLinkTextBlock.Text | Should -BeLike "Delete the link of the GPO 'U - Lyon - Printers' to Users?*not deleted*"
                Invoke-Click $Ui.deleteLinkCancelButton
                $Ui.deleteLinkPanel.IsVisible | Should -BeFalse
                $Users = $Ui.Directory.FindSom('OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com')
                $Users.Links.Count | Should -Be 4

                Invoke-Click $Ui.deleteLinkMenuItem
                Invoke-Click $Ui.deleteLinkConfirmButton
                $Ui.deleteLinkPanel.IsVisible | Should -BeFalse
                @($Users.Links.Gpo.DisplayName) | Should -Not -Contain 'U - Lyon - Printers'
                @($Users.Links.Order) | Should -Be @(1, 2, 3)
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Users
                $Ui.directoryResultTextBlock.Text | Should -Be "Link of the GPO 'U - Lyon - Printers' to Users deleted."
                (Get-DomainNode $Ui 'Sites', 'Lyon', 'Users').Children.Header | Should -Not -Contain 'U - Lyon - Printers'
                (Get-DomainNode $Ui 'Group Policy Objects').Children.Header | Should -Contain 'U - Lyon - Printers'
            }
        }

        It 'Enforces, disables and moves a link, blocks the inheritance and sets the status of a GPO from the context menu' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Users = $Ui.Directory.FindSom('OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com')
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users', 'U - Lyon - Printers'
                $Ui.enforcedLinkMenuItem.IsVisible | Should -BeTrue
                $Ui.enforcedLinkMenuItem.IsChecked | Should -BeFalse
                $Ui.enabledLinkMenuItem.IsChecked | Should -BeTrue
                $Ui.moveLinkUpMenuItem.IsVisible | Should -BeTrue
                $Ui.moveLinkDownMenuItem.IsVisible | Should -BeFalse -Because 'it is the last link'
                $Ui.blockInheritanceMenuItem.IsVisible | Should -BeFalse -Because 'a link is not an OU'

                Invoke-Click $Ui.enforcedLinkMenuItem
                $Link = $Users.Links | Where-Object { $_.Gpo.DisplayName -eq 'U - Lyon - Printers' }
                $Link.Enforced | Should -BeTrue
                $Ui.domainTreeView.SelectedItem.Header | Should -Be 'U - Lyon - Printers (enforced)'
                $Ui.enforcedLinkMenuItem.IsChecked | Should -BeTrue
                $Ui.directoryResultTextBlock.Text | Should -BeLike '*is enforced*'

                Invoke-Click $Ui.moveLinkUpMenuItem
                $Link.Order | Should -Be 3
                @($Users.Links | Sort-Object Order | ForEach-Object { $_.Gpo.DisplayName })[2] | Should -Be 'U - Lyon - Printers'
                $Ui.moveLinkDownMenuItem.IsVisible | Should -BeTrue

                Invoke-Click $Ui.enabledLinkMenuItem
                $Link.Enabled | Should -BeFalse
                $Ui.enabledLinkMenuItem.IsChecked | Should -BeFalse

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users'
                $Ui.blockInheritanceMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.blockInheritanceMenuItem
                $Users.BlockInheritance | Should -BeTrue
                $Ui.domainTreeView.SelectedItem.Header | Should -Be 'Users (blocks inheritance)'

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'U - Lyon - Printers'
                $Ui.gpoStatusMenuItem.IsVisible | Should -BeTrue
                # A user GPO: its computer settings disabled.
                $Ui.gpoStatusComputerDisabledMenuItem.IsChecked | Should -BeTrue
                $Ui.gpoStatusEnabledMenuItem.IsChecked | Should -BeFalse
                Invoke-Click $Ui.gpoStatusAllDisabledMenuItem
                $Ui.Directory.FindGpo('U - Lyon - Printers').GetStatus() | Should -Be 'All settings disabled'
                $Ui.gpoStatusAllDisabledMenuItem.IsChecked | Should -BeTrue
                $Ui.directoryResultTextBlock.Text | Should -BeLike '*All settings disabled*'
            }
        }

        It 'Links a GPO to a WMI filter from its context menu' {
            $Filter = $Directory.NewWmiFilter('Laptops', '', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Laptops - Power Management'
                $Ui.wmiFilterMenuItem.IsVisible | Should -BeTrue
                @($Ui.wmiFilterMenuItem.Items.Header) | Should -Be @('(none)', 'Laptops')
                @($Ui.wmiFilterMenuItem.Items)[0].IsChecked | Should -BeTrue
                Invoke-Click @($Ui.wmiFilterMenuItem.Items)[1]
                $Ui.Directory.FindGpo('C - Laptops - Power Management').WmiFilterId | Should -Be $Filter.Id
                $Ui.directoryResultTextBlock.Text | Should -BeLike "*is linked to the WMI filter 'Laptops'*"
                ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'WMI filter').Value | Should -BeLike 'Laptops (*'
                @($Ui.wmiFilterMenuItem.Items)[1].IsChecked | Should -BeTrue
            }
        }

        It 'Creates a WMI filter in WMI Filters, and deletes it once no GPO uses it' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                $Ui.newWmiFilterMenuItem.IsVisible | Should -BeTrue
                $Ui.deleteWmiFilterMenuItem.IsVisible | Should -BeFalse
                ($Ui.directoryPropertiesList.ItemsSource | Select-Object -First 1).Key | Should -Be 'None'
                Invoke-Click $Ui.newWmiFilterMenuItem
                $Ui.newWmiFilterPanel.IsVisible | Should -BeTrue
                Invoke-Click $Ui.newWmiFilterCreateButton
                $Ui.newWmiFilterErrorTextBlock.Text | Should -Be 'The name of the WMI filter is required.'
                $Ui.newWmiFilterNameTextBox.Text = 'Workstations'
                $Ui.newWmiFilterQueryTextBox.Text = "SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1`n"
                Invoke-Click $Ui.newWmiFilterCreateButton
                $Ui.newWmiFilterPanel.IsVisible | Should -BeFalse
                $Filter = $Ui.Directory.FindWmiFilter('Workstations')
                $Filter.Queries[0].Query | Should -Be 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
                $Filter.Queries[0].Namespace | Should -Be 'root\CIMv2'
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Filter
                $Ui.directoryTitleTextBlock.Text | Should -Be 'Workstations'

                $Ui.deleteWmiFilterMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.deleteWmiFilterMenuItem
                $Ui.deleteWmiFilterTextBlock.Text | Should -BeLike "Delete the WMI filter 'Workstations'? No GPO uses it."
                Invoke-Click $Ui.deleteWmiFilterConfirmButton
                $Ui.Directory.WmiFilters.Count | Should -Be 0
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be 'WmiFilters'
                $Ui.directoryResultTextBlock.Text | Should -Be "WMI filter 'Workstations' deleted."
            }
        }

        It 'Reads the domain again (Refresh, F5), keeping what is selected' {
            $Set = Get-TestLdapEntrySet
            $Read = ConvertTo-PSGPOLdapDirectory -Server 'dc.hardenbox.labo' -VendorName 'Samba Team' -DomainEntry $Set.Domain -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos 3>$null
            # The domain as another console left it: one more GPO.
            $script:Again = ConvertTo-PSGPOLdapDirectory -Server 'dc.hardenbox.labo' -VendorName 'Samba Team' -DomainEntry $Set.Domain -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos 3>$null
            $null = $script:Again.AddGpo('Created by another console', [guid]::Empty)
            Mock Get-PSGPODirectory { $script:Again }
            Mock Use-PSGPODomainConfiguration { }
            Start-PSGPOManagerWindow -Directory $Read -OnShown {
                param($Ui)
                $Ui.refreshButton.IsVisible | Should -BeTrue
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                (Get-DomainNode $Ui 'Group Policy Objects').Children.Header | Should -Not -Contain 'Created by another console'
                Invoke-Click $Ui.refreshButton
                $Ui.directoryResultTextBlock.Text | Should -BeLike 'Reading the domain again from dc.hardenbox.labo...'
                Invoke-UiLoop -Until { $Ui.refreshButton.IsEnabled -and $Ui.directoryResultTextBlock.Text -like '*is read again*' }
                $Ui.directoryResultTextBlock.Text | Should -BeLike 'The domain is read again from dc.hardenbox.labo, at *'
                (Get-DomainNode $Ui 'Group Policy Objects').Children.Header | Should -Contain 'Created by another console'
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be 'GroupPolicyObjects' -Because 'the selection is kept'
                $Ui.Directory.FindGpo('Created by another console') | Should -Not -BeNullOrEmpty -Because 'the same directory object holds the domain read again'
            }
            Should -Invoke Get-PSGPODirectory -Times 1 -ParameterFilter { $Server -eq 'dc.hardenbox.labo' }
        }

        It 'Links an existing GPO from the context menu, offering only the GPOs not linked there' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.linkGpoMenuItem.IsVisible | Should -BeFalse -Because 'only a domain or an OU is linked to'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users', 'U - Lyon - Printers'
                $Ui.linkGpoMenuItem.IsVisible | Should -BeFalse

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users'
                $Users = $Ui.Directory.FindSom('OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com')
                $Ui.linkGpoMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.linkGpoMenuItem
                $Ui.linkGpoPanel.IsVisible | Should -BeTrue
                $Ui.linkGpoTitleTextBlock.Text | Should -Be 'Link an existing GPO of corp.contoso.com to Users'
                $Offered = @($Ui.linkGpoList.ItemsSource)
                $Offered.Count | Should -Be ($Ui.Directory.Gpos.Count - $Users.Links.Count)
                @($Offered.DisplayName) | Should -Not -Contain 'U - Lyon - Printers' -Because 'it is already linked there'
                $Ui.linkGpoConfirmButton.IsEnabled | Should -BeFalse -Because 'no GPO is chosen yet'

                $Ui.linkGpoFilterTextBox.Text = 'no such GPO'
                @($Ui.linkGpoList.ItemsSource).Count | Should -Be 0
                $Ui.linkGpoErrorTextBlock.Text | Should -Be "No GPO named like 'no such GPO' can be linked to Users."
                Invoke-Click $Ui.linkGpoCancelButton
                $Ui.linkGpoPanel.IsVisible | Should -BeFalse

                Invoke-Click $Ui.linkGpoMenuItem
                $Target = $Offered[0]
                $Ui.linkGpoFilterTextBox.Text = $Target.DisplayName.ToUpperInvariant()
                $Ui.linkGpoList.SelectedItem | Should -Be $Target -Because 'the only match is chosen'
                $Ui.linkGpoConfirmButton.IsEnabled | Should -BeTrue
                $Count = $Users.Links.Count
                Invoke-Click $Ui.linkGpoConfirmButton
                $Ui.linkGpoPanel.IsVisible | Should -BeFalse
                $Users.Links.Count | Should -Be ($Count + 1)
                $Users.Links[-1].Gpo | Should -Be $Target
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Users.Links[-1]
                $Ui.directoryResultTextBlock.Text | Should -Be "GPO '$($Target.DisplayName)' linked to Users, link order $($Count + 1)."
                (Get-DomainNode $Ui 'Sites', 'Lyon', 'Users').Children.Header | Should -Contain $Target.DisplayName
            }
        }

        It 'Deletes a GPO once confirmed, keeps it in Deleted GPOs, restores it, and starts a new GPO from a template' {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $Root = Join-Path $TestDrive "bin-$([guid]::NewGuid())"
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Set-PSGPOUserSetting -Values @{ BackupPath = $Root }
            try {
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'Default Domain Policy'
                    $Ui.deleteGpoMenuItem.IsVisible | Should -BeFalse -Because 'a default GPO of the domain is never deleted'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users', 'U - Lyon - Printers'
                    $Ui.deleteGpoMenuItem.IsVisible | Should -BeFalse -Because 'on a link, Delete link deletes the link'

                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'U - Lyon - Printers'
                    $Gpo = $Ui.domainTreeView.SelectedItem.Tag
                    $Ui.deleteGpoMenuItem.IsVisible | Should -BeTrue
                    Invoke-Click $Ui.deleteGpoMenuItem
                    $Ui.deleteGpoPanel.IsVisible | Should -BeTrue
                    $Ui.deleteGpoTextBlock.Text | Should -BeLike "Delete the GPO 'U - Lyon - Printers'? Its 1 link (Users) is deleted too. It is backed up first in $Root*"
                    Invoke-Click $Ui.deleteGpoCancelButton
                    $Ui.Directory.FindGpo('U - Lyon - Printers') | Should -Not -BeNullOrEmpty
                    Invoke-Click $Ui.deleteGpoMenuItem
                    Invoke-Click $Ui.deleteGpoConfirmButton
                    $Ui.Directory.FindGpo('U - Lyon - Printers') | Should -BeNullOrEmpty
                    $Ui.directoryResultTextBlock.Text | Should -Be "GPO 'U - Lyon - Printers' deleted, with its 1 link. Its backup is in Deleted GPOs, to restore it."
                    (Get-DomainNode $Ui 'Sites', 'Lyon', 'Users').Children.Header | Should -Not -Contain 'U - Lyon - Printers'

                    # In the recycle bin: its details, then restored with its link.
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Deleted GPOs'
                    @($Ui.directoryPropertiesList.ItemsSource).Key | Should -Be @('U - Lyon - Printers')
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Deleted GPOs', 'U - Lyon - Printers'
                    $Ui.directoryTitleTextBlock.Text | Should -Be 'U - Lyon - Printers (deleted)'
                    ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Comment').Value | Should -BeLike 'GPO deleted on *'
                    $Ui.historyTab.IsVisible | Should -BeFalse
                    $Ui.restoreDeletedGpoButton.IsVisible | Should -BeTrue
                    $Ui.restoreDeletedGpoMenuItem.IsVisible | Should -BeTrue
                    Invoke-Click $Ui.restoreDeletedGpoButton
                    $Ui.restoreGpoPanel.IsVisible | Should -BeTrue
                    $Ui.restoreGpoLinkCheckBox.Content | Should -Be 'Link it again where it was (1 link)'
                    $Ui.restoreGpoLinkCheckBox.IsChecked | Should -BeTrue
                    Invoke-Click $Ui.restoreGpoConfirmButton
                    $Restored = $Ui.Directory.FindGpo('U - Lyon - Printers')
                    $Restored | Should -Not -BeNullOrEmpty
                    $Restored.Id | Should -Not -Be $Gpo.Id
                    $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Restored
                    $Ui.directoryResultTextBlock.Text | Should -BeLike "GPO 'U - Lyon - Printers' restored from its backup of *, as {*}.*Linked again to Users."
                    (Get-DomainNode $Ui 'Sites', 'Lyon', 'Users').Children.Header | Should -Contain 'U - Lyon - Printers'
                    @((Get-DomainNode $Ui 'Deleted GPOs').Children).Count | Should -Be 0

                    # Its backup made a template, in the History tab; then a new GPO from it.
                    $Ui.directoryTabs.SelectedItem = $Ui.historyTab
                    $Ui.historyNotesTemplateCheckBox.Content | Should -Be 'Template'
                    $Ui.historyNotesTemplateCheckBox.IsChecked = $true
                    Invoke-Click $Ui.historyNotesSaveButton
                    $Ui.directoryTabs.SelectedIndex = 0
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                    Invoke-Click $Ui.newGpoMenuItem
                    @($Ui.newGpoTemplateComboBox.ItemsSource)[0] | Should -Be 'Empty GPO'
                    @($Ui.newGpoTemplateComboBox.ItemsSource)[1] | Should -BeLike 'U - Lyon - Printers, backup of *'
                    $Ui.newGpoTemplateComboBox.SelectedIndex = 1
                    $Ui.newGpoNameTextBox.Text = 'U - Lille - Printers'
                    Invoke-Click $Ui.newGpoCreateButton
                    $New = $Ui.Directory.FindGpo('U - Lille - Printers')
                    $New | Should -Not -BeNullOrEmpty
                    $Ui.directoryResultTextBlock.Text | Should -BeLike "*Settings of the template 'U - Lyon - Printers' copied.*"
                    "$($New.MachineExtensionNames)$($New.UserExtensionNames)" | Should -Be "$($Restored.MachineExtensionNames)$($Restored.UserExtensionNames)"
                }
            } finally {
                $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
            }
        }

        It 'Makes the GPO of a creator wait for its approval, and approves it from the context menu' {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $Root = Join-Path $TestDrive "approval-$([guid]::NewGuid())"
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Set-PSGPOUserSetting -Values @{ BackupPath = $Root }
            $Workflow = {
                param([bool]$Approver)
                [pscustomobject]@{
                    Enabled = $true; Problem = $null; IsApprover = $Approver; IsCreator = -not $Approver
                    Approvers = @('Domain Admins'); ApproverSids = @('S-1-5-21-1-2-3-512'); Creators = @('GPO-Tier1-Admins'); CreatorSids = @('S-1-5-21-1-2-3-1123')
                    AccountCreatorSids = @(); ApprovedOwner = 'Domain Admins'; ApprovedOwnerSid = 'S-1-5-21-1-2-3-512'; CreatorRights = 'EditSettings'
                }
            }
            try {
                $Directory.Account = 'CORP\tech1'
                $Directory.Workflow = & $Workflow $false
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    # A creator: no security filtering groups, and the GPO waits.
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users'
                    Invoke-Click $Ui.createLinkedGpoMenuItem
                    $Ui.newGpoTitleTextBlock.Text | Should -BeLike '*waits for the approval of an approver, and applies to nobody until then'
                    $Ui.newGpoGroupsCheckBox.IsVisible | Should -BeFalse
                    $Ui.newGpoNameTextBox.Text = 'T1 - Lyon - Proxy'
                    Invoke-Click $Ui.newGpoCreateButton
                    $Gpo = $Ui.Directory.FindGpo('T1 - Lyon - Proxy')
                    $Gpo.ApprovalState | Should -Be 'Pending'
                    $Ui.directoryResultTextBlock.Text | Should -BeLike '*It waits for the approval of Domain Admins: it applies to nobody until then.*'
                    (Get-DomainNode $Ui 'Sites', 'Lyon', 'Users').Children.Header | Should -Contain 'T1 - Lyon - Proxy (waiting for approval)'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'T1 - Lyon - Proxy (waiting for approval)'
                    ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Approval').Value | Should -BeLike 'Waiting for approval: it applies to nobody*(created by CORP\tech1).'
                    $Ui.approveGpoMenuItem.IsVisible | Should -BeFalse -Because 'a creator does not approve'

                    # An approver approves it.
                    $Ui.Directory.Workflow = & $Workflow $true
                    $Ui.Directory.Account = 'CORP\admin'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'T1 - Lyon - Proxy (waiting for approval)'
                    $Ui.approveGpoMenuItem.IsVisible | Should -BeTrue
                    Invoke-Click $Ui.approveGpoMenuItem
                    $Ui.approveGpoPanel.IsVisible | Should -BeTrue
                    $Ui.approveGpoTextBlock.Text | Should -BeLike "Approve the GPO 'T1 - Lyon - Proxy', created by CORP\tech1? Its owner becomes Domain Admins*"
                    $Ui.approveGpoRightsComboBox.SelectedItem.Tag | Should -Be 'EditSettings' -Because 'the configuration proposes it'
                    $Ui.approveGpoApplyToTextBox.Text | Should -Be 'Authenticated Users'
                    $Ui.approveGpoDenyToTextBox.Text | Should -Be ''
                    # Its groups do not exist yet: the approver may create them.
                    $Ui.approveGpoGroupsCheckBox.IsVisible | Should -BeTrue
                    $Ui.approveGpoGroupsCheckBox.IsChecked | Should -BeFalse -Because 'the configuration does not check it'
                    $Ui.approveGpoGroupsTextBlock.Text | Should -BeLike 'APPLY_T1 - Lyon - Proxy applies it, DENY_T1 - Lyon - Proxy is denied it; created in CN=Users,DC=corp,DC=contoso,DC=com (Global).'
                    $Ui.approveGpoGroupsCheckBox.IsChecked = $true
                    $Ui.approveGpoFilteringGrid.IsEnabled | Should -BeFalse -Because 'the new groups apply and deny it'
                    $Ui.approveGpoRightsComboBox.SelectedIndex = 0
                    Invoke-Click $Ui.approveGpoConfirmButton
                    $Ui.approveGpoPanel.IsVisible | Should -BeFalse
                    $Gpo.ApprovalState | Should -Be 'Approved'
                    $Gpo.SecurityFiltering | Should -Be @('APPLY_T1 - Lyon - Proxy')
                    $Gpo.DeniedTo | Should -Be @('DENY_T1 - Lyon - Proxy')
                    $Ui.directoryResultTextBlock.Text | Should -BeLike "GPO 'T1 - Lyon - Proxy' approved: owned by Domain Admins, applied by APPLY_T1 - Lyon - Proxy, denied to DENY_T1 - Lyon - Proxy, the creators read it.*Security filtering groups created: CN=APPLY_T1 - Lyon - Proxy,CN=Users,DC=corp,DC=contoso,DC=com; CN=DENY_T1 - Lyon - Proxy,CN=Users,DC=corp,DC=contoso,DC=com.*Backed up as its approved version."
                    (Get-DomainNode $Ui 'Group Policy Objects').Children.Header | Should -Contain 'T1 - Lyon - Proxy'
                    $Ui.approveGpoMenuItem.IsVisible | Should -BeFalse
                }
                (Get-PSGPOBackup -Path $Root -Approved).DisplayName | Should -Be 'T1 - Lyon - Proxy'
            } finally {
                $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
            }
        }

        It 'Does not link a GPO whose security filtering failed, and says why' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users'
                Invoke-Click $Ui.createLinkedGpoMenuItem
                $Name = 'U - ' + ('x' * 60)
                $Ui.newGpoNameTextBox.Text = $Name
                $Ui.newGpoGroupsCheckBox.IsChecked = $true
                $Ui.newGpoGroupsTextBlock.Text | Should -BeLike '*longer than 64 characters*'
                Invoke-Click $Ui.newGpoCreateButton

                $Gpo = $Ui.Directory.FindGpo($Name)
                $Gpo | Should -Not -BeNullOrEmpty -Because 'the GPO itself was created'
                $Ui.Directory.GetLinksOf($Gpo).Count | Should -Be 0 -Because 'without its filtering it would apply to everyone'
                $Ui.directoryResultTextBlock.Text | Should -BeLike '*security filtering groups are not set*longer than 64 characters*not linked to Users*'
                $Ui.directoryResultTextBlock.Foreground.Color.ToString() | Should -Be '#ffd13438'
            }
        }

        It 'Keeps the tree aligned to the left when a long name is selected, trimming it' {
            # Regression (Linux, 1200 px): selecting a deep link with a long name scrolled the tree
            # horizontally and cut the domain and the OUs.
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.Window.Width = 1000
                $Node = Get-DomainNode $Ui 'Sites', 'Paris', 'Workstations', 'C - Workstations - Security Baseline Windows 11 (enforced)'
                for ($Parent = $Node.Parent; $Parent; $Parent = $Parent.Parent) { $Parent.IsExpanded = $true }
                $Ui.domainTreeView.ItemsSource = @($Ui.domainTreeView.ItemsSource)
                $Ui.domainTreeView.SelectedItem = $Node
                $Ui.Window.UpdateLayout()
                [Avalonia.Threading.Dispatcher]::UIThread.RunJobs()
                $Ui.Window.UpdateLayout()

                $Scroll = [Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Ui.domainTreeView) | Where-Object { $_ -is [Avalonia.Controls.ScrollViewer] } | Select-Object -First 1
                $Scroll.Offset.X | Should -Be 0
                $Scroll.Extent.Width | Should -BeLessOrEqual ($Scroll.Viewport.Width + 1)
            }
        }

        It 'Keeps the form open with the error when the name is already used' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers'
                Invoke-Click $Ui.createLinkedGpoMenuItem
                $Ui.newGpoErrorTextBlock.IsVisible | Should -BeFalse -Because 'an empty error takes no room'
                $Ui.newGpoNameTextBox.Text = 'c - servers - windows update'
                Invoke-Click $Ui.newGpoCreateButton
                $Ui.newGpoPanel.IsVisible | Should -BeTrue
                $Ui.newGpoErrorTextBlock.Text | Should -BeLike "*already exists in corp.contoso.com*"
                $Ui.newGpoErrorTextBlock.IsVisible | Should -BeTrue
                $Ui.Directory.Gpos.Count | Should -Be 29

                Invoke-Click $Ui.newGpoCancelButton
                $Ui.newGpoPanel.IsVisible | Should -BeFalse
            }
        }

        It 'Creates an unlinked GPO from the Group Policy Objects container' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                Invoke-Click $Ui.newGpoMenuItem
                $Ui.newGpoTitleTextBlock.Text | Should -Be 'New GPO in corp.contoso.com'
                $Ui.newGpoNameTextBox.Text = 'TEST - Unlinked'
                Invoke-Click $Ui.newGpoCreateButton

                $Gpo = $Ui.Directory.FindGpo('TEST - Unlinked')
                @($Ui.Directory.GetLinksOf($Gpo)).Count | Should -Be 0
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Gpo
                $Ui.domainTreeView.SelectedItem.Parent.Header | Should -Be 'Group Policy Objects'
                $Ui.linksHeaderTextBlock.Text | Should -Be 'Links (0)'
            }
        }

        It 'Edits a GPO in the policy editor, then goes back to the domain tree' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem

                $Ui.editorView.IsVisible | Should -BeTrue
                $Ui.managementView.IsVisible | Should -BeFalse
                $Ui.searchPanel.IsVisible | Should -BeTrue
                $Ui.managementButton.IsVisible | Should -BeTrue
                $Ui.editingBanner.IsVisible | Should -BeTrue
                $Ui.editingGpoTextBlock.Text | Should -Be "Editing the GPO 'C - Servers - Security Baseline' [corp.contoso.com]"
                $Ui.subtitleTextBlock.Text | Should -Be 'Editing the GPO C - Servers - Security Baseline'
                $Ui.Editing.Gpo.DisplayName | Should -Be 'C - Servers - Security Baseline'

                # The policy editor works as before (by ID: an earlier test reloads the ADMX files).
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsPolicy] -and $n.Tag.ID -eq 'DisableAntiSpywareDefender' }
                # Its name in the ADML of Windows 11 26H2.
                $Ui.settingTitleTextBlock.Text | Should -Be 'Turn off Microsoft Defender Antivirus'

                Invoke-Click $Ui.managementButton
                $Ui.managementView.IsVisible | Should -BeTrue
                $Ui.editorView.IsVisible | Should -BeFalse
                $Ui.directoryTitleTextBlock.Text | Should -Be 'C - Servers - Security Baseline'

                # Browsing the ADMX policies is outside any GPO.
                Invoke-Click $Ui.browseAdmxButton
                $Ui.editorView.IsVisible | Should -BeTrue
                $Ui.editingBanner.IsVisible | Should -BeFalse
                $Ui.Editing.Gpo | Should -BeNullOrEmpty
                $Ui.treeView.SelectedItem | Should -BeNullOrEmpty
            }
        }

        It 'Edits the GPO of the details panel with its button' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'TEST - Edge Policies'
                Invoke-Click $Ui.editGpoButton
                $Ui.editorView.IsVisible | Should -BeTrue
                $Ui.Editing.Gpo.DisplayName | Should -Be 'TEST - Edge Policies'
            }
        }

        It 'Shows a directory read over LDAP: GPO creation offered, links to missing GPOs shown' {
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Ui.subtitleTextBlock.Text | Should -Be 'Group Policy Management - hardenbox.labo (Samba AD)'
                $Ui.directoryBreadcrumbTextBlock.Text | Should -Be 'Right-click a domain or an OU to create a GPO'

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon'
                $Ui.createLinkedGpoMenuItem.IsVisible | Should -BeTrue
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.newGpoMenuItem.IsVisible | Should -BeTrue

                $Workstations = Get-DomainNode $Ui 'Lyon', 'Workstations (blocks inheritance)'
                $Ui.domainTreeView.SelectedItem = $Workstations.Children | Where-Object { $_.Tag -is [GPOToolsGpoLink] -and -not $_.Tag.Gpo }
                $Ui.directoryTitleTextBlock.Text | Should -BeLike 'GPO not found (*)'
                $Ui.editGpoMenuItem.IsVisible | Should -BeFalse
                $Ui.editGpoButton.IsVisible | Should -BeFalse

                # The GPOs can still be opened in the policy editor.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon', 'Workstations (blocks inheritance)', 'Workstations (enforced)'
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.editorView.IsVisible | Should -BeTrue
                $Ui.Editing.Gpo.Id | Should -Be ([guid]$TestLdapWorkstationsPolicy)
            }
        }

        It 'Keeps the long distinguished names inside the details panel' {
            # Regression: a padding on the scroll viewer moved its content without narrowing it, so
            # the end of the long values was drawn under the right border, cut.
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Default Domain Policy'
                $Ui.Window.UpdateLayout()
                [Avalonia.Threading.Dispatcher]::UIThread.RunJobs()
                $Ui.Window.UpdateLayout()

                # Compared with what the scroll viewer shows, its bounds, not with its viewport.
                $Scroll = [Avalonia.VisualTree.VisualExtensions]::GetVisualAncestors($Ui.directoryPropertiesList) | Where-Object { $_ -is [Avalonia.Controls.ScrollViewer] } | Select-Object -First 1
                $Texts = @([Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Ui.directoryPropertiesList) | Where-Object { $_ -is [Avalonia.Controls.SelectableTextBlock] })
                $Texts.Count | Should -BeGreaterThan 4
                foreach ($Text in $Texts) {
                    # Right edge in the scroll viewer: the offsets of the ancestors added up.
                    $Right = $Text.Bounds.Width
                    for ($Visual = $Text; $Visual -and -not [object]::ReferenceEquals($Visual, $Scroll); $Visual = [Avalonia.VisualTree.VisualExtensions]::GetVisualParent($Visual)) {
                        $Right += $Visual.Bounds.X
                    }
                    $Visual | Should -Not -BeNullOrEmpty -Because 'the value is drawn in the scroll viewer'
                    $Right | Should -BeLessOrEqual ($Scroll.Bounds.Width - 8) -Because "'$($Text.Text)' must end before the right margin"
                    # A value without spaces is cut inside a word: no line wider than its block.
                    foreach ($Line in $Text.TextLayout.TextLines) { $Line.Width | Should -BeLessOrEqual ($Text.Bounds.Width + 0.5) }
                }
            }
        }

        It 'Creates a GPO in the domain and links it to the OU, from the context menu' {
            Mock New-PSGPODomainGpo {
                $Gpo.Id = [guid]'8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99'
                $Gpo.DistinguishedName = "CN={8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99},CN=Policies,CN=System,$TestLdapDomainDN"
            }
            Mock Add-PSGPODomainGpLink { $Directory.SetLinks($Som, "[LDAP://$($Link.GpoDistinguishedName);0]"); $Link.Order = 1; $Som.Links[0] = $Link }
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon'
                Invoke-Click $Ui.createLinkedGpoMenuItem
                $Ui.newGpoNameTextBox.Text = 'C - Lyon - Proxy'
                Invoke-Click $Ui.newGpoCreateButton

                $Ui.newGpoPanel.IsVisible | Should -BeFalse
                $Ui.newGpoErrorTextBlock.Text | Should -BeNullOrEmpty
                $Ui.domainTreeView.SelectedItem.Tag.Gpo.Id | Should -Be ([guid]'8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99')
                $Ui.domainTreeView.SelectedItem.Parent.Header | Should -Be 'Lyon'
            }
            Should -Invoke New-PSGPODomainGpo -Times 1 -Exactly
            Should -Invoke Add-PSGPODomainGpLink -Times 1 -Exactly
        }

        It 'Shows in the form why the domain refused the GPO' {
            Mock New-PSGPODomainGpo { throw 'samba-tool gpo create failed (255): access denied' }
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon'
                Invoke-Click $Ui.createLinkedGpoMenuItem
                $Ui.newGpoNameTextBox.Text = 'Refused'
                Invoke-Click $Ui.newGpoCreateButton
                $Ui.newGpoPanel.IsVisible | Should -BeTrue
                $Ui.newGpoErrorTextBlock.Text | Should -BeLike '*access denied'
            }
        }

        It 'Shows the setting of the policy read from the Registry.pol of the GPO, and applies a change' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            # A Registry.pol written before: the control panel list of DisallowCpls (User).
            $Policy = [GPOToolsUtility]::Policies | Where-Object { $_.ID -eq 'DisallowCpls' } | Select-Object -First 1
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled -Value @{ DisallowCplsList = [string[]]@('Microsoft.Mouse', 'Microsoft.Sound') }
            $Directory.WritePolicyFile($Gpo, 'User', $Pol.ToBytes())
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.applyPanel.IsVisible | Should -BeTrue

                Select-GuiPolicy $Ui 'DisallowCpls'
                $Ui.enabledRadio.IsChecked | Should -BeTrue
                @($Ui.Editing.Editor.Controls['DisallowCplsList'].Entries) | Should -Be @('Microsoft.Mouse', 'Microsoft.Sound')
                $Ui.applyStatusTextBlock.Text | Should -Be 'Enabled in User\Registry.pol'
                $Ui.applySettingButton.IsEnabled | Should -BeFalse -Because 'the form shows what the file holds'

                # A Machine policy, not configured, then enabled and applied.
                Select-GuiPolicy $Ui 'Biometrics_EnableBio'
                $Ui.notConfiguredRadio.IsChecked | Should -BeTrue
                $Ui.applySettingButton.IsEnabled | Should -BeFalse
                $Ui.enabledRadio.IsChecked = $true
                $Ui.applySettingButton.IsEnabled | Should -BeTrue
                Invoke-Click $Ui.applySettingButton
                $Ui.applyStatusTextBlock.Text | Should -Be 'Saved: Enabled in Machine\Registry.pol (version 17).'
                $Ui.applySettingButton.IsEnabled | Should -BeFalse

                # Selected again: read from the file.
                Select-GuiPolicy $Ui 'DisallowCpls'
                Select-GuiPolicy $Ui 'Biometrics_EnableBio'
                $Ui.enabledRadio.IsChecked | Should -BeTrue
            }
            $Saved = [GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($Gpo, 'Machine'))
            @($Saved.Entries | ForEach-Object { "$_" }) | Should -Be '[SOFTWARE\Policies\Microsoft\Biometrics;Enabled;DWord;1]'
            $Gpo.GetComputerVersion() | Should -Be 17
        }

        It 'Shows the configured settings of the selected GPO in its Settings tab, as GPMC' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy ([GPOToolsUtility]::Policies | Where-Object { $_.ID -eq 'Biometrics_EnableBio' } | Select-Object -First 1) -Pol $Pol -State Disabled
            $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers'
                $Ui.settingsTab.IsVisible | Should -BeFalse -Because 'an OU has no settings'

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                $Ui.settingsTab.IsVisible | Should -BeTrue
                $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                $Ui.computerSettingsHeader.Text | Should -Be 'Computer Configuration (Enabled)'
                $Rows = @($Ui.computerSettingsList.ItemsSource)
                $Rows.Count | Should -Be 1
                $Rows[0].Name | Should -Be 'Allow the use of biometrics'
                $Rows[0].State | Should -Be 'Disabled'
                # Drawn on screen, not only in the list: Avalonia binds the class itself, not a PSObject.
                $Rows[0] | Should -BeOfType ([AvaloniaSettingRow])
                $Rows[0].GetType().Name | Should -Be 'AvaloniaSettingRow'
                $Ui.Window.UpdateLayout()
                $Texts = @([Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Ui.computerSettingsList) | Where-Object { $_ -is [Avalonia.Controls.TextBlock] } | ForEach-Object Text)
                $Texts | Should -Contain 'Allow the use of biometrics'
                $Texts | Should -Contain 'Policies > Administrative Templates > Windows Components > Biometrics'
                $Ui.userSettingsHeader.Text | Should -Be 'User Configuration (Disabled): no settings defined' -Because 'the user settings of this GPO are disabled'

                # Another GPO, then an OU: the tab follows, and leaves when there is no GPO.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Default Domain Policy'
                @($Ui.computerSettingsList.ItemsSource).Count | Should -Be 0
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers'
                $Ui.settingsTab.IsVisible | Should -BeFalse
                $Ui.directoryTabs.SelectedIndex | Should -Be 0

                # A setting applied in the editor shows in the report.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                Select-GuiPolicy $Ui 'Biometrics_EnableBio'
                $Ui.enabledRadio.IsChecked = $true
                Invoke-Click $Ui.applySettingButton
                Invoke-Click $Ui.managementButton
                $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                @($Ui.computerSettingsList.ItemsSource)[0].State | Should -Be 'Enabled'
            }
        }

        It 'Edits the security settings of a GPO in GptTmpl.inf, as the Group Policy editor' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem

                # Machine > Windows Settings > Security Settings > Account Policies > Password Policy
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsSecuritySetting] -and $n.Tag.Key -eq 'MinimumPasswordLength' }
                $Node.Parent.Header | Should -Be 'Password Policy'
                $Node.Parent.Parent.Parent.Header | Should -Be 'Security Settings'
                $Node.Parent.Parent.Parent.Parent.Header | Should -Be 'Windows Settings'
                $Ui.treeView.SelectedItem = $Node
                $Ui.settingTitleTextBlock.Text | Should -Be 'Minimum password length'
                $Ui.notConfiguredRadio.Content | Should -Be 'Not Defined'
                $Ui.enabledRadio.Content | Should -Be 'Define this policy setting'
                $Ui.disabledRadio.IsVisible | Should -BeFalse
                $Ui.notConfiguredRadio.IsChecked | Should -BeTrue
                $Ui.applyStatusTextBlock.Text | Should -Be 'Not defined in GptTmpl.inf'

                $Ui.enabledRadio.IsChecked = $true
                $Ui.Editing.Editor.Controls['Value'].Value = 14
                (Get-PreviewLine $Ui) | Should -Be 'Set in GptTmpl.inf | [System Access] | MinimumPasswordLength | 14'
                $Ui.Editing.Editor.Controls['Value'].Value = 200
                $Ui.settingErrorTextBlock.Text | Should -BeLike '*at most 128 characters*'
                $Ui.applySettingButton.IsEnabled | Should -BeFalse
                $Ui.Editing.Editor.Controls['Value'].Value = 14
                $Ui.applySettingButton.IsEnabled | Should -BeTrue
                Invoke-Click $Ui.applySettingButton
                $Ui.applyStatusTextBlock.Text | Should -Be 'Saved: 14 characters in GptTmpl.inf (version 17).'

                # A user right: accounts added to the list.
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsSecuritySetting] -and $n.Tag.Key -eq 'SeBackupPrivilege' }
                $Ui.enabledRadio.IsChecked = $true
                $Accounts = $Ui.Editing.Editor.Controls['Value']
                foreach ($Account in '*S-1-5-32-544', 'CONTOSO\Backup') { $Accounts.NameInput.Text = $Account; Invoke-Click $Accounts.Add }
                @($Accounts.Entries) | Should -Be @('BUILTIN\Administrators (*S-1-5-32-544)', 'CONTOSO\Backup')
                Invoke-Click $Ui.applySettingButton

                # Selected again: read from GptTmpl.inf.
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsSecuritySetting] -and $n.Tag.Key -eq 'MinimumPasswordLength' }
                $Ui.enabledRadio.IsChecked | Should -BeTrue
                $Ui.Editing.Editor.Controls['Value'].Value | Should -Be 14
                $Ui.applySettingButton.IsEnabled | Should -BeFalse

                # An administrative template again: its labels come back.
                Select-GuiPolicy $Ui 'Biometrics_EnableBio'
                $Ui.notConfiguredRadio.Content | Should -Be 'Not Configured'
                $Ui.disabledRadio.IsVisible | Should -BeTrue

                # The Settings tab lists the security settings first.
                Invoke-Click $Ui.managementButton
                $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                $Rows = @($Ui.computerSettingsList.ItemsSource)
                $Rows[0].Path | Should -Be 'Policies > Windows Settings > Security Settings > Account Policies > Password Policy'
                $Rows[0].State | Should -Be '14 characters'
                ($Rows | Where-Object Name -EQ 'Back up files and directories').State | Should -Be 'BUILTIN\Administrators, CONTOSO\Backup'
            }
            $Template = [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($Gpo))
            $Template.GetValue('System Access', 'MinimumPasswordLength') | Should -Be '14'
            $Template.GetValue('Privilege Rights', 'SeBackupPrivilege') | Should -Be '*S-1-5-32-544,CONTOSO\Backup'
            $Template.GetSectionNames()[0..1] | Should -Be @('Unicode', 'Version')
        }

        It 'Removes a security setting when it is no longer defined' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Template = [GPOToolsSecurityTemplate]::new()
            $Template.SetValue('Event Audit', 'AuditLogonEvents', '3')
            $Directory.WriteSecurityTemplate($Gpo, $Template.ToBytes())
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsSecuritySetting] -and $n.Tag.Key -eq 'AuditLogonEvents' }
                $Ui.enabledRadio.IsChecked | Should -BeTrue
                $Ui.Editing.Editor.Controls['Success'].IsChecked | Should -BeTrue
                $Ui.Editing.Editor.Controls['Failure'].IsChecked | Should -BeTrue
                $Ui.notConfiguredRadio.IsChecked = $true
                $Ui.previewEmptyTextBlock.Text | Should -Be 'Not defined: nothing is written to GptTmpl.inf.'
                Invoke-Click $Ui.applySettingButton
                $Ui.applyStatusTextBlock.Text | Should -BeLike 'Saved: Not Defined in GptTmpl.inf*'
            }
            [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($Gpo)).GetSectionNames() | Should -Not -Contain 'Event Audit'
        }

        It 'Shows only the settings the GPO configures with "Configured settings only"' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy ([GPOToolsUtility]::Policies | Where-Object { $_.ID -eq 'DisallowCpls' } | Select-Object -First 1) -Pol $Pol -State Disabled
            $Directory.WritePolicyFile($Gpo, 'User', $Pol.ToBytes())
            $Template = [GPOToolsSecurityTemplate]::new()
            $Template.SetValue('System Access', 'MinimumPasswordLength', '14')
            $Directory.WriteSecurityTemplate($Gpo, $Template.ToBytes())
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                function Get-TreeSecurity {
                    param($Roots)
                    $Stack = [System.Collections.Generic.Stack[object]]::new()
                    foreach ($Root in $Roots) { $Stack.Push($Root) }
                    while ($Stack.Count) {
                        $Node = $Stack.Pop()
                        foreach ($Child in $Node.Children) { $Stack.Push($Child) }
                        if ($Node.Tag -is [GPOToolsSecuritySetting]) { $Node.Tag }
                    }
                }
                $Ui.configuredOnlyCheckBox.IsVisible | Should -BeFalse -Because 'only a GPO has configured settings'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.configuredOnlyCheckBox.IsVisible | Should -BeTrue
                $Ui.configuredOnlyCheckBox.IsChecked | Should -BeFalse
                @(Get-TreePolicy $Ui.treeView.ItemsSource).Count | Should -Be ([GPOToolsUtility]::Policies.Count)

                $Ui.configuredOnlyCheckBox.IsChecked = $true
                @(Get-TreePolicy $Ui.treeView.ItemsSource).ID | Should -Be @('DisallowCpls')
                @(Get-TreeSecurity $Ui.treeView.ItemsSource).Key | Should -Be @('MinimumPasswordLength')
                $Ui.treeView.ItemsSource.Header | Should -Be @('User', 'Machine')
                # Expanded down to the settings, to see them at once.
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsSecuritySetting] }
                for ($Parent = $Node.Parent; $Parent; $Parent = $Parent.Parent) { $Parent.IsExpanded | Should -BeTrue -Because "$($Parent.Header) leads to the setting" }
                # The tree items themselves, not only the model.
                $Ui.Window.UpdateLayout()
                $Machine = $Ui.treeView.ContainerFromItem(@($Ui.treeView.ItemsSource)[1])
                $Machine | Should -Not -BeNullOrEmpty
                $Machine.IsExpanded | Should -BeTrue

                # With the search too.
                $Ui.searchTextBox.Text = 'password'
                Invoke-Click $Ui.searchButton
                @(Get-TreePolicy $Ui.treeView.ItemsSource).Count | Should -Be 0
                @(Get-TreeSecurity $Ui.treeView.ItemsSource).Key | Should -Be @('MinimumPasswordLength')
                $Ui.searchTextBox.Text = 'BitLocker'
                Invoke-Click $Ui.searchButton
                $Ui.treeView.ItemsSource | Should -BeNullOrEmpty
                $Ui.breadcrumbTextBlock.Text | Should -Be 'No configured setting matches the search'
                $Ui.searchTextBox.Text = ''

                $Ui.configuredOnlyCheckBox.IsChecked = $false
                @(Get-TreePolicy $Ui.treeView.ItemsSource).Count | Should -Be ([GPOToolsUtility]::Policies.Count)

                # Browsing the ADMX outside any GPO: no filter.
                $Ui.configuredOnlyCheckBox.IsChecked = $true
                Invoke-Click $Ui.managementButton
                Invoke-Click $Ui.browseAdmxButton
                $Ui.configuredOnlyCheckBox.IsVisible | Should -BeFalse
                $Ui.configuredOnlyCheckBox.IsChecked | Should -BeFalse
                @(Get-TreePolicy $Ui.treeView.ItemsSource).Count | Should -Be ([GPOToolsUtility]::Policies.Count)
            }
        }

        It 'Says when the GPO configures no setting with "Configured settings only"' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.configuredOnlyCheckBox.IsChecked = $true
                $Ui.treeView.ItemsSource | Should -BeNullOrEmpty
                $Ui.breadcrumbTextBlock.Text | Should -Be 'This GPO configures no setting'
            }
        }

        It 'Keeps the setting read when the domain refuses the change' {
            Mock Read-PSGPOSysvolFile { $null }
            Mock Save-PSGPODomainGpoFile { throw 'access denied' }
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Default Domain Policy'
                Invoke-Click $Ui.editGpoMenuItem
                Select-GuiPolicy $Ui 'Biometrics_EnableBio'
                $Ui.enabledRadio.IsChecked = $true
                Invoke-Click $Ui.applySettingButton
                $Ui.applyStatusTextBlock.Text | Should -Be 'Not saved: access denied'
                $Ui.applySettingButton.IsEnabled | Should -BeTrue -Because 'the change is still to apply'
                $Ui.Editing.Pol['Machine'].Entries.Count | Should -Be 0
            }
        }

        It 'Says when the settings of the GPO cannot be read' {
            Mock Read-PSGPOSysvolFile { throw 'smbclient failed: NT_STATUS_ACCESS_DENIED' }
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Default Domain Policy'
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.editingGpoTextBlock.Text | Should -BeLike '*settings of the GPO cannot be read: smbclient failed: NT_STATUS_ACCESS_DENIED'
                Select-GuiPolicy $Ui 'Biometrics_EnableBio'
                $Ui.applySettingButton.IsEnabled | Should -BeFalse
                $Ui.enabledRadio.IsChecked = $true
                $Ui.applySettingButton.IsEnabled | Should -BeFalse -Because 'nothing was read to change'
            }
        }

        It 'Shows the demonstration banner over a demonstration directory only' {
            $Directory.IsDemonstration = $true
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.demoBanner.IsVisible | Should -BeTrue
                $Ui.demoBannerTextBlock.Text | Should -Be 'Demonstration environment: no Active Directory or Samba AD domain discovered'
                $Ui.subtitleTextBlock.Text | Should -Be 'Group Policy Management - corp.contoso.com (demonstration)'
                # The tree stays usable under the banner.
                $Ui.domainTreeView.IsVisible | Should -BeTrue
                $Ui.Window.UpdateLayout()
                $Ui.domainTreeView.Bounds.Height | Should -BeGreaterThan 200
            }
            foreach ($Other in (Import-PSGPODirectory -Path $SamplePath), (New-TestLdapDirectory)) {
                Start-PSGPOManagerWindow -Directory $Other -OnShown {
                    param($Ui)
                    $Ui.demoBanner.IsVisible | Should -BeFalse
                    $Ui.subtitleTextBlock.Text | Should -Not -BeLike '*demonstration*'
                }
            }
        }

        It 'Opens on the Group Policy Management view with the reason when the domain could not be read' {
            Start-PSGPOManagerWindow -DirectoryError 'LDAP connection to dc.hardenbox.labo:389 failed: no ticket' -OnShown {
                param($Ui)
                $Ui.managementView.IsVisible | Should -BeTrue
                $Ui.domainTreeView.IsVisible | Should -BeFalse
                $Ui.directoryEmptyTextBlock.IsVisible | Should -BeTrue
                $Ui.directoryEmptyTextBlock.Text | Should -BeLike "The domain could not be read.*LDAP connection to dc.hardenbox.labo:389 failed: no ticket"
                $Ui.directoryBreadcrumbTextBlock.Text | Should -Be 'Domain not read'
                $Ui.browseAdmxButton.IsVisible | Should -BeTrue
            }
        }

        It 'Opens on the Group Policy Management view by default, explaining how to load a directory' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Ui.managementView.IsVisible | Should -BeTrue
                $Ui.editorView.IsVisible | Should -BeFalse
                $Ui.directoryEmptyTextBlock.IsVisible | Should -BeTrue
                $Ui.directoryEmptyTextBlock.Text | Should -BeLike '*Get-PSGPODirectory*Import-PSGPODirectory*'
                $Ui.domainTreeView.IsVisible | Should -BeFalse
                $Ui.demoBanner.IsVisible | Should -BeFalse

                Invoke-Click $Ui.browseAdmxButton
                $Ui.editorView.IsVisible | Should -BeTrue
                $Ui.editingBanner.IsVisible | Should -BeFalse
                $Ui.managementButton.IsVisible | Should -BeTrue
            }
        }

        It 'Opens on the policy editor with -StartView Editor' {
            Start-PSGPOManagerWindow -StartView Editor -OnShown {
                param($Ui)
                $Ui.editorView.IsVisible | Should -BeTrue
                $Ui.managementView.IsVisible | Should -BeFalse
                $Ui.searchPanel.IsVisible | Should -BeTrue
            }
        }

        It 'Shows this computer, its addresses, its domain and the domain controller in the status bar' {
            $Platform = Get-PSGPOPlatform
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Items = @($Ui.statusBarList.ItemsSource)
                $Items.Count | Should -Be 4
                $Items[0].Text | Should -BeLike "$($Platform.ComputerName) - *"
                $Items[3].Text | Should -Be 'DC dc.hardenbox.labo (Samba AD)'

                # Drawn at the bottom of the window, below the views.
                $Ui.Window.UpdateLayout()
                $Ui.statusBar.IsVisible | Should -BeTrue
                $Ui.statusBar.Bounds.Height | Should -BeGreaterThan 15
                $Ui.statusBar.Bounds.Bottom | Should -BeGreaterThan ($Ui.Window.Bounds.Height - 2)
                $Ui.statusBar.Bounds.Top | Should -BeGreaterOrEqual $Ui.managementView.Bounds.Bottom
                $Icons = @([Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Ui.statusBarList) | Where-Object { $_ -is [Avalonia.Controls.PathIcon] })
                $Icons.Count | Should -Be 4
                $Icons | ForEach-Object { $_.Data | Should -Not -BeNullOrEmpty }
            }
        }
    }

    Describe 'ADMX window' -Skip:$AvaloniaMissing {
        BeforeAll {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
        }
        BeforeEach {
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        }
        AfterAll {
            $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
            # The ADMX files the other tests expect.
            Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
        }

        It 'Proposes the folders found, detects the language from the language folders, and loads them' {
            $Loaded = Show-PSGPOAdmxWindow -OnShown {
                param($Ui)
                @($Ui.candidateComboBox.ItemsSource) | Should -Contain $PolicyDefinitions
                $Ui.pathTextBox.Text = $PolicyDefinitions
                @($Ui.cultureComboBox.ItemsSource) | Should -Contain 'en-US'
                @($Ui.cultureComboBox.ItemsSource) | Should -Contain 'fr-FR'
                $Ui.cultureComboBox.SelectedItem | Should -Not -BeNullOrEmpty -Because 'the language of the session or en-US is there'
                $Ui.statusTextBlock.Text | Should -Match '^\d+ ADMX files, \d+ languages\.$'
                $Ui.loadButton.IsEnabled | Should -BeTrue

                # The folder as it is named: fr-fr in the ADMX of Windows 11 26H2.
                $Ui.cultureComboBox.SelectedItem = @($Ui.cultureComboBox.ItemsSource | Where-Object { $_ -eq 'fr-FR' })[0]
                Invoke-Click $Ui.loadButton
                $Ui.statusTextBlock.Text | Should -BeLike 'Loading the ADMX files of*in fr-FR...'
                $Ui.loadButton.IsEnabled | Should -BeFalse
                Invoke-UiLoop -Until { -not $Ui.Window.IsVisible } -TimeoutMilliseconds 120000
                $Ui.Window.IsVisible | Should -BeFalse -Because 'the window closes once the files are loaded'
            }
            $Loaded | Should -BeTrue
            [GPOToolsUtility]::Policies.Count | Should -BeGreaterThan 1000
            $Settings = Get-PSGPOUserSetting
            $Settings.PolicyDefinitions | Should -Be $PolicyDefinitions
            $Settings.UICulture | Should -Be 'fr-FR'

            # Next time: the folder and the language chosen are selected.
            $null = Show-PSGPOAdmxWindow -OnShown {
                param($Ui)
                $Ui.pathTextBox.Text | Should -Be $PolicyDefinitions
                $Ui.cultureComboBox.SelectedItem | Should -Be 'fr-FR'
            }
        }

        It 'Does not open the console when no ADMX file is loaded' {
            Mock Show-PSGPOAdmxWindow { $false }
            Mock Start-PSGPOManagerWindow { }
            [GPOToolsUtility]::RemoveAll()
            Show-GPOManagerAvalonia -NoDirectory -WarningVariable Warn 3>$null
            Should -Invoke Start-PSGPOManagerWindow -Times 0 -Exactly
            $Warn | Should -BeLike '*console is not opened*'
        }

        It 'Says what is wrong with a folder, and loads nothing when cancelled' {
            $NotAdmx = Join-Path $TestDrive 'NotAdmx'
            $null = New-Item -ItemType Directory -Path $NotAdmx -Force
            $Loaded = Show-PSGPOAdmxWindow -OnShown {
                param($Ui)
                $Ui.pathTextBox.Text = Join-Path $TestDrive 'Missing'
                $Ui.statusTextBlock.Text | Should -BeLike "The folder '*Missing' does not exist."
                $Ui.loadButton.IsEnabled | Should -BeFalse
                $Ui.pathTextBox.Text = $NotAdmx
                $Ui.statusTextBlock.Text | Should -BeLike 'No .admx file in*choose the PolicyDefinitions folder itself.'
                $Ui.cultureComboBox.ItemsSource | Should -BeNullOrEmpty
                Invoke-Click $Ui.cancelButton
                $Ui.Window.IsVisible | Should -BeFalse
            }
            $Loaded | Should -BeFalse
            (Get-PSGPOUserSetting).Count | Should -Be 0 -Because 'nothing was chosen'
        }
    }
}
