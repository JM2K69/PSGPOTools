<#
    XAML of the Show-GPOManagerAvalonia window (Start-PSGPOManagerWindow).
#>

function Get-PSGPOManagerWindowXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='GPO Policy Manager'
        Width='1200' Height='700'
        MinWidth='800' MinHeight='500'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='MainWindow'>

$(Get-PSGPOWindowResourceXaml)

    <Grid RowDefinitions='Auto,*,Auto'>

        <!-- Header: title, view switch, theme toggle, search (policy editor only) -->
        <Border Grid.Row='0'
                Background='{DynamicResource BackgroundBrush}'
                BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}'
                Padding='20,16'>
            <!-- The buttons keep their width; the title takes the rest, trimmed when the window is narrow. -->
            <Grid ColumnDefinitions='*,Auto'>
                <Grid Grid.Column='0' ColumnDefinitions='Auto,*' VerticalAlignment='Center' Margin='0,0,16,0'>
                    <!-- The logo of HGPM (Resources/hgpm.png), set when the window opens. -->
                    <Image Grid.Column='0' Name='logoImage' Width='44' Height='44' VerticalAlignment='Center' Margin='0,0,12,0'
                           RenderOptions.BitmapInterpolationMode='HighQuality'/>
                    <StackPanel Grid.Column='1' VerticalAlignment='Center'>
                        <TextBlock Text='GPO Policy Manager' FontSize='22' FontWeight='Bold' TextTrimming='CharacterEllipsis'
                                   Foreground='{DynamicResource TextBrush}'/>
                        <TextBlock Name='subtitleTextBlock' Text='Explore and manage Group Policy Objects' FontSize='12'
                                   TextTrimming='CharacterEllipsis' ToolTip.Tip='{Binding Text, RelativeSource={RelativeSource Self}}'
                                   Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,2,0,0'/>
                    </StackPanel>
                </Grid>

                <StackPanel Grid.Column='1' Orientation='Horizontal'
                            HorizontalAlignment='Right' VerticalAlignment='Center' Spacing='12'>
                    <Button Name='managementButton' Height='36'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.organization}'/>
                            <TextBlock Text='Group Policy Management' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='refreshButton' Height='36' ToolTip.Tip='Read the domain again (F5)'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.arrow-sync}'/>
                            <TextBlock Text='Refresh' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='browseAdmxButton' Height='36'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.book}'/>
                            <TextBlock Text='Browse the ADMX policies' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='configurationButton' Height='36' ToolTip.Tip='Configuration of HGPM (Configuration.psd1)'>
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
                                <MenuItem Name='renameMenuItem' Header='Rename...' InputGesture='F2'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.rename}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='enforcedLinkMenuItem' Header='Enforced' ToggleType='CheckBox'/>
                                <MenuItem Name='enabledLinkMenuItem' Header='Link Enabled' ToggleType='CheckBox'/>
                                <MenuItem Name='moveLinkUpMenuItem' Header='Move link up'/>
                                <MenuItem Name='moveLinkDownMenuItem' Header='Move link down'/>
                                <MenuItem Name='blockInheritanceMenuItem' Header='Block Inheritance' ToggleType='CheckBox'/>
                                <MenuItem Name='gpoStatusMenuItem' Header='GPO Status'>
                                    <MenuItem Name='gpoStatusEnabledMenuItem' Header='Enabled' ToggleType='Radio' Tag='0'/>
                                    <MenuItem Name='gpoStatusUserDisabledMenuItem' Header='User Configuration Settings Disabled' ToggleType='Radio' Tag='1'/>
                                    <MenuItem Name='gpoStatusComputerDisabledMenuItem' Header='Computer Configuration Settings Disabled' ToggleType='Radio' Tag='2'/>
                                    <MenuItem Name='gpoStatusAllDisabledMenuItem' Header='All Settings Disabled' ToggleType='Radio' Tag='3'/>
                                </MenuItem>
                                <MenuItem Name='wmiFilterMenuItem' Header='WMI Filter'/>
                                <MenuItem Name='newWmiFilterMenuItem' Header='New WMI Filter...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.add}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='editWmiFilterMenuItem' Header='Edit WMI filter...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.edit}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='useWmiFilterMenuItem' Header='Use it in a GPO...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.link}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='exportWmiFilterMenuItem' Header='Export...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.arrow-export}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='importWmiFilterMenuItem' Header='Import...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.arrow-import}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='deleteWmiFilterMenuItem' Header='Delete WMI filter...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.delete}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='deleteLinkMenuItem' Header='Delete link...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.link-dismiss}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='approveGpoMenuItem' Header='Approve...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.shield}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='importGpoMenuItem' Header='Import Settings...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.document-copy}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='deleteGpoMenuItem' Header='Delete GPO...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.delete}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='restoreDeletedGpoMenuItem' Header='Restore...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.arrow-undo}'/></MenuItem.Icon>
                                </MenuItem>
                                <MenuItem Name='purgeDeletedGpoMenuItem' Header='Delete for good...'>
                                    <MenuItem.Icon><PathIcon Data='{StaticResource Icon.delete-dismiss}'/></MenuItem.Icon>
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

                                    <!-- Approval of a GPO waiting for it (approval workflow) -->
                                    <Border Name='approveGpoPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='#107C10'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='approveGpoTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <Grid ColumnDefinitions='Auto,*'>
                                                <TextBlock Text='The creators' VerticalAlignment='Center' Margin='0,0,12,0'
                                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <ComboBox Grid.Column='1' Name='approveGpoRightsComboBox' HorizontalAlignment='Stretch'>
                                                    <ComboBoxItem Content='Read it only: they cannot change it anymore' Tag='ReadOnly'/>
                                                    <ComboBoxItem Content='Keep editing its settings: each change needs a new approval' Tag='EditSettings'/>
                                                </ComboBox>
                                            </Grid>
                                            <!-- Security filtering groups APPLY_<GPO> and DENY_<GPO>, created by the approver -->
                                            <CheckBox Name='approveGpoGroupsCheckBox' Content='Create the security filtering groups'/>
                                            <TextBlock Name='approveGpoGroupsTextBlock' TextWrapping='Wrap' FontSize='12' Margin='28,0,0,0'
                                                       Foreground='{DynamicResource SecondaryTextBrush}'/>
                                            <Grid ColumnDefinitions='Auto,*' RowDefinitions='Auto,Auto' Name='approveGpoFilteringGrid'>
                                                <TextBlock Text='Applies to' VerticalAlignment='Center' Margin='0,0,12,6'
                                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <TextBox Grid.Column='1' Name='approveGpoApplyToTextBox' Margin='0,0,0,6' Watermark='A group of the domain, or Authenticated Users'/>
                                                <TextBlock Grid.Row='1' Text='Denied to' VerticalAlignment='Center' Margin='0,0,12,0'
                                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <TextBox Grid.Row='1' Grid.Column='1' Name='approveGpoDenyToTextBox' Watermark='A group of the domain (optional)'/>
                                            </Grid>
                                            <TextBlock Name='approveGpoErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='approveGpoConfirmButton' Content='Approve' Width='110'/>
                                                <Button Name='approveGpoCancelButton' Content='Cancel' Width='100'/>
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

                                    <!-- Rename of a GPO or of a WMI filter, as GPMC: its name only -->
                                    <Border Name='renamePanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='renameTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='renameTextBox' Watermark='New name'/>
                                            <TextBlock Name='renameErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='renameConfirmButton' Content='Rename' MinWidth='110'/>
                                                <Button Name='renameCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- A deleted GPO deleted for good: all its backups -->
                                    <Border Name='purgeDeletedGpoPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='#D13438'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='purgeDeletedGpoTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='purgeDeletedGpoConfirmButton' Content='Delete for good' MinWidth='120'/>
                                                <Button Name='purgeDeletedGpoCancelButton' Content='Cancel' Width='100'/>
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

                                    <!-- Import Settings, as GPMC: the settings of a backup (GPMC or HGPM), with a migration table -->
                                    <Border Name='importGpoPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='importGpoTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBlock Text='Folder of the backups (GPMC or HGPM)' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                            <Grid ColumnDefinitions='*,Auto'>
                                                <TextBox Grid.Column='0' Name='importGpoPathTextBox' Watermark='C:\backupGPO'/>
                                                <Button Grid.Column='1' Name='importGpoReadButton' Content='Read the backups' Margin='8,0,0,0'/>
                                            </Grid>
                                            <ComboBox Name='importGpoSourceComboBox' HorizontalAlignment='Stretch' PlaceholderText='No backup read yet'/>
                                            <TextBlock Text='Migration table (.migtable), optional' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                            <TextBox Name='importGpoTableTextBox' Watermark='C:\backupGPO\production.migtable'/>
                                            <CheckBox Name='importGpoExclusiveCheckBox' Content='Use the migration table exclusively: every account and path of the settings must be in it'/>
                                            <TextBlock Name='importGpoTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBlock Name='importGpoErrorTextBlock' TextWrapping='Wrap' Foreground='#D13438'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='importGpoConfirmButton' Content='Import' Width='110' Classes='accent' IsEnabled='False'/>
                                                <Button Name='importGpoCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- A new WMI filter of the domain, or one changed, as GPMC: its name, description and WQL queries -->
                                    <Border Name='newWmiFilterPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='newWmiFilterTitleTextBlock' Text='New WMI filter' FontWeight='SemiBold' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBlock Text='Name' FontSize='12' Opacity='0.8' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='newWmiFilterNameTextBox' Watermark='Name'/>
                                            <TextBlock Text='Description' FontSize='12' Opacity='0.8' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='newWmiFilterDescriptionTextBox' Watermark='Description (optional)'/>
                                            <TextBlock Text='Namespace' FontSize='12' Opacity='0.8' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='newWmiFilterNamespaceTextBox' Text='root\CIMv2' Watermark='Namespace'/>
                                            <TextBlock Text='WQL queries, one per line (namespace: query for another namespace)' FontSize='12' Opacity='0.8' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='newWmiFilterQueryTextBox' AcceptsReturn='True' TextWrapping='Wrap' MinHeight='70'
                                                     Watermark='WQL queries, one per line: SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'/>
                                            <TextBlock Name='newWmiFilterErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='newWmiFilterCreateButton' Content='Create' Width='100'/>
                                                <Button Name='newWmiFilterCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Export of a WMI filter to a .mof file, as GPMC -->
                                    <Border Name='exportWmiFilterPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='exportWmiFilterTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBlock Text='File (.mof), in the format of GPMC' FontSize='12' Opacity='0.8' Foreground='{DynamicResource TextBrush}'/>
                                            <Grid ColumnDefinitions='*,Auto'>
                                                <TextBox Name='exportWmiFilterPathTextBox'/>
                                                <Button Grid.Column='1' Name='exportWmiFilterBrowseButton' Content='Browse...' Margin='8,0,0,0'/>
                                            </Grid>
                                            <TextBlock Name='exportWmiFilterErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='exportWmiFilterConfirmButton' Content='Export' MinWidth='100'/>
                                                <Button Name='exportWmiFilterCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Import of a WMI filter from a .mof file (GPMC or HGPM), as GPMC -->
                                    <Border Name='importWmiFilterPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='importWmiFilterTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBlock Text='File (.mof) exported by GPMC or HGPM' FontSize='12' Opacity='0.8' Foreground='{DynamicResource TextBrush}'/>
                                            <Grid ColumnDefinitions='*,Auto,Auto'>
                                                <TextBox Name='importWmiFilterPathTextBox' Watermark='C:\Exports\Workstations.mof'/>
                                                <Button Grid.Column='1' Name='importWmiFilterBrowseButton' Content='Browse...' Margin='8,0,0,0'/>
                                                <Button Grid.Column='2' Name='importWmiFilterReadButton' Content='Read the file' Margin='8,0,0,0'/>
                                            </Grid>
                                            <TextBlock Name='importWmiFilterInfoTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'
                                                       IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <TextBlock Text='Name' FontSize='12' Opacity='0.8' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='importWmiFilterNameTextBox' Watermark='Name of the filter in this domain'/>
                                            <TextBlock Name='importWmiFilterErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='importWmiFilterConfirmButton' Content='Import' MinWidth='100' IsEnabled='False'/>
                                                <Button Name='importWmiFilterCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- A WMI filter given to a GPO from the filter: the GPOs the account edits that do not use it -->
                                    <Border Name='useWmiFilterPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='useWmiFilterTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBox Name='useWmiFilterSearchTextBox' Watermark='Search a GPO'/>
                                            <ListBox Name='useWmiFilterList' MaxHeight='240' SelectionMode='Single'>
                                                <ListBox.ItemTemplate>
                                                    <DataTemplate>
                                                        <TextBlock Text='{Binding DisplayName}' TextTrimming='CharacterEllipsis'/>
                                                    </DataTemplate>
                                                </ListBox.ItemTemplate>
                                            </ListBox>
                                            <TextBlock Name='useWmiFilterErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='useWmiFilterConfirmButton' Content='Use the filter' MinWidth='110' IsEnabled='False'/>
                                                <Button Name='useWmiFilterCancelButton' Content='Cancel' Width='100'/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Deletion of a WMI filter no GPO uses -->
                                    <Border Name='deleteWmiFilterPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                            BorderThickness='1' BorderBrush='#D13438'
                                            Background='{DynamicResource SecondaryBackgroundBrush}'>
                                        <StackPanel Spacing='8'>
                                            <TextBlock Name='deleteWmiFilterTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                                <Button Name='deleteWmiFilterConfirmButton' Content='Delete' Width='120'/>
                                                <Button Name='deleteWmiFilterCancelButton' Content='Cancel' Width='100'/>
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
                                    <!-- The WMI filter of the GPO, as the WMI Filtering of the Scope tab of GPMC -->
                                    <Grid Name='gpoWmiFilterPanel' ColumnDefinitions='180,*' IsVisible='False' Margin='0,0,0,8'>
                                        <TextBlock Text='Change the WMI filter' VerticalAlignment='Center' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                        <ComboBox Grid.Column='1' Name='gpoWmiFilterComboBox' HorizontalAlignment='Stretch'
                                                  ToolTip.Tip='The computers apply the GPO only when a query of its WMI filter returns something'/>
                                    </Grid>
                                    <Button Name='editWmiFilterButton' IsVisible='False' Margin='0,8,0,8'>
                                        <StackPanel Orientation='Horizontal' Spacing='8'>
                                            <PathIcon Data='{StaticResource Icon.edit}'/>
                                            <TextBlock Text='Edit this WMI filter' VerticalAlignment='Center'/>
                                        </StackPanel>
                                    </Button>
                                    <StackPanel Orientation='Horizontal' Spacing='8'>
                                        <Button Name='restoreDeletedGpoButton' IsVisible='False' Margin='0,8,0,8'>
                                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                                <PathIcon Data='{StaticResource Icon.arrow-undo}'/>
                                                <TextBlock Text='Restore this GPO...' VerticalAlignment='Center'/>
                                            </StackPanel>
                                        </Button>
                                        <Button Name='purgeDeletedGpoButton' IsVisible='False' Margin='0,8,0,8'>
                                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                                <PathIcon Data='{StaticResource Icon.delete-dismiss}'/>
                                                <TextBlock Text='Delete for good...' VerticalAlignment='Center'/>
                                            </StackPanel>
                                        </Button>
                                    </StackPanel>

                                    <ItemsControl Name='directoryPropertiesList'>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <Grid ColumnDefinitions='180,*' Margin='0,3'>
                                                    <!-- A long name (in French) wraps instead of running over its value -->
                                                    <TextBlock Grid.Column='0' Text='{Binding Key}' Foreground='{DynamicResource SecondaryTextBrush}'
                                                               TextWrapping='Wrap' Margin='0,0,8,0'/>
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
                        <!-- Permissions of the GPO, as the Scope (security filtering) and Delegation tabs of GPMC -->
                        <TabItem Name='delegationTab' Header='Delegation' IsVisible='False'>
                            <ScrollViewer>
                                <StackPanel Margin='16,8' Spacing='6'>
                                    <TextBlock Text='Security Filtering' FontSize='14' FontWeight='SemiBold' Foreground='{DynamicResource TextBrush}'/>
                                    <TextBlock Text='The settings in this GPO apply only to the following groups, users, and computers:' TextWrapping='Wrap'
                                               Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <ListBox Name='filteringList' MaxHeight='160'>
                                        <ListBox.ItemTemplate>
                                            <DataTemplate>
                                                <TextBlock Text='{Binding Name}'/>
                                            </DataTemplate>
                                        </ListBox.ItemTemplate>
                                    </ListBox>
                                    <Grid ColumnDefinitions='*,Auto,Auto'>
                                        <TextBox Grid.Column='0' Name='filteringNameTextBox' Watermark='Group, user or computer (PC01`$)'/>
                                        <Button Grid.Column='1' Name='filteringAddButton' Content='Add' Margin='8,0,0,0'/>
                                        <Button Grid.Column='2' Name='filteringRemoveButton' Content='Remove' Margin='8,0,0,0' IsEnabled='False'/>
                                    </Grid>
                                    <TextBlock Text='Delegation' FontSize='14' FontWeight='SemiBold' Margin='0,12,0,0' Foreground='{DynamicResource TextBrush}'/>
                                    <TextBlock Text='These groups and users have the specified permission for this GPO:' TextWrapping='Wrap'
                                               Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <Grid ColumnDefinitions='*,280,90' Margin='12,0,12,0'>
                                        <TextBlock Grid.Column='0' Text='Name' FontWeight='SemiBold'/>
                                        <TextBlock Grid.Column='1' Text='Allowed Permissions' FontWeight='SemiBold'/>
                                        <TextBlock Grid.Column='2' Text='Inherited' FontWeight='SemiBold'/>
                                    </Grid>
                                    <ListBox Name='delegationList' MaxHeight='280'>
                                        <ListBox.ItemTemplate>
                                            <DataTemplate>
                                                <Grid ColumnDefinitions='*,280,90'>
                                                    <TextBlock Grid.Column='0' Text='{Binding Name}' TextTrimming='CharacterEllipsis'/>
                                                    <!-- An account of the security filtering: it applies the GPO, whatever its level -->
                                                    <DockPanel Grid.Column='1' Margin='0,0,8,0'>
                                                        <Border DockPanel.Dock='Right' IsVisible='{Binding Applies}' Background='{DynamicResource PrimaryBrush}'
                                                                CornerRadius='8' Padding='7,1' Margin='6,0,0,0' VerticalAlignment='Center'
                                                                ToolTip.Tip='Security filtering: this account reads and applies the GPO (Apply Group Policy).'>
                                                            <TextBlock Text='Applies' FontSize='11' Foreground='White'/>
                                                        </Border>
                                                        <TextBlock Text='{Binding PermissionText}' TextTrimming='CharacterEllipsis' VerticalAlignment='Center'
                                                                   ToolTip.Tip='{Binding PermissionText}'/>
                                                    </DockPanel>
                                                    <TextBlock Grid.Column='2' Text='{Binding InheritedText}'/>
                                                </Grid>
                                            </DataTemplate>
                                        </ListBox.ItemTemplate>
                                    </ListBox>
                                    <Grid ColumnDefinitions='*,Auto'>
                                        <TextBox Grid.Column='0' Name='delegationNameTextBox' Watermark='Group, user or computer (PC01`$)'/>
                                        <ComboBox Grid.Column='1' Name='delegationPermissionComboBox' Margin='8,0,0,0' MinWidth='300' SelectedIndex='0'>
                                            <ComboBoxItem Content='Read' Tag='GpoRead'/>
                                            <ComboBoxItem Content='Read and apply' Tag='GpoApply'/>
                                            <ComboBoxItem Content='Edit settings' Tag='GpoEdit'/>
                                            <ComboBoxItem Content='Edit settings, delete, modify security' Tag='GpoEditDeleteModifySecurity'/>
                                        </ComboBox>
                                    </Grid>
                                    <StackPanel Orientation='Horizontal' HorizontalAlignment='Right' Spacing='8'>
                                        <Button Name='delegationSetButton' Content='Set the permission'/>
                                        <Button Name='delegationRemoveButton' Content='Remove' IsEnabled='False'/>
                                    </StackPanel>
                                    <TextBlock Name='delegationStatusTextBlock' TextWrapping='Wrap' Margin='0,4,0,0'/>
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
                                                    <TextBlock Grid.Row='2' Text='{Binding Subtitle}' FontSize='11' HorizontalAlignment='Center' TextAlignment='Center' TextWrapping='Wrap'
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
                <!-- The part of the GPO its status disables: saved, not applied -->
                <TextBlock Name='editingStatusTextBlock' FontSize='12' FontWeight='SemiBold' Foreground='#CA5010' TextWrapping='Wrap' Margin='0,4,0,0'
                           IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
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
                            <!-- The title gives way to the check box (longer in French) -->
                            <Grid ColumnDefinitions='Auto,*,Auto'>
                                <PathIcon Grid.Column='0' Data='{StaticResource Icon.tree}' Foreground='{DynamicResource HeaderTextBrush}' VerticalAlignment='Center'/>
                                <TextBlock Grid.Column='1' Text='Policy Structure' FontSize='15' FontWeight='SemiBold' Margin='8,0,8,0'
                                           TextTrimming='CharacterEllipsis' VerticalAlignment='Center'
                                           Foreground='{DynamicResource HeaderTextBrush}'/>
                                <!-- Editing a GPO: only the settings it configures -->
                                <CheckBox Grid.Column='2' Name='configuredOnlyCheckBox' Content='Configured settings only'
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

                    <!-- Restricted Groups: the groups of [Group Membership] in GptTmpl.inf -->
                    <Grid Grid.Row='1' Name='restrictedGroupsPanel' IsVisible='False' Margin='16,8' RowDefinitions='Auto,Auto,Auto,*'>
                        <StackPanel Grid.Row='0' Spacing='2'>
                            <TextBlock Text='Restricted Groups' FontSize='16' FontWeight='SemiBold' TextWrapping='Wrap'/>
                            <TextBlock Name='restrictedGroupsInfoTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                       Text='The computers give each group the members defined, and remove the others; they add it to the groups it is a member of. In GptTmpl.inf, [Group Membership].'/>
                        </StackPanel>
                        <WrapPanel Grid.Row='1' Orientation='Horizontal' Margin='0,8,0,0'>
                            <Button Name='restrictedGroupsAddButton' Margin='0,0,8,4'>
                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                    <PathIcon Data='{StaticResource Icon.add}' Width='14' Height='14'/>
                                    <TextBlock Text='Add group' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Name='restrictedGroupsEditButton' Content='Edit' Margin='0,0,8,4'/>
                            <Button Name='restrictedGroupsDeleteButton' Content='Delete' Margin='0,0,8,4'/>
                        </WrapPanel>
                        <TextBlock Grid.Row='2' Name='restrictedGroupsStatusTextBlock' TextWrapping='Wrap' Margin='0,4,0,0'
                                   IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                        <ScrollViewer Grid.Row='3' Margin='0,8,0,0'>
                            <StackPanel Spacing='8' Margin='0,0,12,0'>
                                <TextBlock Name='restrictedGroupsEmptyTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <ListBox Name='restrictedGroupsList' MaxHeight='320'>
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
                                <Border Name='restrictedGroupsDeletePanel' IsVisible='False' Padding='12' CornerRadius='4'
                                        BorderThickness='1' BorderBrush='#D13438' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                    <StackPanel Spacing='8'>
                                        <TextBlock Name='restrictedGroupsDeleteTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                        <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                            <Button Name='restrictedGroupsDeleteConfirmButton' Content='Delete' Width='100'/>
                                            <Button Name='restrictedGroupsDeleteCancelButton' Content='Cancel' Width='100'/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                                <!-- The group added or edited -->
                                <Border Name='restrictedGroupsFormBorder' IsVisible='False' Padding='12' CornerRadius='4'
                                        BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                    <StackPanel Spacing='6'>
                                        <TextBlock Name='restrictedGroupsFormTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                        <TextBlock Text='Group' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                        <TextBox Name='restrictedGroupNameTextBox' Watermark='DOMAIN\group, or a SID: *S-1-5-32-544 (Administrators)'/>
                                        <CheckBox Name='restrictedGroupMembersCheckBox' Content='Members of this group: the computers keep these members only (empty: none)' IsChecked='True'/>
                                        <TextBox Name='restrictedGroupMembersTextBox' AcceptsReturn='True' MinHeight='70' TextWrapping='NoWrap'
                                                 Watermark='One account per line: DOMAIN\name, or *S-1-5-...'/>
                                        <TextBlock Text='This group is a member of' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                        <TextBox Name='restrictedGroupMemberOfTextBox' AcceptsReturn='True' MinHeight='50' TextWrapping='NoWrap'
                                                 Watermark='One group per line: DOMAIN\name, or *S-1-5-...'/>
                                        <TextBlock Name='restrictedGroupsFormErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap'
                                                   IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                        <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                            <Button Name='restrictedGroupsSaveButton' Width='100'>
                                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                                    <PathIcon Data='{StaticResource Icon.save}' Width='14' Height='14'/>
                                                    <TextBlock Text='Save' VerticalAlignment='Center'/>
                                                </StackPanel>
                                            </Button>
                                            <Button Name='restrictedGroupsCancelButton' Content='Cancel' Width='100'/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>
                    </Grid>

                    <!-- A certificate store of the public key policies: its certificates in Registry.pol -->
                    <Grid Grid.Row='1' Name='certificatesPanel' IsVisible='False' Margin='16,8' RowDefinitions='Auto,Auto,Auto,*'>
                        <StackPanel Grid.Row='0' Spacing='2'>
                            <TextBlock Name='certificatesTitleTextBlock' FontSize='16' FontWeight='SemiBold' TextWrapping='Wrap'/>
                            <TextBlock Name='certificatesInfoTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                        </StackPanel>
                        <Grid Grid.Row='1' ColumnDefinitions='*,Auto,Auto' Margin='0,8,0,0'>
                            <TextBox Grid.Column='0' Name='certificatesPathTextBox' Watermark='Certificate file to import: .cer, .crt or .pem (DER or Base-64)'/>
                            <Button Grid.Column='1' Name='certificatesImportButton' Margin='8,0,0,0'>
                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                    <PathIcon Data='{StaticResource Icon.add}' Width='14' Height='14'/>
                                    <TextBlock Text='Import' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Grid.Column='2' Name='certificatesDeleteButton' Content='Delete' Margin='8,0,0,0'/>
                        </Grid>
                        <TextBlock Grid.Row='2' Name='certificatesStatusTextBlock' TextWrapping='Wrap' Margin='0,4,0,0'
                                   IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                        <ScrollViewer Grid.Row='3' Margin='0,8,0,0'>
                            <StackPanel Spacing='8' Margin='0,0,12,0'>
                                <TextBlock Name='certificatesEmptyTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <ListBox Name='certificatesList' MaxHeight='360'>
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
                                <Border Name='certificatesDeletePanel' IsVisible='False' Padding='12' CornerRadius='4'
                                        BorderThickness='1' BorderBrush='#D13438' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                    <StackPanel Spacing='8'>
                                        <TextBlock Name='certificatesDeleteTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                        <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                            <Button Name='certificatesDeleteConfirmButton' Content='Delete' Width='100'/>
                                            <Button Name='certificatesDeleteCancelButton' Content='Cancel' Width='100'/>
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
                            <Ellipse Width='9' Height='9' VerticalAlignment='Center' Fill='{Binding BadgeBrush}' IsVisible='{Binding HasBadge}'/>
                        </StackPanel>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </Border>
    </Grid>
</Window>
"@
}

# The styles and resources of the windows of the consoles: the icons of Resources/Icons as geometry
# resources ({StaticResource Icon.<name>}) and the brushes of the light and dark themes.
function Get-PSGPOWindowResourceXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $iconResources = (Get-PSGPOIconName | ForEach-Object {
        "            <StreamGeometry x:Key='Icon.$_'>$(Get-PSGPOIconData -Name $_)</StreamGeometry>"
    }) -join [Environment]::NewLine

    @"
    <Window.Styles>
        <Style Selector='PathIcon'>
            <Setter Property='Width' Value='16'/>
            <Setter Property='Height' Value='16'/>
        </Style>
        <!-- The button of the view shown -->
        <Style Selector='Button.active'>
            <Setter Property='Background' Value='{DynamicResource PrimaryBrush}'/>
            <Setter Property='Foreground' Value='White'/>
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
"@
}
