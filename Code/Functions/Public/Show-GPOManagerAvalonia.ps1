function Show-GPOManagerAvalonia {
    <#
    .SYNOPSIS
        Cross-platform (Windows/Linux/macOS) Avalonia UI equivalent of Show-GPOManager.
    .DESCRIPTION
        Same GPO tree/details experience as Show-GPOManager, but hosted on Avalonia UI
        instead of WPF so it also runs on Linux and macOS via PowerShell 7+.

        The Avalonia assemblies are not bundled with the module; run
        .\Avalonia\Get-AvaloniaBinaries.ps1 once per target platform beforehand (see that
        script's help for details). All GPO/ADMX logic stays in PowerShell; Avalonia is
        only used to render the window, loaded at runtime the same way
        Add-Type -AssemblyName PresentationFramework is used for the WPF version.
    .LINK
        https://www.deploymentresearch.com/using-avalonia-ui-in-deployr-task-sequences/
    #>
    [CmdletBinding()]
    Param()

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
                    <Button Name='themeToggleButton' Content='🌙 Mode Sombre' Height='36' Width='140'/>
                    <TextBox Name='searchTextBox' Width='320' Height='36'
                             Watermark='Rechercher une GPO...' VerticalContentAlignment='Center'/>
                    <Button Name='searchButton' Content='🔍 Rechercher' Height='36' Width='130'/>
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
                                <MenuItem Name='enableMenuItem' Header='✅ Enable this parameter'/>
                                <MenuItem Name='disableMenuItem' Header='❌ Disable this parameter'/>
                                <Separator/>
                                <MenuItem Name='createGpoMenuItem' Header='➕ Create a GPO'/>
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

                    <ScrollViewer Grid.Row='1' Padding='16'>
                        <StackPanel Name='detailsPanel'>
                            <TextBlock Text='Display Name' FontSize='12' FontWeight='SemiBold'
                                       Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,8,0,4'/>
                            <TextBox Name='displayNameTextBox' IsReadOnly='True'/>

                            <TextBlock Text='Description' FontSize='12' FontWeight='SemiBold'
                                       Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                            <TextBox Name='descriptionTextBox' IsReadOnly='True' TextWrapping='Wrap'
                                     AcceptsReturn='True' MinHeight='60' MaxHeight='120'/>

                            <TextBlock Text='Scope' FontSize='12' FontWeight='SemiBold'
                                       Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                            <TextBox Name='scopeTextBox' IsReadOnly='True'/>

                            <TextBlock Text='Registry Path' FontSize='12' FontWeight='SemiBold'
                                       Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                            <TextBox Name='registryPathTextBox' IsReadOnly='True'/>

                            <TextBlock Text='Registry Key' FontSize='12' FontWeight='SemiBold'
                                       Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                            <TextBox Name='registryKeyTextBox' IsReadOnly='True'/>

                            <TextBlock Text='Registry Values' FontSize='12' FontWeight='SemiBold'
                                       Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                            <DataGrid Name='registryValuesGrid' AutoGenerateColumns='False'
                                      IsReadOnly='True' MaxHeight='200' Margin='0,0,0,16'
                                      GridLinesVisibility='None' HeadersVisibility='Column'>
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header='Name' Binding='{Binding Key}' Width='*'/>
                                    <DataGridTextColumn Header='Value' Binding='{Binding Value}' Width='2*'/>
                                </DataGrid.Columns>
                            </DataGrid>
                        </StackPanel>
                    </ScrollViewer>
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
    $registryValuesGrid = Get-PSGPOAvaloniaControl $window 'registryValuesGrid'
    $enableMenuItem = Get-PSGPOAvaloniaControl $window 'enableMenuItem'
    $disableMenuItem = Get-PSGPOAvaloniaControl $window 'disableMenuItem'
    $createGpoMenuItem = Get-PSGPOAvaloniaControl $window 'createGpoMenuItem'

    # Theme management: Avalonia FluentTheme + our ThemeDictionaries swap automatically
    # when RequestedThemeVariant changes, no manual brush-by-brush update needed.
    $script:isDarkTheme = $false
    $themeToggleButton.Add_Click({
        $script:isDarkTheme = -not $script:isDarkTheme
        $window.RequestedThemeVariant = if ($script:isDarkTheme) { [Avalonia.Styling.ThemeVariant]::Dark } else { [Avalonia.Styling.ThemeVariant]::Light }
        $themeToggleButton.Content = if ($script:isDarkTheme) { '☀️ Mode Clair' } else { '🌙 Mode Sombre' }
    })

    # Context menu actions operate on the current TreeView selection, same as the WPF version.
    $enableMenuItem.Add_Click({
        $selected = $treeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsPolicy]) {
            Write-Host "Enable: $($selected.Tag.DisplayName)"
        }
    })
    $disableMenuItem.Add_Click({
        $selected = $treeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsPolicy]) {
            Write-Host "Disable: $($selected.Tag.DisplayName)"
        }
    })
    $createGpoMenuItem.Add_Click({
        $selected = $treeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsPolicy]) {
            Write-Host "Create GPO for: $($selected.Tag.DisplayName)"
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
        if ($policy -is [GPOToolsPolicy]) {
            $displayNameTextBox.Text = $policy.DisplayName
            $descriptionTextBox.Text = if ($policy.Description) { $policy.Description } else { '(Aucune description disponible)' }
            $scopeTextBox.Text = $policy.Scope.ToString()

            if ($policy.Registry) {
                $registryPathTextBox.Text = if ($policy.Registry.Path) { $policy.Registry.Path } else { '(Aucun chemin de registre défini)' }
                $registryKeyTextBox.Text = if ($policy.Registry.Key) { $policy.Registry.Key } else { '(Aucune clé de registre définie)' }

                if ($policy.Registry.Value -and $policy.Registry.Value.Keys.Count -gt 0) {
                    $registryValuesGrid.ItemsSource = @(
                        foreach ($key in $policy.Registry.Value.Keys) {
                            $row = [AvaloniaRegistryRow]::new()
                            $row.Key = $key
                            $row.Value = if ($policy.Registry.Value[$key]) { $policy.Registry.Value[$key] } else { '(Valeur non définie)' }
                            $row
                        }
                    )
                } else {
                    $row = [AvaloniaRegistryRow]::new()
                    $row.Key = 'Information'
                    $row.Value = '(Aucune valeur de registre disponible pour cette GPO)'
                    $registryValuesGrid.ItemsSource = @($row)
                }
            } else {
                $registryPathTextBox.Text = '(Cette GPO ne nécessite pas de configuration de registre)'
                $registryKeyTextBox.Text = '(Aucune clé de registre)'
                $row = [AvaloniaRegistryRow]::new()
                $row.Key = 'Information'
                $row.Value = '(Cette policy ne stocke pas de données dans le registre)'
                $registryValuesGrid.ItemsSource = @($row)
            }
        } else {
            $displayNameTextBox.Text = ''
            $descriptionTextBox.Text = ''
            $scopeTextBox.Text = ''
            $registryPathTextBox.Text = ''
            $registryKeyTextBox.Text = ''
            $registryValuesGrid.ItemsSource = $null
        }
    })

    function Populate-TreeView {
        param([string]$Filter = '')

        $rootNodes = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

        foreach ($scope in [Enum]::GetValues([ScopePolicy])) {
            $scopeNode = [AvaloniaTreeNode]::new()
            $scopeNode.Header = $scope.ToString()
            $scopeNode.Icon = '📋'
            $scopeNode.Tag = $scope

            $policies = Get-PSGPOPolicy -Scope $scope
            if ($Filter) {
                $policies = $policies | Where-Object { $_.DisplayName -like "*$Filter*" }
            }

            foreach ($policy in $policies) {
                $category = $policy.Category
                $parentCategory = $category.ParentCategory
                $currentNode = $scopeNode

                # Build (or reuse) the category chain, deepest-parent-first, same as the WPF version.
                $chain = [System.Collections.Generic.List[object]]::new()
                while ($null -ne $parentCategory) {
                    $chain.Add($parentCategory)
                    $parentCategory = $parentCategory.ParentCategory
                }
                for ($i = $chain.Count - 1; $i -ge 0; $i--) {
                    $cat = $chain[$i]
                    $existing = $currentNode.Children | Where-Object { $_.Tag -and $_.Tag.DisplayName -eq $cat.DisplayName } | Select-Object -First 1
                    if (-not $existing) {
                        $existing = [AvaloniaTreeNode]::new()
                        $existing.Header = $cat.DisplayName
                        $existing.Icon = '📂'
                        $existing.Tag = $cat
                        $existing.Parent = $currentNode
                        $currentNode.Children.Add($existing)
                    }
                    $currentNode = $existing
                }

                $policyNode = [AvaloniaTreeNode]::new()
                $policyNode.Header = $policy.DisplayName
                $policyNode.Icon = '📄'
                $policyNode.Tag = $policy
                $policyNode.Parent = $currentNode
                $currentNode.Children.Add($policyNode)
            }

            if ($scopeNode.Children.Count -gt 0) {
                $rootNodes.Add($scopeNode)
            }
        }

        $treeView.ItemsSource = $rootNodes
    }

    Populate-TreeView

    $searchButton.Add_Click({ Populate-TreeView -Filter $searchTextBox.Text })
    $searchTextBox.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            Populate-TreeView -Filter $searchTextBox.Text
        }
    })

    # Avalonia's SetupWithoutStarting() does not run a message loop by itself; drive one
    # manually and stop it when the window closes (mirrors WPF's blocking ShowDialog()).
    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
        [Avalonia.Threading.Dispatcher]::UIThread.Post(
            [System.Action] { $cts.Cancel() },
            [Avalonia.Threading.DispatcherPriority]::Background
        )
    })

    $window.Show()
    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        # Expected: the loop exits by cancellation once the window is closed.
    }
}
