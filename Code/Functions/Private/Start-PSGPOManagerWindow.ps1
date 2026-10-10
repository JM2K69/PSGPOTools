<#
    Private implementation of Show-GPOManagerAvalonia: builds the window, wires its
    handlers and runs the Avalonia loop until the window closes.

    -OnShown exists for the GUI tests: the scriptblock receives a hashtable of the named
    controls, runs inside the loop once the window is shown, and the window is then
    closed. Event handlers keep resolving the local variables below because this
    function scope stays alive for the whole loop.
#>

function Start-PSGPOManagerWindow {
    [CmdletBinding()]
    Param(
        # Domain of the Group Policy Management view; without it the window opens on the ADMX policies.
        [GPOToolsDirectory]$Directory,

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime

    $xaml = Get-PSGPOManagerWindowXaml

    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse($xaml)

    $treeView = Get-PSGPOAvaloniaControl $window 'treeView'
    $themeToggleButton = Get-PSGPOAvaloniaControl $window 'themeToggleButton'
    $breadcrumbTextBlock = Get-PSGPOAvaloniaControl $window 'breadcrumbTextBlock'
    $searchTextBox = Get-PSGPOAvaloniaControl $window 'searchTextBox'
    $searchButton = Get-PSGPOAvaloniaControl $window 'searchButton'
    $displayNameTextBox = Get-PSGPOAvaloniaControl $window 'displayNameTextBox'
    $descriptionTextBox = Get-PSGPOAvaloniaControl $window 'descriptionTextBox'
    $scopeTextBox = Get-PSGPOAvaloniaControl $window 'scopeTextBox'
    $registryPathTextBox = Get-PSGPOAvaloniaControl $window 'registryPathTextBox'
    $registryKeyTextBox = Get-PSGPOAvaloniaControl $window 'registryKeyTextBox'
    $registryValuesList = Get-PSGPOAvaloniaControl $window 'registryValuesList'
    $settingTitleTextBlock = Get-PSGPOAvaloniaControl $window 'settingTitleTextBlock'
    $previewEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'previewEmptyTextBlock'
    $copyNameMenuItem = Get-PSGPOAvaloniaControl $window 'copyNameMenuItem'
    $copyRegistryMenuItem = Get-PSGPOAvaloniaControl $window 'copyRegistryMenuItem'
    $copyCommandMenuItem = Get-PSGPOAvaloniaControl $window 'copyCommandMenuItem'
    $notConfiguredRadio = Get-PSGPOAvaloniaControl $window 'notConfiguredRadio'
    $enabledRadio = Get-PSGPOAvaloniaControl $window 'enabledRadio'
    $disabledRadio = Get-PSGPOAvaloniaControl $window 'disabledRadio'
    $optionsHost = Get-PSGPOAvaloniaControl $window 'optionsHost'
    $settingErrorTextBlock = Get-PSGPOAvaloniaControl $window 'settingErrorTextBlock'
    $registryPreviewList = Get-PSGPOAvaloniaControl $window 'registryPreviewList'

    $subtitleTextBlock = Get-PSGPOAvaloniaControl $window 'subtitleTextBlock'
    $managementButton = Get-PSGPOAvaloniaControl $window 'managementButton'
    $browseAdmxButton = Get-PSGPOAvaloniaControl $window 'browseAdmxButton'
    $searchPanel = Get-PSGPOAvaloniaControl $window 'searchPanel'
    $managementView = Get-PSGPOAvaloniaControl $window 'managementView'
    $editorView = Get-PSGPOAvaloniaControl $window 'editorView'
    $editingBanner = Get-PSGPOAvaloniaControl $window 'editingBanner'
    $editingGpoTextBlock = Get-PSGPOAvaloniaControl $window 'editingGpoTextBlock'
    $domainTreeView = Get-PSGPOAvaloniaControl $window 'domainTreeView'
    $directoryEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'directoryEmptyTextBlock'
    $directoryBreadcrumbTextBlock = Get-PSGPOAvaloniaControl $window 'directoryBreadcrumbTextBlock'
    $directoryTitleTextBlock = Get-PSGPOAvaloniaControl $window 'directoryTitleTextBlock'
    $directoryPropertiesList = Get-PSGPOAvaloniaControl $window 'directoryPropertiesList'
    $linksHeaderTextBlock = Get-PSGPOAvaloniaControl $window 'linksHeaderTextBlock'
    $linksList = Get-PSGPOAvaloniaControl $window 'linksList'
    $createLinkedGpoMenuItem = Get-PSGPOAvaloniaControl $window 'createLinkedGpoMenuItem'
    $newGpoMenuItem = Get-PSGPOAvaloniaControl $window 'newGpoMenuItem'
    $editGpoMenuItem = Get-PSGPOAvaloniaControl $window 'editGpoMenuItem'
    $editGpoButton = Get-PSGPOAvaloniaControl $window 'editGpoButton'
    $newGpoPanel = Get-PSGPOAvaloniaControl $window 'newGpoPanel'
    $newGpoTitleTextBlock = Get-PSGPOAvaloniaControl $window 'newGpoTitleTextBlock'
    $newGpoNameTextBox = Get-PSGPOAvaloniaControl $window 'newGpoNameTextBox'
    $newGpoErrorTextBlock = Get-PSGPOAvaloniaControl $window 'newGpoErrorTextBlock'
    $newGpoCreateButton = Get-PSGPOAvaloniaControl $window 'newGpoCreateButton'
    $newGpoCancelButton = Get-PSGPOAvaloniaControl $window 'newGpoCancelButton'

    # Options form of the selected policy (New-PSGPOPolicyEditor), the policy it edits and the
    # GPO opened from the Group Policy Management view ($null: browsing the ADMX policies).
    $editing = @{ Policy = $null; Editor = $null; Gpo = $null }

    # Registry values the current setting writes (what Registry.pol will contain).
    function Update-RegistryPreview {
        $policy = $editing.Policy
        $state = if ($enabledRadio.IsChecked) { 'Enabled' } elseif ($disabledRadio.IsChecked) { 'Disabled' } else { 'NotConfigured' }
        # Like the Group Policy editor, options can only be edited when the policy is enabled.
        $optionsHost.IsEnabled = $state -eq 'Enabled'
        $settingErrorTextBlock.Text = ''
        $rows = @()
        if ($policy) {
            try {
                $changes = @(Get-PSGPOPolicyRegistryChange -Policy $policy -State $state -Value (& $editing.Editor.GetValue))
                $rows = @(foreach ($change in $changes) { ConvertTo-PSGPOPreviewRow -Change $change -Scope $policy.Scope })
            } catch {
                $settingErrorTextBlock.Text = $_.Exception.Message
            }
        }
        $registryPreviewList.ItemsSource = $rows
        $previewEmptyTextBlock.IsVisible = $rows.Count -eq 0
        $previewEmptyTextBlock.Text = if (-not $policy) { 'Select a policy in the tree.' }
            elseif ($settingErrorTextBlock.Text) { 'Fix the options above to see the registry values.' }
            else { 'Not configured: nothing is written to the registry.' }
    }
    foreach ($radio in $notConfiguredRadio, $enabledRadio, $disabledRadio) {
        $radio.add_IsCheckedChanged({ Update-RegistryPreview })
    }

    # Theme management: Avalonia FluentTheme + our ThemeDictionaries swap automatically
    # when RequestedThemeVariant changes, no manual brush-by-brush update needed.
    # The window starts on the OS theme, so the toggle starts from the actual variant.
    $platformSettings = [Avalonia.Application]::Current.PlatformSettings
    $script:isDarkTheme = $null -ne $platformSettings -and
        $platformSettings.GetColorValues().ThemeVariant -eq [Avalonia.Platform.PlatformThemeVariant]::Dark
    $updateThemeButton = { $themeToggleButton.Content = if ($script:isDarkTheme) { '☀️ Light mode' } else { '🌙 Dark mode' } }
    & $updateThemeButton
    $themeToggleButton.Add_Click({
        $script:isDarkTheme = -not $script:isDarkTheme
        $window.RequestedThemeVariant = if ($script:isDarkTheme) { [Avalonia.Styling.ThemeVariant]::Dark } else { [Avalonia.Styling.ThemeVariant]::Light }
        & $updateThemeButton
    })

    # Context menu actions copy information about the selected policy to the clipboard.
    # The last copy task is kept: a failed copy (no clipboard on a Linux session...) is reported
    # instead of being lost, and the tests can wait for it.
    $clipboard = @{ Task = $null; Error = $null; Text = $null }
    function Copy-SelectedPolicyText {
        param([scriptblock]$Text)

        $selected = $treeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsPolicy]) {
            $value = & $Text $selected.Tag
            if ($value) {
                $clipboard.Error = $null
                $clipboard.Text = $value
                try {
                    $clipboard.Task = $window.Clipboard.SetTextAsync($value)
                } catch {
                    $clipboard.Task = $null
                    $clipboard.Error = $_.Exception
                    Write-Warning "Copy to the clipboard failed: $($_.Exception.Message)"
                }
            }
        }
    }
    $copyNameMenuItem.Add_Click({ Copy-SelectedPolicyText { param($p) $p.DisplayName } })
    $copyRegistryMenuItem.Add_Click({ Copy-SelectedPolicyText { param($p) $p.Registry.Path } })
    $copyCommandMenuItem.Add_Click({
        Copy-SelectedPolicyText {
            param($p)
            if ($p.Registry.Key) {
                "Get-ItemProperty -Path '{0}' -Name '{1}'" -f $p.Registry.Path, $p.Registry.Key
            } elseif ($p.Registry.Path) {
                "Get-ItemProperty -Path '{0}'" -f $p.Registry.Path
            }
        }
    })

    $treeView.add_SelectionChanged({
        $selected = $treeView.SelectedItem

        # Breadcrumb: walk the node's own Parent chain (built while populating the tree).
        $pathParts = [System.Collections.Generic.List[string]]::new()
        $current = $selected
        while ($null -ne $current) {
            $pathParts.Insert(0, $current.Header)
            $current = $current.Parent
        }
        $breadcrumbTextBlock.Text = if ($pathParts.Count -gt 0) { "📍 $($pathParts -join ' > ')" } else { 'Select a policy to see its path' }

        $policy = if ($selected) { $selected.Tag } else { $null }
        # The setting is not read from a GPO yet: every policy starts as Not Configured.
        $notConfiguredRadio.IsChecked = $true
        if ($policy -is [GPOToolsPolicy]) {
            $editing.Policy = $policy
            $settingTitleTextBlock.Text = $policy.DisplayName
            $editing.Editor = New-PSGPOPolicyEditor -Policy $policy -OnChange { Update-RegistryPreview }
            $optionsHost.Content = $editing.Editor.Panel

            $displayNameTextBox.Text = $policy.DisplayName
            $descriptionTextBox.Text = if ($policy.Description) { $policy.Description } else { '(No description available)' }
            $scopeTextBox.Text = $policy.Scope.ToString()

            if ($policy.Registry) {
                $registryPathTextBox.Text = if ($policy.Registry.Path) { $policy.Registry.Path } else { '(No registry path defined)' }
                $registryKeyTextBox.Text = if ($policy.Registry.Key) { $policy.Registry.Key } else { '(No registry value name defined)' }

                $rows = @(Get-PSGPOPolicyRegistryRow -Policy $policy)
                if ($rows.Count -gt 0) {
                    $registryValuesList.ItemsSource = $rows
                } else {
                    $row = [AvaloniaRegistryRow]::new()
                    $row.Key = 'Information'
                    $row.Value = '(No registry value available for this policy)'
                    $registryValuesList.ItemsSource = @($row)
                }
            } else {
                $registryPathTextBox.Text = '(This policy does not use the registry)'
                $registryKeyTextBox.Text = '(No registry value name)'
                $row = [AvaloniaRegistryRow]::new()
                $row.Key = 'Information'
                $row.Value = '(This policy does not store data in the registry)'
                $registryValuesList.ItemsSource = @($row)
            }
        } else {
            $displayNameTextBox.Text = ''
            $descriptionTextBox.Text = ''
            $scopeTextBox.Text = ''
            $registryPathTextBox.Text = ''
            $registryKeyTextBox.Text = ''
            $registryValuesList.ItemsSource = $null
            $editing.Policy = $null
            $editing.Editor = $null
            $optionsHost.Content = $null
            $settingTitleTextBlock.Text = 'Select a policy in the tree'
        }
        Update-RegistryPreview
    })

    function Update-PolicyTree {
        $treeView.ItemsSource = New-PSGPOPolicyTree -Filter $searchTextBox.Text
    }

    if ([GPOToolsUtility]::Policies.Count -eq 0) {
        Write-Warning 'No policy loaded: run Initialize-PSGPOAdmx before Show-GPOManagerAvalonia.'
        $breadcrumbTextBlock.Text = 'No policy loaded - run Initialize-PSGPOAdmx first'
    } else {
        Update-PolicyTree
    }

    $searchButton.Add_Click({ Update-PolicyTree })
    $searchTextBox.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            Update-PolicyTree
        }
    })

    # --- Group Policy Management view --------------------------------------------------------

    function Show-View {
        param([ValidateSet('Management', 'Editor')][string]$View)
        $managementView.IsVisible = $View -eq 'Management'
        $editorView.IsVisible = $View -eq 'Editor'
        $managementButton.IsVisible = $View -eq 'Editor'
        $browseAdmxButton.IsVisible = $View -eq 'Management'
        $searchPanel.IsVisible = $View -eq 'Editor'
        $subtitleTextBlock.Text = if ($View -eq 'Management') {
            if ($Directory) { "Group Policy Management - $($Directory.DomainName)" } else { 'Group Policy Management' }
        } elseif ($editing.Gpo) { "Editing the GPO $($editing.Gpo.DisplayName)" } else { 'Explore and manage Group Policy Objects' }
    }

    # Opens the policy editor on a GPO ($null: browse the ADMX policies, outside any GPO).
    function Open-GpoEditor {
        param([GPOToolsGpo]$Gpo)
        $editing.Gpo = $Gpo
        $treeView.SelectedItem = $null
        $editingBanner.IsVisible = $null -ne $Gpo
        $editingGpoTextBlock.Text = if ($Gpo) { "✏️ Editing the GPO '$($Gpo.DisplayName)' [$($Directory.DomainName)]" } else { '' }
        Show-View 'Editor'
    }

    # Keys of the expanded nodes, to keep them expanded when the tree is rebuilt.
    function Get-ExpandedKey {
        $keys = [System.Collections.Generic.HashSet[string]]::new()
        $stack = [System.Collections.Generic.Stack[object]]::new()
        foreach ($root in @($domainTreeView.ItemsSource)) { if ($root) { $stack.Push($root) } }
        while ($stack.Count) {
            $node = $stack.Pop()
            if ($node.IsExpanded) { [void]$keys.Add("$(Get-PSGPODirectoryNodeKey $node)") }
            foreach ($child in $node.Children) { $stack.Push($child) }
        }
        , $keys
    }

    # Rebuilds the tree and selects the first node whose Tag is $Select, its parents expanded.
    function Update-DirectoryTree {
        param($Select)
        $keys = Get-ExpandedKey
        if ($null -ne $Select) {
            $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys
            $target = $null
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($root in $roots) { $stack.Push($root) }
            while ($stack.Count -and -not $target) {
                $node = $stack.Pop()
                if ([object]::ReferenceEquals($node.Tag, $Select)) { $target = $node }
                foreach ($child in $node.Children) { $stack.Push($child) }
            }
            for ($parent = $target.Parent; $parent; $parent = $parent.Parent) { [void]$keys.Add("$(Get-PSGPODirectoryNodeKey $parent)") }
        }
        $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys
        $domainTreeView.ItemsSource = $roots
        if ($null -ne $Select) {
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($root in $roots) { $stack.Push($root) }
            while ($stack.Count) {
                $node = $stack.Pop()
                if ([object]::ReferenceEquals($node.Tag, $Select)) { $domainTreeView.SelectedItem = $node; break }
                foreach ($child in $node.Children) { $stack.Push($child) }
            }
        }
    }

    # New GPO form: linked to $Som, or only created in the domain when $Som is $null.
    $newGpo = @{ Som = $null }
    function Open-NewGpoForm {
        param([GPOToolsSom]$Som)
        $newGpo.Som = $Som
        $newGpoTitleTextBlock.Text = if ($Som) { "New GPO in $($Directory.DomainName), linked to $($Som.Name)" } else { "New GPO in $($Directory.DomainName)" }
        $newGpoNameTextBox.Text = 'New Group Policy Object'
        $newGpoErrorTextBlock.Text = ''
        $newGpoPanel.IsVisible = $true
        [void]$newGpoNameTextBox.Focus()
        $newGpoNameTextBox.SelectAll()
    }

    function Submit-NewGpo {
        try {
            $gpo = $Directory.NewGpo($newGpoNameTextBox.Text)
        } catch {
            $newGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $select = $gpo
        if ($newGpo.Som) {
            try {
                $select = $Directory.NewLink($newGpo.Som, $gpo)
            } catch {
                Write-Warning "The GPO '$($gpo.DisplayName)' was created but not linked: $($_.Exception.GetBaseException().Message)"
            }
        }
        $newGpoPanel.IsVisible = $false
        Update-DirectoryTree -Select $select
    }

    function Get-SelectedGpo {
        $item = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($item -is [GPOToolsGpoLink]) { $item.Gpo } elseif ($item -is [GPOToolsGpo]) { $item }
    }

    $domainTreeView.add_SelectionChanged({
        $selected = $domainTreeView.SelectedItem
        $item = if ($selected) { $selected.Tag }

        $pathParts = [System.Collections.Generic.List[string]]::new()
        for ($current = $selected; $current; $current = $current.Parent) { $pathParts.Insert(0, $current.Header) }
        $directoryBreadcrumbTextBlock.Text = if ($pathParts.Count) { "📍 $($pathParts -join ' > ')" } else { 'Right-click a domain or an OU to create a GPO' }

        $detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $item
        $directoryTitleTextBlock.Text = $detail.Title
        $directoryPropertiesList.ItemsSource = $detail.Properties
        $linksHeaderTextBlock.Text = $detail.LinksHeader
        $linksHeaderTextBlock.IsVisible = [bool]$detail.LinksHeader
        $linksList.ItemsSource = $detail.Links
        $editGpoButton.IsVisible = $null -ne $detail.Gpo
        $newGpoPanel.IsVisible = $false

        # Context menu of the selected node, as in GPMC.
        $createLinkedGpoMenuItem.IsVisible = $item -is [GPOToolsSom]
        $newGpoMenuItem.IsVisible = $item -eq 'GroupPolicyObjects'
        $editGpoMenuItem.IsVisible = $null -ne $detail.Gpo
    })
    # Nothing to offer on this node: do not open an empty menu.
    (Get-PSGPOAvaloniaControl $window 'domainContextMenu').add_Opening({
        param($sender, $e)
        if (-not ($createLinkedGpoMenuItem.IsVisible -or $newGpoMenuItem.IsVisible -or $editGpoMenuItem.IsVisible) -or
            -not $domainTreeView.SelectedItem) { $e.Cancel = $true }
    })

    $createLinkedGpoMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsSom]) { Open-NewGpoForm -Som $item } })
    $newGpoMenuItem.Add_Click({ Open-NewGpoForm -Som $null })
    $editGpoMenuItem.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $editGpoButton.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $domainTreeView.add_DoubleTapped({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $newGpoCreateButton.Add_Click({ Submit-NewGpo })
    $newGpoCancelButton.Add_Click({ $newGpoPanel.IsVisible = $false })
    $newGpoNameTextBox.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-NewGpo }
        elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $newGpoPanel.IsVisible = $false }
    })
    $managementButton.Add_Click({ Show-View 'Management' })
    $browseAdmxButton.Add_Click({ Open-GpoEditor -Gpo $null })

    $directoryEmptyTextBlock.IsVisible = -not $Directory
    $domainTreeView.IsVisible = [bool]$Directory
    if ($Directory) {
        Update-DirectoryTree
        Show-View 'Management'
    } else {
        Show-View 'Editor'
    }

    # Avalonia's SetupWithoutStarting() does not run a message loop by itself; drive one
    # manually and stop it when the window closes so the call blocks until then.
    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
        [Avalonia.Threading.Dispatcher]::UIThread.Post(
            [System.Action] { $cts.Cancel() },
            [Avalonia.Threading.DispatcherPriority]::Background
        )
    })

    $window.Show()

    # A hashtable, because assigning a variable inside the posted action would only set a child-scope copy.
    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Editing = $editing; Clipboard = $clipboard; Directory = $Directory }
        foreach ($name in 'treeView', 'themeToggleButton', 'breadcrumbTextBlock', 'searchTextBox', 'searchButton',
            'displayNameTextBox', 'descriptionTextBox', 'scopeTextBox', 'registryPathTextBox',
            'registryKeyTextBox', 'registryValuesList', 'settingTitleTextBlock', 'previewEmptyTextBlock', 'detailsTabs', 'copyNameMenuItem', 'copyRegistryMenuItem', 'copyCommandMenuItem',
            'notConfiguredRadio', 'enabledRadio', 'disabledRadio', 'optionsHost', 'settingErrorTextBlock', 'registryPreviewList',
            'subtitleTextBlock', 'managementButton', 'browseAdmxButton', 'searchPanel', 'managementView', 'editorView',
            'editingBanner', 'editingGpoTextBlock', 'domainTreeView', 'domainContextMenu', 'directoryEmptyTextBlock', 'directoryBreadcrumbTextBlock',
            'directoryTitleTextBlock', 'directoryPropertiesList', 'linksHeaderTextBlock', 'linksList', 'createLinkedGpoMenuItem',
            'newGpoMenuItem', 'editGpoMenuItem', 'editGpoButton', 'newGpoPanel', 'newGpoTitleTextBlock', 'newGpoNameTextBox',
            'newGpoErrorTextBlock', 'newGpoCreateButton', 'newGpoCancelButton') {
            $controls[$name] = Get-PSGPOAvaloniaControl $window $name
        }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
            try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { $window.Close() }
        })
    }

    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        # Expected: the loop exits by cancellation once the window is closed.
    }

    if ($onShownState.Error) { throw $onShownState.Error }
}
