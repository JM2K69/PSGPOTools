<#
    The Policy Analyzer view of Show-GPOManagerAvalonia, a view of its own as Group Policy
    Management and the policy editor: the rule sets (the .PolicyRules files of a folder, GPOs of
    the domain, GPMC backups) | the comparison of those checked, a column per set, with the
    colours of Policy Analyzer, and the details of the selected setting. Its logic:
    Initialize-PSGPOPolicyAnalyzerView.
#>

function Get-PSGPOPolicyAnalyzerViewXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Single-quoted: the bindings keep their $self.
    @'
        <!-- Policy Analyzer view: rule sets | Splitter | comparison of the sets checked -->
        <Grid Grid.Row='1' Name='analyzerView' ColumnDefinitions='340,Auto,*' IsVisible='False'>
            <Border Grid.Column='0' Background='{DynamicResource BackgroundBrush}' Margin='16,16,8,16' CornerRadius='8' BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000'>
                <Grid RowDefinitions='Auto,Auto,*,Auto'>
                    <Border Grid.Row='0' Background='{DynamicResource HeaderBackgroundBrush}' Padding='16,12' CornerRadius='8,8,0,0'>
                        <StackPanel>
                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                <PathIcon Data='{StaticResource Icon.table-search}' Foreground='{DynamicResource HeaderTextBrush}'/>
                                <TextBlock Text='Rule sets' FontSize='15' FontWeight='SemiBold' Foreground='{DynamicResource HeaderTextBrush}'/>
                            </StackPanel>
                            <TextBlock Text='Check the sets to compare, as in Policy Analyzer' FontSize='11' Margin='0,4,0,0' TextWrapping='Wrap'
                                       Foreground='{DynamicResource SecondaryTextBrush}'/>
                        </StackPanel>
                    </Border>
                    <!-- The folder of the .PolicyRules files: Documents\PolicyAnalyzer, as Policy Analyzer -->
                    <StackPanel Grid.Row='1' Margin='12,12,12,4' Spacing='4'>
                        <TextBlock Text='Policy Rule sets in' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                        <Grid ColumnDefinitions='*,Auto,Auto'>
                            <TextBox Grid.Column='0' Name='analyzerFolderTextBox' FontSize='12'/>
                            <Button Grid.Column='1' Name='analyzerFolderBrowseButton' Content='Browse...' Margin='6,0,0,0'/>
                            <Button Grid.Column='2' Name='analyzerFolderReadButton' Margin='6,0,0,0' ToolTip.Tip='Read the folder again'>
                                <PathIcon Data='{StaticResource Icon.arrow-sync}'/>
                            </Button>
                        </Grid>
                    </StackPanel>
                    <ListBox Grid.Row='2' Name='analyzerSetsList' Margin='8' SelectionMode='Single' ScrollViewer.HorizontalScrollBarVisibility='Disabled'>
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Grid ColumnDefinitions='Auto,*' ToolTip.Tip='{Binding Path}'>
                                    <CheckBox Grid.Column='0' IsChecked='{Binding IsChecked, Mode=TwoWay}' VerticalAlignment='Center' Margin='0,0,4,0'/>
                                    <StackPanel Grid.Column='1' VerticalAlignment='Center'>
                                        <TextBlock Text='{Binding Name}' FontWeight='SemiBold' TextTrimming='CharacterEllipsis' Foreground='{DynamicResource TextBrush}'/>
                                        <TextBlock Text='{Binding Detail}' FontSize='11' TextTrimming='CharacterEllipsis' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    </StackPanel>
                                </Grid>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                    <StackPanel Grid.Row='3' Margin='12' Spacing='8'>
                        <TextBlock Name='analyzerSetsEmptyTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                   Text='No .PolicyRules file in this folder: copy those of the security baselines of Microsoft there, or add GPOs.'/>
                        <WrapPanel>
                            <Button Name='analyzerAddGposButton' Margin='0,0,6,6'>
                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                    <PathIcon Data='{StaticResource Icon.organization}'/>
                                    <TextBlock Text='GPOs of the domain...' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Name='analyzerAddGpmcButton' Margin='0,0,6,6' ToolTip.Tip='A rule set of backups of GPMC (the GPOs folder of a security baseline of Microsoft) or of HGPM'>
                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                    <PathIcon Data='{StaticResource Icon.folder}'/>
                                    <TextBlock Text='Backups...' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Name='analyzerSaveSetButton' Margin='0,0,6,6' ToolTip.Tip='Save the selected set as a .PolicyRules file, which Policy Analyzer and LGPO.exe read'>
                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                    <PathIcon Data='{StaticResource Icon.save}'/>
                                    <TextBlock Text='Save as .PolicyRules...' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Name='analyzerApplySetButton' Margin='0,0,6,6' ToolTip.Tip='Write the settings of the selected set in a GPO of the domain, as LGPO.exe /p applies them to a computer'>
                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                    <PathIcon Data='{StaticResource Icon.arrow-import}'/>
                                    <TextBlock Text='Write in a GPO...' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Name='analyzerRemoveSetButton' Margin='0,0,6,6' ToolTip.Tip='Remove the selected set from the list (its file is kept)'>
                                <StackPanel Orientation='Horizontal' Spacing='6'>
                                    <PathIcon Data='{StaticResource Icon.delete}'/>
                                    <TextBlock Text='Remove from the list' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                        </WrapPanel>
                        <Button Name='analyzerCompareButton' HorizontalAlignment='Stretch' HorizontalContentAlignment='Center' Height='36' Classes='accent'>
                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                <PathIcon Data='{StaticResource Icon.table-search}'/>
                                <TextBlock Text='View / Compare' VerticalAlignment='Center'/>
                            </StackPanel>
                        </Button>
                        <!-- Windows: the sets checked against this computer, as Policy Analyzer -->
                        <Button Name='analyzerEffectiveButton' HorizontalAlignment='Stretch' HorizontalContentAlignment='Center' Height='36'
                                ToolTip.Tip='The sets checked against the settings this computer and its user have now; the security settings and the audit policy need PowerShell run as an administrator'>
                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                <PathIcon Data='{StaticResource Icon.desktop}'/>
                                <TextBlock Text='Compare to effective state' VerticalAlignment='Center'/>
                            </StackPanel>
                        </Button>
                        <TextBlock Name='analyzerSetsStatusTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                   IsVisible='{Binding $self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                    </StackPanel>
                </Grid>
            </Border>

            <GridSplitter Grid.Column='1' Width='4' Background='Transparent' ResizeDirection='Columns'/>

            <Border Grid.Column='2' Background='{DynamicResource BackgroundBrush}' Margin='8,16,16,16' CornerRadius='8' BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000'>
                <Grid RowDefinitions='Auto,Auto,Auto,3*,Auto,Auto,*' Margin='12'>
                    <!-- The form of the moment: GPOs of the domain to add, a folder of GPMC backups, a file to save -->
                    <Border Grid.Row='0' Name='analyzerGposPanel' IsVisible='False' Margin='0,0,0,8' Padding='12' CornerRadius='4'
                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
                        <StackPanel Spacing='8'>
                            <TextBlock Text='A rule set of GPOs of the domain, as they are now' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                            <!-- The GPOs chosen, or those that apply to a domain or an OU by precedence -->
                            <ComboBox Name='analyzerGposModeComboBox' HorizontalAlignment='Stretch' SelectedIndex='0'>
                                <ComboBoxItem Content='The GPOs chosen'/>
                                <ComboBoxItem Content='The GPOs that apply to a domain or an OU, by precedence (the value that wins)'/>
                            </ComboBox>
                            <ComboBox Name='analyzerGposSomComboBox' HorizontalAlignment='Stretch' IsVisible='False'/>
                            <TextBlock Name='analyzerGposSomTextBlock' FontSize='12' TextWrapping='Wrap' IsVisible='False' Foreground='{DynamicResource SecondaryTextBrush}'
                                       Text='As the Group Policy Inheritance tab of GPMC: the enforced links first, then those of the OU and of its parents until one blocks the inheritance. The security filtering and the WMI filters, which depend on each computer, are not taken into account.'/>
                            <TextBox Name='analyzerGposFilterTextBox' Watermark='Search a GPO...'/>
                            <ListBox Name='analyzerGposList' MaxHeight='220' SelectionMode='Multiple,Toggle'>
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <TextBlock Text='{Binding DisplayName}' TextTrimming='CharacterEllipsis'/>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                            </ListBox>
                            <Grid ColumnDefinitions='Auto,*'>
                                <TextBlock Grid.Column='0' Text='Name of the set' VerticalAlignment='Center' Margin='0,0,8,0' Foreground='{DynamicResource TextBrush}'/>
                                <TextBox Grid.Column='1' Name='analyzerGposNameTextBox'/>
                            </Grid>
                            <TextBlock Name='analyzerGposErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding $self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                <Button Name='analyzerGposConfirmButton' Content='Add' MinWidth='100'/>
                                <Button Name='analyzerGposCancelButton' Content='Cancel' Width='100'/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                    <!-- The settings of a set written in a GPO of the domain, merged or in place of its own -->
                    <Border Grid.Row='1' Name='analyzerApplyPanel' IsVisible='False' Margin='0,0,0,8' Padding='12' CornerRadius='4'
                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
                        <StackPanel Spacing='8'>
                            <TextBlock Name='analyzerApplyTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                            <Grid ColumnDefinitions='Auto,*' RowDefinitions='Auto,Auto'>
                                <TextBlock Grid.Row='0' Grid.Column='0' Text='GPO of the domain' VerticalAlignment='Center' Margin='0,0,8,0' Foreground='{DynamicResource TextBrush}'/>
                                <ComboBox Grid.Row='0' Grid.Column='1' Name='analyzerApplyGpoComboBox' HorizontalAlignment='Stretch'>
                                    <ComboBox.ItemTemplate>
                                        <DataTemplate>
                                            <TextBlock Text='{Binding DisplayName}'/>
                                        </DataTemplate>
                                    </ComboBox.ItemTemplate>
                                </ComboBox>
                                <TextBlock Grid.Row='1' Grid.Column='0' Text='or a new GPO' VerticalAlignment='Center' Margin='0,8,8,0' Foreground='{DynamicResource TextBrush}'/>
                                <TextBox Grid.Row='1' Grid.Column='1' Name='analyzerApplyNewNameTextBox' Margin='0,8,0,0' Watermark='Name of the GPO to create'/>
                            </Grid>
                            <TextBlock Text='The settings of these GPOs of the set' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <ListBox Name='analyzerApplyPoliciesList' MaxHeight='160' SelectionMode='Multiple,Toggle'/>
                            <CheckBox Name='analyzerApplyReplaceCheckBox' Content='Replace the registry settings, security template and audit policy of the GPO, instead of merging them'/>
                            <TextBlock Text='The GPO is backed up first, in the folder of the backups of the console.' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <TextBlock Name='analyzerApplyErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding $self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                <Button Name='analyzerApplyConfirmButton' Content='Write' MinWidth='100'/>
                                <Button Name='analyzerApplyCancelButton' Content='Cancel' Width='100'/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                    <Border Grid.Row='1' Name='analyzerFilePanel' IsVisible='False' Margin='0,0,0,8' Padding='12' CornerRadius='4'
                            BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
                        <StackPanel Spacing='8'>
                            <TextBlock Name='analyzerFileTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                            <Grid ColumnDefinitions='*,Auto'>
                                <TextBox Grid.Column='0' Name='analyzerFilePathTextBox'/>
                                <Button Grid.Column='1' Name='analyzerFileBrowseButton' Content='Browse...' Margin='8,0,0,0'/>
                            </Grid>
                            <CheckBox Name='analyzerFileAllCheckBox' Content='All data: the value of each GPO, the explanation and the reference of each setting'/>
                            <TextBlock Name='analyzerFileErrorTextBlock' Foreground='#D13438' TextWrapping='Wrap' IsVisible='{Binding $self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                            <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                <Button Name='analyzerFileConfirmButton' MinWidth='100'/>
                                <Button Name='analyzerFileCancelButton' Content='Cancel' Width='100'/>
                            </StackPanel>
                        </StackPanel>
                    </Border>

                    <!-- What is shown: all the settings, the differences or the conflicts; a search; the export -->
                    <Grid Grid.Row='2' ColumnDefinitions='Auto,*,Auto' Margin='0,0,0,8'>
                        <ComboBox Grid.Column='0' Name='analyzerShowComboBox' MinWidth='200' SelectedIndex='0'>
                            <ComboBoxItem Content='All the settings'/>
                            <ComboBoxItem Content='Only the differences'/>
                            <ComboBoxItem Content='Only the conflicts'/>
                        </ComboBox>
                        <TextBox Grid.Column='1' Name='analyzerSearchTextBox' Margin='8,0' Watermark='Search a setting, a value, a GPO...'/>
                        <Button Grid.Column='2' Name='analyzerExportButton' ToolTip.Tip='Export the table to an Excel workbook, with the colours of Policy Analyzer'>
                            <StackPanel Orientation='Horizontal' Spacing='6'>
                                <PathIcon Data='{StaticResource Icon.arrow-export}'/>
                                <TextBlock Text='Export to Excel...' VerticalAlignment='Center'/>
                            </StackPanel>
                        </Button>
                    </Grid>

                    <Grid Grid.Row='3'>
                        <TextBlock Name='analyzerEmptyTextBlock' Margin='8' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                   Text='Check one or more rule sets, then View / Compare: a row per setting, a column per set. Yellow: the sets, or two GPOs of a set, give the setting different values; grey: the set does not configure it; light grey: it is set more than once to the same value.'/>
                        <DataGrid Name='analyzerGrid' IsVisible='False' IsReadOnly='True' CanUserSortColumns='True' CanUserReorderColumns='True'
                                  CanUserResizeColumns='True' GridLinesVisibility='Horizontal' HeadersVisibility='Column' SelectionMode='Single'
                                  RowHeight='28' FontSize='12'/>
                    </Grid>

                    <TextBlock Grid.Row='4' Name='analyzerSummaryTextBlock' Margin='0,8,0,0' FontSize='12' TextWrapping='Wrap'
                               Foreground='{DynamicResource SecondaryTextBrush}' IsVisible='{Binding $self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                    <GridSplitter Grid.Row='5' Height='6' Background='Transparent' ResizeDirection='Rows' IsVisible='{Binding #analyzerDetailsBorder.IsVisible}'/>

                    <!-- Details of the selected setting: where GPMC shows it, the value of each GPO, its explanation -->
                    <Border Grid.Row='6' Name='analyzerDetailsBorder' IsVisible='False' Margin='0,2,0,0' Padding='12' CornerRadius='4'
                            BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
                        <ScrollViewer>
                            <StackPanel Spacing='6' Margin='0,0,12,0'>
                                <TextBlock Name='analyzerDetailsNameTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                <TextBlock Name='analyzerDetailsPathTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <TextBlock Name='analyzerDetailsSettingTextBlock' FontSize='12' TextWrapping='Wrap' FontFamily='Consolas,Menlo,monospace' Foreground='{DynamicResource TextBrush}'/>
                                <ItemsControl Name='analyzerDetailsValuesList'>
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Grid ColumnDefinitions='Auto,*' Margin='0,2'>
                                                <TextBlock Grid.Column='0' Text='{Binding Set}' FontWeight='SemiBold' FontSize='12' Margin='0,0,8,0' Foreground='{DynamicResource TextBrush}'/>
                                                <TextBlock Grid.Column='1' Text='{Binding Text}' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            </Grid>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                                <TextBlock Name='analyzerDetailsExplainTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                           IsVisible='{Binding $self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                            </StackPanel>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </Border>
        </Grid>
'@
}
