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
        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime

    $xaml = @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='GPO Policy Manager'
        Width='1200' Height='700'
        MinWidth='800' MinHeight='500'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='MainWindow'>

    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.ThemeDictionaries>
                <ResourceDictionary x:Key='Light'>
                    <SolidColorBrush x:Key='PrimaryBrush'>#0078D4</SolidColorBrush>
                    <SolidColorBrush x:Key='PrimaryHoverBrush'>#106EBE</SolidColorBrush>
                    <SolidColorBrush x:Key='PrimaryPressedBrush'>#005A9E</SolidColorBrush>
                    <SolidColorBrush x:Key='AccentBrush'>#00BCF2</SolidColorBrush>
                    <SolidColorBrush x:Key='BackgroundBrush'>#FFFFFF</SolidColorBrush>
                    <SolidColorBrush x:Key='SecondaryBackgroundBrush'>#F5F5F5</SolidColorBrush>
                    <SolidColorBrush x:Key='BorderBrush'>#E1E1E1</SolidColorBrush>
                    <SolidColorBrush x:Key='TextBrush'>#1F1F1F</SolidColorBrush>
                    <SolidColorBrush x:Key='SecondaryTextBrush'>#605E5C</SolidColorBrush>
                    <SolidColorBrush x:Key='TreeViewHoverBrush'>#F3F2F1</SolidColorBrush>
                    <SolidColorBrush x:Key='IconFolderBrush'>#FDB900</SolidColorBrush>
                    <SolidColorBrush x:Key='IconFileBrush'>#0078D4</SolidColorBrush>
                    <SolidColorBrush x:Key='IconScopeBrush'>#107C10</SolidColorBrush>
                    <SolidColorBrush x:Key='HeaderBackgroundBrush'>#F3F2F1</SolidColorBrush>
                    <SolidColorBrush x:Key='HeaderTextBrush'>#1F1F1F</SolidColorBrush>
                </ResourceDictionary>
                <ResourceDictionary x:Key='Dark'>
                    <SolidColorBrush x:Key='PrimaryBrush'>#0086F0</SolidColorBrush>
                    <SolidColorBrush x:Key='PrimaryHoverBrush'>#3399FF</SolidColorBrush>
                    <SolidColorBrush x:Key='PrimaryPressedBrush'>#0066CC</SolidColorBrush>
                    <SolidColorBrush x:Key='AccentBrush'>#00D4FF</SolidColorBrush>
                    <SolidColorBrush x:Key='BackgroundBrush'>#1E1E1E</SolidColorBrush>
                    <SolidColorBrush x:Key='SecondaryBackgroundBrush'>#2D2D30</SolidColorBrush>
                    <SolidColorBrush x:Key='BorderBrush'>#3F3F46</SolidColorBrush>
                    <SolidColorBrush x:Key='TextBrush'>#FFFFFF</SolidColorBrush>
                    <SolidColorBrush x:Key='SecondaryTextBrush'>#CCCCCC</SolidColorBrush>
                    <SolidColorBrush x:Key='TreeViewHoverBrush'>#2D2D30</SolidColorBrush>
                    <SolidColorBrush x:Key='IconFolderBrush'>#FFD700</SolidColorBrush>
                    <SolidColorBrush x:Key='IconFileBrush'>#64B5F6</SolidColorBrush>
                    <SolidColorBrush x:Key='IconScopeBrush'>#81C784</SolidColorBrush>
                    <SolidColorBrush x:Key='HeaderBackgroundBrush'>#252526</SolidColorBrush>
                    <SolidColorBrush x:Key='HeaderTextBrush'>#FFFFFF</SolidColorBrush>
                </ResourceDictionary>
            </ResourceDictionary.ThemeDictionaries>
        </ResourceDictionary>
    </Window.Resources>

    <Grid RowDefinitions='Auto,*'>

        <!-- Header: title, theme toggle, search -->
        <Border Grid.Row='0'
                Background='{DynamicResource BackgroundBrush}'
                BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}'
                Padding='20,16'>
            <Grid ColumnDefinitions='Auto,*'>
                <StackPanel Grid.Column='0' VerticalAlignment='Center'>
                    <TextBlock Text='GPO Policy Manager' FontSize='22' FontWeight='Bold'
                               Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Text='Explore and manage Group Policy Objects' FontSize='12'
                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,2,0,0'/>
                </StackPanel>

                <StackPanel Grid.Column='1' Orientation='Horizontal'
                            HorizontalAlignment='Right' VerticalAlignment='Center' Spacing='12'>
                    <Button Name='themeToggleButton' Content='🌙 Dark mode' Height='36' Width='140'/>
                    <TextBox Name='searchTextBox' Width='320' Height='36'
                             Watermark='Search a policy...' VerticalContentAlignment='Center'/>
                    <Button Name='searchButton' Content='🔍 Search' Height='36' Width='130'/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main content: TreeView | Splitter | Details -->
        <Grid Grid.Row='1' ColumnDefinitions='2*,Auto,3*' Margin='0'>

            <Border Grid.Column='0'
                    Background='{DynamicResource BackgroundBrush}'
                    Margin='16,16,8,16' CornerRadius='8' BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}'
                    BoxShadow='0 2 10 0 #1A000000'>
                <Grid RowDefinitions='Auto,*'>
                    <Border Grid.Row='0' Name='treeHeaderBorder'
                            Background='{DynamicResource HeaderBackgroundBrush}'
                            Padding='16,12' CornerRadius='8,8,0,0'>
                        <StackPanel>
                            <TextBlock Text='📁 Policy Structure' FontSize='15' FontWeight='SemiBold'
                                       Foreground='{DynamicResource HeaderTextBrush}'/>
                            <TextBlock Name='breadcrumbTextBlock' Text='Select a policy to see its path'
                                       FontSize='11' Foreground='{DynamicResource SecondaryTextBrush}'
                                       Margin='0,4,0,0' TextTrimming='CharacterEllipsis'/>
                        </StackPanel>
                    </Border>

                    <TreeView Grid.Row='1' Name='treeView' Margin='8'>
                        <TreeView.ItemTemplate>
                            <TreeDataTemplate ItemsSource='{Binding Children}'>
                                <StackPanel Orientation='Horizontal' Spacing='4'>
                                    <TextBlock Text='{Binding Icon}' FontSize='13'/>
                                    <TextBlock Text='{Binding Header}'/>
                                </StackPanel>
                            </TreeDataTemplate>
                        </TreeView.ItemTemplate>
                        <TreeView.ContextMenu>
                            <ContextMenu>
                                <MenuItem Name='copyNameMenuItem' Header='📋 Copy policy name'/>
                                <MenuItem Name='copyRegistryMenuItem' Header='📋 Copy registry path'/>
                                <Separator/>
                                <MenuItem Name='copyCommandMenuItem' Header='⌨️ Copy PowerShell command'/>
                            </ContextMenu>
                        </TreeView.ContextMenu>
                    </TreeView>
                </Grid>
            </Border>

            <GridSplitter Grid.Column='1' Width='6' HorizontalAlignment='Center'
                          VerticalAlignment='Stretch' Background='Transparent'/>

            <Border Grid.Column='2'
                    Background='{DynamicResource BackgroundBrush}'
                    Margin='8,16,16,16' CornerRadius='8' BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}'
                    BoxShadow='0 2 10 0 #1A000000'>
                <Grid RowDefinitions='Auto,*'>
                    <Border Grid.Row='0' Name='detailsHeaderBorder'
                            Background='{DynamicResource HeaderBackgroundBrush}'
                            Padding='16,12' CornerRadius='8,8,0,0'>
                        <TextBlock Text='ℹ️ Policy Details' FontSize='15' FontWeight='SemiBold'
                                   Foreground='{DynamicResource HeaderTextBrush}'/>
                    </Border>

                    <!-- Setting: what the administrator edits; Details: what the ADMX defines. -->
                    <TabControl Grid.Row='1' Name='detailsTabs' Margin='8,0,8,8'>
                        <TabItem Header='Setting'>
                            <ScrollViewer Padding='8'>
                                <StackPanel>
                                    <TextBlock Name='settingTitleTextBlock' FontSize='16' FontWeight='SemiBold'
                                               TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'
                                               Text='Select a policy in the tree'/>

                                    <StackPanel Orientation='Horizontal' Spacing='16' Margin='0,12,0,0'>
                                        <RadioButton Name='notConfiguredRadio' GroupName='policyState' Content='Not Configured' IsChecked='True'/>
                                        <RadioButton Name='enabledRadio' GroupName='policyState' Content='Enabled'/>
                                        <RadioButton Name='disabledRadio' GroupName='policyState' Content='Disabled'/>
                                    </StackPanel>

                                    <TextBlock Text='Options' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <Border BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' CornerRadius='4' Padding='12'>
                                        <ContentControl Name='optionsHost'/>
                                    </Border>
                                    <TextBlock Name='settingErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' Margin='0,8,0,0'/>

                                    <TextBlock Text='Registry Preview' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <TextBlock Name='previewEmptyTextBlock' Foreground='{DynamicResource SecondaryTextBrush}'
                                               TextWrapping='Wrap' Text='Not configured: nothing is written to the registry.'/>
                                    <ItemsControl Name='registryPreviewList'>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <Border BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}' Padding='0,6'>
                                                    <Grid ColumnDefinitions='Auto,*' RowDefinitions='Auto,Auto,Auto,Auto'>
                                                        <TextBlock Grid.Row='0' Grid.ColumnSpan='2' FontWeight='SemiBold' Text='{Binding Title}'/>
                                                        <TextBlock Grid.Row='1' Grid.Column='0' Text='Key' Margin='0,2,12,0' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        <SelectableTextBlock Grid.Row='1' Grid.Column='1' Text='{Binding Key}' TextWrapping='Wrap' Margin='0,2,0,0'/>
                                                        <TextBlock Grid.Row='2' Grid.Column='0' Text='Value' Margin='0,2,12,0' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        <SelectableTextBlock Grid.Row='2' Grid.Column='1' Text='{Binding ValueName}' TextWrapping='Wrap' Margin='0,2,0,0'/>
                                                        <TextBlock Grid.Row='3' Grid.Column='0' Text='Data' Margin='0,2,12,0' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        <SelectableTextBlock Grid.Row='3' Grid.Column='1' Text='{Binding Data}' TextWrapping='Wrap' Margin='0,2,0,0'/>
                                                    </Grid>
                                                </Border>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>
                                </StackPanel>
                            </ScrollViewer>
                        </TabItem>

                        <TabItem Header='Details'>
                            <ScrollViewer Padding='8'>
                                <StackPanel Name='detailsPanel'>
                                    <TextBlock Text='Display Name' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,8,0,4'/>
                                    <TextBox Name='displayNameTextBox' IsReadOnly='True' TextWrapping='Wrap'/>

                                    <TextBlock Text='Description' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <TextBox Name='descriptionTextBox' IsReadOnly='True' TextWrapping='Wrap'
                                             AcceptsReturn='True' MinHeight='60' MaxHeight='240'/>

                                    <TextBlock Text='Scope' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <TextBox Name='scopeTextBox' IsReadOnly='True'/>

                                    <TextBlock Text='Registry Key' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <TextBox Name='registryPathTextBox' IsReadOnly='True'/>

                                    <TextBlock Text='Value Name' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <TextBox Name='registryKeyTextBox' IsReadOnly='True'/>

                                    <TextBlock Text='Registry Values defined by the ADMX' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <ItemsControl Name='registryValuesList'>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <Border BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}' Padding='0,6'>
                                                    <StackPanel Spacing='2'>
                                                        <TextBlock FontWeight='SemiBold' Text='{Binding Key}' TextWrapping='Wrap'/>
                                                        <SelectableTextBlock Text='{Binding Value}' TextWrapping='Wrap'/>
                                                    </StackPanel>
                                                </Border>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>
                                </StackPanel>
                            </ScrollViewer>
                        </TabItem>
                    </TabControl>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

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

    # Options form of the selected policy (New-PSGPOPolicyEditor) and the policy it edits.
    $editing = @{ Policy = $null; Editor = $null }

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
    function Copy-SelectedPolicyText {
        param([scriptblock]$Text)

        $selected = $treeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsPolicy]) {
            $value = & $Text $selected.Tag
            if ($value) { $null = $window.Clipboard.SetTextAsync($value) }
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
        $controls = @{ Window = $window; Editing = $editing }
        foreach ($name in 'treeView', 'themeToggleButton', 'breadcrumbTextBlock', 'searchTextBox', 'searchButton',
            'displayNameTextBox', 'descriptionTextBox', 'scopeTextBox', 'registryPathTextBox',
            'registryKeyTextBox', 'registryValuesList', 'settingTitleTextBlock', 'previewEmptyTextBlock', 'detailsTabs', 'copyNameMenuItem', 'copyRegistryMenuItem', 'copyCommandMenuItem',
            'notConfiguredRadio', 'enabledRadio', 'disabledRadio', 'optionsHost', 'settingErrorTextBlock', 'registryPreviewList') {
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
