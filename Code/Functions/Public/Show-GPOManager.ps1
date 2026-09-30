function Show-GPOManager {
    [cmdletbinding()]
    Param()

    # Ensure WPF assemblies are loaded for PowerShell 7.5 and .NET 9 compatibility
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='GPO Policy Manager'
        Height='700' Width='1200'
        MinHeight='500' MinWidth='800'
        WindowStartupLocation='CenterScreen'
        Background='#F5F5F5'
        Name='MainWindow'>
    <Window.Resources>
        <!-- Light Theme Colors -->
        <SolidColorBrush x:Key='PrimaryBrush' Color='#0078D4'/>
        <SolidColorBrush x:Key='PrimaryHoverBrush' Color='#106EBE'/>
        <SolidColorBrush x:Key='PrimaryPressedBrush' Color='#005A9E'/>
        <SolidColorBrush x:Key='AccentBrush' Color='#00BCF2'/>
        <SolidColorBrush x:Key='BackgroundBrush' Color='#FFFFFF'/>
        <SolidColorBrush x:Key='SecondaryBackgroundBrush' Color='#F5F5F5'/>
        <SolidColorBrush x:Key='BorderBrush' Color='#E1E1E1'/>
        <SolidColorBrush x:Key='TextBrush' Color='#1F1F1F'/>
        <SolidColorBrush x:Key='SecondaryTextBrush' Color='#605E5C'/>
        <SolidColorBrush x:Key='TreeViewSelectedBrush' Color='#0078D4'/>
        <SolidColorBrush x:Key='TreeViewSelectedTextBrush' Color='#FFFFFF'/>
        <SolidColorBrush x:Key='TreeViewHoverBrush' Color='#F3F2F1'/>
        <SolidColorBrush x:Key='IconFolderBrush' Color='#FDB900'/>
        <SolidColorBrush x:Key='IconFileBrush' Color='#0078D4'/>
        <SolidColorBrush x:Key='IconScopeBrush' Color='#107C10'/>
        <SolidColorBrush x:Key='HeaderBackgroundBrush' Color='#F3F2F1'/>
        <SolidColorBrush x:Key='HeaderTextBrush' Color='#1F1F1F'/>

        <!-- Modern Button Style -->
        <Style x:Key='ModernButton' TargetType='Button'>
            <Setter Property='Background' Value='{StaticResource PrimaryBrush}'/>
            <Setter Property='Foreground' Value='White'/>
            <Setter Property='BorderThickness' Value='0'/>
            <Setter Property='Padding' Value='16,8'/>
            <Setter Property='FontSize' Value='14'/>
            <Setter Property='FontWeight' Value='SemiBold'/>
            <Setter Property='Cursor' Value='Hand'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='Button'>
                        <Border Background='{TemplateBinding Background}'
                                CornerRadius='4'
                                Padding='{TemplateBinding Padding}'>
                            <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property='IsMouseOver' Value='True'>
                    <Setter Property='Background' Value='{StaticResource PrimaryHoverBrush}'/>
                </Trigger>
                <Trigger Property='IsPressed' Value='True'>
                    <Setter Property='Background' Value='{StaticResource PrimaryPressedBrush}'/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Modern TextBox Style -->
        <Style x:Key='ModernTextBox' TargetType='TextBox'>
            <Setter Property='Background' Value='{StaticResource BackgroundBrush}'/>
            <Setter Property='Foreground' Value='{StaticResource TextBrush}'/>
            <Setter Property='BorderBrush' Value='{StaticResource BorderBrush}'/>
            <Setter Property='BorderThickness' Value='1'/>
            <Setter Property='Padding' Value='12,8'/>
            <Setter Property='FontSize' Value='14'/>
            <Setter Property='VerticalContentAlignment' Value='Center'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='TextBox'>
                        <Border Background='{TemplateBinding Background}'
                                BorderBrush='{TemplateBinding BorderBrush}'
                                BorderThickness='{TemplateBinding BorderThickness}'
                                CornerRadius='4'>
                            <ScrollViewer x:Name='PART_ContentHost' Margin='2'/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property='IsMouseOver' Value='True'>
                                <Setter Property='BorderBrush' Value='{StaticResource PrimaryBrush}'/>
                            </Trigger>
                            <Trigger Property='IsFocused' Value='True'>
                                <Setter Property='BorderBrush' Value='{StaticResource PrimaryBrush}'/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern TreeView Style with proper selection colors -->
        <Style TargetType='TreeView'>
            <Setter Property='Background' Value='{DynamicResource BackgroundBrush}'/>
            <Setter Property='BorderBrush' Value='{DynamicResource BorderBrush}'/>
            <Setter Property='BorderThickness' Value='1'/>
            <Setter Property='Padding' Value='8'/>
            <Setter Property='FontSize' Value='13'/>
        </Style>

        <Style TargetType='TreeViewItem'>
            <Setter Property='Padding' Value='4'/>
            <Setter Property='Margin' Value='0,1'/>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
            <Style.Triggers>
                <Trigger Property='IsMouseOver' Value='True'>
                    <Setter Property='Background' Value='{DynamicResource TreeViewHoverBrush}'/>
                </Trigger>
                <Trigger Property='IsSelected' Value='True'>
                    <Setter Property='Background' Value='{DynamicResource TreeViewSelectedBrush}'/>
                    <Setter Property='Foreground' Value='{DynamicResource TreeViewSelectedTextBrush}'/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Modern DataGrid Style -->
        <Style TargetType='DataGrid'>
            <Setter Property='Background' Value='{DynamicResource BackgroundBrush}'/>
            <Setter Property='BorderBrush' Value='{DynamicResource BorderBrush}'/>
            <Setter Property='BorderThickness' Value='1'/>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
            <Setter Property='RowBackground' Value='{DynamicResource BackgroundBrush}'/>
            <Setter Property='AlternatingRowBackground' Value='{DynamicResource SecondaryBackgroundBrush}'/>
            <Setter Property='GridLinesVisibility' Value='None'/>
            <Setter Property='HeadersVisibility' Value='Column'/>
            <Setter Property='FontSize' Value='13'/>
            <Setter Property='CanUserResizeRows' Value='False'/>
        </Style>

        <Style TargetType='DataGridColumnHeader'>
            <Setter Property='Background' Value='{DynamicResource HeaderBackgroundBrush}'/>
            <Setter Property='Foreground' Value='{DynamicResource HeaderTextBrush}'/>
            <Setter Property='FontWeight' Value='SemiBold'/>
            <Setter Property='Padding' Value='12,8'/>
            <Setter Property='BorderThickness' Value='0,0,0,2'/>
            <Setter Property='BorderBrush' Value='{DynamicResource BorderBrush}'/>
        </Style>

        <Style TargetType='DataGridRow'>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
        </Style>

        <Style TargetType='DataGridCell'>
            <Setter Property='BorderThickness' Value='0'/>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
        </Style>

        <!-- Label Style -->
        <Style x:Key='LabelStyle' TargetType='TextBlock'>
            <Setter Property='FontSize' Value='12'/>
            <Setter Property='FontWeight' Value='SemiBold'/>
            <Setter Property='Foreground' Value='{DynamicResource SecondaryTextBrush}'/>
            <Setter Property='Margin' Value='0,8,0,4'/>
        </Style>

        <Style x:Key='ReadOnlyTextBox' TargetType='TextBox' BasedOn='{StaticResource ModernTextBox}'>
            <Setter Property='IsReadOnly' Value='True'/>
            <Setter Property='Background' Value='{DynamicResource SecondaryBackgroundBrush}'/>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
            <Setter Property='TextWrapping' Value='Wrap'/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height='Auto'/>
            <RowDefinition Height='*'/>
        </Grid.RowDefinitions>

        <!-- Header Section with Modern Search and Theme Toggle -->
        <Border Grid.Row='0' Background='{DynamicResource BackgroundBrush}'
                BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}'
                Padding='20,16'>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width='Auto'/>
                    <ColumnDefinition Width='*'/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column='0' VerticalAlignment='Center'>
                    <TextBlock Text='GPO Policy Manager'
                               FontSize='22'
                               FontWeight='Bold'
                               Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Text='Explore and manage Group Policy Objects'
                               FontSize='12'
                               Foreground='{DynamicResource SecondaryTextBrush}'
                               Margin='0,2,0,0'/>
                </StackPanel>

                <StackPanel Grid.Column='1'
                           Orientation='Horizontal'
                           HorizontalAlignment='Right'
                           VerticalAlignment='Center'>
                    <Button Name='themeToggleButton'
                            Content='🌙 Mode Sombre'
                            Height='36'
                            Width='140'
                            Style='{StaticResource ModernButton}'
                            Margin='0,0,12,0'/>
                    <TextBox Name='searchTextBox'
                             Width='320'
                             Height='36'
                             Style='{StaticResource ModernTextBox}'
                             VerticalContentAlignment='Center'
                             Margin='0,0,12,0'
                             Text='Rechercher une GPO...'
                             Foreground='#999999'/>
                    <Button Name='searchButton'
                            Content='🔍 Rechercher'
                            Height='36'
                            Width='130'
                            Style='{StaticResource ModernButton}'/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main Content Area with Splitter -->
        <Grid Grid.Row='1' Margin='0'>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width='2*' MinWidth='250'/>
                <ColumnDefinition Width='Auto'/>
                <ColumnDefinition Width='3*' MinWidth='300'/>
            </Grid.ColumnDefinitions>

            <!-- TreeView Panel -->
            <Border Grid.Column='0'
                    Background='{DynamicResource BackgroundBrush}'
                    Margin='16,16,8,16'
                    CornerRadius='8'
                    BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}'>
                <Border.Effect>
                    <DropShadowEffect BlurRadius='10' ShadowDepth='2' Opacity='0.1' Color='Black'/>
                </Border.Effect>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height='Auto'/>
                        <RowDefinition Height='*'/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row='0'
                            Name='treeHeaderBorder'
                            Background='{DynamicResource HeaderBackgroundBrush}'
                            Padding='16,12'
                            CornerRadius='8,8,0,0'>
                        <StackPanel>
                            <TextBlock Name='treeTitleTextBlock'
                                       Text='📁 Policy Structure'
                                       FontSize='15'
                                       FontWeight='SemiBold'
                                       Foreground='{DynamicResource HeaderTextBrush}'/>
                            <TextBlock Name='breadcrumbTextBlock'
                                       Text='Select a policy to see its path'
                                       FontSize='11'
                                       Foreground='{DynamicResource SecondaryTextBrush}'
                                       Margin='0,4,0,0'
                                       TextTrimming='CharacterEllipsis'/>
                        </StackPanel>
                    </Border>

                    <TreeView Name='treeView' Grid.Row='1' Margin='8'>
                        <TreeView.ContextMenu>
                            <ContextMenu Name='treeViewContextMenu'>
                                <MenuItem Name='enableMenuItem' Header='✅ Enable this parameter'/>
                                <MenuItem Name='disableMenuItem' Header='❌ Disable this parameter'/>
                                <Separator/>
                                <MenuItem Name='createGpoMenuItem' Header='➕ Create a GPO'/>
                            </ContextMenu>
                        </TreeView.ContextMenu>
                    </TreeView>
                </Grid>
            </Border>

            <!-- Splitter -->
            <GridSplitter Grid.Column='1'
                         Width='6'
                         HorizontalAlignment='Center'
                         VerticalAlignment='Stretch'
                         Background='Transparent'
                         ShowsPreview='True'/>

            <!-- Details Panel -->
            <Border Grid.Column='2'
                    Background='{DynamicResource BackgroundBrush}'
                    Margin='8,16,16,16'
                    CornerRadius='8'
                    BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}'>
                <Border.Effect>
                    <DropShadowEffect BlurRadius='10' ShadowDepth='2' Opacity='0.1' Color='Black'/>
                </Border.Effect>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height='Auto'/>
                        <RowDefinition Height='*'/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row='0'
                            Name='detailsHeaderBorder'
                            Background='{DynamicResource HeaderBackgroundBrush}'
                            Padding='16,12'
                            CornerRadius='8,8,0,0'>
                        <TextBlock Name='detailsTitleTextBlock'
                                   Text='ℹ️ Policy Details'
                                   FontSize='15'
                                   FontWeight='SemiBold'
                                   Foreground='{DynamicResource HeaderTextBrush}'/>
                    </Border>

                    <ScrollViewer Grid.Row='1'
                                 VerticalScrollBarVisibility='Auto'
                                 Padding='16'>
                        <StackPanel Name='detailsPanel'>
                            <TextBlock Text='Display Name' Style='{StaticResource LabelStyle}'/>
                            <TextBox Name='displayNameTextBox' Style='{StaticResource ReadOnlyTextBox}'/>

                            <TextBlock Text='Description' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <TextBox Name='descriptionTextBox'
                                    Style='{StaticResource ReadOnlyTextBox}'
                                    MinHeight='60'
                                    MaxHeight='120'
                                    VerticalScrollBarVisibility='Auto'/>

                            <TextBlock Text='Scope' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <TextBox Name='scopeTextBox' Style='{StaticResource ReadOnlyTextBox}'/>

                            <TextBlock Text='Registry Path' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <TextBox Name='registryPathTextBox' Style='{StaticResource ReadOnlyTextBox}'/>

                            <TextBlock Text='Registry Key' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <TextBox Name='registryKeyTextBox' Style='{StaticResource ReadOnlyTextBox}'/>

                            <TextBlock Text='Registry Values' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <DataGrid Name='registryValuesGrid'
                                     AutoGenerateColumns='False'
                                     IsReadOnly='True'
                                     MaxHeight='200'
                                     Margin='0,0,0,16'>
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

        $xmlDocument = New-Object System.Xml.XmlDocument
        $xmlDocument.LoadXml($xaml)
        $reader = New-Object System.Xml.XmlNodeReader $xmlDocument
        $window = [Windows.Markup.XamlReader]::Load($reader)

    $treeView = $window.FindName("treeView")
    $themeToggleButton = $window.FindName("themeToggleButton")
    $treeTitleTextBlock = $window.FindName("treeTitleTextBlock")
    $detailsTitleTextBlock = $window.FindName("detailsTitleTextBlock")

    # Theme management
    $isDarkTheme = $false

    function Set-Theme {
        param([bool]$dark)

        $resources = $window.Resources

        if ($dark) {
            # Dark Theme - Improved colors
            $resources['PrimaryBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0086F0')
            $resources['PrimaryHoverBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#3399FF')
            $resources['PrimaryPressedBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0066CC')
            $resources['AccentBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#00D4FF')
            $resources['BackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1E1E1E')
            $resources['SecondaryBackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#2D2D30')
            $resources['BorderBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#3F3F46')
            $resources['TextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')
            $resources['SecondaryTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#CCCCCC')
            $resources['TreeViewSelectedBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0086F0')
            $resources['TreeViewSelectedTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')
            $resources['TreeViewHoverBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#2D2D30')
            $resources['IconFolderBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFD700')
            $resources['IconFileBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#64B5F6')
            $resources['IconScopeBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#81C784')
            $resources['HeaderBackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#252526')
            $resources['HeaderTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')

            $window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1E1E1E')
            $themeToggleButton.Content = '☀️ Mode Clair'

            # Update header backgrounds
            $treeHeaderBorder = $window.FindName("treeHeaderBorder")
            $detailsHeaderBorder = $window.FindName("detailsHeaderBorder")
            if ($treeHeaderBorder) {
                $treeHeaderBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#252526')
            }
            if ($detailsHeaderBorder) {
                $detailsHeaderBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#252526')
            }
        } else {
            # Light Theme
            $resources['PrimaryBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0078D4')
            $resources['PrimaryHoverBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#106EBE')
            $resources['PrimaryPressedBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#005A9E')
            $resources['AccentBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#00BCF2')
            $resources['BackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')
            $resources['SecondaryBackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F5F5F5')
            $resources['BorderBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#E1E1E1')
            $resources['TextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1F1F1F')
            $resources['SecondaryTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#605E5C')
            $resources['TreeViewSelectedBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0078D4')
            $resources['TreeViewSelectedTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')
            $resources['TreeViewHoverBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F3F2F1')
            $resources['IconFolderBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FDB900')
            $resources['IconFileBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0078D4')
            $resources['IconScopeBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#107C10')
            $resources['HeaderBackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F3F2F1')
            $resources['HeaderTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1F1F1F')

            $window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F5F5F5')
            $themeToggleButton.Content = '🌙 Mode Sombre'

            # Update header backgrounds
            $treeHeaderBorder = $window.FindName("treeHeaderBorder")
            $detailsHeaderBorder = $window.FindName("detailsHeaderBorder")
            if ($treeHeaderBorder) {
                $treeHeaderBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F3F2F1')
            }
            if ($detailsHeaderBorder) {
                $detailsHeaderBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F3F2F1')
            }
        }
    }

    $themeToggleButton.Add_Click({
        $script:isDarkTheme = -not $script:isDarkTheme
        Set-Theme -dark $script:isDarkTheme
    })

    # Get context menu items from XAML
    $enableMenuItem = $window.FindName("enableMenuItem")
    $disableMenuItem = $window.FindName("disableMenuItem")
    $createGpoMenuItem = $window.FindName("createGpoMenuItem")

    # Add click handlers to menu items
    if ($enableMenuItem) {
        $enableMenuItem.Add_Click({
            $selectedItem = $treeView.SelectedItem
            if ($selectedItem -and $selectedItem.Tag -is [GPOToolsPolicy]) {
                Write-Host "Enable: $($selectedItem.Tag.DisplayName)"
            }
        })
    }

    if ($disableMenuItem) {
        $disableMenuItem.Add_Click({
            $selectedItem = $treeView.SelectedItem
            if ($selectedItem -and $selectedItem.Tag -is [GPOToolsPolicy]) {
                Write-Host "Disable: $($selectedItem.Tag.DisplayName)"
            }
        })
    }

    if ($createGpoMenuItem) {
        $createGpoMenuItem.Add_Click({
            $selectedItem = $treeView.SelectedItem
            if ($selectedItem -and $selectedItem.Tag -is [GPOToolsPolicy]) {
                Write-Host "Create GPO for: $($selectedItem.Tag.DisplayName)"
            }
        })
    }

    $displayNameTextBox = $window.FindName("displayNameTextBox")
    $descriptionTextBox = $window.FindName("descriptionTextBox")
    $scopeTextBox = $window.FindName("scopeTextBox")
    $registryPathTextBox = $window.FindName("registryPathTextBox")
    $registryKeyTextBox = $window.FindName("registryKeyTextBox")
    $registryValuesGrid = $window.FindName("registryValuesGrid")
    $searchTextBox = $window.FindName("searchTextBox")
    $searchButton = $window.FindName("searchButton")
    $breadcrumbTextBlock = $window.FindName("breadcrumbTextBlock")

    $treeView.add_SelectedItemChanged({
        $selectedItem = $treeView.SelectedItem
        if ($selectedItem -is [Windows.Controls.TreeViewItem]) {
            $policy = $selectedItem.Tag

            # Build breadcrumb path
            $breadcrumbPath = ""
            $currentItem = $selectedItem
            $pathParts = @()

            while ($currentItem -ne $null) {
                if ($currentItem.Tag -is [GPOToolsPolicy]) {
                    $pathParts = @($currentItem.Tag.DisplayName) + $pathParts
                } elseif ($currentItem.Tag -is [GPOToolsCategory]) {
                    $pathParts = @($currentItem.Tag.DisplayName) + $pathParts
                } elseif ($currentItem.Tag -is [ScopePolicy]) {
                    $pathParts = @($currentItem.Tag.ToString()) + $pathParts
                }
                $currentItem = $currentItem.Parent
                if ($currentItem -isnot [Windows.Controls.TreeViewItem]) {
                    break
                }
            }

            $breadcrumbPath = $pathParts -join ' > '
            if ($breadcrumbPath) {
                $breadcrumbTextBlock.Text = "📍 $breadcrumbPath"
            } else {
                $breadcrumbTextBlock.Text = "Select a policy to see its path"
            }

            if ($policy -is [GPOToolsPolicy]) {
                $displayNameTextBox.Text = $policy.DisplayName
                $descriptionTextBox.Text = if ($policy.Description) { $policy.Description } else { "(Aucune description disponible)" }
                $scopeTextBox.Text = $policy.Scope.ToString()

                # Handle registry information with null checks
                if ($policy.Registry) {
                    $registryPathTextBox.Text = if ($policy.Registry.Path) { $policy.Registry.Path } else { "(Aucun chemin de registre défini)" }
                    $registryKeyTextBox.Text = if ($policy.Registry.Key) { $policy.Registry.Key } else { "(Aucune clé de registre définie)" }

                    # Populate registry values in the DataGrid
                    if ($policy.Registry.Value -and $policy.Registry.Value.Keys.Count -gt 0) {
                        $registryValuesGrid.ItemsSource = @(
                            foreach ($key in $policy.Registry.Value.Keys) {
                                [PSCustomObject]@{
                                    Key   = $key
                                    Value = if ($policy.Registry.Value[$key]) { $policy.Registry.Value[$key] } else { "(Valeur non définie)" }
                                }
                            }
                        )
                    } else {
                        $registryValuesGrid.ItemsSource = @(
                            [PSCustomObject]@{
                                Key   = "Information"
                                Value = "(Aucune valeur de registre disponible pour cette GPO)"
                            }
                        )
                    }
                } else {
                    $registryPathTextBox.Text = "(Cette GPO ne nécessite pas de configuration de registre)"
                    $registryKeyTextBox.Text = "(Aucune clé de registre)"
                    $registryValuesGrid.ItemsSource = @(
                        [PSCustomObject]@{
                            Key   = "Information"
                            Value = "(Cette policy ne stocke pas de données dans le registre)"
                        }
                    )
                }
            } else {
                $displayNameTextBox.Text = ""
                $descriptionTextBox.Text = ""
                $scopeTextBox.Text = ""
                $registryPathTextBox.Text = ""
                $registryKeyTextBox.Text = ""
                $registryValuesGrid.ItemsSource = $null
            }
        }
    })

    function Populate-TreeView {
        param(
            [string]$Filter = ''
        )
        $treeView.Items.Clear()
        $scopes = [Enum]::GetValues([ScopePolicy])
        foreach ($scope in $scopes) {
            $scopeItem = New-Object Windows.Controls.TreeViewItem

            # Create StackPanel for icon + text
            $scopePanel = New-Object Windows.Controls.StackPanel
            $scopePanel.Orientation = 'Horizontal'

            $scopeIcon = New-Object Windows.Controls.TextBlock
            $scopeIcon.Text = '📋 '
            $scopeIcon.FontSize = 14
            $scopeIcon.Foreground = $window.Resources['IconScopeBrush']

            $scopeText = New-Object Windows.Controls.TextBlock
            $scopeText.Text = $scope.ToString()
            $scopeText.FontWeight = 'SemiBold'

            $scopePanel.Children.Add($scopeIcon) | Out-Null
            $scopePanel.Children.Add($scopeText) | Out-Null
            $scopeItem.Header = $scopePanel
            $scopeItem.Tag = $scope

            $policies = Get-PSGPOPolicy -Scope $scope
            if ($Filter -and $Filter -ne '' -and $Filter -ne 'Rechercher une GPO...') {
                $policies = $policies | Where-Object { $_.DisplayName -like "*$Filter*" }
            }

            foreach ($policy in $policies) {
                $category = $policy.Category
                $parentCategory = $category.ParentCategory
                $currentItem = $scopeItem

                while ($null -ne $parentCategory) {
                    # Check if category already exists
                    $existingItem = $null
                    foreach ($item in $currentItem.Items) {
                        if ($item.Tag -and $item.Tag.DisplayName -eq $parentCategory.DisplayName) {
                            $existingItem = $item
                            break
                        }
                    }

                    if (-not $existingItem) {
                        $newItem = New-Object Windows.Controls.TreeViewItem

                        # Create StackPanel for folder icon + text
                        $folderPanel = New-Object Windows.Controls.StackPanel
                        $folderPanel.Orientation = 'Horizontal'

                        $folderIcon = New-Object Windows.Controls.TextBlock
                        $folderIcon.Text = '📂 '
                        $folderIcon.FontSize = 13
                        $folderIcon.Foreground = $window.Resources['IconFolderBrush']

                        $folderText = New-Object Windows.Controls.TextBlock
                        $folderText.Text = $parentCategory.DisplayName

                        $folderPanel.Children.Add($folderIcon) | Out-Null
                        $folderPanel.Children.Add($folderText) | Out-Null
                        $newItem.Header = $folderPanel
                        $newItem.Tag = $parentCategory

                        $currentItem.Items.Add($newItem) | Out-Null
                        $currentItem = $newItem
                    } else {
                        $currentItem = $existingItem
                    }
                    $parentCategory = $parentCategory.ParentCategory
                }

                $policyItem = New-Object Windows.Controls.TreeViewItem

                # Create StackPanel for file icon + text
                $policyPanel = New-Object Windows.Controls.StackPanel
                $policyPanel.Orientation = 'Horizontal'

                $policyIcon = New-Object Windows.Controls.TextBlock
                $policyIcon.Text = '📄 '
                $policyIcon.FontSize = 13
                $policyIcon.Foreground = $window.Resources['IconFileBrush']

                $policyText = New-Object Windows.Controls.TextBlock
                $policyText.Text = $policy.DisplayName

                $policyPanel.Children.Add($policyIcon) | Out-Null
                $policyPanel.Children.Add($policyText) | Out-Null
                $policyItem.Header = $policyPanel
                $policyItem.Tag = $policy

                $currentItem.Items.Add($policyItem) | Out-Null
            }

            if ($scopeItem.Items.Count -gt 0) {
                $treeView.Items.Add($scopeItem) | Out-Null
            }
        }
    }

    # Initial population

    Populate-TreeView

    # Modern search functionality with placeholder behavior
    $searchPlaceholder = "Rechercher une GPO..."

    $searchTextBox.Add_GotFocus({
        if ($searchTextBox.Text -eq $searchPlaceholder) {
            $searchTextBox.Text = ""
            $searchTextBox.Foreground = [System.Windows.Media.Brushes]::Black
        }
    })

    $searchTextBox.Add_LostFocus({
        if ([string]::IsNullOrWhiteSpace($searchTextBox.Text)) {
            $searchTextBox.Text = $searchPlaceholder
            $searchTextBox.Foreground = [System.Windows.Media.Brushes]::Gray
        }
    })

    $searchButton.Add_Click({
        $filter = $searchTextBox.Text
        if ($filter -ne $searchPlaceholder) {
            Populate-TreeView -Filter $filter
        } else {
            Populate-TreeView
        }
    })

    $searchTextBox.Add_KeyDown({
        if ($_.Key -eq 'Return') {
            $filter = $searchTextBox.Text
            if ($filter -ne $searchPlaceholder) {
                Populate-TreeView -Filter $filter
            } else {
                Populate-TreeView
            }
        }
    })

    # Set window icon if available
    try {
        $window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]::new("pack://application:,,,/icon.ico"))
    } catch {
        # Icon not found, continue without it
    }

    $window.ShowDialog() | Out-Null
}
