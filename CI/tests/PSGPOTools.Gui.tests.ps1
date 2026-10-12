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
                $Domain.Children[-1].Header | Should -Be 'Group Policy Objects'
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
                $Ui.settingTitleTextBlock.Text | Should -Be 'Turn off Windows Defender Antivirus'

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

        It 'Shows a directory read over LDAP read-only: no GPO creation, links to missing GPOs shown' {
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Ui.subtitleTextBlock.Text | Should -Be 'Group Policy Management - hardenbox.labo (Samba AD, read-only)'
                $Ui.directoryBreadcrumbTextBlock.Text | Should -Be 'Read-only: read over LDAP from dc.hardenbox.labo (Samba AD), read-only'

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon'
                $Ui.createLinkedGpoMenuItem.IsVisible | Should -BeFalse
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.newGpoMenuItem.IsVisible | Should -BeFalse

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
}
