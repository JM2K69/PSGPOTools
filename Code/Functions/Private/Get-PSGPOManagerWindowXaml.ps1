<#
    XAML of the Show-GPOManagerAvalonia window (Start-PSGPOManagerWindow).
#>

function Get-PSGPOManagerWindowXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Icons of Resources/Icons as geometry resources: {StaticResource Icon.<name>}
    $iconResources = (Get-PSGPOIconName | ForEach-Object {
        "            <StreamGeometry x:Key='Icon.$_'>$(Get-PSGPOIconData -Name $_)</StreamGeometry>"
    }) -join [Environment]::NewLine

    @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='GPO Policy Manager'
        Width='1200' Height='700'
        MinWidth='800' MinHeight='500'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='MainWindow'>

    <Window.Styles>
        <Style Selector='PathIcon'>
            <Setter Property='Width' Value='16'/>
            <Setter Property='Height' Value='16'/>
        </Style>
    </Window.Styles>

    <Window.Resources>
        <ResourceDictionary>
$iconResources
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

    <Grid RowDefinitions='Auto,*,Auto'>

        <!-- Header: title, view switch, theme toggle, search (policy editor only) -->
        <Border Grid.Row='0'
                Background='{DynamicResource BackgroundBrush}'
                BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}'
                Padding='20,16'>
            <Grid ColumnDefinitions='Auto,*'>
                <StackPanel Grid.Column='0' VerticalAlignment='Center'>
                    <TextBlock Text='GPO Policy Manager' FontSize='22' FontWeight='Bold'
                               Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Name='subtitleTextBlock' Text='Explore and manage Group Policy Objects' FontSize='12'
                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,2,0,0'/>
                </StackPanel>

                <StackPanel Grid.Column='1' Orientation='Horizontal'
                            HorizontalAlignment='Right' VerticalAlignment='Center' Spacing='12'>
                    <Button Name='managementButton' Height='36'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.organization}'/>
                            <TextBlock Text='Group Policy Management' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='browseAdmxButton' Height='36'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.book}'/>
                            <TextBlock Text='Browse the ADMX policies' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='configurationButton' Height='36' ToolTip.Tip='Configuration of PSGPOTools (Configuration.psd1)'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.settings}'/>
                            <TextBlock Text='Settings' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='themeToggleButton' Height='36' Width='140'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Name='themeToggleIcon' Data='{StaticResource Icon.weather-moon}'/>
                            <TextBlock Name='themeToggleText' Text='Dark mode' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <StackPanel Name='searchPanel' Orientation='Horizontal' Spacing='12'>
                        <TextBox Name='searchTextBox' Width='320' Height='36'
                                 Watermark='Search a policy...' VerticalContentAlignment='Center'/>
                        <Button Name='searchButton' Height='36' Width='130'>
                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                <PathIcon Data='{StaticResource Icon.search}'/>
                                <TextBlock Text='Search' VerticalAlignment='Center'/>
                            </StackPanel>
                        </Button>
                    </StackPanel>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Group Policy Management view: domain tree | Splitter | details of the selection -->
        <Grid Grid.Row='1' Name='managementView' ColumnDefinitions='2*,Auto,3*' RowDefinitions='Auto,*' IsVisible='False'>

            <!-- Shown when no domain was discovered and the sample directory is displayed -->
            <Border Grid.Row='0' Grid.ColumnSpan='3' Name='demoBanner' IsVisible='False' Margin='16,16,16,0' Padding='12,8'
                    CornerRadius='6' Background='#FFF4CE' BorderThickness='1' BorderBrush='#F2C94C'>
                <StackPanel Orientation='Horizontal' Spacing='8'>
                    <PathIcon Data='{StaticResource Icon.info}' Foreground='#8A6100'/>
                    <StackPanel>
                        <TextBlock Name='demoBannerTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='#3D2C00'
                                   Text='Demonstration environment: no Active Directory or Samba AD domain discovered'/>
                        <TextBlock FontSize='11' TextWrapping='Wrap' Foreground='#3D2C00'
                                   Text='The domain shown is sample data and its changes stay in memory. Read a domain with Show-GPOManagerAvalonia -Server, or from a computer of the domain.'/>
                    </StackPanel>
                </StackPanel>
            </Border>


            <Border Grid.Row='1' Grid.Column='0'
                    Background='{DynamicResource BackgroundBrush}'
                    Margin='16,16,8,16' CornerRadius='8' BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}'
                    BoxShadow='0 2 10 0 #1A000000'>
                <Grid RowDefinitions='Auto,*'>
                    <Border Grid.Row='0'
                            Background='{DynamicResource HeaderBackgroundBrush}'
                            Padding='16,12' CornerRadius='8,8,0,0'>
                        <StackPanel>
                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                <PathIcon Data='{StaticResource Icon.organization}' Foreground='{DynamicResource HeaderTextBrush}'/>
                                <TextBlock Text='Group Policy Management' FontSize='15' FontWeight='SemiBold'
                                           Foreground='{DynamicResource HeaderTextBrush}'/>
                            </StackPanel>
                            <Grid ColumnDefinitions='Auto,*' Margin='0,4,0,0'>
                                <PathIcon Grid.Column='0' Data='{StaticResource Icon.location}' Width='12' Height='12'
                                          Margin='0,0,4,0' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <TextBlock Grid.Column='1' Name='directoryBreadcrumbTextBlock' Text='Right-click a domain or an OU to create a GPO'
                                           FontSize='11' Foreground='{DynamicResource SecondaryTextBrush}' TextTrimming='CharacterEllipsis'/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <TextBlock Grid.Row='1' Name='directoryEmptyTextBlock' Margin='16' TextWrapping='Wrap'
                               Foreground='{DynamicResource SecondaryTextBrush}'
                               Text='No directory loaded: read the domain with Get-PSGPODirectory (or a JSON description with Import-PSGPODirectory), then open the window with Show-GPOManagerAvalonia -Directory.'/>
                    <TreeView Grid.Row='1' Name='domainTreeView' Margin='8' ScrollViewer.HorizontalScrollBarVisibility='Disabled'>
                        <TreeView.Styles>
                            <Style Selector='TreeViewItem'>
                                <Setter Property='IsExpanded' Value='{Binding IsExpanded, Mode=TwoWay}'/>
                            </Style>
                        </TreeView.Styles>
                        <TreeView.ItemTemplate>
                            <TreeDataTemplate ItemsSource='{Binding Children}'>
                                <Grid ColumnDefinitions='Auto,*'>
                                    <PathIcon Grid.Column='0' Data='{Binding IconData}' Foreground='{Binding IconBrush}' VerticalAlignment='Center' Margin='0,0,6,0'/>
                                    <TextBlock Grid.Column='1' Text='{Binding Header}' TextTrimming='CharacterEllipsis' ToolTip.Tip='{Binding Header}'/>
                                </Grid>
                            </TreeDataTemplate>
                        </TreeView.ItemTemplate>
                        <TreeView.ContextMenu>
                            <ContextMenu Name='domainContextMenu'>
                                <MenuItem Name='createLinkedGpoMenuItem' Header='Create a GPO in this domain, and Link it here...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.add}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='linkGpoMenuItem' Header='Link an Existing GPO...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.link}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='newGpoMenuItem' Header='New GPO...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.add}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='editGpoMenuItem' Header='Edit...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.edit}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='deleteLinkMenuItem' Header='Delete link...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.link-dismiss}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='deleteGpoMenuItem' Header='Delete GPO...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.delete}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='restoreDeletedGpoMenuItem' Header='Restore...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.arrow-undo}'/></MenuItem.Icon>
                                </MenuItem>
                            </ContextMenu>
                        </TreeView.ContextMenu>
                    </TreeView>
                </Grid>
            </Border>

            <GridSplitter Grid.Row='1' Grid.Column='1' Width='6' HorizontalAlignment='Center'
                          VerticalAlignment='Stretch' Background='Transparent'/>

            <Border Grid.Row='1' Grid.Column='2'
                    Background='{DynamicResource BackgroundBrush}'
                    Margin='8,16,16,16' CornerRadius='8' BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}'
                    BoxShadow='0 2 10 0 #1A000000'>
                <Grid RowDefinitions='Auto,*'>
                    <Border Grid.Row='0'
                            Background='{DynamicResource HeaderBackgroundBrush}'
                            Padding='16,12' CornerRadius='8,8,0,0'>
                        <TextBlock Name='directoryTitleTextBlock' Text='Select an item in the tree' FontSize='15' FontWeight='SemiBold'
                                   TextWrapping='Wrap' Foreground='{DynamicResource HeaderTextBrush}'/>
                    </Border>

                    <!-- Details of the selection; Settings: the configured settings of a GPO, as GPMC -->
                    <TabControl Grid.Row='1' Name='directoryTabs' Margin='8,0,8,8'>
                        <TabItem Header='Details'>
                            <ScrollViewer>
                                <StackPanel Margin='16,8'>
                                    <!-- New GPO form, opened from the context menu -->
                                    <Border Name='newGpoPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='newGpoTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap'
                                                       Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='newGpoNameTextBox' Watermark='Name of the new GPO'/>
                                            <!-- GPO status (flags of the GPO), as GPMC: the configuration it applies -->
                                            <Grid ColumnDefinitions='Auto,*'>
                                                <TextBlock Text='GPO status' VerticalAlignment='Center' Margin='0,0,12,0'
                                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <ComboBox Grid.Column='1' Name='newGpoStatusComboBox' SelectedIndex='0' HorizontalAlignment='Stretch'>
                                                    <ComboBoxItem Content='Enabled: computer and user settings' Tag='0'/>
                                                    <ComboBoxItem Content='Computer settings only (user configuration disabled)' Tag='1'/>
                                                    <ComboBoxItem Content='User settings only (computer configuration disabled)' Tag='2'/>
                                                </ComboBox>
                                            </Grid>
                                            <!-- Template: a backup whose settings the GPO starts with -->
                                            <Grid ColumnDefinitions='Auto,*'>
                                                <TextBlock Text='Start from' VerticalAlignment='Center' Margin='0,0,12,0'
                                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <ComboBox Grid.Column='1' Name='newGpoTemplateComboBox' HorizontalAlignment='Stretch'
                                                          ToolTip.Tip='A backup labelled as a template (History tab): the new GPO starts with its settings'/>
                                            </Grid>
                                            <!-- Security filtering groups APPLY_<GPO> and DENY_<GPO> -->
                                            <CheckBox Name='newGpoGroupsCheckBox' Content='Create the security filtering groups'/>
                                            <StackPanel Name='newGpoGroupsPanel' Spacing='6' Margin='28,0,0,0' IsVisible='False'>
                                                <TextBlock Name='newGpoGroupsTextBlock' TextWrapping='Wrap' FontSize='12'
                                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <Grid ColumnDefinitions='Auto,*'>
                                                    <TextBlock Text='Groups in' VerticalAlignment='Center' Margin='0,0,12,0'
                                                               Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                    <ComboBox Grid.Column='1' Name='newGpoGroupsContainerComboBox' HorizontalAlignment='Stretch'/>
                                                </Grid>
                                            </StackPanel>
                                            <TextBlock Name='newGpoErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='newGpoCreateButton' Content='Create' Width='100'/>
                                                <Button Name='newGpoCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Confirmation of the deletion of a link, as GPMC asks for it -->
                                    <Border Name='deleteLinkPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='#D13438'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='deleteLinkTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='deleteLinkConfirmButton' Content='Delete link' Width='120'/>
                                                <Button Name='deleteLinkCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Confirmation of the deletion of a GPO, backed up first -->
                                    <Border Name='deleteGpoPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='#D13438'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='deleteGpoTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='deleteGpoConfirmButton' Content='Delete GPO' Width='120'/>
                                                <Button Name='deleteGpoCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- A deleted GPO created again from its backup -->
                                    <Border Name='restoreGpoPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='restoreGpoTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <CheckBox Name='restoreGpoLinkCheckBox'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='restoreGpoConfirmButton' Content='Restore' Width='110'/>
                                                <Button Name='restoreGpoCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Link of an existing GPO of the domain to the selected domain or OU, as GPMC -->
                                    <Border Name='linkGpoPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='linkGpoTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap'
                                                       Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='linkGpoFilterTextBox' Watermark='Search a GPO'/>
                                            <ListBox Name='linkGpoList' MaxHeight='240' SelectionMode='Single'>
                                                <ListBox.ItemTemplate>
                                                    <DataTemplate>
                                                        <TextBlock Text='{Binding DisplayName}' TextTrimming='CharacterEllipsis'/>
                                                    </DataTemplate>
                                                </ListBox.ItemTemplate>
                                            </ListBox>
                                            <TextBlock Name='linkGpoErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='linkGpoConfirmButton' Content='Link' Width='100' IsEnabled='False'/>
                                                <Button Name='linkGpoCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- What the last change of the directory did, and what failed -->
                                    <TextBlock Name='directoryResultTextBlock' TextWrapping='Wrap' Margin='0,8,0,0'
                                               IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>

                                    <Button Name='editGpoButton' IsVisible='False' Margin='0,8,0,8'>
                                        <StackPanel Orientation='Horizontal' Spacing='8'>
                                            <PathIcon Data='{StaticResource Icon.edit}'/>
                                            <TextBlock Text='Edit this GPO' VerticalAlignment='Center'/>
                                        </StackPanel>
                                    </Button>
                                    <Button Name='restoreDeletedGpoButton' IsVisible='False' Margin='0,8,0,8'>
                                        <StackPanel Orientation='Horizontal' Spacing='8'>
                                            <PathIcon Data='{StaticResource Icon.arrow-undo}'/>
                                            <TextBlock Text='Restore this GPO...' VerticalAlignment='Center'/>
                                        </StackPanel>
                                    </Button>

                                    <ItemsControl Name='directoryPropertiesList'>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <Grid ColumnDefinitions='180,*' Margin='0,3'>
                                                    <TextBlock Grid.Column='0' Text='{Binding Key}' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                    <SelectableTextBlock Grid.Column='1' Text='{Binding Value}' TextWrapping='Wrap'/>
                                                </Grid>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>

                                    <TextBlock Name='linksHeaderTextBlock' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <ItemsControl Name='linksList'>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <Border BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}' Padding='0,6'>
                                                    <Grid ColumnDefinitions='Auto,*' RowDefinitions='Auto,Auto,Auto'>
                                                        <TextBlock Grid.Row='0' Grid.Column='0' Text='{Binding Order}' FontWeight='SemiBold' Margin='0,0,12,0'/>
                                                        <TextBlock Grid.Row='0' Grid.Column='1' Text='{Binding Name}' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                                        <TextBlock Grid.Row='1' Grid.Column='1' Text='{Binding Location}' TextWrapping='Wrap' IsVisible='{Binding Location, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'
                                                                   Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        <StackPanel Grid.Row='2' Grid.Column='1' Orientation='Horizontal' Spacing='16'>
                                                            <TextBlock Text='{Binding Enforced}'/>
                                                            <TextBlock Text='{Binding LinkEnabled}'/>
                                                            <TextBlock Text='{Binding Status}' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>
                                </StackPanel>
                            </ScrollViewer>
                        </TabItem>
                        <TabItem Name='settingsTab' Header='Settings' IsVisible='False'>
                            <ScrollViewer>
                                <StackPanel Margin='16,8' Spacing='4'>
                                    <TextBlock Name='settingsStatusTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <TextBlock Name='computerSettingsHeader' FontSize='14' FontWeight='SemiBold' Margin='0,8,0,0' Foreground='{DynamicResource TextBrush}'/>
                                    <ItemsControl Name='computerSettingsList'>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <Border BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}' Padding='0,6'>
                                                    <StackPanel Spacing='2'>
                                                        <TextBlock Text='{Binding Path}' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        <Grid ColumnDefinitions='*,Auto'>
                                                            <SelectableTextBlock Grid.Column='0' Text='{Binding Name}' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                                            <TextBlock Grid.Column='1' Text='{Binding State}' Margin='12,0,0,0'/>
                                                        </Grid>
                                                        <SelectableTextBlock Text='{Binding Options}' TextWrapping='Wrap' Margin='12,2,0,0'
                                                                             IsVisible='{Binding Options, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                                    </StackPanel>
                                                </Border>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>
                                    <TextBlock Name='userSettingsHeader' FontSize='14' FontWeight='SemiBold' Margin='0,16,0,0' Foreground='{DynamicResource TextBrush}'/>
                                    <ItemsControl Name='userSettingsList'>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <Border BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}' Padding='0,6'>
                                                    <StackPanel Spacing='2'>
                                                        <TextBlock Text='{Binding Path}' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        <Grid ColumnDefinitions='*,Auto'>
                                                            <SelectableTextBlock Grid.Column='0' Text='{Binding Name}' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                                            <TextBlock Grid.Column='1' Text='{Binding State}' Margin='12,0,0,0'/>
                                                        </Grid>
                                                        <SelectableTextBlock Text='{Binding Options}' TextWrapping='Wrap' Margin='12,2,0,0'
                                                                             IsVisible='{Binding Options, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                                    </StackPanel>
                                                </Border>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>
                                </StackPanel>
                            </ScrollViewer>
                        </TabItem>
                        <!-- History of the GPO: its backups as a timeline (oldest on the left), and what
                             changed at the selected one -->
                        <TabItem Name='historyTab' Header='History' IsVisible='False'>
                            <Grid RowDefinitions='Auto,Auto,Auto,Auto,Auto,*' Margin='16,8'>
                                <Grid Grid.Row='0' ColumnDefinitions='Auto,*,Auto,Auto'>
                                    <TextBlock Text='Backups in' VerticalAlignment='Center' Margin='0,0,8,0'
                                               Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <TextBox Grid.Column='1' Name='historyPathTextBox' Watermark='Folder of the backups'/>
                                    <Button Grid.Column='2' Name='historyBackupButton' Margin='8,0,0,0'
                                            ToolTip.Tip='Back up this GPO, when it changed since its last backup'>
                                        <StackPanel Orientation='Horizontal' Spacing='6'>
                                            <PathIcon Data='{StaticResource Icon.save}' Width='14' Height='14'/>
                                            <TextBlock Text='Back up now' VerticalAlignment='Center'/>
                                        </StackPanel>
                                    </Button>
                                    <Button Grid.Column='3' Name='historyBackupAllButton' Content='Back up all GPOs' Margin='8,0,0,0'
                                            ToolTip.Tip='Back up every GPO shown that changed since its last backup'/>
                                </Grid>
                                <TextBox Grid.Row='1' Name='historyCommentTextBox' Margin='0,8,0,0'
                                         Watermark='Comment of the next backup (optional): why the GPO changed, the ticket of the change'/>
                                <TextBlock Grid.Row='2' Name='historyStatusTextBlock' TextWrapping='Wrap' Margin='0,8,0,0'
                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <!-- The GPO compared to its approved version: what changed since, here or elsewhere -->
                                <Border Grid.Row='3' Name='historyDriftBorder' IsVisible='False' Margin='0,8,0,0' Padding='10,6'
                                        CornerRadius='4' BorderThickness='1' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                    <Grid ColumnDefinitions='*,Auto'>
                                        <TextBlock Name='historyDriftTextBlock' TextWrapping='Wrap' VerticalAlignment='Center'
                                                   Foreground='{DynamicResource TextBrush}'/>
                                        <Button Grid.Column='1' Name='historyDriftButton' Content='Show the changes' Margin='8,0,0,0' IsVisible='False'
                                                ToolTip.Tip='What changed from the approved version to the GPO now'/>
                                    </Grid>
                                </Border>
                                <ScrollViewer Grid.Row='4' Name='historyTimelineScrollViewer' Margin='0,8,0,0'
                                              HorizontalScrollBarVisibility='Auto' VerticalScrollBarVisibility='Disabled'>
                                    <ListBox Name='historyTimelineList' Background='Transparent' Margin='0,0,0,14'>
                                        <ListBox.ItemsPanel>
                                            <ItemsPanelTemplate><StackPanel Orientation='Horizontal'/></ItemsPanelTemplate>
                                        </ListBox.ItemsPanel>
                                        <ListBox.Styles>
                                            <Style Selector='ListBoxItem'>
                                                <Setter Property='Padding' Value='0'/>
                                                <Setter Property='Margin' Value='0'/>
                                            </Style>
                                        </ListBox.Styles>
                                        <ListBox.ItemTemplate>
                                            <DataTemplate>
                                                <Grid Width='150' RowDefinitions='24,Auto,Auto,Auto,Auto' Margin='0,6' Background='Transparent'
                                                      ToolTip.Tip='{Binding Comment}'>
                                                    <!-- The branch, through the node, as a git graph -->
                                                    <Rectangle Grid.Row='0' Height='3' VerticalAlignment='Center' Fill='{Binding LineBrush}'/>
                                                    <Ellipse Grid.Row='0' Width='18' Height='18' HorizontalAlignment='Center'
                                                             Fill='{Binding NodeFill}' Stroke='{Binding NodeStroke}' StrokeThickness='3'/>
                                                    <TextBlock Grid.Row='1' Text='{Binding Title}' FontSize='11' FontWeight='SemiBold' HorizontalAlignment='Center' Margin='0,4,0,0'/>
                                                    <TextBlock Grid.Row='2' Text='{Binding Subtitle}' FontSize='11' HorizontalAlignment='Center'
                                                               Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                    <TextBlock Grid.Row='3' Text='{Binding Summary}' FontSize='11' HorizontalAlignment='Center'/>
                                                    <TextBlock Grid.Row='4' Text='{Binding LabelsText}' FontSize='10' FontWeight='SemiBold' HorizontalAlignment='Center'
                                                               TextTrimming='CharacterEllipsis' Margin='4,2,4,0' Foreground='{Binding LabelBrush}' IsVisible='{Binding HasLabels}'/>
                                                </Grid>
                                            </DataTemplate>
                                        </ListBox.ItemTemplate>
                                    </ListBox>
                                </ScrollViewer>
                                <ScrollViewer Grid.Row='5' Margin='0,8,0,0'>
                                    <StackPanel Spacing='4' Margin='0,0,12,0'>
                                        <Grid ColumnDefinitions='*,Auto'>
                                            <TextBlock Name='historyCompareTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' VerticalAlignment='Center'/>
                                            <Button Grid.Column='1' Name='historyRestoreButton' Content='Restore this version...' Margin='8,0,0,0' IsVisible='False'
                                                    ToolTip.Tip='Put the GPO back as this backup has it'/>
                                        </Grid>
                                        <!-- Notes of the selected backup: its comment, its labels, the approved version -->
                                        <Border Name='historyNotesPanel' IsVisible='False' Margin='0,4,0,4' Padding='10' CornerRadius='4'
                                                BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                            <StackPanel Spacing='6'>
                                                <TextBlock Name='historyNotesInfoTextBlock' FontSize='11' TextWrapping='Wrap'
                                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <TextBox Name='historyNotesCommentTextBox' AcceptsReturn='True' TextWrapping='Wrap' MinHeight='48'
                                                         Watermark='Comment of this backup'/>
                                                <Grid ColumnDefinitions='*,Auto,Auto,Auto'>
                                                    <TextBox Name='historyNotesLabelsTextBox' Watermark='Labels, separated by commas'/>
                                                    <CheckBox Grid.Column='1' Name='historyNotesApprovedCheckBox' Margin='12,0,0,0'
                                                              ToolTip.Tip='The approved version: the GPO is compared to it, to find what changed since'/>
                                                    <CheckBox Grid.Column='2' Name='historyNotesTemplateCheckBox' Margin='12,0,0,0'
                                                              ToolTip.Tip='A template: a new GPO can start with the settings of this backup'/>
                                                    <Button Grid.Column='3' Name='historyNotesSaveButton' Content='Save notes' Margin='8,0,0,0'/>
                                                </Grid>
                                            </StackPanel>
                                        </Border>
                                        <!-- Confirmation of a restore, as GPMC asks for it -->
                                        <Border Name='historyRestorePanel' IsVisible='False' Margin='0,4,0,4' Padding='12' CornerRadius='4'
                                                BorderThickness='1' BorderBrush='#D13438' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                            <StackPanel Spacing='8'>
                                                <TextBlock Name='historyRestoreTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                                <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                    <Button Name='historyRestoreConfirmButton' Content='Restore' Width='110'/>
                                                    <Button Name='historyRestoreCancelButton' Content='Cancel' Width='100'/>
                                                </StackPanel>
                                            </StackPanel>
                                        </Border>
                                        <ItemsControl Name='historyChangesList'>
                                            <ItemsControl.ItemTemplate>
                                                <DataTemplate>
                                                    <Border BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}' Padding='0,6'>
                                                        <Grid ColumnDefinitions='Auto,*'>
                                                            <Border Grid.Column='0' Background='{Binding ChangeBrush}' CornerRadius='3' Padding='6,1'
                                                                    VerticalAlignment='Top' Margin='0,2,10,0'>
                                                                <TextBlock Text='{Binding Change}' Foreground='White' FontSize='11' FontWeight='SemiBold'/>
                                                            </Border>
                                                            <StackPanel Grid.Column='1' Spacing='2'>
                                                                <TextBlock Text='{Binding Location}' FontSize='11' TextWrapping='Wrap'
                                                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                                <SelectableTextBlock Text='{Binding Name}' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                                                <SelectableTextBlock Text='{Binding Before}' TextWrapping='Wrap' Foreground='#D13438'
                                                                                     TextDecorations='Strikethrough' IsVisible='{Binding HasBefore}'/>
                                                                <SelectableTextBlock Text='{Binding After}' TextWrapping='Wrap' Foreground='#107C10'
                                                                                     IsVisible='{Binding HasAfter}'/>
                                                            </StackPanel>
                                                        </Grid>
                                                    </Border>
                                                </DataTemplate>
                                            </ItemsControl.ItemTemplate>
                                        </ItemsControl>
                                    </StackPanel>
                                </ScrollViewer>
                            </Grid>
                        </TabItem>
                    </TabControl>
                </Grid>
            </Border>
        </Grid>

        <!-- Policy editor view: banner of the edited GPO, then TreeView | Splitter | Details -->
        <Grid Grid.Row='1' Name='editorView' RowDefinitions='Auto,*'>
        <Border Grid.Row='0' Name='editingBanner' IsVisible='False' Margin='16,16,16,0' Padding='12,8' CornerRadius='6'
                Background='{DynamicResource SecondaryBackgroundBrush}' BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'>
            <StackPanel>
                <StackPanel Orientation='Horizontal' Spacing='8'>
                    <PathIcon Data='{StaticResource Icon.edit}' Foreground='{DynamicResource PrimaryBrush}'/>
                    <TextBlock Name='editingGpoTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                </StackPanel>
                <TextBlock Text='The setting of each policy is read from the GPO (Registry.pol, GptTmpl.inf for the security settings); Apply saves it there.' FontSize='11'
                           Foreground='{DynamicResource SecondaryTextBrush}' TextWrapping='Wrap'/>
            </StackPanel>
        </Border>
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
                            <Grid ColumnDefinitions='*,Auto'>
                                <StackPanel Orientation='Horizontal' Spacing='8' VerticalAlignment='Center'>
                                    <PathIcon Data='{StaticResource Icon.tree}' Foreground='{DynamicResource HeaderTextBrush}'/>
                                    <TextBlock Text='Policy Structure' FontSize='15' FontWeight='SemiBold'
                                               Foreground='{DynamicResource HeaderTextBrush}'/>
                                </StackPanel>
                                <!-- Editing a GPO: only the settings it configures -->
                                <CheckBox Grid.Column='1' Name='configuredOnlyCheckBox' Content='Configured settings only'
                                          IsVisible='False' Foreground='{DynamicResource HeaderTextBrush}'
                                          ToolTip.Tip='Shows only the policies and security settings this GPO configures'/>
                            </Grid>
                            <Grid ColumnDefinitions='Auto,*' Margin='0,4,0,0'>
                                <PathIcon Grid.Column='0' Data='{StaticResource Icon.location}' Width='12' Height='12'
                                          Margin='0,0,4,0' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <TextBlock Grid.Column='1' Name='breadcrumbTextBlock' Text='Select a policy to see its path'
                                           FontSize='11' Foreground='{DynamicResource SecondaryTextBrush}' TextTrimming='CharacterEllipsis'/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <TreeView Grid.Row='1' Name='treeView' Margin='8' ScrollViewer.HorizontalScrollBarVisibility='Disabled'>
                        <TreeView.Styles>
                            <Style Selector='TreeViewItem'>
                                <Setter Property='IsExpanded' Value='{Binding IsExpanded, Mode=TwoWay}'/>
                            </Style>
                        </TreeView.Styles>
                        <TreeView.ItemTemplate>
                            <TreeDataTemplate ItemsSource='{Binding Children}'>
                                <Grid ColumnDefinitions='Auto,*'>
                                    <PathIcon Grid.Column='0' Data='{Binding IconData}' Foreground='{Binding IconBrush}' VerticalAlignment='Center' Margin='0,0,6,0'/>
                                    <TextBlock Grid.Column='1' Text='{Binding Header}' TextTrimming='CharacterEllipsis' ToolTip.Tip='{Binding Header}'/>
                                </Grid>
                            </TreeDataTemplate>
                        </TreeView.ItemTemplate>
                        <TreeView.ContextMenu>
                            <ContextMenu>
                                <MenuItem Name='copyNameMenuItem' Header='Copy policy name'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.copy}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='copyRegistryMenuItem' Header='Copy registry path'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.copy}'/></MenuItem.Icon>
                                </MenuItem>
                                <Separator/>
                                <MenuItem Name='copyCommandMenuItem' Header='Copy PowerShell command'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.code}'/></MenuItem.Icon>
                                </MenuItem>
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
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.info}' Foreground='{DynamicResource HeaderTextBrush}'/>
                            <TextBlock Name='detailsTitleTextBlock' Text='Policy Details' FontSize='15' FontWeight='SemiBold'
                                       Foreground='{DynamicResource HeaderTextBrush}'/>
                        </StackPanel>
                    </Border>

                    <!-- Preferences ([MS-GPPREF]) of the selected type: its items, in their order, and the
                         form of the item created or edited. Shown instead of the tabs of a policy. -->
                    <Grid Grid.Row='1' Name='preferencesPanel' IsVisible='False' Margin='16,8' RowDefinitions='Auto,Auto,Auto,*'>
                        <StackPanel Grid.Row='0' Spacing='2'>
                            <TextBlock Name='preferencesTitleTextBlock' FontSize='16' FontWeight='SemiBold' TextWrapping='Wrap'/>
                            <TextBlock Name='preferencesInfoTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                        </StackPanel>
                        <WrapPanel Grid.Row='1' Name='preferencesToolbar' Orientation='Horizontal' Margin='0,8,0,0'>
                            <ComboBox Name='preferencesNewTypeComboBox' MinWidth='200' Margin='0,0,8,4'/>
                            <Button Name='preferencesNewButton' Margin='0,0,8,4'>
                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                    <PathIcon Data='{StaticResource Icon.add}' Width='14' Height='14'/>
                                    <TextBlock Text='New item' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Name='preferencesEditButton' Content='Edit' Margin='0,0,8,4'/>
                            <Button Name='preferencesDeleteButton' Content='Delete' Margin='0,0,8,4'/>
                            <Button Name='preferencesUpButton' Content='Move up' Margin='0,0,8,4' ToolTip.Tip='The items apply in their order'/>
                            <Button Name='preferencesDownButton' Content='Move down' Margin='0,0,8,4'/>
                        </WrapPanel>
                        <TextBlock Grid.Row='2' Name='preferencesStatusTextBlock' TextWrapping='Wrap' Margin='0,4,0,0'
                                   IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                        <ScrollViewer Grid.Row='3' Margin='0,8,0,0'>
                            <StackPanel Spacing='8' Margin='0,0,12,0'>
                                <TextBlock Name='preferencesEmptyTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <ListBox Name='preferencesList' MaxHeight='320'>
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <StackPanel Spacing='2' Margin='0,2'>
                                                <TextBlock Text='{Binding Name}' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                                <TextBlock Text='{Binding Summary}' FontSize='12' TextWrapping='Wrap'/>
                                                <TextBlock Text='{Binding Flags}' FontSize='11' Foreground='#CA5010' TextWrapping='Wrap'
                                                           IsVisible='{Binding Flags, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            </StackPanel>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                                <!-- Confirmation of a deletion -->
                                <Border Name='preferencesDeletePanel' IsVisible='False' Padding='12' CornerRadius='4'
                                        BorderThickness='1' BorderBrush='#D13438' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                    <StackPanel Spacing='8'>
                                        <TextBlock Name='preferencesDeleteTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                        <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                            <Button Name='preferencesDeleteConfirmButton' Content='Delete' Width='100'/>
                                            <Button Name='preferencesDeleteCancelButton' Content='Cancel' Width='100'/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                                <!-- The item created or edited -->
                                <Border Name='preferencesFormBorder' IsVisible='False' Padding='12' CornerRadius='4'
                                        BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                    <StackPanel Spacing='8'>
                                        <TextBlock Name='preferencesFormTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                        <ContentControl Name='preferencesFormHost'/>
                                        <TextBlock Name='preferencesFormErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap'
                                                   IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                        <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                            <Button Name='preferencesSaveButton' Width='100'>
                                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                                    <PathIcon Data='{StaticResource Icon.save}' Width='14' Height='14'/>
                                                    <TextBlock Text='Save' VerticalAlignment='Center'/>
                                                </StackPanel>
                                            </Button>
                                            <Button Name='preferencesCancelButton' Content='Cancel' Width='100'/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>
                    </Grid>

                    <!-- Setting: what the administrator edits; Details: what the ADMX defines. -->
                    <TabControl Grid.Row='1' Name='detailsTabs' Margin='8,0,8,8'>
                        <TabItem Header='Setting'>
                            <ScrollViewer>
                                <StackPanel Margin='8'>
                                    <TextBlock Name='settingTitleTextBlock' FontSize='16' FontWeight='SemiBold'
                                               TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'
                                               Text='Select a policy in the tree'/>

                                    <StackPanel Orientation='Horizontal' Spacing='16' Margin='0,12,0,0'>
                                        <RadioButton Name='notConfiguredRadio' Content='Not Configured' IsChecked='True'/>
                                        <RadioButton Name='enabledRadio' Content='Enabled'/>
                                        <RadioButton Name='disabledRadio' Content='Disabled'/>
                                    </StackPanel>

                                    <!-- Editing a GPO: what its Registry.pol holds, and Apply to save the setting -->
                                    <StackPanel Name='applyPanel' Orientation='Horizontal' Spacing='12' Margin='0,12,0,0' IsVisible='False'>
                                        <Button Name='applySettingButton' IsEnabled='False'>
                                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                                <PathIcon Data='{StaticResource Icon.save}'/>
                                                <TextBlock Text='Apply' VerticalAlignment='Center'/>
                                            </StackPanel>
                                        </Button>
                                        <TextBlock Name='applyStatusTextBlock' VerticalAlignment='Center' TextWrapping='Wrap' FontSize='12'
                                                   Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    </StackPanel>

                                    <TextBlock Text='Options' FontSize='12' FontWeight='SemiBold'
                                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,16,0,4'/>
                                    <Border BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' CornerRadius='4' Padding='12'>
                                        <ContentControl Name='optionsHost'/>
                                    </Border>
                                    <TextBlock Name='settingErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' Margin='0,8,0,0'/>

                                    <TextBlock Name='previewHeaderTextBlock' Text='Registry Preview' FontSize='12' FontWeight='SemiBold'
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
                            <ScrollViewer>
                                <StackPanel Name='detailsPanel' Margin='8'>
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

        <!-- Status bar: this computer, its addresses, the domain and the domain controller read -->
        <Border Grid.Row='2' Name='statusBar' Background='{DynamicResource HeaderBackgroundBrush}'
                BorderThickness='0,1,0,0' BorderBrush='{DynamicResource BorderBrush}' Padding='16,6'>
            <ItemsControl Name='statusBarList'>
                <ItemsControl.ItemsPanel>
                    <ItemsPanelTemplate>
                        <WrapPanel Orientation='Horizontal'/>
                    </ItemsPanelTemplate>
                </ItemsControl.ItemsPanel>
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <StackPanel Orientation='Horizontal' Spacing='6' Margin='0,0,24,0' ToolTip.Tip='{Binding ToolTip}'>
                            <PathIcon Data='{Binding IconData}' Width='14' Height='14' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <TextBlock Text='{Binding Text}' FontSize='12' VerticalAlignment='Center' Foreground='{DynamicResource TextBrush}'/>
                        </StackPanel>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </Border>
    </Grid>
</Window>
"@
}
