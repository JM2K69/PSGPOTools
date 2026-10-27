#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# GUI tests: each test opens the real Show-GPOManagerAvalonia window (through the private
# Start-PSGPOManagerWindow -OnShown hook), drives its controls, then the window closes.
# They are skipped when the Avalonia runtime has not been staged with Get-AvaloniaBinaries.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    # Evaluated during discovery, here and not in BeforeDiscovery: InModuleScope runs this block
    # in the module scope, where the variables of the test file are not visible (-Skip:$null).
    $Rid = Get-PSGPOAvaloniaRid
    $AvaloniaMissing = -not (Test-Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Avalonia' 'bin' $Rid 'Avalonia.dll'))
    if ($AvaloniaMissing) {
        Write-Warning "Avalonia runtime not staged for ${Rid}: GUI tests skipped (run HGPM/Avalonia/Get-AvaloniaBinaries.ps1)."
    }

    BeforeAll {
        $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path
        # Root BeforeAll also runs when every test is skipped: only load the ADMX for the GUI tests.
        $AvaloniaDll = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Avalonia' 'bin' (Get-PSGPOAvaloniaRid) 'Avalonia.dll'
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
        It 'Opens with the Machine then User scopes and the default breadcrumb' {
            Start-PSGPOManagerWindow -OnShown {
                param($Ui)
                $Ui.Window.IsVisible | Should -BeTrue
                $Ui.treeView.ItemsSource.Header | Should -Be @('Computer Configuration', 'User Configuration')
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

                $Ui.breadcrumbTextBlock.Text | Should -BeLike "Computer Configuration > Policies > Administrative Templates > Windows Components > *$($DefenderPolicy.Category.DisplayName) > $($DefenderPolicy.DisplayName)"
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
                    $Ui.treeView.ItemsSource.Header | Should -Be @('Computer Configuration', 'User Configuration')
                    @($Ui.treeView.ItemsSource)[0].Children.Header | Should -Be @('Policies', 'Preferences')
                    @(@($Ui.treeView.ItemsSource)[0].Children[0].Children.Header) | Should -Be @('Windows Settings') -Because 'no Administrative Templates without ADMX'
                    @($Ui.treeView.ItemsSource)[1].Children.Header | Should -Be @('Policies', 'Preferences') -Because 'the public key policies of the users'
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
            $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
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

        It 'Shows the logo of HGPM as the icon of its windows and in the header of the console' {
            (Get-Item -LiteralPath (Get-PSGPOLogoPath)).Directory.Name | Should -Be 'Resources'
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.Window.Icon | Should -Not -BeNullOrEmpty -Because 'the logo is the icon of the window'
                $Ui.logoImage.Source | Should -Not -BeNullOrEmpty
                $Ui.logoImage.Source.PixelSize.Width | Should -Be 256
                $Ui.logoImage.IsVisible | Should -BeTrue
                $Ui.logoImage.Bounds.Width | Should -Be 44 -Because 'the logo is drawn beside the title'

                # A narrow window: the title is trimmed, the buttons keep their place.
                $Ui.subtitleTextBlock.Text = 'Group Policy Management - hardenbox.labo (Samba AD) - connected as HARDENBOX\Administrator'
                $Ui.Window.Width = 900
                $Ui.Window.UpdateLayout()
                $Buttons = $Ui.browseAdmxButton.Parent
                $SubtitleRight = [Avalonia.VisualExtensions]::TranslatePoint($Ui.subtitleTextBlock, [Avalonia.Point]::new($Ui.subtitleTextBlock.Bounds.Width, 0), $Ui.Window).X
                $ButtonsLeft = [Avalonia.VisualExtensions]::TranslatePoint($Buttons, [Avalonia.Point]::new(0, 0), $Ui.Window).X
                $SubtitleRight | Should -BeLessThan $ButtonsLeft -Because 'the subtitle never runs under the buttons'
                [Avalonia.Controls.ToolTip]::GetTip($Ui.subtitleTextBlock) | Should -Be $Ui.subtitleTextBlock.Text -Because 'the whole subtitle is in its tooltip'
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

        It 'Shows the console in French with -Language fr-FR, the names of the directory as they are' {
            try {
                Start-PSGPOManagerWindow -Directory $Directory -Language 'fr-FR' -OnShown {
                    param($Ui)
                    # From the XAML, and from the code.
                    $Ui.themeToggleText.Text | Should -BeIn @('Mode sombre', 'Mode clair') -Because 'it follows the theme of the system'
                    $Ui.historyTab.Header | Should -Be 'Historique'
                    $Ui.subtitleTextBlock.Text | Should -Be 'Gestion de stratégie de groupe - corp.contoso.com'
                    $Domain = @($Ui.domainTreeView.ItemsSource)[0]
                    @($Domain.Children[-3..-1].Header) | Should -Be @('Objets de stratégie de groupe', 'Filtres WMI', 'GPO supprimés')

                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Paris', 'Workstations'
                    $Ui.linksHeaderTextBlock.Text | Should -Be 'Objets de stratégie de groupe liés (3)'
                    @($Ui.linksList.ItemsSource.Name)[0] | Should -Be 'C - Workstations - Security Baseline Windows 11' -Because 'the names of the GPOs are not translated'
                    ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Nom unique').Value | Should -Be 'OU=Workstations,OU=Paris,OU=Sites,DC=corp,DC=contoso,DC=com'
                    ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Type').Value | Should -Be "Unité d'organisation"

                    $Ui.treeView.ItemsSource.Header | Should -Be @('Configuration ordinateur', 'Configuration utilisateur')
                }
            } finally {
                $null = Set-PSGPOLanguage -Language 'en-US'
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

        It 'Opens without the central backups: Tier 0 is told why, the other tiers see no History tab nor Deleted GPOs' {
            $Before = $script:PSGPOConfigurationState.Override
            $TierBefore = $Directory.AuditTier
            try {
                $script:PSGPOConfigurationState.Override = @{ Backup = @{ Path = '\\files\gpo-backups' } }
                # The configuration of the domain as given, not read again from the sample.
                Mock Use-PSGPODomainConfiguration { }
                # The share not mounted on Linux.
                Mock Get-PSGPODefaultBackupPath { throw 'The share //files/gpo-backups is not mounted on this computer: mount it first.' }
                $Directory.AuditTier = 'Tier0'
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.historyPathTextBox.IsReadOnly | Should -BeTrue -Because 'the central backups, not another folder'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Servers - Security Baseline'
                    $Ui.historyTab.IsVisible | Should -BeTrue
                    $Ui.directoryTabs.SelectedItem = $Ui.historyTab
                    $Ui.historyStatusTextBlock.Text | Should -BeLike '*is not mounted on this computer*'
                }
                $Directory.AuditTier = 'Tier1'
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    @(@($Ui.domainTreeView.ItemsSource)[0].Children.Tag) | Should -Not -Contain 'DeletedGpos'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Servers - Security Baseline'
                    $Ui.historyTab.IsVisible | Should -BeFalse -Because 'the backups are for Tier 0'
                }
                Should -Invoke Get-PSGPODefaultBackupPath -ParameterFilter { $true } -Times 1 -Because 'Tier 1 never reaches for the share'
            } finally {
                $script:PSGPOConfigurationState.Override = $Before
                $Directory.AuditTier = $TierBefore
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
                    # The version of each part, named: '3 / 0' read as a fraction.
                    $Nodes[2].Subtitle | Should -Be ('computer {0}, user {1}' -f $Gpo.GetComputerVersion(), $Gpo.GetUserVersion())
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
                    $Rows.Count | Should -Be 29
                    @($Rows | Where-Object Source -EQ 'Default').Count | Should -Be 29
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

        It 'Imports the settings of a GPMC backup into a GPO with Import Settings, a migration table that cannot be applied refused' {
            $Fixture = Join-Path $PSScriptRoot 'Fixtures' 'GpmcBackup'
            $Root = Join-Path $TestDrive "import-$([guid]::NewGuid())"
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.historyPathTextBox.Text = $Root
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Servers - Security Baseline'
                $Ui.importGpoMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.importGpoMenuItem
                $Ui.importGpoPanel.IsVisible | Should -BeTrue
                $Ui.importGpoPathTextBox.Text | Should -Be $Root -Because 'the folder of the History tab by default'
                $Ui.importGpoConfirmButton.IsEnabled | Should -BeFalse -Because 'that folder holds no backup yet'

                $Ui.importGpoPathTextBox.Text = $Fixture
                Invoke-Click $Ui.importGpoReadButton
                @($Ui.importGpoSourceComboBox.ItemsSource).Count | Should -Be 4
                $Ui.importGpoSourceComboBox.SelectedIndex = [array]::IndexOf(@($Ui.importGpoSourceComboBox.ItemsSource | ForEach-Object { $_ -like 'Default Domain Controllers Policy - GPMC backup of *' }), $true)

                # A table whose destination is not an account of this domain: nothing is imported.
                $Wrong = Join-Path $TestDrive "wrong-$([guid]::NewGuid()).migtable"
                Save-PSGPOMigrationTable -Path $Wrong -Entry @([pscustomobject]@{ Type = 'Unknown'; Source = 'Backup Operators'; Destination = 'OTHER\Group'; Mode = 'Explicit' })
                $Ui.importGpoTableTextBox.Text = $Wrong
                Invoke-Click $Ui.importGpoConfirmButton
                $Ui.importGpoErrorTextBlock.Text | Should -BeLike "*'Backup Operators' cannot be found*"
                $Ui.importGpoPanel.IsVisible | Should -BeTrue

                # The table of the lab: Backup Operators becomes Server Operators.
                $Ui.importGpoTableTextBox.Text = Join-Path $Fixture 'test.migtable'
                Invoke-Click $Ui.importGpoConfirmButton
                $Ui.importGpoPanel.IsVisible | Should -BeFalse
                $Ui.directoryResultTextBlock.Text | Should -BeLike "Settings of 'Default Domain Controllers Policy' imported into 'C - Servers - Security Baseline' (version *).*Backup Operators -> Server Operators*"
                $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
                [System.Text.Encoding]::Unicode.GetString($Directory.ReadSecurityTemplate($Gpo)) | Should -BeLike '*SeBackupPrivilege = `*S-1-5-32-549,`*S-1-5-32-544*'
                @(Get-PSGPOBackup -Path $Root).Comment | Should -BeLike "Before the import of the settings of 'Default Domain Controllers Policy'*"
            }
        }

        It 'Changes the security filtering and the delegation of a GPO in its Delegation tab' {
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Servers - Security Baseline'
                $Ui.delegationTab.IsVisible | Should -BeTrue
                $Ui.directoryTabs.SelectedItem = $Ui.delegationTab
                @($Ui.filteringList.ItemsSource.Name) | Should -Be @('Authenticated Users')
                # What the list draws, not only its items: Avalonia shows nothing of a row wrapped in a PSObject.
                $Ui.Window.UpdateLayout()
                $Drawn = [Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Ui.filteringList.ContainerFromIndex(0)) | Where-Object { $_ -is [Avalonia.Controls.TextBlock] }
                @($Drawn.Text) | Should -Contain 'Authenticated Users'
                $Admins = @($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'Domain Admins'
                $Admins.PermissionText | Should -Be 'Edit settings, delete, modify security'
                $Admins.InheritedText | Should -Be 'No'
                (@($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'ENTERPRISE DOMAIN CONTROLLERS').PermissionText | Should -Be 'Read'

                # Security filtering: a group in, Authenticated Users out (it keeps reading the GPO).
                $Ui.filteringNameTextBox.Text = 'Servers-Paris'
                Invoke-Click $Ui.filteringAddButton
                $Ui.delegationStatusTextBlock.Text | Should -Be "'Servers-Paris' applies the GPO now."
                # The badge of the security filtering, on its accounts only.
                (@($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'Servers-Paris').Applies | Should -BeTrue
                (@($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'Domain Admins').Applies | Should -BeFalse
                # The row realized first: the list shows a few rows at a time.
                $Index = [array]::IndexOf(@($Ui.delegationList.ItemsSource.Name), 'Servers-Paris')
                $Ui.delegationList.ScrollIntoView($Index)
                $Ui.Window.UpdateLayout()
                $Badge = [Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Ui.delegationList.ContainerFromIndex($Index)) | Where-Object { $_ -is [Avalonia.Controls.Border] -and $_.IsVisible -and ([Avalonia.Controls.ToolTip]::GetTip($_)) }
                @($Badge).Count | Should -Be 1
                $Ui.filteringList.SelectedItem = @($Ui.filteringList.ItemsSource) | Where-Object Name -EQ 'Authenticated Users'
                $Ui.filteringRemoveButton.IsEnabled | Should -BeTrue
                Invoke-Click $Ui.filteringRemoveButton
                @($Ui.filteringList.ItemsSource.Name) | Should -Be @('Servers-Paris')
                (@($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'Authenticated Users').PermissionText | Should -Be 'Read' -Because 'the computers must read every GPO (MS16-072)'
                $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
                $Gpo.SecurityFiltering | Should -Be @('Servers-Paris')
                ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Security filtering').Value | Should -Be 'Servers-Paris' -Because 'the details show it at once'

                # Delegation: read and apply, as the security filtering gives it.
                $Ui.delegationNameTextBox.Text = 'Servers-Lyon'
                $Ui.delegationPermissionComboBox.SelectedIndex = 1
                Invoke-Click $Ui.delegationSetButton
                $Ui.delegationStatusTextBlock.Text | Should -Be "'Servers-Lyon' has the permission Read and apply now."
                @($Ui.filteringList.ItemsSource.Name) | Should -Contain 'Servers-Lyon'
                $Ui.filteringList.SelectedItem = @($Ui.filteringList.ItemsSource) | Where-Object Name -EQ 'Servers-Lyon'
                Invoke-Click $Ui.filteringRemoveButton
                @($Ui.delegationList.ItemsSource.Name) | Should -Not -Contain 'Servers-Lyon'

                # Delegation: an editor, its level changed, then removed.
                $Ui.delegationNameTextBox.Text = 'GPO-Tier1-Admins'
                $Ui.delegationPermissionComboBox.SelectedIndex = 2
                Invoke-Click $Ui.delegationSetButton
                $Ui.delegationStatusTextBlock.Text | Should -Be "'GPO-Tier1-Admins' has the permission Edit settings now."
                # An editor added to the security filtering keeps its level, and has the badge.
                $Ui.filteringNameTextBox.Text = 'GPO-Tier1-Admins'
                Invoke-Click $Ui.filteringAddButton
                $Editor = @($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier1-Admins'
                $Editor.PermissionText | Should -Be 'Edit settings'
                $Editor.Applies | Should -BeTrue
                $Ui.delegationList.SelectedItem = @($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier1-Admins'
                $Ui.delegationNameTextBox.Text | Should -Be 'GPO-Tier1-Admins'
                $Ui.delegationPermissionComboBox.SelectedIndex | Should -Be 2
                $Ui.delegationPermissionComboBox.SelectedIndex = 3
                Invoke-Click $Ui.delegationSetButton
                (@($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier1-Admins').PermissionText | Should -Be 'Edit settings, delete, modify security'
                $Ui.delegationList.SelectedItem = @($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier1-Admins'
                Invoke-Click $Ui.delegationRemoveButton
                @($Ui.delegationList.ItemsSource.Name) | Should -Not -Contain 'GPO-Tier1-Admins'

                # Nobody reads it for the computers anymore: said at once.
                $Ui.delegationList.SelectedItem = @($Ui.delegationList.ItemsSource) | Where-Object Name -EQ 'Authenticated Users'
                Invoke-Click $Ui.delegationRemoveButton
                $Ui.delegationStatusTextBlock.Text | Should -BeLike "*The permissions of 'Authenticated Users' are removed.*MS16-072*"

                # A GPO waiting for its approval: its permissions are set when it is approved.
                $Gpo.ApprovalState = 'Pending'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Servers - Security Baseline'
                $Ui.directoryTabs.SelectedItem = $Ui.delegationTab
                $Ui.delegationSetButton.IsEnabled | Should -BeFalse
                $Ui.filteringAddButton.IsEnabled | Should -BeFalse
                $Ui.delegationStatusTextBlock.Text | Should -BeLike 'The GPO waits for its approval*'
            }
        }

        It 'Greys Settings for an account that is not an administrator of the domain, and for a directory that cannot be written' {
            try {
                $Directory.IsDomainAdministrator = $false
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.configurationButton.IsEnabled | Should -BeFalse
                    [Avalonia.Controls.ToolTip]::GetTip($Ui.configurationButton) | Should -Be 'Only the administrators of the domain change the configuration of HGPM'
                    # Opened anyway, it shows the configuration without saving it.
                    $Settings = New-PSGPOConfigurationWindow -Directory $Directory
                    $Settings.Controls.saveButton.IsEnabled | Should -BeFalse
                    $Settings.Controls.pathTextBlock.Text | Should -BeLike '*Only the administrators of the domain change it: the configuration is shown, not saved.'
                    $Settings.Window.Close()
                }
                $Directory.IsDomainAdministrator = $true
                $Directory.IsReadOnly = $true
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.configurationButton.IsEnabled | Should -BeFalse
                    $Settings = New-PSGPOConfigurationWindow -Directory $Directory
                    $Settings.Controls.saveButton.IsEnabled | Should -BeFalse
                    $Settings.Controls.pathTextBlock.Text | Should -BeLike '*cannot be written: the configuration is shown, not saved*'
                    $Settings.Window.Close()
                }
                Start-PSGPOManagerWindow -StartView Editor -OnShown { param($Ui) $Ui.configurationButton.IsEnabled | Should -BeFalse }
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
                # Its attributes by the labels of its form, not their names in the XML.
                $Row.Options | Should -Match '(?m)^Hive: HKEY_'
                $Row.Options | Should -Not -Match '(?m)^hive = '
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

        It 'Changes a WMI filter from its context menu, a query of another namespace included' {
            $Filter = $Directory.NewWmiFilter('Laptops', 'Computers with a battery', @(
                    [pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }
                    [pscustomobject]@{ Namespace = 'root\WMI'; Query = 'SELECT * FROM BatteryStatus' }))
            $Directory.SetWmiFilter($Directory.FindGpo('C - Laptops - Power Management'), $Filter)
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                $Ui.editWmiFilterMenuItem.IsVisible | Should -BeFalse
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters', 'Laptops'
                $Ui.editWmiFilterMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.editWmiFilterMenuItem
                $Ui.newWmiFilterPanel.IsVisible | Should -BeTrue
                $Ui.newWmiFilterTitleTextBlock.Text | Should -Be 'Edit WMI filter'
                $Ui.newWmiFilterCreateButton.Content | Should -Be 'Save'
                $Ui.newWmiFilterNameTextBox.Text | Should -Be 'Laptops'
                $Ui.newWmiFilterDescriptionTextBox.Text | Should -Be 'Computers with a battery'
                $Ui.newWmiFilterNamespaceTextBox.Text | Should -Be 'root\CIMv2'
                $Ui.newWmiFilterQueryTextBox.Text | Should -Be ('SELECT * FROM Win32_Battery', 'root\WMI: SELECT * FROM BatteryStatus' -join [Environment]::NewLine)

                $Ui.newWmiFilterQueryTextBox.Text = ''
                Invoke-Click $Ui.newWmiFilterCreateButton
                $Ui.newWmiFilterErrorTextBlock.Text | Should -Be 'A WMI filter has at least one query.'
                $Ui.newWmiFilterNameTextBox.Text = 'Portables'
                $Ui.newWmiFilterQueryTextBox.Text = "SELECT * FROM Win32_PortableBattery`nroot\WMI : SELECT * FROM BatteryStatus WHERE Voltage > 0`n"
                Invoke-Click $Ui.newWmiFilterCreateButton
                $Ui.newWmiFilterPanel.IsVisible | Should -BeFalse
                $Filter.Name | Should -Be 'Portables'
                $Filter.GetQueryText() | Should -Be 'root\CIMv2: SELECT * FROM Win32_PortableBattery; root\WMI: SELECT * FROM BatteryStatus WHERE Voltage > 0'
                $Ui.Directory.FindGpo('C - Laptops - Power Management').WmiFilterId | Should -Be $Filter.Id
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Filter
                $Ui.domainTreeView.SelectedItem.Header | Should -Be 'Portables'
                $Ui.directoryResultTextBlock.Text | Should -Be "WMI filter 'Portables' saved: C - Laptops - Power Management apply it with its new queries."

                # Without the right to change it, the filter offers no action.
                $Filter.CanEdit = $false
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters', 'Portables'
                $Ui.editWmiFilterMenuItem.IsVisible | Should -BeFalse
                $Ui.deleteWmiFilterMenuItem.IsVisible | Should -BeFalse
                $Filter.CanEdit = $true

                # The same form creates a filter again afterwards.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                Invoke-Click $Ui.newWmiFilterMenuItem
                $Ui.newWmiFilterTitleTextBlock.Text | Should -Be 'New WMI filter'
                $Ui.newWmiFilterCreateButton.Content | Should -Be 'Create'
                $Ui.newWmiFilterNameTextBox.Text | Should -BeNullOrEmpty
            }
        }

        It 'Renames a GPO from its node, a link to it or F2, and a WMI filter; edits a filter from its details' {
            $Filter = $Directory.NewWmiFilter('Laptops', 'Computers with a battery', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Gpo = $Ui.Directory.FindGpo('U - Lyon - Printers')
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'U - Lyon - Printers'
                $Ui.renameMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.renameMenuItem
                $Ui.renamePanel.IsVisible | Should -BeTrue
                $Ui.renameTitleTextBlock.Text | Should -Be "Rename the GPO 'U - Lyon - Printers'"
                $Ui.renameTextBox.Text | Should -Be 'U - Lyon - Printers'
                $Ui.renameTextBox.Text = 'Default Domain Policy'
                Invoke-Click $Ui.renameConfirmButton
                $Ui.renameErrorTextBlock.Text | Should -Be "A GPO named 'Default Domain Policy' already exists in corp.contoso.com."
                $Ui.renameTextBox.Text = 'U - Lyon - Color printers'
                Invoke-Click $Ui.renameConfirmButton
                $Ui.renamePanel.IsVisible | Should -BeFalse
                $Gpo.DisplayName | Should -Be 'U - Lyon - Color printers'
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Gpo
                $Ui.domainTreeView.SelectedItem.Header | Should -Be 'U - Lyon - Color printers'
                $Ui.directoryResultTextBlock.Text | Should -Be "GPO 'U - Lyon - Printers' renamed 'U - Lyon - Color printers': its links, its settings and its history are kept."
                (Get-DomainNode $Ui 'Sites', 'Lyon', 'Users').Children.Header | Should -Contain 'U - Lyon - Color printers'

                # F2 on a link renames its GPO; Escape gives up.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Sites', 'Lyon', 'Users', 'U - Lyon - Color printers'
                $KeyArgs = [Avalonia.Input.KeyEventArgs]::new()
                $KeyArgs.RoutedEvent = [Avalonia.Input.InputElement]::KeyDownEvent
                $KeyArgs.Key = [Avalonia.Input.Key]::F2
                $Ui.domainTreeView.RaiseEvent($KeyArgs)
                $Ui.renamePanel.IsVisible | Should -BeTrue
                $Ui.renameTitleTextBlock.Text | Should -Be "Rename the GPO 'U - Lyon - Color printers'"
                $KeyArgs = [Avalonia.Input.KeyEventArgs]::new()
                $KeyArgs.RoutedEvent = [Avalonia.Input.InputElement]::KeyDownEvent
                $KeyArgs.Key = [Avalonia.Input.Key]::Escape
                $Ui.renameTextBox.RaiseEvent($KeyArgs)
                $Ui.renamePanel.IsVisible | Should -BeFalse

                # Without the right to edit the GPO, no Rename.
                $Gpo.CanEdit = $false
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'U - Lyon - Color printers'
                $Ui.renameMenuItem.IsVisible | Should -BeFalse
                $Gpo.CanEdit = $true

                # A WMI filter: Edit this WMI filter in its details, Rename in its menu.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters', 'Laptops'
                $Ui.editWmiFilterButton.IsVisible | Should -BeTrue
                Invoke-Click $Ui.editWmiFilterButton
                $Ui.newWmiFilterPanel.IsVisible | Should -BeTrue
                $Ui.newWmiFilterTitleTextBlock.Text | Should -Be 'Edit WMI filter'
                Invoke-Click $Ui.renameMenuItem
                $Ui.newWmiFilterPanel.IsVisible | Should -BeFalse -Because 'one form at a time'
                $Ui.renameTitleTextBlock.Text | Should -Be "Rename the WMI filter 'Laptops'"
                $Ui.renameTextBox.Text = 'Portables'
                Invoke-Click $Ui.renameConfirmButton
                $Filter.Name | Should -Be 'Portables'
                $Filter.Description | Should -Be 'Computers with a battery' -Because 'only its name changes'
                $Filter.GetQueryText() | Should -Be 'root\CIMv2: SELECT * FROM Win32_Battery'
                $Ui.domainTreeView.SelectedItem.Header | Should -Be 'Portables'
                $Ui.directoryResultTextBlock.Text | Should -Be "WMI filter 'Laptops' renamed 'Portables'."
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                $Ui.editWmiFilterButton.IsVisible | Should -BeFalse
                $Ui.renameMenuItem.IsVisible | Should -BeFalse
            }
        }

        It 'Exports a WMI filter to a .mof file and imports it, from their context menus' {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $script:MofRoot = Join-Path $TestDrive "mof-$([guid]::NewGuid())"
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Set-PSGPOUserSetting -Values @{ BackupPath = $script:MofRoot }
            $script:WindowsMof = Join-Path $PSScriptRoot 'Fixtures' 'WmiFilter' 'windows-export.mof'
            $null = $Directory.NewWmiFilter('Laptops', 'Computers with a battery', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            try {
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $File = Join-Path $script:MofRoot 'WMI filters' 'Laptops.mof'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                    $Ui.exportWmiFilterMenuItem.IsVisible | Should -BeFalse
                    $Ui.importWmiFilterMenuItem.IsVisible | Should -BeTrue
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters', 'Laptops'
                    $Ui.importWmiFilterMenuItem.IsVisible | Should -BeFalse
                    $Ui.exportWmiFilterMenuItem.IsVisible | Should -BeTrue
                    Invoke-Click $Ui.exportWmiFilterMenuItem
                    $Ui.exportWmiFilterPanel.IsVisible | Should -BeTrue
                    $Ui.exportWmiFilterTitleTextBlock.Text | Should -Be "Export the WMI filter 'Laptops'"
                    $Ui.exportWmiFilterPathTextBox.Text | Should -Be $File
                    Invoke-Click $Ui.exportWmiFilterConfirmButton
                    $Ui.exportWmiFilterPanel.IsVisible | Should -BeFalse
                    Test-Path -LiteralPath $File | Should -BeTrue
                    $Ui.directoryResultTextBlock.Text | Should -BeLike "WMI filter 'Laptops' exported to $File*"

                    # A file there: replaced once confirmed.
                    Invoke-Click $Ui.exportWmiFilterMenuItem
                    Invoke-Click $Ui.exportWmiFilterConfirmButton
                    $Ui.exportWmiFilterPanel.IsVisible | Should -BeTrue
                    $Ui.exportWmiFilterErrorTextBlock.Text | Should -Be "$File exists: Replace writes the filter over it."
                    $Ui.exportWmiFilterConfirmButton.Content | Should -Be 'Replace'
                    Invoke-Click $Ui.exportWmiFilterConfirmButton
                    $Ui.exportWmiFilterPanel.IsVisible | Should -BeFalse

                    # Imported: refused under the name of a filter of the domain, then under another one.
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                    Invoke-Click $Ui.importWmiFilterMenuItem
                    $Ui.importWmiFilterPanel.IsVisible | Should -BeTrue
                    $Ui.importWmiFilterConfirmButton.IsEnabled | Should -BeFalse
                    $Ui.importWmiFilterPathTextBox.Text = $File
                    Invoke-Click $Ui.importWmiFilterReadButton
                    $Ui.importWmiFilterInfoTextBlock.Text | Should -Be ("'Laptops', exported from corp.contoso.com", 'Computers with a battery', 'root\CIMv2: SELECT * FROM Win32_Battery' -join [Environment]::NewLine)
                    $Ui.importWmiFilterErrorTextBlock.Text | Should -Be "A WMI filter named 'Laptops' exists in corp.contoso.com: give the imported one another name."
                    $Ui.importWmiFilterNameTextBox.Text | Should -Be 'Laptops'
                    Invoke-Click $Ui.importWmiFilterConfirmButton
                    $Ui.importWmiFilterErrorTextBlock.Text | Should -BeLike "*'Laptops' already exists*"
                    $Ui.importWmiFilterNameTextBox.Text = 'Laptops (copy)'
                    Invoke-Click $Ui.importWmiFilterConfirmButton
                    $Ui.importWmiFilterPanel.IsVisible | Should -BeFalse
                    $Copy = $Ui.Directory.FindWmiFilter('Laptops (copy)')
                    $Copy.GetQueryText() | Should -Be 'root\CIMv2: SELECT * FROM Win32_Battery'
                    $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Copy
                    $Ui.directoryResultTextBlock.Text | Should -BeLike "WMI filter 'Laptops (copy)' imported from $File.*"

                    # The file of Windows (GPMC), and a file that is not a filter.
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                    Invoke-Click $Ui.importWmiFilterMenuItem
                    $Ui.importWmiFilterPathTextBox.Text = $script:WindowsMof
                    $KeyArgs = [Avalonia.Input.KeyEventArgs]::new()
                    $KeyArgs.RoutedEvent = [Avalonia.Input.InputElement]::KeyDownEvent
                    $KeyArgs.Key = [Avalonia.Input.Key]::Enter
                    $Ui.importWmiFilterPathTextBox.RaiseEvent($KeyArgs)
                    $Ui.importWmiFilterInfoTextBlock.Text | Should -BeLike "'HGPM - MOF reference', exported from powershell.labo*root\StandardCimv2: SELECT * FROM MSFT_NetAdapter"
                    $Ui.importWmiFilterErrorTextBlock.Text | Should -BeNullOrEmpty
                    $Ui.importWmiFilterConfirmButton.IsEnabled | Should -BeTrue
                    $Ui.importWmiFilterPathTextBox.Text = $PSCommandPath
                    Invoke-Click $Ui.importWmiFilterReadButton
                    $Ui.importWmiFilterErrorTextBlock.Text | Should -BeLike 'The file cannot be imported: *'
                    $Ui.importWmiFilterConfirmButton.IsEnabled | Should -BeFalse
                }
            } finally {
                $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
            }
        }

        It 'Gives a WMI filter to a GPO from the filter, and from the details of the GPO' {
            $Laptops = $Directory.NewWmiFilter('Laptops', '', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            $Workstations = $Directory.NewWmiFilter('Workstations', '', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1' }))
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Gpo = $Ui.Directory.FindGpo('C - Laptops - Power Management')
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters', 'Laptops'
                $Ui.useWmiFilterMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.useWmiFilterMenuItem
                $Ui.useWmiFilterPanel.IsVisible | Should -BeTrue
                $Ui.useWmiFilterTitleTextBlock.Text | Should -Be "Use the WMI filter 'Laptops' in a GPO: the computers apply it only when each of its queries returns something (root\CIMv2: SELECT * FROM Win32_Battery)"
                @($Ui.useWmiFilterList.ItemsSource).Count | Should -Be $Ui.Directory.Gpos.Count
                $Ui.useWmiFilterSearchTextBox.Text = 'power management'
                $Ui.useWmiFilterList.SelectedItem | Should -Be $Gpo -Because 'the only match is chosen'
                Invoke-Click $Ui.useWmiFilterConfirmButton
                $Ui.useWmiFilterPanel.IsVisible | Should -BeFalse
                $Gpo.WmiFilterId | Should -Be $Laptops.Id
                $Ui.domainTreeView.SelectedItem.Tag | Should -Be $Laptops
                ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'GPOs using it').Value | Should -Be 'C - Laptops - Power Management'
                $Ui.directoryResultTextBlock.Text | Should -Be "'C - Laptops - Power Management' is linked to the WMI filter 'Laptops': the computers apply it only when each of its queries returns something (root\CIMv2: SELECT * FROM Win32_Battery)."
                Invoke-Click $Ui.useWmiFilterMenuItem
                @($Ui.useWmiFilterList.ItemsSource) | Should -Not -Contain $Gpo -Because 'it uses the filter already'
                Invoke-Click $Ui.useWmiFilterCancelButton

                # In the details of the GPO: its filter, another one, none.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Laptops - Power Management'
                $Ui.gpoWmiFilterPanel.IsVisible | Should -BeTrue
                @($Ui.gpoWmiFilterComboBox.ItemsSource.Content) | Should -Be @('(none)', 'Laptops', 'Workstations')
                $Ui.gpoWmiFilterComboBox.SelectedItem.Content | Should -Be 'Laptops'
                $Ui.gpoWmiFilterComboBox.SelectedIndex = 2
                $Gpo.WmiFilterId | Should -Be $Workstations.Id
                $Ui.directoryResultTextBlock.Text | Should -BeLike "'C - Laptops - Power Management' is linked to the WMI filter 'Workstations'*"
                $Ui.gpoWmiFilterComboBox.SelectedItem.Content | Should -Be 'Workstations'
                $Ui.gpoWmiFilterComboBox.SelectedIndex = 0
                $Gpo.WmiFilterId | Should -BeNullOrEmpty
                $Ui.directoryResultTextBlock.Text | Should -Be "'C - Laptops - Power Management' is linked to no WMI filter."

                # A filter the domain does not have anymore, and a GPO the account does not edit.
                $Gpo.WmiFilterId = [guid]::NewGuid()
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Laptops - Power Management'
                $Ui.gpoWmiFilterComboBox.SelectedItem.Content | Should -BeLike '{*}: not in the domain anymore*'
                $Gpo.CanEdit = $false
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'C - Laptops - Power Management'
                $Ui.gpoWmiFilterPanel.IsVisible | Should -BeFalse
            }
        }

        It 'Delegates the WMI filters in their Delegation tab: who creates them, who changes one' {
            $Filter = $Directory.NewWmiFilter('Laptops', '', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            Mock Resolve-PSGPOApplyTo { [pscustomobject]@{ Name = $Name; Sid = $Name } }
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                $Ui.wmiDelegationTab.IsVisible | Should -BeFalse
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                $Ui.wmiDelegationTab.IsVisible | Should -BeTrue
                $Ui.delegationTab.IsVisible | Should -BeFalse -Because 'the one of the GPOs'
                $Ui.directoryTabs.SelectedItem = $Ui.wmiDelegationTab
                $Ui.wmiDelegationTitleTextBlock.Text | Should -Be 'Delegation of the WMI filters of corp.contoso.com'
                @($Ui.wmiDelegationList.ItemsSource | ForEach-Object { "$($_.Name)=$($_.PermissionText)" }) |
                    Should -Be @('Domain Admins=Full control', 'Enterprise Admins=Full control', 'Administrators=Creator owner', 'Group Policy Creator Owners=Creator owner')
                @($Ui.wmiDelegationPermissionComboBox.ItemsSource.Content) | Should -Be @('Creator owner', 'Full control')
                $Ui.wmiDelegationNameTextBox.Text = 'GPO-Tier1-Admins'
                Invoke-Click $Ui.wmiDelegationSetButton
                $Ui.wmiDelegationStatusTextBlock.Text | Should -Be "'GPO-Tier1-Admins' has the permission Creator owner now."
                (@($Ui.wmiDelegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier1-Admins').PermissionText | Should -Be 'Creator owner'
                # Full control: each filter inherits it.
                $Ui.wmiDelegationList.SelectedItem = @($Ui.wmiDelegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier1-Admins'
                $Ui.wmiDelegationNameTextBox.Text | Should -Be 'GPO-Tier1-Admins'
                $Ui.wmiDelegationRemoveButton.IsEnabled | Should -BeTrue
                $Ui.wmiDelegationPermissionComboBox.SelectedIndex = 1
                Invoke-Click $Ui.wmiDelegationSetButton
                (@($Ui.wmiDelegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier1-Admins').PermissionText | Should -Be 'Full control'

                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters', 'Laptops'
                $Ui.directoryTabs.SelectedItem = $Ui.wmiDelegationTab
                $Ui.wmiDelegationTitleTextBlock.Text | Should -Be "Delegation of the WMI filter 'Laptops'"
                @($Ui.wmiDelegationPermissionComboBox.ItemsSource.Content) | Should -Be @('Edit', 'Full control')
                $Inherited = @($Ui.wmiDelegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier1-Admins'
                "$($Inherited.PermissionText) $($Inherited.InheritedText)" | Should -Be 'Full control Yes'
                $Ui.wmiDelegationList.SelectedItem = $Inherited
                $Ui.wmiDelegationRemoveButton.IsEnabled | Should -BeFalse -Because 'an inherited permission comes from WMI Filters'
                $Ui.wmiDelegationNameTextBox.Text = 'GPO-Tier2-Admins'
                $Ui.wmiDelegationPermissionComboBox.SelectedIndex = 0
                Invoke-Click $Ui.wmiDelegationSetButton
                $Row = @($Ui.wmiDelegationList.ItemsSource) | Where-Object Name -EQ 'GPO-Tier2-Admins'
                "$($Row.PermissionText) $($Row.InheritedText)" | Should -Be 'Edit No'
                $Ui.wmiDelegationList.SelectedItem = $Row
                Invoke-Click $Ui.wmiDelegationRemoveButton
                $Ui.wmiDelegationStatusTextBlock.Text | Should -Be "The permissions of 'GPO-Tier2-Admins' are removed."
                @($Ui.wmiDelegationList.ItemsSource.Name) | Should -Not -Contain 'GPO-Tier2-Admins'

                # Without the right to change the filter, read only.
                $Filter.CanEdit = $false
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters'
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'WMI Filters', 'Laptops'
                $Ui.directoryTabs.SelectedItem = $Ui.wmiDelegationTab
                $Ui.wmiDelegationSetButton.IsEnabled | Should -BeFalse
                $Ui.wmiDelegationStatusTextBlock.Text | Should -Be 'Read only: the account cannot change the permissions of this WMI filter.'
            }
        }

        It 'Says in the editor what the status of the GPO disables' {
            $Directory.SetGpoStatus($Directory.FindGpo('U - Lyon - Printers'), 2)
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'U - Lyon - Printers'
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.editingStatusTextBlock.Text | Should -Be 'The GPO status disables its Computer Configuration: its settings are saved, but the computers do not apply them.'
                $Ui.editingStatusTextBlock.IsVisible | Should -BeTrue
                Invoke-Click $Ui.managementButton
                $Ui.Directory.SetGpoStatus($Ui.Directory.FindGpo('U - Lyon - Printers'), 0)
                Invoke-Click $Ui.editGpoMenuItem
                $Ui.editingStatusTextBlock.Text | Should -BeNullOrEmpty
                $Ui.editingStatusTextBlock.IsVisible | Should -BeFalse
            }
        }

        It 'Deletes a GPO of Deleted GPOs for good, once confirmed' {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $Root = Join-Path $TestDrive "purge-$([guid]::NewGuid())"
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Set-PSGPOUserSetting -Values @{ BackupPath = $Root }
            try {
                $Gpo = $Directory.FindGpo('U - Lyon - Printers')
                $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName -Label 'Template'
                $null = Remove-PSGPO -Name $Gpo.DisplayName -Directory $Directory -BackupPath $Root -Confirm:$false
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Deleted GPOs', 'U - Lyon - Printers'
                    $Ui.purgeDeletedGpoButton.IsVisible | Should -BeTrue
                    $Ui.purgeDeletedGpoMenuItem.IsVisible | Should -BeTrue
                    Invoke-Click $Ui.purgeDeletedGpoButton
                    $Ui.purgeDeletedGpoPanel.IsVisible | Should -BeTrue
                    # Unchanged since its backup: deleted with that backup only, a template.
                    $Ui.purgeDeletedGpoTextBlock.Text | Should -Be "Delete the GPO 'U - Lyon - Printers' for good? Its backup in $Root is deleted: it cannot be restored afterwards. Templates of new GPOs made from it: 1, deleted too."
                    Invoke-Click $Ui.purgeDeletedGpoCancelButton
                    @(Get-PSGPOBackup -Path $Root -Id $Gpo.Id).Count | Should -Be 1
                    Invoke-Click $Ui.purgeDeletedGpoMenuItem
                    Invoke-Click $Ui.purgeDeletedGpoConfirmButton
                    @(Get-PSGPOBackup -Path $Root -Id $Gpo.Id).Count | Should -Be 0
                    $Ui.domainTreeView.SelectedItem.Tag | Should -Be 'DeletedGpos'
                    @((Get-DomainNode $Ui 'Deleted GPOs').Children).Count | Should -Be 0
                    $Ui.directoryResultTextBlock.Text | Should -Be "GPO 'U - Lyon - Printers' deleted for good: its backup is deleted."
                }
            } finally {
                $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
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
                    # Found without expanding: the OUs on the way say it, and a node lists it.
                    (Get-DomainNode $Ui 'Sites (1 waiting for approval)', 'Lyon (1 waiting for approval)', 'Users (1 waiting for approval)').Children.Header | Should -Contain 'T1 - Lyon - Proxy (waiting for approval)'
                    (Get-DomainNode $Ui 'Waiting for approval (1)').Children.Header | Should -Be @('T1 - Lyon - Proxy (waiting for approval)')
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'T1 - Lyon - Proxy (waiting for approval)'
                    ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Approval').Value | Should -BeLike 'Waiting for approval: it applies to nobody*(created by CORP\tech1).'
                    $Ui.approveGpoMenuItem.IsVisible | Should -BeFalse -Because 'a creator does not approve'

                    # An approver approves it.
                    $Ui.Directory.Workflow = & $Workflow $true
                    $Ui.Directory.Account = 'CORP\admin'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects'
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Group Policy Objects', 'T1 - Lyon - Proxy (waiting for approval)'
                    $Ui.approveGpoMenuItem.IsVisible | Should -BeTrue
                    # Opened from another tab: its form is in the Details tab, which is shown.
                    $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                    Invoke-Click $Ui.approveGpoMenuItem
                    $Ui.directoryTabs.SelectedIndex | Should -Be 0 -Because 'the form of Approve... is in the Details tab'
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

        It 'Shows the settings the console does not interpret, and has them reviewed before the approval' {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Set-PSGPOUserSetting -Values @{ BackupPath = (Join-Path $TestDrive "unseen-$([guid]::NewGuid())") }
            try {
                $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
                $Gpo.ApprovalState = 'Pending'
                $Gpo.Owner = 'CORP\tech1'
                $Gpo.UserExtensionNames = '[{25537BA6-77A8-11D2-9B6C-0000F8080861}{88E729D6-BDC1-11D1-BD2A-00C04FB9603F}]'
                $Directory.GpoFiles["$($Gpo.Id)\User\Documents & Settings\fdeploy1.ini"] = [byte[]](65, 66)
                $Directory.Account = 'CORP\admin'
                $Directory.Workflow = [pscustomobject]@{
                    Enabled = $true; Problem = $null; IsApprover = $true; IsCreator = $false
                    Approvers = @('Domain Admins'); ApproverSids = @('S-1-5-21-1-2-3-512'); Creators = @('GPO-Tier1-Admins'); CreatorSids = @('S-1-5-21-1-2-3-1123')
                    AccountCreatorSids = @(); ApprovedOwner = 'Domain Admins'; ApprovedOwnerSid = 'S-1-5-21-1-2-3-512'; CreatorRights = 'ReadOnly'
                }
                Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                    param($Ui)
                    $Ui.domainTreeView.SelectedItem = @((Get-DomainNode $Ui 'Group Policy Objects').Children | Where-Object { [object]::ReferenceEquals($_.Tag, $Gpo) })[0]
                    ($Ui.directoryPropertiesList.ItemsSource | Where-Object Key -EQ 'Not interpreted').Value | Should -BeLike 'Folder Redirection: *'
                    $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                    $Ui.uninterpretedSettingsBorder.IsVisible | Should -BeTrue
                    $Ui.uninterpretedSettingsHeader.Text | Should -Be 'Settings the console does not interpret (2)'
                    @($Ui.uninterpretedSettingsList.ItemsSource).Name | Should -Be @('Folder Redirection', 'User\Documents & Settings\fdeploy1.ini')
                    $Ui.settingsReportButton.IsVisible | Should -BeTrue

                    # Save report... of the context menu: its result in the Details tab.
                    $Ui.saveReportGpoMenuItem.IsVisible | Should -BeTrue
                    $Report = Join-Path $TestDrive "report-$([guid]::NewGuid()).html"
                    $Ui.GpoReport.Gpo = $Gpo
                    $Ui.GpoReport.FromMenu = $true
                    & $Ui.SaveGpoReport -Path $Report
                    $Ui.directoryTabs.SelectedIndex | Should -Be 0
                    $Ui.directoryResultTextBlock.Text | Should -Be "Report saved: $Report"
                    Get-Content -LiteralPath $Report -Raw | Should -BeLike '*Settings the console does not interpret (2)*fdeploy1.ini*'

                    Invoke-Click $Ui.approveGpoMenuItem
                    $Ui.approveGpoUninterpretedPanel.IsVisible | Should -BeTrue
                    $Ui.approveGpoUninterpretedTextBlock.Text | Should -Be 'The console does not interpret 2 setting(s) of this GPO, which the computers apply: Folder Redirection, User\Documents & Settings\fdeploy1.ini. See them in the Settings tab.'
                    $Ui.approveGpoUninterpretedCheckBox.IsChecked | Should -BeFalse
                    Invoke-Click $Ui.approveGpoConfirmButton
                    $Ui.approveGpoErrorTextBlock.Text | Should -BeLike 'Review the settings the console does not interpret*'
                    $Gpo.ApprovalState | Should -Be 'Pending'
                    $Ui.approveGpoUninterpretedCheckBox.IsChecked = $true
                    Invoke-Click $Ui.approveGpoConfirmButton
                    $Gpo.ApprovalState | Should -Be 'Approved'
                }
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

        It 'Changes the domain controller from the context menu of the domain, as GPMC' {
            $Ldap = New-TestLdapDirectory
            $Ldap.PdcEmulator = 'dc.hardenbox.labo'
            Mock Get-PSGPODomainController { 'dc.hardenbox.labo', 'dc2.hardenbox.labo' }
            Mock Update-PSGPODirectoryFromDomain { $Directory.Server = $Server }
            Start-PSGPOManagerWindow -Directory $Ldap -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = @($Ui.domainTreeView.ItemsSource)[0]
                $Ui.changeDcMenuItem.IsVisible | Should -BeTrue
                Invoke-Click $Ui.changeDcMenuItem
                $Ui.changeDcPanel.IsVisible | Should -BeTrue
                $Ui.changeDcTitleTextBlock.Text | Should -Be 'Domain controller of hardenbox.labo: dc.hardenbox.labo now'
                @($Ui.changeDcList.ItemsSource) | Should -Be @('dc.hardenbox.labo (PDC emulator, current)', 'dc2.hardenbox.labo')
                $Ui.changeDcConfirmButton.IsEnabled | Should -BeFalse
                $Ui.changeDcList.SelectedIndex = 0
                $Ui.changeDcConfirmButton.IsEnabled | Should -BeFalse -Because 'the domain is read from it now'
                $Ui.changeDcList.SelectedIndex = 1
                $Ui.changeDcConfirmButton.IsEnabled | Should -BeTrue
                Invoke-Click $Ui.changeDcConfirmButton
                $Ui.changeDcPanel.IsVisible | Should -BeFalse
                Invoke-UiLoop -Until { $Ui.directoryResultTextBlock.Text -like 'The domain is read from*' }
                $Ui.directoryResultTextBlock.Text | Should -BeLike 'The domain is read from dc2.hardenbox.labo, at *'
                @($Ui.statusBarList.ItemsSource.Text) | Should -Contain 'DC dc2.hardenbox.labo (Samba AD, not the PDC emulator (dc.hardenbox.labo))'
                # The domain only.
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Lyon'
                $Ui.changeDcMenuItem.IsVisible | Should -BeFalse
            }
            Should -Invoke Update-PSGPODirectoryFromDomain -Times 1 -Exactly -ParameterFilter { $Server -eq 'dc2.hardenbox.labo' }
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

        It 'Opens at once and loads the ADMX files chosen before the first time it needs them' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy ([GPOToolsUtility]::Policies | Where-Object { $_.ID -eq 'Biometrics_EnableBio' } | Select-Object -First 1) -Pol $Pol -State Disabled
            $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
            [GPOToolsUtility]::RemoveAll()
            try {
                Start-PSGPOManagerWindow -Directory $Directory -AdmxSource @{ Path = $PolicyDefinitions; UICulture = 'en-US' } -WarningVariable Warn 3>$null -OnShown {
                    param($Ui)
                    [GPOToolsUtility]::Policies.Count | Should -Be 0 -Because 'the console opens before the ADMX files are read'
                    $Ui.breadcrumbTextBlock.Text | Should -Not -BeLike 'No ADMX policy loaded*'
                    # The links and the details do not wait for them.
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                    $Ui.directoryTitleTextBlock.Text | Should -Be 'C - Servers - Security Baseline'
                    $Ui.admxLoadingBanner.IsVisible | Should -BeFalse

                    # The Settings tab names the policies: it waits for them, a banner says so.
                    $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                    $Ui.admxLoadingBanner.IsVisible | Should -BeTrue
                    $Ui.admxLoadingTextBlock.Text | Should -BeLike "Loading the administrative templates (ADMX) of $PolicyDefinitions*"
                    $Ui.settingsStatusTextBlock.Text | Should -Be 'Loading the administrative templates (ADMX)...'
                    # A report and the editor asked for meanwhile wait too, and the files are read once.
                    $Generation = [GPOToolsUtility]::Generation
                    $Report = Join-Path $TestDrive 'deferred-report.html'
                    $Ui.GpoReport.Gpo = $Ui.Directory.FindGpo('C - Servers - Security Baseline')
                    $Ui.GpoReport.FromMenu = $false
                    & $Ui.SaveGpoReport -Path $Report
                    Test-Path -LiteralPath $Report | Should -BeFalse
                    Invoke-Click $Ui.editGpoMenuItem
                    $Ui.editorView.IsVisible | Should -BeFalse

                    Invoke-UiLoop -Until { -not $Ui.admxLoadingBanner.IsVisible } -TimeoutMilliseconds 120000
                    $Ui.admxLoadingBanner.IsVisible | Should -BeFalse
                    [GPOToolsUtility]::Policies.Count | Should -BeGreaterThan 0
                    [GPOToolsUtility]::Generation | Should -Be ($Generation + 1) -Because 'one load for the three of them'
                    Get-Content -LiteralPath $Report -Raw | Should -Match 'Allow the use of biometrics'
                    @($Ui.computerSettingsList.ItemsSource)[0].Name | Should -Be 'Allow the use of biometrics'
                    $Ui.editorView.IsVisible | Should -BeTrue
                    $Ui.Editing.Gpo.DisplayName | Should -Be 'C - Servers - Security Baseline'
                    @(@($Ui.treeView.ItemsSource)[0].Children[0].Children.Header) | Should -Contain 'Administrative Templates'
                }
                $Warn | Should -BeNullOrEmpty
            } finally {
                if (-not [GPOToolsUtility]::Policies.Count) { Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null }
            }
        }

        It 'Says when the ADMX files chosen before cannot be loaded, and goes on without them' {
            [GPOToolsUtility]::RemoveAll()
            $Missing = Join-Path $TestDrive 'NoPolicyDefinitions'
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            try {
                Start-PSGPOManagerWindow -Directory $Directory -AdmxSource @{ Path = $Missing; UICulture = 'en-US' } 3>$null -OnShown {
                    param($Ui)
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                    Invoke-Click $Ui.editGpoMenuItem
                    Invoke-UiLoop -Until { $Ui.editorView.IsVisible }
                    $Ui.editorView.IsVisible | Should -BeTrue -Because 'the security settings do not need the ADMX files'
                    $Ui.admxLoadingBanner.IsVisible | Should -BeTrue
                    $Ui.admxLoadingTextBlock.Text | Should -BeLike "The administrative templates of $Missing are not loaded: *"
                    $Ui.breadcrumbTextBlock.Text | Should -Be $Ui.admxLoadingTextBlock.Text
                    # Asked for once: the next views do not try again.
                    Invoke-Click $Ui.managementButton
                    $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                    $Ui.settingsStatusTextBlock.Text | Should -BeLike 'No ADMX loaded*'
                    [GPOToolsUtility]::Policies.Count | Should -Be 0
                }
                (Get-PSGPOUserSetting).AdmxFailed | Should -BeTrue -Because 'the next start asks for them'
            } finally {
                $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
                Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
            }
        }

        It 'Says which ADMX files it leaves out when they cannot be read' {
            [GPOToolsUtility]::RemoveAll()
            $Store = Join-Path $TestDrive 'StoreWithBrokenFile'
            $null = New-Item -ItemType Directory -Path (Join-Path $Store 'en-US') -Force
            foreach ($Name in 'Windows', 'Biometrics') {
                Copy-Item -LiteralPath (Join-Path $PolicyDefinitions "$Name.admx") -Destination $Store
                Copy-Item -LiteralPath (Join-Path $PolicyDefinitions 'en-US' "$Name.adml") -Destination (Join-Path $Store 'en-US')
            }
            Set-Content -LiteralPath (Join-Path $Store 'Broken.admx') -Value '<policyDefinitions><policies>'
            try {
                Start-PSGPOManagerWindow -Directory $Directory -AdmxSource @{ Path = $Store; UICulture = 'en-US' } 3>$null -OnShown {
                    param($Ui)
                    $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                    $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                    Invoke-UiLoop -Until { $Ui.admxLoadingTextBlock.Text -like '*cannot be read*' } -TimeoutMilliseconds 60000
                    $Ui.admxLoadingBanner.IsVisible | Should -BeTrue
                    $Ui.admxLoadingTextBlock.Text | Should -BeLike "The administrative templates of $Store are loaded without the files that cannot be read: Broken.admx: *"
                    @([GPOToolsUtility]::Policies | Where-Object FileName -EQ 'Biometrics.admx').Count | Should -BeGreaterThan 0
                    # In their categories: the malformed file does not hide windows.admx.
                    @([GPOToolsUtility]::Policies | Where-Object FileName -EQ 'Biometrics.admx')[0].Path | Should -BeLike 'Machine\Windows Components\Biometrics\'
                }
            } finally {
                Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
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

        It 'Edits the restricted groups of a GPO, as the Group Policy editor' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                # Security Settings > Restricted Groups, after Event Log and before the advanced audit policy.
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -eq 'RestrictedGroups' }
                $Node.Parent.Header | Should -Be 'Security Settings'
                $Headers = @($Node.Parent.Children.Header)
                [array]::IndexOf($Headers, 'Restricted Groups') | Should -Be ([array]::IndexOf($Headers, 'Event Log') + 1)
                $Headers[-1] | Should -Be 'Advanced Audit Policy Configuration'
                $Ui.treeView.SelectedItem = $Node
                $Ui.restrictedGroupsPanel.IsVisible | Should -BeTrue
                $Ui.detailsTabs.IsVisible | Should -BeFalse
                $Ui.restrictedGroupsEmptyTextBlock.Text | Should -Be 'This GPO has no restricted group.'

                # A group: the members of the local Administrators.
                Invoke-Click $Ui.restrictedGroupsAddButton
                $Ui.restrictedGroupNameTextBox.Text = '*S-1-5-32-544'
                $Ui.restrictedGroupMembersTextBox.Text = "CONTOSO\Domain Admins`nCONTOSO\Tier1-Admins"
                $Ui.restrictedGroupMemberOfTextBox.Text = ''
                Invoke-Click $Ui.restrictedGroupsSaveButton
                $Ui.restrictedGroupsFormErrorTextBlock.Text | Should -BeNullOrEmpty
                $Ui.restrictedGroupsStatusTextBlock.Text | Should -BeLike "Restricted group '*S-1-5-32-544' added in GptTmpl.inf (version *)."
                $Row = @($Ui.restrictedGroupsList.ItemsSource)[0]
                $Row.Name | Should -Be 'BUILTIN\Administrators (*S-1-5-32-544)'
                $Row.Summary | Should -Be 'Members: CONTOSO\Domain Admins, CONTOSO\Tier1-Admins'

                # The same group again: refused, it is edited instead.
                Invoke-Click $Ui.restrictedGroupsAddButton
                $Ui.restrictedGroupNameTextBox.Text = '*s-1-5-32-544'
                Invoke-Click $Ui.restrictedGroupsSaveButton
                $Ui.restrictedGroupsFormErrorTextBlock.Text | Should -BeLike '*is already a restricted group*'
                Invoke-Click $Ui.restrictedGroupsCancelButton

                # Edited: its members no longer defined, a member of Remote Desktop Users.
                $Ui.restrictedGroupsList.SelectedItem = $Row
                Invoke-Click $Ui.restrictedGroupsEditButton
                $Ui.restrictedGroupMembersCheckBox.IsChecked = $false
                $Ui.restrictedGroupMemberOfTextBox.Text = '*S-1-5-32-555'
                Invoke-Click $Ui.restrictedGroupsSaveButton
                @($Ui.restrictedGroupsList.ItemsSource)[0].Summary | Should -Be 'Members: not defined - Member of: BUILTIN\Remote Desktop Users (*S-1-5-32-555)'

                # "Configured settings only" keeps the node.
                $Ui.configuredOnlyCheckBox.IsChecked = $true
                Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -eq 'RestrictedGroups' } | Should -Not -BeNullOrEmpty
                $Ui.configuredOnlyCheckBox.IsChecked = $false

                # Deleted.
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -eq 'RestrictedGroups' }
                $Ui.restrictedGroupsList.SelectedItem = @($Ui.restrictedGroupsList.ItemsSource)[0]
                Invoke-Click $Ui.restrictedGroupsDeleteButton
                $Ui.restrictedGroupsDeletePanel.IsVisible | Should -BeTrue
                Invoke-Click $Ui.restrictedGroupsDeleteConfirmButton
                @($Ui.restrictedGroupsList.ItemsSource).Count | Should -Be 0
            }
            [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($Gpo)).GetSectionNames() | Should -Not -Contain 'Group Membership'
        }

        It 'Edits the startup scripts of a GPO, a file copied into it, as the Group Policy editor' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Local = Join-Path $TestDrive 'Set-Baseline.ps1'
            Set-Content -LiteralPath $Local -Value 'Set-ItemProperty -Path HKLM:\Software\Contoso -Name Baseline -Value 1' -Encoding utf8
            $Version = $Gpo.GetComputerVersion()
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                # Windows Settings > Scripts (Startup/Shutdown) > Startup, before Security Settings.
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -eq 'Scripts:Machine|Startup' }
                $Node.Parent.Header | Should -Be 'Scripts (Startup/Shutdown)'
                @($Node.Parent.Children.Header) | Should -Be @('Startup', 'Shutdown')
                @($Node.Parent.Parent.Children.Header)[0..1] | Should -Be @('Scripts (Startup/Shutdown)', 'Security Settings')
                (Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -eq 'Scripts:User|Logon' }).Parent.Header | Should -Be 'Scripts (Logon/Logoff)'
                $Ui.treeView.SelectedItem = $Node
                $Ui.scriptsPanel.IsVisible | Should -BeTrue
                $Ui.detailsTabs.IsVisible | Should -BeFalse
                $Ui.scriptsTitleTextBlock.Text | Should -Be 'Startup (Computer Configuration)'
                $Ui.scriptsEmptyTextBlock.Text | Should -Be 'This GPO has no script of this kind.'

                # A PowerShell script, its file copied from this computer.
                Invoke-Click $Ui.scriptsAddButton
                $Ui.scriptsTypeComboBox.SelectedItem.Tag | Should -Be 'PowerShell'
                $Ui.scriptsCopyPathTextBox.Text = $Local
                $Ui.scriptsParametersTextBox.Text = '-Quiet'
                Invoke-Click $Ui.scriptsSaveButton
                $Ui.scriptsFormErrorTextBlock.Text | Should -BeNullOrEmpty
                $Ui.scriptsStatusTextBlock.Text | Should -BeLike "Script 'Set-Baseline.ps1' saved in Machine\Scripts\Startup\Set-Baseline.ps1, Machine\Scripts\psscripts.ini (version *)."
                $Row = @($Ui.scriptsList.ItemsSource)[0]
                $Row.Name | Should -Be 'Set-Baseline.ps1'
                $Row.Summary | Should -Be 'Windows PowerShell script - Parameters: -Quiet'
                $Ui.scriptsList.SelectedItem | Should -Be $Row
                $Ui.scriptsContentPanel.IsVisible | Should -BeTrue
                $Ui.scriptsContentTitleTextBlock.Text | Should -BeLike 'Machine\Scripts\Startup\Set-Baseline.ps1: * bytes, SHA-256 *'
                $Ui.scriptsContentTextBox.Text | Should -BeLike 'Set-ItemProperty -Path HKLM:\Software\Contoso*'

                # A script outside the GPO: the scripts of scripts.ini come before the PowerShell scripts.
                Invoke-Click $Ui.scriptsAddButton
                $Ui.scriptsTypeComboBox.SelectedIndex = 0
                $Ui.scriptsNameTextBox.Text = '\\corp\netlogon\inventory.cmd'
                Invoke-Click $Ui.scriptsSaveButton
                @($Ui.scriptsList.ItemsSource).Name | Should -Be @('\\corp\netlogon\inventory.cmd', 'Set-Baseline.ps1')
                @($Ui.scriptsList.ItemsSource)[0].Flags | Should -Be 'Outside the GPO: the computers run it from there'
                $Ui.scriptsUpButton.IsEnabled | Should -BeFalse -Because 'it is the first of the scripts of scripts.ini'

                # The PowerShell scripts run first.
                $Ui.scriptsOrderComboBox.SelectedIndex = 1
                $Ui.scriptsStatusTextBlock.Text | Should -BeLike 'Order of the PowerShell scripts saved in Machine\Scripts\psscripts.ini (version *).'

                # "Configured settings only" keeps the node.
                $Ui.configuredOnlyCheckBox.IsChecked = $true
                Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -eq 'Scripts:Machine|Startup' } | Should -Not -BeNullOrEmpty
                $Ui.configuredOnlyCheckBox.IsChecked = $false

                # Deleted: its file stays in the GPO.
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -eq 'Scripts:Machine|Startup' }
                $Ui.scriptsList.SelectedItem = @($Ui.scriptsList.ItemsSource)[0]
                Invoke-Click $Ui.scriptsDeleteButton
                $Ui.scriptsDeletePanel.IsVisible | Should -BeTrue
                Invoke-Click $Ui.scriptsDeleteConfirmButton
                @($Ui.scriptsList.ItemsSource).Name | Should -Be @('Set-Baseline.ps1')
            }
            $Gpo.GetComputerVersion() | Should -Be ($Version + 4) -Because 'each change is one increase of the version'
            $Gpo.MachineExtensionNames | Should -BeLike '*42B5FAAE-6536-11D2-AE5A-0000F87571E3*40B6664F-4972-11D1-A7CA-0000F87571E3*'
            [System.Text.Encoding]::UTF8.GetString($Directory.ReadGpoFile($Gpo, 'Machine\Scripts\Startup\Set-Baseline.ps1')) | Should -BeLike 'Set-ItemProperty*'
            $List = [GPOToolsScriptsFile]::Parse($Directory.ReadGpoFile($Gpo, 'Machine\Scripts\psscripts.ini'))
            $List.GetScripts('Startup').CmdLine | Should -Be 'Set-Baseline.ps1'
            $List.GetConfig('StartExecutePSFirst') | Should -Be 'true'
        }

        It 'Imports and deletes the certificates of the public key policies of a GPO' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $Request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=HGPM GUI Root CA', $Rsa,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $Der = $Request.CreateSelfSigned([datetimeoffset]::Now.AddDays(-1), [datetimeoffset]::Now.AddDays(30)).Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            $Rsa.Dispose()
            $CerPath = Join-Path $TestDrive 'gui-root.cer'
            [System.IO.File]::WriteAllBytes($CerPath, $Der)
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem
                # Security Settings > Public Key Policies > Trusted Root Certification Authorities, for the computers.
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsCertificateStoreNode] -and $n.Tag.Scope -eq 'Machine' -and $n.Tag.Store -eq 'Root' }
                $Node.Header | Should -Be 'Trusted Root Certification Authorities'
                $Node.Parent.Header | Should -Be 'Public Key Policies'
                $Node.Parent.Parent.Header | Should -Be 'Security Settings'
                @(Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsCertificateStoreNode] -and $n.Tag.Scope -eq 'User' }).Count | Should -BeGreaterThan 0
                $Ui.treeView.SelectedItem = $Node
                $Ui.certificatesPanel.IsVisible | Should -BeTrue
                $Ui.certificatesEmptyTextBlock.Text | Should -Be 'This GPO has no certificate in this store.'

                $Ui.certificatesPathTextBox.Text = Join-Path $TestDrive 'missing.cer'
                Invoke-Click $Ui.certificatesImportButton
                $Ui.certificatesStatusTextBlock.Text | Should -BeLike 'Give the path of a certificate file*'
                $Ui.certificatesPathTextBox.Text = $CerPath
                Invoke-Click $Ui.certificatesImportButton
                $Ui.certificatesStatusTextBlock.Text | Should -BeLike 'Certificate imported in Machine\Registry.pol (version *).'
                $Row = @($Ui.certificatesList.ItemsSource)[0]
                $Row.Name | Should -Be 'HGPM GUI Root CA'
                $Row.Summary | Should -BeLike 'Issued by HGPM GUI Root CA - expires * - thumbprint *'
                $Ui.certificatesList.SelectedItem | Should -Be $Row

                # The Settings tab lists it.
                Invoke-Click $Ui.managementButton
                $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                ($Ui.computerSettingsList.ItemsSource | Where-Object Name -EQ 'HGPM GUI Root CA').Path | Should -BeLike '*Public Key Policies > Trusted Root Certification Authorities'
                $Ui.directoryTabs.SelectedIndex = 0
                Invoke-Click $Ui.editGpoMenuItem

                # Deleted.
                $Ui.treeView.SelectedItem = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsCertificateStoreNode] -and $n.Tag.Scope -eq 'Machine' -and $n.Tag.Store -eq 'Root' }
                $Ui.certificatesList.SelectedItem = @($Ui.certificatesList.ItemsSource)[0]
                Invoke-Click $Ui.certificatesDeleteButton
                Invoke-Click $Ui.certificatesDeleteConfirmButton
                @($Ui.certificatesList.ItemsSource).Count | Should -Be 0
            }
            @(Get-PSGPOPolicyCertificate -Pol ([GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($Gpo, 'Machine'))) -Store 'Root').Count | Should -Be 0
            $Gpo.MachineExtensionNames | Should -Match ([regex]::Escape('{53D6AB1D-2488-11D1-A28C-00C04FB94F17}'))
        }

        It 'Edits the advanced audit policy of a GPO in audit.csv' {
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            Start-PSGPOManagerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.domainTreeView.SelectedItem = Get-DomainNode $Ui 'Servers', 'C - Servers - Security Baseline'
                Invoke-Click $Ui.editGpoMenuItem

                # Security Settings > Advanced Audit Policy Configuration > Audit Policies > Account Logon
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsSecuritySetting] -and $n.Tag.Name -eq 'Audit Credential Validation' }
                $Node.Parent.Header | Should -Be 'Account Logon'
                $Node.Parent.Parent.Header | Should -Be 'Audit Policies'
                $Node.Parent.Parent.Parent.Header | Should -Be 'Advanced Audit Policy Configuration'
                $Node.Parent.Parent.Parent.Parent.Header | Should -Be 'Security Settings'
                $Ui.treeView.SelectedItem = $Node
                $Ui.applyStatusTextBlock.Text | Should -Be 'Not defined in audit.csv'
                $Ui.previewHeaderTextBlock.Text | Should -Be 'audit.csv Preview'
                $Ui.enabledRadio.IsChecked = $true
                $Ui.Editing.Editor.Controls['Success'].IsChecked = $true
                $Ui.Editing.Editor.Controls['Failure'].IsChecked = $true
                (Get-PreviewLine $Ui) | Should -Be 'Set in audit.csv | Audit Credential Validation | {0cce923f-69ae-11d9-bed3-505054503030} | 3'
                Invoke-Click $Ui.applySettingButton
                $Ui.applyStatusTextBlock.Text | Should -BeLike 'Saved: Success, Failure in audit.csv*'

                # The Settings tab lists it.
                Invoke-Click $Ui.managementButton
                $Ui.directoryTabs.SelectedItem = $Ui.settingsTab
                ($Ui.computerSettingsList.ItemsSource | Where-Object Name -EQ 'Audit Credential Validation').State | Should -Be 'Success and Failure'
            }
            [GPOToolsAuditPolicyFile]::Parse($Directory.ReadAuditPolicyFile($Gpo)).GetValue('AdvancedAudit', '{0cce923f-69ae-11d9-bed3-505054503030}') | Should -Be '3'
            $Gpo.MachineExtensionNames | Should -Match 'F3CCC681-B74C-4060-9F26-CD84525DCA2A'
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
                $Ui.treeView.ItemsSource.Header | Should -Be @('Computer Configuration', 'User Configuration')
                # Expanded down to the settings, to see them at once.
                $Node = Find-TreeNode $Ui.treeView.ItemsSource { param($n) $n.Tag -is [GPOToolsSecuritySetting] }
                for ($Parent = $Node.Parent; $Parent; $Parent = $Parent.Parent) { $Parent.IsExpanded | Should -BeTrue -Because "$($Parent.Header) leads to the setting" }
                # The tree items themselves, not only the model.
                $Ui.Window.UpdateLayout()
                $Machine = $Ui.treeView.ContainerFromItem(@($Ui.treeView.ItemsSource)[0])
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

        It 'Shows this computer, its addresses, its domain, the domain controller and the version of HGPM in the status bar' {
            $Platform = Get-PSGPOPlatform
            Start-PSGPOManagerWindow -Directory (New-TestLdapDirectory) -OnShown {
                param($Ui)
                $Items = @($Ui.statusBarList.ItemsSource)
                $Items.Count | Should -Be 5
                $Items[0].Text | Should -BeLike "$($Platform.ComputerName) - *"
                $Items[3].Text | Should -Be 'DC dc.hardenbox.labo (Samba AD)'
                # The tests do not read the Gallery (PSGPOTOOLS_SKIP_UPDATE_CHECK): the version, a grey dot.
                $Items[4].Text | Should -Be "HGPM $((Get-PSGPOModuleVersion).Version)"
                $Items[4].HasBadge | Should -BeTrue
                $Items[4].BadgeBrush | Should -Be '#8A8886'
                @($Items | Where-Object HasBadge).Count | Should -Be 1

                # Drawn at the bottom of the window, below the views.
                $Ui.Window.UpdateLayout()
                $Ui.statusBar.IsVisible | Should -BeTrue
                $Ui.statusBar.Bounds.Height | Should -BeGreaterThan 15
                $Ui.statusBar.Bounds.Bottom | Should -BeGreaterThan ($Ui.Window.Bounds.Height - 2)
                $Ui.statusBar.Bounds.Top | Should -BeGreaterOrEqual $Ui.managementView.Bounds.Bottom
                $Icons = @([Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Ui.statusBarList) | Where-Object { $_ -is [Avalonia.Controls.PathIcon] })
                $Icons.Count | Should -Be 5
                $Icons | ForEach-Object { $_.Data | Should -Not -BeNullOrEmpty }
                $Dots = @([Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Ui.statusBarList) | Where-Object { $_ -is [Avalonia.Controls.Shapes.Ellipse] -and $_.IsVisible })
                $Dots.Count | Should -Be 1
                "$($Dots[0].Fill)" | Should -Match '8A8886'
            }
        }
    }

    Describe 'Policy Analyzer window' -Skip:$AvaloniaMissing {
        BeforeAll {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive 'settings.json'
            $Fixture = Join-Path $PSScriptRoot 'Fixtures' 'PolicyRules'
            $Rules = Join-Path $TestDrive 'Rules'
            $null = New-Item -ItemType Directory -Path $Rules -Force
            Copy-Item -LiteralPath (Join-Path $Fixture 'gpo2policyrules.PolicyRules') -Destination (Join-Path $Rules 'Fixture.PolicyRules')
            $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
            # The texts the cells of the grid show: what Avalonia binds, not the rows given to it.
            function Get-GridText {
                param($Grid)
                @([Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Grid) | Where-Object { $_ -is [Avalonia.Controls.TextBlock] -and $_.DataContext -is [AvaloniaPolicyRuleRow] } | ForEach-Object Text)
            }
        }
        AfterAll {
            $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
        }

        It 'Compares the sets checked to the effective state of the computer, saved in the folder as Policy Analyzer does' {
            $Folder = Join-Path $TestDrive 'Effective'
            $null = New-Item -ItemType Directory -Path $Folder -Force
            Copy-Item -LiteralPath (Join-Path $Rules 'Fixture.PolicyRules') -Destination $Folder
            Mock New-PSGPOPolicyRuleSetFromEffectiveState {
                $Set = [GPOToolsPolicyRuleSet]::new('EffectiveState_TEST_20261024-120000')
                foreach ($Rule in @($RuleSet[0].Rules)[0..4]) { $Copy = $Rule.Clone(); $Copy.PolicyName = 'Effective state'; $Set.Rules.Add($Copy) }
                [pscustomobject]@{ RuleSet = $Set; Skipped = 2 }
            }
            Start-PSGPOPolicyAnalyzerWindow -Path $Folder -OnShown {
                param($Ui)
                $Ui.analyzerEffectiveButton.IsVisible | Should -Be ([bool]$IsWindows) -Because 'the effective state is the one of a Windows computer'
                @($Ui.analyzerSetsList.ItemsSource)[0].IsChecked = $true
                Invoke-Click $Ui.analyzerEffectiveButton
                Invoke-UiLoop -Until { $Ui.analyzerGrid.IsVisible -and $Ui.analyzerEffectiveButton.IsEnabled } -TimeoutMilliseconds 30000
                @($Ui.analyzerGrid.Columns | ForEach-Object Header) | Should -Be @('Scope', 'Setting', 'Option', 'Fixture', 'EffectiveState_TEST_20261024-120000', 'Path')
                $Saved = Join-Path $Folder 'EffectiveState_TEST_20261024-120000.PolicyRules'
                $Ui.analyzerSetsStatusTextBlock.Text | Should -Be "2 security and audit settings are not read: secedit and auditpol need PowerShell run as an administrator.$([Environment]::NewLine)The effective state is saved in $Saved."
                Test-Path -LiteralPath $Saved | Should -BeTrue
                @($Ui.analyzerSetsList.ItemsSource.Name) | Should -Be @('EffectiveState_TEST_20261024-120000', 'Fixture') -Because 'the folder is read again'
            }
            Should -Invoke New-PSGPOPolicyRuleSetFromEffectiveState -Times 1 -Exactly -ParameterFilter { $RuleSet.Count -eq 1 -and $RuleSet[0].Name -eq 'Fixture' }
        }

        It 'Lists the rule sets of its folder, compares them and shows the details of a setting' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            Start-PSGPOPolicyAnalyzerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.Window.Title | Should -Be 'Policy Analyzer'
                $Ui.Window.Icon | Should -Not -BeNullOrEmpty
                $Ui.analyzerView.IsVisible | Should -BeTrue
                $Ui.subtitleTextBlock.Text | Should -Be "GPOs and security baselines compared setting by setting - $($Directory.DomainName)"
                $Ui.analyzerFolderTextBox.Text = $Rules
                Invoke-Click $Ui.analyzerFolderReadButton
                $Sets = @($Ui.analyzerSetsList.ItemsSource)
                $Sets.Count | Should -Be 1
                $Sets[0].Name | Should -Be 'Fixture'
                $Sets[0].Detail | Should -Be '2 GPO(s), 41 settings'
                (Get-PSGPOUserSetting).PolicyAnalyzerPath | Should -Be $Rules -Because 'the folder chosen is the one of the next time'

                Invoke-Click $Ui.analyzerCompareButton
                $Ui.analyzerSetsStatusTextBlock.Text | Should -Be 'Check one or more rule sets to compare.'
                $Sets[0].IsChecked = $true
                Invoke-Click $Ui.analyzerCompareButton
                Invoke-UiLoop -Until { $Ui.analyzerGrid.IsVisible -and $Ui.analyzerCompareButton.IsEnabled } -TimeoutMilliseconds 30000
                $Ui.analyzerSummaryTextBlock.Text | Should -Be '36 settings, 3 differences, 3 conflicts; 36 shown'
                @($Ui.analyzerGrid.Columns | ForEach-Object Header) | Should -Be @('Scope', 'Setting', 'Option', 'Fixture', 'Path')
                Invoke-UiLoop -TimeoutMilliseconds 300
                @(Get-GridText $Ui.analyzerGrid | Where-Object { $_ }) | Should -Not -BeNullOrEmpty -Because 'the cells show their values: Avalonia does not bind the PSObjects of a pipeline'

                $Ui.analyzerShowComboBox.SelectedIndex = 2
                @($Ui.analyzerGrid.ItemsSource).Count | Should -Be 3
                $Conflict = @($Ui.analyzerGrid.ItemsSource) | Where-Object { $_.Source.Setting -eq 'Differs' }
                $Conflict.Values | Should -Be @('***CONFLICT***')
                $Conflict.Brushes | Should -Be @('#80FFE14D')
                $Ui.analyzerShowComboBox.SelectedIndex = 0
                $Ui.analyzerSearchTextBox.Text = 'Spooler'
                @($Ui.analyzerGrid.ItemsSource).Count | Should -Be 1
                $Ui.analyzerGrid.SelectedIndex = 0
                Invoke-UiLoop -Until { $Ui.analyzerDetailsBorder.IsVisible } -TimeoutMilliseconds 3000
                $Ui.analyzerDetailsBorder.IsVisible | Should -BeTrue
                $Ui.analyzerDetailsNameTextBlock.Text | Should -Be 'Spooler'
                $Ui.analyzerDetailsPathTextBlock.Text | Should -Be 'Computer > Policies > Windows Settings > Security Settings > System Services'
                $Ui.analyzerDetailsSettingTextBlock.Text | Should -Be 'Security Template: [Service General Setting] Spooler'
                @($Ui.analyzerDetailsValuesList.ItemsSource)[0].Text | Should -Be 'HGPM Test - Computer: Disabled; D:AR(A;;RPWPCCDCLCSWRCWDWOGA;;;BA)'
            }
        }

        It 'Adds GPOs of the domain and GPMC backups as sets, saves a set as a .PolicyRules file and exports the comparison to Excel' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Folder = Join-Path $TestDrive 'Saved'
            Start-PSGPOPolicyAnalyzerWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.analyzerFolderTextBox.Text = $Folder
                Invoke-Click $Ui.analyzerFolderReadButton
                $Ui.analyzerSetsStatusTextBlock.Text | Should -BeLike 'No folder *'
                $Ui.analyzerSetsEmptyTextBlock.IsVisible | Should -BeTrue

                Invoke-Click $Ui.analyzerAddGposButton
                $Ui.analyzerGposPanel.IsVisible | Should -BeTrue
                $Ui.analyzerGposFilterTextBox.Text = 'Servers - Security Baseline'
                $Gpo = @($Ui.analyzerGposList.ItemsSource)[0]
                $Gpo.DisplayName | Should -Be 'C - Servers - Security Baseline'
                Invoke-Click $Ui.analyzerGposConfirmButton
                $Ui.analyzerGposErrorTextBlock.Text | Should -Be 'Select one or more GPOs.'
                $Ui.analyzerGposList.SelectedItems.Add($Gpo)
                Invoke-Click $Ui.analyzerGposConfirmButton
                $Ui.analyzerGposPanel.IsVisible | Should -BeFalse
                $Domain = @($Ui.analyzerSetsList.ItemsSource)[0]
                $Domain.Kind | Should -Be 'Domain'
                $Domain.Name | Should -Be 'C - Servers - Security Baseline'
                $Domain.IsChecked | Should -BeTrue

                Invoke-Click $Ui.analyzerAddGpmcButton
                $Ui.analyzerFilePathTextBox.Text = Join-Path $PSScriptRoot 'Fixtures' 'PolicyRules' 'GPOs'
                Invoke-Click $Ui.analyzerFileConfirmButton
                $Gpmc = @($Ui.analyzerSetsList.ItemsSource)[1]
                $Gpmc.Kind | Should -Be 'Gpmc'
                $Gpmc.Detail | Should -Be 'Backups: 2 GPO(s), 41 settings'

                $Ui.analyzerSetsList.SelectedItem = $Gpmc
                Invoke-Click $Ui.analyzerSaveSetButton
                $Ui.analyzerFilePathTextBox.Text | Should -Be (Join-Path $Folder 'GPOs.PolicyRules')
                Invoke-Click $Ui.analyzerFileConfirmButton
                Test-Path -LiteralPath (Join-Path $Folder 'GPOs.PolicyRules') | Should -BeTrue
                # The set saved in the folder is now its file, still checked.
                @($Ui.analyzerSetsList.ItemsSource | ForEach-Object Kind) | Should -Be @('File', 'Domain')
                $Saved = @($Ui.analyzerSetsList.ItemsSource)[0]
                $Saved.Name | Should -Be 'GPOs'
                $Saved.IsChecked | Should -BeTrue

                Invoke-Click $Ui.analyzerCompareButton
                Invoke-UiLoop -Until { $Ui.analyzerGrid.IsVisible -and $Ui.analyzerCompareButton.IsEnabled } -TimeoutMilliseconds 30000
                @($Ui.analyzerGrid.Columns | ForEach-Object Header)[3..4] | Should -Be @('GPOs', 'C - Servers - Security Baseline')
                Invoke-Click $Ui.analyzerExportButton
                $Ui.analyzerFileAllCheckBox.IsVisible | Should -BeTrue
                $Workbook = Join-Path $Folder 'Comparison.xlsx'
                $Ui.analyzerFilePathTextBox.Text = $Workbook
                Invoke-Click $Ui.analyzerFileConfirmButton
                Test-Path -LiteralPath $Workbook | Should -BeTrue
                $Ui.analyzerSummaryTextBlock.Text | Should -Be "Exported: $Workbook"
                # A file there is replaced once confirmed.
                Invoke-Click $Ui.analyzerExportButton
                $Ui.analyzerFilePathTextBox.Text = $Workbook
                Invoke-Click $Ui.analyzerFileConfirmButton
                $Ui.analyzerFileErrorTextBlock.Text | Should -Be "$Workbook exists: click again to replace it."
                Invoke-Click $Ui.analyzerFileConfirmButton
                $Ui.analyzerFilePanel.IsVisible | Should -BeFalse
            }
        }

        It 'Opens on the folder given, without keeping it for the next time' {
            Start-PSGPOPolicyAnalyzerWindow -Path $Rules -OnShown {
                param($Ui)
                $Ui.analyzerFolderTextBox.Text | Should -Be $Rules
                @($Ui.analyzerSetsList.ItemsSource).Count | Should -Be 1
                (Get-PSGPOUserSetting).PolicyAnalyzerPath | Should -Not -Be $Rules
            }
        }

        It 'Says there is no domain to read the GPOs from, and reads the one given the first time they are asked for' {
            Mock Get-PSGPOPlatform { [pscustomobject]@{ DomainName = $null } }
            Start-PSGPOPolicyAnalyzerWindow -OnShown {
                param($Ui)
                Invoke-Click $Ui.analyzerAddGposButton
                $Ui.analyzerGposPanel.IsVisible | Should -BeTrue
                $Ui.analyzerGposErrorTextBlock.Text | Should -Be 'No domain: this computer is not in a domain, and no domain controller was given (-Server).'
                @($Ui.analyzerGposList.ItemsSource).Count | Should -Be 0
            }
            Mock Get-PSGPODirectory { Import-PSGPODirectory -Path $SamplePath }
            Start-PSGPOPolicyAnalyzerWindow -DomainParameters @{ Server = 'dc.hgpm.test' } -OnShown {
                param($Ui)
                Invoke-Click $Ui.analyzerAddGposButton
                $Ui.analyzerGposErrorTextBlock.Text | Should -BeNullOrEmpty
                @($Ui.analyzerGposList.ItemsSource).Count | Should -BeGreaterThan 0
                Invoke-Click $Ui.analyzerGposCancelButton
                Invoke-Click $Ui.analyzerAddGposButton
            }
            Should -Invoke Get-PSGPODirectory -Times 1 -Exactly -ParameterFilter { $Server -eq 'dc.hgpm.test' } -Because 'the domain is read once'
        }

        It 'Adds the GPOs that apply to an OU as a set, by precedence, and shows which one wins' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            foreach ($Pair in @(@('C - Laptops - Power Management', 1), @('C - Workstations - BitLocker', 2))) {
                $Pol = [GPOToolsRegistryPol]::new()
                $Pol.Entries.Add([GPOToolsPolEntry]::new('Software\Policies\HGPM', 'Value', [GPOToolsPolType]::DWord, [BitConverter]::GetBytes([uint32]$Pair[1])))
                $Directory.WritePolicyFile($Directory.FindGpo($Pair[0]), 'Machine', $Pol.ToBytes())
            }
            Start-PSGPOPolicyAnalyzerWindow -Directory $Directory -Path (Join-Path $TestDrive 'Empty') -OnShown {
                param($Ui)
                Invoke-Click $Ui.analyzerAddGposButton
                $Ui.analyzerGposSomComboBox.IsVisible | Should -BeFalse
                $Ui.analyzerGposModeComboBox.SelectedIndex = 1
                $Ui.analyzerGposSomComboBox.IsVisible | Should -BeTrue
                $Ui.analyzerGposList.IsVisible | Should -BeFalse
                @($Ui.analyzerGposSomComboBox.ItemsSource)[0] | Should -Be 'corp.contoso.com'
                $Ui.analyzerGposSomComboBox.SelectedIndex = [array]::IndexOf(@($Ui.analyzerGposSomComboBox.ItemsSource), 'corp.contoso.com > Sites > Lyon > Workstations > Laptops')
                Invoke-Click $Ui.analyzerGposConfirmButton
                $Set = @($Ui.analyzerSetsList.ItemsSource)[0]
                $Set.Kind | Should -Be 'Container'
                $Set.Name | Should -Be 'Laptops (precedence)'
                $Set.Detail | Should -BeLike 'The GPOs that apply, by precedence: 8 GPO(s), * settings'
                Invoke-Click $Ui.analyzerCompareButton
                Invoke-UiLoop -Until { $Ui.analyzerGrid.IsVisible -and $Ui.analyzerCompareButton.IsEnabled } -TimeoutMilliseconds 30000
                $Ui.analyzerSearchTextBox.Text = 'HGPM'
                $Row = @($Ui.analyzerGrid.ItemsSource) | Where-Object { $_.Source.Setting -eq 'Value' }
                $Row.Values | Should -Be @('1')
                $Ui.analyzerGrid.SelectedItem = $Row
                Invoke-UiLoop -Until { $Ui.analyzerDetailsBorder.IsVisible } -TimeoutMilliseconds 3000
                @($Ui.analyzerDetailsValuesList.ItemsSource)[0].Text | Should -Be ("C - Laptops - Power Management (precedence 3, applied): 1" + [Environment]::NewLine + "C - Workstations - BitLocker (precedence 4): 2")
            }
        }

        It 'Writes the settings of the selected set in a GPO of the domain, or in a new one' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            Mock Get-PSGPODefaultBackupPath { Join-Path $TestDrive 'ApplyBackups' }
            Start-PSGPOPolicyAnalyzerWindow -Directory $Directory -Path $Rules -OnShown {
                param($Ui)
                Invoke-Click $Ui.analyzerApplySetButton
                $Ui.analyzerSetsStatusTextBlock.Text | Should -Be 'Select the set to write in a GPO.'
                $Ui.analyzerSetsList.SelectedIndex = 0
                Invoke-Click $Ui.analyzerApplySetButton
                $Ui.analyzerApplyPanel.IsVisible | Should -BeTrue
                $Ui.analyzerApplyTitleTextBlock.Text | Should -Be "Write the settings of the set 'Fixture' in a GPO of the domain"
                @($Ui.analyzerApplyPoliciesList.SelectedItems) | Should -Be @('HGPM Test - Computer', 'HGPM Test - Second')
                Invoke-Click $Ui.analyzerApplyConfirmButton
                $Ui.analyzerApplyErrorTextBlock.Text | Should -Be 'Choose the GPO, or give the name of a new one.'

                $Ui.analyzerApplyGpoComboBox.SelectedItem = @($Ui.analyzerApplyGpoComboBox.ItemsSource | Where-Object DisplayName -EQ 'C - Servers - Security Baseline')[0]
                $Ui.analyzerApplyPoliciesList.SelectedItems.Remove('HGPM Test - Computer')
                Invoke-Click $Ui.analyzerApplyConfirmButton
                $Ui.analyzerApplyPanel.IsVisible | Should -BeFalse
                $Ui.analyzerSetsStatusTextBlock.Text | Should -Be "Written in the GPO 'C - Servers - Security Baseline': 4 registry settings, 2 security settings, 0 audit settings."
                $Written = Get-PSGPOPolicyRuleSet -Directory $Directory -Name 'C - Servers - Security Baseline'
                ($Written.Rules | Where-Object ValueName -EQ 'OnlyB').RegData | Should -Be '0'

                Invoke-Click $Ui.analyzerApplySetButton
                $Ui.analyzerApplyNewNameTextBox.Text = 'C - Servers - Security Baseline'
                Invoke-Click $Ui.analyzerApplyConfirmButton
                $Ui.analyzerApplyErrorTextBlock.Text | Should -Be "A GPO named 'C - Servers - Security Baseline' already exists: choose it in the list."
                $Ui.analyzerApplyNewNameTextBox.Text = 'C - Baseline from a rule set'
                Invoke-Click $Ui.analyzerApplyConfirmButton
                $Ui.analyzerSetsStatusTextBlock.Text | Should -BeLike "Written in the GPO 'C - Baseline from a rule set': 20 registry settings*; 1 not written (no data in the set)."
                $Directory.FindGpo('C - Baseline from a rule set') | Should -Not -BeNullOrEmpty
            }
            @(Get-ChildItem -LiteralPath (Join-Path $TestDrive 'ApplyBackups') -Recurse -Filter 'manifest.json').Count | Should -BeGreaterThan 0 -Because 'the GPO is backed up first'
        }

    }

    Describe 'ADMX window' -Skip:$AvaloniaMissing {
        BeforeAll {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
        }
        BeforeEach {
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            # Show-GPOManagerAvalonia sets the language of the session (French on a French computer).
            $null = Set-PSGPOLanguage -Language 'en-US'
            # Not the central store of the domain of the computer running the tests.
            Mock Get-PSGPOAdmxCentralStore { }
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
            # No central store proposed (none reached): a fallback, tried after the stores.
            $Settings.AdmxFallback | Should -Be $PolicyDefinitions
            $Settings.PolicyDefinitions | Should -BeNullOrEmpty
            $Settings.UICulture | Should -Be 'fr-FR'

            # Next time: the folder and the language chosen are selected.
            $null = Show-PSGPOAdmxWindow -OnShown {
                param($Ui)
                $Ui.pathTextBox.Text | Should -Be $PolicyDefinitions
                $Ui.cultureComboBox.SelectedItem | Should -Be 'fr-FR'
            }
        }

        It 'Selects the central store of the domain rather than the folder chosen last' {
            $Store = Join-Path $TestDrive 'Store'
            $null = New-Item -ItemType Directory -Path (Join-Path $Store 'en-US') -Force
            Set-Content -LiteralPath (Join-Path $Store 'test.admx') -Value '<policyDefinitions/>'
            Set-Content -LiteralPath (Join-Path $Store 'en-US' 'test.adml') -Value '<policyDefinitionResources/>'
            $Store = [System.IO.Path]::GetFullPath($Store)
            Mock Get-PSGPOAdmxCentralStore { $Store }
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $PolicyDefinitions; UICulture = 'en-US' }
            $null = Show-PSGPOAdmxWindow -OnShown {
                param($Ui)
                @($Ui.candidateComboBox.ItemsSource)[0] | Should -Be $Store
                $Ui.candidateComboBox.SelectedItem | Should -Be $Store
                $Ui.pathTextBox.Text | Should -Be $Store
                $Ui.statusTextBlock.Text | Should -Be 'Central store of the domain: 1 ADMX files, 1 language.'
                # The folder chosen last is still there, without the words of the central store.
                $Ui.pathTextBox.Text = $PolicyDefinitions
                $Ui.statusTextBlock.Text | Should -Match '^\d+ ADMX files'
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

        It 'Opens the console at once on the folder chosen before, and asks only when there is none' {
            Mock Show-PSGPOAdmxWindow { $true }
            Mock Start-PSGPOManagerWindow { $script:AdmxSource = $AdmxSource }
            Mock Initialize-PSGPODomainConfiguration { $false }
            $Sample = Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json')
            [GPOToolsUtility]::RemoveAll()
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $PolicyDefinitions; UICulture = 'fr-FR' }
            Show-GPOManagerAvalonia -Directory $Sample -Language 'en-US'
            Should -Invoke Show-PSGPOAdmxWindow -Times 0 -Exactly
            $script:AdmxSource.Path | Should -Be $PolicyDefinitions
            $script:AdmxSource.UICulture | Should -Be 'fr-FR'
            [GPOToolsUtility]::Policies.Count | Should -Be 0 -Because 'the console loads them the first time it needs them'

            # A folder no longer there: asked for.
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = (Join-Path $TestDrive 'Gone') }
            Show-GPOManagerAvalonia -Directory $Sample -Language 'en-US'
            Should -Invoke Show-PSGPOAdmxWindow -Times 1 -Exactly
            $script:AdmxSource | Should -BeNullOrEmpty

            # Browsing the policies only (-NoDirectory): loaded before, as the editor shows them at once.
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $PolicyDefinitions; UICulture = 'en-US' }
            Show-GPOManagerAvalonia -NoDirectory -Language 'en-US' 3>$null
            Should -Invoke Show-PSGPOAdmxWindow -Times 1 -Exactly
            $script:AdmxSource | Should -BeNullOrEmpty
            [GPOToolsUtility]::Policies.Count | Should -BeGreaterThan 0
        }

        It 'Opens the console on the folder chosen last, else on the central store of the domain shown, as GPMC' {
            Mock Show-PSGPOAdmxWindow { $true }
            Mock Start-PSGPOManagerWindow { $script:AdmxSource = $AdmxSource }
            Mock Initialize-PSGPODomainConfiguration { $false }
            $Store = Join-Path $TestDrive 'CentralStore'
            $null = New-Item -ItemType Directory -Path (Join-Path $Store 'en-US') -Force
            Set-Content -LiteralPath (Join-Path $Store 'test.admx') -Value '<policyDefinitions/>'
            Set-Content -LiteralPath (Join-Path $Store 'en-US' 'test.adml') -Value '<policyDefinitionResources/>'
            $Store = [System.IO.Path]::GetFullPath($Store)
            Mock Get-PSGPOAdmxCentralStore { $Store }
            $Sample = Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json')
            [GPOToolsUtility]::RemoveAll()

            # The folder chosen in the ADMX window: the choice of the user.
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $PolicyDefinitions; UICulture = 'fr-FR' }
            Show-GPOManagerAvalonia -Directory $Sample -Language 'en-US'
            $script:AdmxSource.Path | Should -Be $PolicyDefinitions
            Should -Invoke Get-PSGPOAdmxCentralStore -Times 0 -Exactly -Because 'the store is not looked for when a folder is chosen'

            # None chosen: the central store, of the computer for a description of a domain, of the
            # domain read otherwise.
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $null; UICulture = $null }
            Show-GPOManagerAvalonia -Directory $Sample -Language 'en-US'
            Should -Invoke Show-PSGPOAdmxWindow -Times 0 -Exactly
            $script:AdmxSource.Path | Should -Be $Store
            $script:AdmxSource.UICulture | Should -Be 'en-US' -Because 'the only language of the store'
            Should -Invoke Get-PSGPOAdmxCentralStore -Times 1 -Exactly -ParameterFilter { -not $DomainName }
            . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')
            Show-GPOManagerAvalonia -Directory (New-TestLdapDirectory) -Language 'en-US'
            Should -Invoke Get-PSGPOAdmxCentralStore -Times 1 -Exactly -ParameterFilter { $DomainName -eq 'hardenbox.labo' -and $Server -eq 'dc.hardenbox.labo' }

            # The central store of another domain saved by 0.1.17: the store of the domain shown.
            $Other = Join-Path $TestDrive 'sysvol' 'other.labo' 'Policies' 'PolicyDefinitions'
            $null = New-Item -ItemType Directory -Path (Join-Path $Other 'en-US') -Force
            Set-Content -LiteralPath (Join-Path $Other 'test.admx') -Value '<policyDefinitions/>'
            Set-Content -LiteralPath (Join-Path $Other 'en-US' 'test.adml') -Value '<policyDefinitionResources/>'
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $Other; UICulture = 'en-US' }
            Show-GPOManagerAvalonia -Directory $Sample -Language 'en-US'
            $script:AdmxSource.Path | Should -Be $Store

            # The last load of the console failed: the window asks, with the store found already.
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $PolicyDefinitions; UICulture = 'en-US'; AdmxFailed = $true }
            Show-GPOManagerAvalonia -Directory $Sample -Language 'en-US'
            Should -Invoke Show-PSGPOAdmxWindow -Times 1 -Exactly -ParameterFilter { $CentralStore -contains $Store }
            $script:AdmxSource | Should -BeNullOrEmpty
        }

        It 'Remembers the language, not the central store it proposed: the console takes the store of the domain it shows' {
            $Store = Join-Path $TestDrive 'ProposedStore'
            $null = New-Item -ItemType Directory -Path (Join-Path $Store 'en-US') -Force
            foreach ($Name in 'Windows', 'Biometrics') {
                Copy-Item -LiteralPath (Join-Path $PolicyDefinitions "$Name.admx") -Destination $Store
                Copy-Item -LiteralPath (Join-Path $PolicyDefinitions 'en-US' "$Name.adml") -Destination (Join-Path $Store 'en-US')
            }
            $Store = [System.IO.Path]::GetFullPath($Store)
            Mock Get-PSGPOAdmxCentralStore { $Store }
            Set-PSGPOUserSetting -Values @{ AdmxFailed = $true }
            $Loaded = Show-PSGPOAdmxWindow -OnShown {
                param($Ui)
                $Ui.pathTextBox.Text | Should -Be $Store
                Invoke-Click $Ui.loadButton
                Invoke-UiLoop -Until { -not $Ui.Window.IsVisible } -TimeoutMilliseconds 60000
            }
            $Loaded | Should -BeTrue
            $Settings = Get-PSGPOUserSetting
            $Settings.PolicyDefinitions | Should -BeNullOrEmpty
            $Settings.UICulture | Should -Be 'en-US'
            $Settings.AdmxFailed | Should -BeNullOrEmpty -Because 'the load worked'
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

    Describe 'PSO Manager window' -Skip:$AvaloniaMissing {
        BeforeEach {
            $SamplePolicies = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'PasswordPolicy.sample.json'
            $Store = Import-PSGPOPasswordPolicyStore -Path $SamplePolicies
            $Store.IsDemonstration = $true
        }

        It 'Lists the PSOs by order of priority, and shows the settings and subjects of the selected one' {
            Start-PSGPOPasswordPolicyWindow -Store $Store -OnShown {
                param($Ui)
                $Ui.Window.Icon | Should -Not -BeNullOrEmpty -Because 'the logo of HGPM is the icon of the window'
                $Ui.demoBanner.IsVisible | Should -BeTrue
                $Ui.policiesView.IsVisible | Should -BeTrue
                $Ui.policiesButton.Classes | Should -Contain 'active'
                @($Ui.policiesList.ItemsSource).Name | Should -Be @($Store.Policies.Name)
                $Ui.policiesHeaderTextBlock.Text | Should -BeLike '7 password settings objects*'
                $Ui.domainPolicyTextBlock.Text | Should -Be '7 characters, history 24, expires after 42 days, no lockout'
                $Ui.editPolicyButton.IsEnabled | Should -BeFalse
                $Ui.policiesList.SelectedItem = @($Ui.policiesList.ItemsSource) | Where-Object Name -EQ 'PSO - Tier 0 Admins'
                $Ui.policyTitleTextBlock.Text | Should -Be 'PSO - Tier 0 Admins'
                ($Ui.policySettingsList.ItemsSource | Where-Object Key -EQ 'Minimum password length').Value | Should -Be '20 characters'
                ($Ui.policySettingsList.ItemsSource | Where-Object Key -EQ 'Account will be locked out').Value | Should -Be 'Until an administrator manually unlocks the account'
                $Ui.appliesToHeaderTextBlock.Text | Should -Be 'Directly Applies To (1)'
                @($Ui.appliesToList.ItemsSource)[0].Kind | Should -Be 'Global security group'
                @($Ui.statusBarList.ItemsSource).Count | Should -Be 5 -Because 'this computer, its addresses, its domain, the source of the policies and the version of HGPM'
                @($Ui.statusBarList.ItemsSource)[4] | Should -BeOfType [AvaloniaStatusItem]
                @($Ui.statusBarList.ItemsSource)[4].Text | Should -BeLike 'HGPM *'
                @($Ui.statusBarList.ItemsSource)[0].Text | Should -Not -BeNullOrEmpty
                @($Ui.statusBarList.ItemsSource)[0] | Should -BeOfType [AvaloniaStatusItem] -Because 'a binding does not read the properties of a PSObject'
            }
        }

        It 'Creates a PSO in its window, checked first, and applies it to a user' {
            Start-PSGPOPasswordPolicyWindow -Store $Store -OnShown {
                param($Ui)
                Invoke-Click $Ui.newPolicyButton
                $Editor = $Ui.Editor.Ui.Controls
                $Ui.Editor.Ui.Window.Title | Should -Be 'Create Password Settings'
                $Editor.protectCheckBox.IsChecked | Should -BeTrue
                $Editor.minLengthUpDown.Value | Should -Be 7
                Invoke-Click $Editor.okButton
                $Editor.errorTextBlock.Text | Should -Be 'The name is required. The precedence is a number of 1 or more.'
                $Editor.nameTextBox.Text = 'PSO - Helpdesk'
                $Editor.precedenceUpDown.Value = [decimal]2
                $Editor.enforceMaxAgeCheckBox.IsChecked = $false
                $Editor.maxAgeUpDown.IsEnabled | Should -BeFalse -Because 'a value is entered for a setting enforced only'
                $Editor.enforceLockoutCheckBox.IsChecked = $true
                $Editor.lockUntilUnlockRadio.IsChecked = $true
                $Editor.subjectSearchTextBox.Text = 'Jean'
                Invoke-Click $Editor.subjectSearchButton
                @($Editor.subjectResultsList.ItemsSource).Name | Should -Be @('Jean Dupont')
                $Editor.subjectResultsList.SelectedIndex = 0
                Invoke-Click $Editor.subjectAddButton
                Invoke-Click $Editor.okButton
                $Ui.Editor.Ui.Window.IsVisible | Should -BeFalse -Because 'the PSO is created'
                $New = $Store.FindPolicy('PSO - Helpdesk')
                $New.MaxPasswordAge | Should -Be ([TimeSpan]::Zero)
                $New.LockoutThreshold | Should -Be 5
                $New.LockoutDuration | Should -Be ([TimeSpan]::Zero)
                $New.AppliesTo | Should -Be @($Store.ResolveAccount('jdupont').DistinguishedName)
                $Ui.policyTitleTextBlock.Text | Should -Be 'PSO - Helpdesk' -Because 'the new PSO is selected'
                $Ui.policyResultTextBlock.Text | Should -Be 'Saved: PSO - Helpdesk.'
                @($Ui.policiesList.ItemsSource)[0].Name | Should -Be 'PSO - Helpdesk' -Because 'precedence 2 comes first'
            }
        }

        It 'Changes nothing when a PSO is opened and saved as it is' {
            $Policy = $Store.FindPolicy('PSO - IT Staff')
            $Policy.MinPasswordAge = [TimeSpan]::FromHours(36)
            $Before = Get-PSGPOPasswordPolicyValue -Policy $Policy
            Start-PSGPOPasswordPolicyWindow -Store $Store -OnShown {
                param($Ui)
                $Ui.policiesList.SelectedItem = @($Ui.policiesList.ItemsSource) | Where-Object Name -EQ 'PSO - IT Staff'
                Invoke-Click $Ui.editPolicyButton
                $Ui.Editor.Ui.Window.Title | Should -Be 'Password Settings: PSO - IT Staff'
                $Ui.Editor.Ui.Controls.minAgeUpDown.Value | Should -Be 2 -Because '1.5 days shows rounded'
                Invoke-Click $Ui.Editor.Ui.Controls.okButton
                $Ui.Editor.Ui.Window.IsVisible | Should -BeFalse
            }
            $After = Get-PSGPOPasswordPolicyValue -Policy $Policy
            foreach ($Name in $Before.Keys) { "$($After[$Name])" | Should -Be "$($Before[$Name])" -Because "$Name did not change" }
        }

        It 'Deletes a PSO once confirmed, but not one protected from accidental deletion' {
            Start-PSGPOPasswordPolicyWindow -Store $Store -OnShown {
                param($Ui)
                $Ui.policiesList.SelectedItem = @($Ui.policiesList.ItemsSource) | Where-Object Name -EQ 'PSO - Tier 0 Admins'
                Invoke-Click $Ui.deletePolicyButton
                $Ui.deletePolicyPanel.IsVisible | Should -BeFalse
                $Ui.policyResultTextBlock.Text | Should -BeLike '*protected from accidental deletion*'
                $Ui.policiesList.SelectedItem = @($Ui.policiesList.ItemsSource) | Where-Object Name -EQ 'PSO - IT Staff'
                Invoke-Click $Ui.deletePolicyButton
                $Ui.deletePolicyPanel.IsVisible | Should -BeTrue
                Invoke-Click $Ui.deletePolicyConfirmButton
                $Store.FindPolicy('PSO - IT Staff') | Should -BeNullOrEmpty
                $Ui.policyResultTextBlock.Text | Should -Be 'PSO - IT Staff deleted.'
                @($Ui.policiesList.ItemsSource).Count | Should -Be 6
            }
        }

        It 'Shows what applies to a user and why, by order of priority' {
            Start-PSGPOPasswordPolicyWindow -Store $Store -StartView Resultant -OnShown {
                param($Ui)
                $Ui.resultantView.IsVisible | Should -BeTrue
                $Ui.resultantButton.Classes | Should -Contain 'active'
                $Ui.resultEmptyTextBlock.IsVisible | Should -BeTrue
                $Ui.identitySearchTextBox.Text = 'Bob'
                Invoke-Click $Ui.identitySearchButton
                $Ui.identityStatusTextBlock.Text | Should -Be '1 users and groups found.'
                $Ui.identitiesList.SelectedIndex = 0
                $Ui.resultTitleTextBlock.Text | Should -Be 'Bob Durand (User)'
                $Ui.appliedNameTextBlock.Text | Should -Be 'PSO - Tier 1 Admins'
                $Ui.appliedSourceTextBlock.Text | Should -Be 'Computed from the password settings objects and the groups of the account.'
                $Ui.differsTextBlock.IsVisible | Should -BeFalse
                $Rows = @($Ui.candidatesList.ItemsSource)
                $Rows.Name | Should -Be @('PSO - VPN Users', 'PSO - Tier 1 Admins', 'PSO - IT Staff', 'Default domain password policy')
                $Rows.Status | Should -Be @('Ignored', 'Applies', 'Not applied', 'Not applied')
                $Rows[2].Through | Should -Be 'Through Tier 1 Admins > IT Staff'
                $Ui.groupRuleTextBlock.Text | Should -BeLike '*global security groups only*'
                # A change of the PSOs shows there at once.
                Invoke-Click $Ui.policiesButton
                $Ui.policiesList.SelectedItem = @($Ui.policiesList.ItemsSource) | Where-Object Name -EQ 'PSO - IT Staff'
                Invoke-Click $Ui.editPolicyButton
                $Ui.Editor.Ui.Controls.precedenceUpDown.Value = [decimal]1
                Invoke-Click $Ui.Editor.Ui.Controls.okButton
                $Ui.appliedNameTextBlock.Text | Should -Be 'PSO - IT Staff'
            }
        }

        It 'Speaks French' {
            try {
                Start-PSGPOPasswordPolicyWindow -Store $Store -Language 'fr-FR' -OnShown {
                    param($Ui)
                    $Ui.subtitleTextBlock.Text | Should -Be 'Stratégies de mot de passe affinées de corp.contoso.com'
                    $Ui.domainPolicyTextBlock.Text | Should -Be '7 caractères, historique 24, expire après 42 jours, pas de verrouillage'
                    Invoke-Click $Ui.newPolicyButton
                    $Ui.Editor.Ui.Window.Title | Should -Be 'Créer des paramètres de mot de passe'
                    $Ui.Editor.Ui.Controls.enforceLengthCheckBox.Content | Should -Be 'Appliquer la longueur minimale du mot de passe'
                }
            } finally { $null = Set-PSGPOLanguage -Language 'en-US' }
        }

        It 'Says why the domain was not read, and opens anyway' {
            Start-PSGPOPasswordPolicyWindow -Store $null -StoreError 'dc.contoso.com cannot be reached' -OnShown {
                param($Ui)
                $Ui.errorBanner.IsVisible | Should -BeTrue
                $Ui.errorBannerTextBlock.Text | Should -Be 'The domain could not be read. dc.contoso.com cannot be reached'
                $Ui.newPolicyButton.IsEnabled | Should -BeFalse
                $Ui.identitySearchButton.IsEnabled | Should -BeFalse
            }
        }

        It 'Opens on the sample policies when no domain is discovered' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Linux' } }
            Mock Start-PSGPOPasswordPolicyWindow { }
            Show-PSOManagerAvalonia -Language en-US -View Resultant
            Should -Invoke Start-PSGPOPasswordPolicyWindow -Times 1 -Exactly -ParameterFilter { $Store.IsDemonstration -and $Store.Policies.Count -eq 7 -and $StartView -eq 'Resultant' -and -not $StoreError }
        }
    }
    Describe 'Launcher window' -Skip:$AvaloniaMissing {
        It 'Shows a tile for each console, and a click opens it in a process of its own, in the language of the launcher' {
            $script:LauncherProcess = [pscustomobject]@{ HasExited = $false; ExitCode = 0 }
            Mock Start-PSGPOToolProcess { [pscustomobject]@{ Process = $script:LauncherProcess; ProblemPath = $null } }
            Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -OnShown {
                param($Ui)
                $Ui.Window.Icon | Should -Not -BeNullOrEmpty
                @($Ui.Tiles.Tag.Command) | Should -Be @('Show-GPOManagerAvalonia', 'Show-PSOManagerAvalonia', 'Show-WmiFilterCreatorAvalonia', 'Show-PolicyAnalyzerAvalonia', 'Show-AuditLogAvalonia')
                $Ui.Tiles[1].Content.Children[1].Text | Should -Be 'Password Settings'
                Invoke-Click $Ui.Tiles[1]
                $Ui.Tiles[1].IsEnabled | Should -BeFalse -Because 'its console runs'
                $Ui.Tiles[0].IsEnabled | Should -BeTrue -Because 'the other consoles open beside it'
                Invoke-UiLoop -TimeoutMilliseconds 700
                $Ui.Tiles[1].IsEnabled | Should -BeFalse -Because 'its process still runs'
                $script:LauncherProcess.HasExited = $true
                Invoke-UiLoop -Until { $Ui.Tiles[1].IsEnabled }
                $Ui.Tiles[1].IsEnabled | Should -BeTrue -Because 'the tile comes back once the console is closed'
                $Ui.statusTextBlock.IsVisible | Should -BeFalse
            }
            Should -Invoke Start-PSGPOToolProcess -Times 1 -Exactly -ParameterFilter { $Command -eq 'Show-PSOManagerAvalonia' -and $Language -eq 'en-US' }
        }

        It 'Starts a console in a PowerShell process of its own, which says why it did not open' {
            # A command without -Language: the console process stops on its error, and writes it.
            $Started = Start-PSGPOToolProcess -Command 'Get-Date' -Language 'en-US'
            try {
                $Started.Process.StartInfo.ArgumentList | Should -Contain '-NoProfile'
                ($Started.Process.StartInfo.ArgumentList | Select-Object -Last 1) | Should -BeLike "Import-Module -Name '*HGPM.psd1'; & (Get-Module -Name 'HGPM') { Invoke-PSGPOLauncherTool @args } 'Get-Date' 'en-US' '*'"
                $Started.Process.WaitForExit(120000) | Should -BeTrue
                $Started.Process.ExitCode | Should -Be 1
                Read-PSGPOToolProblem -Path $Started.ProblemPath | Should -BeLike "*parameter*'Language'*"
                Test-Path -LiteralPath $Started.ProblemPath | Should -BeFalse -Because 'the launcher reads it once'
            } finally {
                if (-not $Started.Process.HasExited) { $Started.Process.Kill() }
            }
        }

        It 'Gives its theme to every window: those open, and those opened after' {
            try {
                $Seen = @{}
                Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -OnShown {
                    param($Ui)
                    $Before = $Ui.Window.RequestedThemeVariant
                    Invoke-Click $Ui.themeToggleButton
                    $Ui.Window.RequestedThemeVariant | Should -Not -Be $Before
                    $Seen.Theme = $Ui.Window.RequestedThemeVariant
                    $Seen.Text = $Ui.themeToggleText.Text
                    # Kept for the consoles the launcher starts in their own processes.
                    (Get-PSGPOUserSetting).Theme | Should -Be "$($Seen.Theme)"
                }
                Start-PSGPOManagerWindow -OnShown {
                    param($Ui)
                    $Ui.Window.RequestedThemeVariant | Should -Be $Seen.Theme -Because 'a console opened after starts on the theme chosen'
                    $Ui.themeToggleText.Text | Should -Be $Seen.Text
                    # A window open changes with the theme chosen in another one.
                    $Other = [Avalonia.Controls.Window]::new()
                    Register-PSGPOThemeWindow -Window $Other
                    $Other.RequestedThemeVariant | Should -Be $Seen.Theme
                    Invoke-Click $Ui.themeToggleButton
                    $Other.RequestedThemeVariant | Should -Be $Ui.Window.RequestedThemeVariant
                    $Other.RequestedThemeVariant | Should -Not -Be $Seen.Theme
                    $Other.Close()
                    $Seen.Theme = $Ui.Window.RequestedThemeVariant
                }
                # The windows the consoles open too: the ADMX files to load.
                $null = Show-PSGPOAdmxWindow -OnShown {
                    param($Ui)
                    $Ui.Window.RequestedThemeVariant | Should -Be $Seen.Theme
                }
            } finally {
                $script:PSGPOThemeDark = $null
                Set-PSGPOUserSetting -Values @{ Theme = $null } -Confirm:$false
            }
        }

        It 'Follows the theme chosen in the console of another process' {
            try {
                Set-PSGPOUserSetting -Values @{ Theme = 'Light' } -Confirm:$false
                $script:PSGPOThemeDark = $null
                Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -OnShown {
                    param($Ui)
                    "$($Ui.Window.RequestedThemeVariant)" | Should -Be 'Light' -Because 'it starts on the theme of the settings'
                    # Another process writes its choice in the settings of the user.
                    Start-Sleep -Milliseconds 50
                    $Settings = Get-PSGPOUserSetting
                    $Settings.Theme = 'Dark'
                    $Settings | ConvertTo-Json | Set-Content -LiteralPath (Get-PSGPOUserSettingPath) -Encoding utf8
                    Invoke-UiLoop -Until { "$($Ui.Window.RequestedThemeVariant)" -eq 'Dark' } -TimeoutMilliseconds 4000
                    "$($Ui.Window.RequestedThemeVariant)" | Should -Be 'Dark'
                    $Ui.themeToggleText.Text | Should -Be 'Light mode'
                }
            } finally {
                $script:PSGPOThemeDark = $null
                Set-PSGPOUserSetting -Values @{ Theme = $null } -Confirm:$false
            }
        }

        It 'Says why a console did not open' {
            $script:LauncherProblem = Join-Path $TestDrive "problem-$([guid]::NewGuid()).txt"
            Set-Content -LiteralPath $script:LauncherProblem -Value 'no display'
            Mock Start-PSGPOToolProcess { [pscustomobject]@{ Process = [pscustomobject]@{ HasExited = $true; ExitCode = 1 }; ProblemPath = $script:LauncherProblem } }
            Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -OnShown {
                param($Ui)
                Invoke-Click $Ui.Tiles[1]
                Invoke-UiLoop -Until { $Ui.statusTextBlock.IsVisible }
                $Ui.statusTextBlock.IsVisible | Should -BeTrue
                $Ui.statusTextBlock.Text | Should -Be 'Show-PSOManagerAvalonia did not open: no display'
                $Ui.Tiles[1].IsEnabled | Should -BeTrue
            }
            Test-Path -LiteralPath $script:LauncherProblem | Should -BeFalse
        }

        It 'Stops the loop of its own window only: another window opened from its loop keeps running' {
            Initialize-PSGPOAvaloniaRuntime
            $A = [Avalonia.Controls.Window]::new()
            $B = [Avalonia.Controls.Window]::new()
            $State = @{ OpenWhenItsLoopStopped = $null; Guarded = $false }
            # The handlers find $A, $B and $State here (no closure): this block runs both loops.
            # B is closed half a second after it is shown; never a hang: after 10 seconds both
            # windows are closed, and the test fails.
            $Later = [Avalonia.Threading.DispatcherTimer]::new()
            $Later.Interval = [TimeSpan]::FromMilliseconds(500)
            $Later.Add_Tick({ $Later.Stop(); $B.Close() })
            $Guard = [Avalonia.Threading.DispatcherTimer]::new()
            $Guard.Interval = [TimeSpan]::FromSeconds(10)
            $Guard.Add_Tick({ $Guard.Stop(); $State.Guarded = $true; $B.Close(); $A.Close() })
            try {
                $A.Show()
                $Guard.Start()
                # B runs its loop inside the loop of A, as the consoles ran inside the launcher; A
                # (the launcher) is closed meanwhile.
                [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                        $B.Show()
                        $Later.Start()
                        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { $A.Close() })
                        Invoke-PSGPOWindowLoop -Window $B
                        $State.OpenWhenItsLoopStopped = $B.IsVisible
                        if ($B.IsVisible) { $B.Close() }
                    })
                Invoke-PSGPOWindowLoop -Window $A
            } finally {
                $Later.Stop()
                $Guard.Stop()
                if ($B.IsVisible) { $B.Close() }
                if ($A.IsVisible) { $A.Close() }
            }
            $State.Guarded | Should -BeFalse -Because 'both loops stopped once their windows were closed'
            $State.OpenWhenItsLoopStopped | Should -BeFalse -Because 'closing A stopped the loop of A only: B ran until it was closed'
        }

        It 'Says why a console was not started' {
            Mock Start-PSGPOToolProcess { throw 'pwsh is not found: /opt/pwsh' }
            Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -OnShown {
                param($Ui)
                Invoke-Click $Ui.Tiles[2]
                $Ui.statusTextBlock.IsVisible | Should -BeTrue
                $Ui.statusTextBlock.Text | Should -Be 'Show-WmiFilterCreatorAvalonia did not open: pwsh is not found: /opt/pwsh'
                $Ui.Tiles[2].IsEnabled | Should -BeTrue
            }
        }

        It 'Speaks French' {
            try {
                $null = Set-PSGPOLanguage -Language 'fr-FR'
                Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -Language 'fr-FR' -OnShown {
                    param($Ui)
                    $Ui.Tiles[0].Content.Children[1].Text | Should -Be 'Gestion de stratégie de groupe'
                    $Ui.themeToggleText.Text | Should -BeIn 'Mode sombre', 'Mode clair'
                }
            } finally { $null = Set-PSGPOLanguage -Language 'en-US' }
        }

        It 'Changes its language in its list: its texts at once, the consoles opened after, and the next start' {
            $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
            try {
                $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
                Mock Start-PSGPOToolProcess { [pscustomobject]@{ Process = [pscustomobject]@{ HasExited = $true; ExitCode = 0 }; ProblemPath = $null } }
                Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -Language 'en-US' -OnShown {
                    param($Ui)
                    @($Ui.languageComboBox.Items.Tag) | Should -Be @('en-US', 'fr-FR')
                    $Ui.languageComboBox.SelectedItem.Tag | Should -Be 'en-US'
                    $Ui.languageComboBox.Items[1].Content | Should -Be ('Fran' + [char]0xE7 + 'ais')
                    $Ui.languageComboBox.SelectedIndex = 1
                    $Ui.subtitleTextBlock.Text | Should -Be 'Choisissez une console'
                    $Ui.themeToggleText.Text | Should -BeIn 'Mode sombre', 'Mode clair'
                    $Ui.toolsPanel.Children[0].Content.Children[1].Text | Should -Be ('Gestion de strat' + [char]0xE9 + 'gie de groupe')
                    Invoke-Click $Ui.toolsPanel.Children[1]
                    Invoke-UiLoop -Until { $Ui.toolsPanel.Children[1].IsEnabled }
                }
                Should -Invoke Start-PSGPOToolProcess -Times 1 -Exactly -ParameterFilter { $Command -eq 'Show-PSOManagerAvalonia' -and $Language -eq 'fr-FR' }
                (Get-PSGPOUserSetting).Language | Should -Be 'fr-FR'
                Mock Start-PSGPOLauncherWindow { }
                Start-HGPM
                Should -Invoke Start-PSGPOLauncherWindow -Times 1 -Exactly -ParameterFilter { $Language -eq 'fr-FR' }
                Start-HGPM -Language en-US
                Should -Invoke Start-PSGPOLauncherWindow -Times 1 -Exactly -ParameterFilter { $Language -eq 'en-US' }
            } finally {
                $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore
                $null = Set-PSGPOLanguage -Language 'en-US'
            }
        }
    }

    Describe 'Audit log window' -Skip:$AvaloniaMissing {
        BeforeAll {
            # A log of two domains: changes of now, of ten days ago and of a year ago.
            $Log = Join-Path $TestDrive 'AuditLog'
            $null = New-Item -ItemType Directory -Path $Log -Force
            function New-TestEntry {
                param([datetime]$Time, [string]$Domain, [string]$Account, [string]$Action, [string]$Target, [string]$GpoName, [hashtable]$Details = @{})
                [ordered]@{
                    Format = 'PSGPOTools.Audit/1'; Time = $Time.ToUniversalTime().ToString('o'); Domain = $Domain; Server = "dc1.$Domain"
                    Account = $Account; Computer = 'ADMIN-PC'; Action = $Action; Target = $Target
                    GpoId = if ($GpoName) { '11111111-2222-3333-4444-555555555555' }; GpoName = $GpoName; Details = $Details
                } | ConvertTo-Json -Compress -Depth 5
            }
            $Now = [datetime]::UtcNow
            Set-Content -LiteralPath (Join-Path $Log 'contoso.com-2026-10.jsonl') -Encoding utf8 -Value @(
                (New-TestEntry -Time $Now.AddDays(-10) -Domain 'contoso.com' -Account 'CONTOSO\admin1' -Action 'NewGpo' -Target 'CN=Policies' -GpoName 'C - Servers - Baseline')
                (New-TestEntry -Time $Now.AddMinutes(-5) -Domain 'contoso.com' -Account 'CONTOSO\tiers1' -Action 'SaveGpoFile' -Target 'CN=Policies' -GpoName 'C - Servers - Baseline' -Details @{ Path = 'Machine\Registry.pol'; Version = 4 })
                (New-TestEntry -Time $Now.AddDays(-400) -Domain 'contoso.com' -Account 'CONTOSO\admin1' -Action 'SaveConfiguration' -Target 'Configuration')
            )
            Set-Content -LiteralPath (Join-Path $Log 'fabrikam.com-2026-10.jsonl') -Encoding utf8 -Value @(
                (New-TestEntry -Time $Now.AddHours(-2) -Domain 'fabrikam.com' -Account 'FABRIKAM\admin' -Action 'NewLink' -Target 'OU=Servers,DC=fabrikam,DC=com' -GpoName 'F - Servers')
            )
        }

        It 'Shows the changes, newest first, filtered by period, domain, action and a search, their details, and exports them' {
            Start-PSGPOAuditLogWindow -Path $Log -OnShown {
                param($Ui)
                $Ui.Window.Title | Should -Be 'Audit Log'
                $Ui.auditFolderTextBox.Text | Should -Be $Log
                $Ui.auditPeriodComboBox.SelectedIndex | Should -Be 2 -Because 'the last 30 days at first'
                @($Ui.auditGrid.ItemsSource).Count | Should -Be 3
                @($Ui.auditGrid.ItemsSource)[0].Action | Should -Be 'Settings of a GPO saved' -Because 'the newest first, the action by its name'
                @($Ui.auditGrid.ItemsSource)[0].Object | Should -Be 'C - Servers - Baseline'
                $Ui.auditSummaryTextBlock.Text | Should -Be '3 change(s) shown, 4 in the log'
                @($Ui.auditDomainComboBox.ItemsSource) | Should -Be @('All the domains', 'contoso.com', 'fabrikam.com')
                @($Ui.auditActionComboBox.ItemsSource) | Should -Be @('All the actions', 'Configuration saved', 'GPO created', 'Link created', 'Settings of a GPO saved')

                $Ui.auditPeriodComboBox.SelectedIndex = 3
                @($Ui.auditGrid.ItemsSource).Count | Should -Be 4
                $Ui.auditPeriodComboBox.SelectedIndex = 0
                @($Ui.auditGrid.ItemsSource).Count | Should -Be 2
                $Ui.auditPeriodComboBox.SelectedIndex = 3
                $Ui.auditDomainComboBox.SelectedIndex = 2
                @($Ui.auditGrid.ItemsSource).Account | Should -Be @('FABRIKAM\admin')
                $Ui.auditDomainComboBox.SelectedIndex = 0
                $Ui.auditActionComboBox.SelectedIndex = 2
                @($Ui.auditGrid.ItemsSource).Account | Should -Be @('CONTOSO\admin1')
                $Ui.auditActionComboBox.SelectedIndex = 0
                $Ui.auditSearchTextBox.Text = 'registry.pol tiers1'
                @($Ui.auditGrid.ItemsSource).Count | Should -Be 1 -Because 'the search reads the details too, every word'

                # The rows laid out before one is selected.
                Invoke-UiLoop -TimeoutMilliseconds 300
                $Ui.auditGrid.SelectedIndex = 0
                $Ui.auditDetailsBorder.IsVisible | Should -BeTrue
                $Ui.auditDetailsTitleTextBlock.Text | Should -Be 'Settings of a GPO saved - C - Servers - Baseline'
                $Ui.auditDetailsWhoTextBlock.Text | Should -BeLike '* by CONTOSO\tiers1 from ADMIN-PC, on dc1.contoso.com (contoso.com)'
                $Ui.auditDetailsTargetTextBlock.Text | Should -BeLike 'GPO: C - Servers - Baseline {11111111-2222-3333-4444-555555555555}*Action: SaveGpoFile*Check: Not chained. Written before HGPM 0.1.15*'
                $Ui.auditDetailsTextBlock.Text | Should -Be "Path: Machine\Registry.pol$([Environment]::NewLine)Version: 4"

                $Csv = Join-Path $TestDrive 'shown.csv'
                & $Ui.Export -File $Csv
                @(Import-Csv -LiteralPath $Csv).Action | Should -Be @('SaveGpoFile')
                $Ui.auditStatusTextBlock.Text | Should -Be "1 change(s) exported to $Csv."

                $Ui.auditSearchTextBox.Text = 'nothing like this'
                $Ui.auditGrid.IsVisible | Should -BeFalse
                $Ui.auditEmptyTextBlock.Text | Should -Be 'No change matches the filters.'
                $Ui.auditExportButton.IsEnabled | Should -BeFalse
            }
        }

        It 'Says when the folder holds no log yet, and speaks French' {
            try {
                Start-PSGPOAuditLogWindow -Path (Join-Path $TestDrive 'none') -Language 'fr-FR' -OnShown {
                    param($Ui)
                    $Ui.Window.Title | Should -Be "Journal d'audit"
                    $Ui.auditStatusTextBlock.Text | Should -BeLike "Pas de journal d'audit dans *"
                    $Ui.auditEmptyTextBlock.Text | Should -Be "Aucune modification dans ce journal d'audit pour l'instant."
                }
            } finally { $null = Set-PSGPOLanguage -Language 'en-US' }
        }

        It 'Reads the folder of the configuration of the domain it is given' {
            $Directory = Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json')
            Mock Get-PSGPOAuditPath { $Log }
            Start-PSGPOAuditLogWindow -Directory $Directory -OnShown {
                param($Ui)
                $Ui.auditFolderTextBox.Text | Should -Be $Log
                $Ui.subtitleTextBlock.Text | Should -BeLike "What the consoles and the commands changed in the domain - $($Directory.DomainName) - Connected as *" -Because 'who reads the log'
                @($Ui.auditGrid.ItemsSource).Count | Should -Be 3
            }
        }
    }

    Describe 'WMI Filter Creator window' -Skip:$AvaloniaMissing {
        BeforeAll {
            $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        }
        AfterEach { $null = Set-PSGPOLanguage -Language 'en-US' }

        It 'Adds a ready-made query with its parameters, checks a query typed, and exports the filter to .mof' {
            $File = Join-Path $TestDrive 'creator.mof'
            Start-PSGPOWmiFilterCreatorWindow -OnShown {
                param($Ui)
                $Ui.Window.Icon | Should -Not -BeNullOrEmpty
                @($Ui.templatesList.ItemsSource).Count | Should -BeGreaterThan 60
                $Ui.exportButton.IsEnabled | Should -BeFalse
                $Ui.filterStatusTextBlock.Text | Should -Be 'Give the filter a name. Add at least one query.'

                $Ui.templateSearchTextBox.Text = 'minimum memory'
                @($Ui.templatesList.ItemsSource).Count | Should -Be 1
                $Ui.templatesList.SelectedIndex = 0
                $Ui.templateParametersPanel.Children[1].Text = 'lots'
                $Ui.addTemplateButton.IsEnabled | Should -BeFalse
                $Ui.templateErrorTextBlock.Text | Should -Be 'Memory (GB) is a number: lots is not one.'
                $Ui.templateParametersPanel.Children[1].Text = '16'
                $Ui.templateQueryTextBlock.Text | Should -Be 'SELECT * FROM Win32_ComputerSystem WHERE TotalPhysicalMemory >= 16000000000'
                Invoke-Click $Ui.addTemplateButton
                $Ui.Rows.Count | Should -Be 1
                $Ui.filterNameTextBox.Text | Should -Be 'Minimum memory' -Because 'the first query names an unnamed filter'

                # A query typed, checked as it is typed.
                Invoke-Click $Ui.newQueryButton
                $Ui.queryTextBox.Text = 'SELECT * FROM Win32_Service WHERE Name ='
                $Ui.Rows[1].Status | Should -Be 'Not valid: A value expected after =, not the end of the query.'
                $Ui.exportButton.IsEnabled | Should -BeFalse
                $Ui.filterStatusTextBlock.Text | Should -Be '1 query(ies) not valid: correct or remove them.'
                $Ui.queryTextBox.Text = "SELECT * FROM Win32_Service WHERE Name = 'Spooler'"
                $Ui.Rows[1].Status | Should -Be 'Valid WQL'
                $Ui.exportButton.IsEnabled | Should -BeTrue

                $Ui.exportPathTextBox.Text = $File
                Invoke-Click $Ui.exportButton
                $Ui.resultTextBlock.Text | Should -BeLike "WMI filter 'Minimum memory' exported to *creator.mof*"
                Invoke-Click $Ui.exportButton
                $Ui.exportButtonTextBlock.Text | Should -Be 'Replace' -Because 'a file there is replaced once confirmed'
                Invoke-Click $Ui.exportButton
                $Ui.exportButtonTextBlock.Text | Should -Be 'Export .mof'
            }
            $Read = ConvertFrom-PSGPOWmiFilterMof -Bytes ([System.IO.File]::ReadAllBytes($File))
            $Read.Name | Should -Be 'Minimum memory'
            @($Read.Queries.Query) | Should -Be @('SELECT * FROM Win32_ComputerSystem WHERE TotalPhysicalMemory >= 16000000000', "SELECT * FROM Win32_Service WHERE Name = 'Spooler'")
        }

        It 'Builds a query from a class, its properties and conditions' {
            Start-PSGPOWmiFilterCreatorWindow -OnShown {
                param($Ui)
                $Ui.builderClassComboBox.SelectedIndex = [array]::IndexOf(@((Get-PSGPOWmiCatalog).Classes.Name), 'Win32_ComputerSystem')
                $Ui.builderPropertyComboBox.SelectedItem = 'PCSystemType'
                $Ui.builderKnownValueComboBox.IsVisible | Should -BeTrue
                $Ui.builderKnownValueComboBox.SelectedIndex = 1
                $Ui.builderValueTextBox.Text | Should -Be '2'
                Invoke-Click $Ui.builderAddConditionButton
                $Ui.builderJoinComboBox.SelectedItem = 'OR'
                $Ui.builderPropertyComboBox.SelectedItem = 'Model'
                $Ui.builderOperatorComboBox.SelectedItem = 'LIKE'
                $Ui.builderValueTextBox.Text = '%Surface%'
                Invoke-Click $Ui.builderAddConditionButton
                $Ui.builderQueryTextBlock.Text | Should -Be "SELECT * FROM Win32_ComputerSystem WHERE PCSystemType = 2 OR Model LIKE '%Surface%'"
                $Ui.builderPropertyComboBox.SelectedItem = 'TotalPhysicalMemory'
                $Ui.builderValueTextBox.Text = 'much'
                Invoke-Click $Ui.builderAddConditionButton
                $Ui.builderErrorTextBlock.Text | Should -Be 'TotalPhysicalMemory is a number: much is not one.'
                Invoke-Click $Ui.builderAddQueryButton
                $Ui.Rows[0].Query | Should -Be "SELECT * FROM Win32_ComputerSystem WHERE PCSystemType = 2 OR Model LIKE '%Surface%'"
                $Ui.Rows[0].Namespace | Should -Be 'root\CIMv2'
            }
        }

        It 'Opens a .mof file, creates the filter in the domain, and clears it once confirmed' {
            $File = Join-Path $TestDrive 'open.mof'
            $null = [pscustomobject]@{ Name = 'Opened'; Description = 'From a file'; Queries = @(Get-PSGPOWmiQueryTemplate -Id Laptops) } | Export-PSGPOWmiFilter -Path $File -Domain 'contoso.com'
            $Directory = Import-PSGPODirectory -Path $SamplePath
            Start-PSGPOWmiFilterCreatorWindow -Directory $Directory -OnShown {
                param($Ui)
                Invoke-Click $Ui.openFilterButton
                $Ui.openPanel.IsVisible | Should -BeTrue
                $Ui.openPathTextBox.Text = Join-Path $TestDrive 'none.mof'
                Invoke-Click $Ui.openConfirmButton
                $Ui.openErrorTextBlock.Text | Should -BeLike '*none.mof cannot be opened:*'
                $Ui.openPathTextBox.Text = $File
                Invoke-Click $Ui.openConfirmButton
                $Ui.openPanel.IsVisible | Should -BeFalse
                $Ui.filterNameTextBox.Text | Should -Be 'Opened'
                $Ui.filterDescriptionTextBox.Text | Should -Be 'From a file'
                $Ui.Rows.Count | Should -Be 1

                $Ui.domainHintTextBlock.Text | Should -BeLike "Creates the filter in $($Directory.DomainName)*"
                Invoke-Click $Ui.createInDomainButton
                $Ui.resultTextBlock.Text | Should -BeLike "WMI filter 'Opened' created in *"
                Invoke-Click $Ui.createInDomainButton
                $Ui.resultTextBlock.Text | Should -BeLike "The WMI filter is not created: A WMI filter named 'Opened' already exists*"

                Invoke-Click $Ui.newFilterButton
                $Ui.Rows.Count | Should -Be 1 -Because 'New asks to be clicked again'
                $Ui.resultTextBlock.Text | Should -Be 'Click New again to clear the filter: its queries are not kept.'
                Invoke-Click $Ui.newFilterButton
                $Ui.Rows.Count | Should -Be 0
                $Ui.filterNameTextBox.Text | Should -Be ''
            }
            $Directory.FindWmiFilter('Opened').GetQueryText() | Should -Be 'root\CIMv2: SELECT * FROM Win32_ComputerSystem WHERE PCSystemType = 2'
        }

        It 'Tests the filter on this computer without blocking the window' -Skip:(-not $IsWindows) {
            Start-PSGPOWmiFilterCreatorWindow -Filter ([pscustomobject]@{ Name = 'Test'; Queries = @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_OperatingSystem' }) }) -OnShown {
                param($Ui)
                $Ui.testButton.IsEnabled | Should -BeTrue
                Invoke-Click $Ui.testButton
                $Ui.testButton.IsEnabled | Should -BeFalse -Because 'the test runs'
                Invoke-UiLoop -Until { $Ui.testButton.IsEnabled } -TimeoutMilliseconds 30000
                $Ui.testSummaryTextBlock.Text | Should -Be "The filter is True on $([Environment]::MachineName): this computer applies the GPOs linked to it."
                @($Ui.testResultsList.ItemsSource).ResultText | Should -Be 'True: the query returns something'
            }
        }

        It 'Speaks French, the ready-made queries included' {
            $null = Set-PSGPOLanguage -Language 'fr-FR'
            Start-PSGPOWmiFilterCreatorWindow -Language 'fr-FR' -OnShown {
                param($Ui)
                $Ui.Window.Title | Should -Be 'Créateur de filtres WMI'
                @($Ui.templatesList.ItemsSource).Name | Should -Contain 'Ordinateurs portables'
                $Ui.templateCategoryComboBox.SelectedItem | Should -Be 'Toutes les catégories'
                $Ui.filterStatusTextBlock.Text | Should -Be 'Donnez un nom au filtre. Ajoutez au moins une requête.'
            }
        }
    }
}
