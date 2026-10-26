<#
    XAML of the Show-AuditLogAvalonia window (Start-PSGPOAuditLogWindow): its header (logo, title,
    theme), the folder of the audit log, the filters (period, domain, action, a search), the
    changes, newest first, and the details of the selected one.
#>

function Get-PSGPOAuditLogWindowXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Audit Log'
        Width='1280' Height='800'
        MinWidth='900' MinHeight='560'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='AuditLogWindow'>

$(Get-PSGPOWindowResourceXaml)

    <Grid RowDefinitions='Auto,*'>

        <!-- Header: logo, title, theme -->
        <Border Grid.Row='0' Background='{DynamicResource BackgroundBrush}' BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}' Padding='20,16'>
            <Grid ColumnDefinitions='Auto,*,Auto'>
                <Image Grid.Column='0' Name='logoImage' Width='44' Height='44' VerticalAlignment='Center' Margin='0,0,12,0'
                       RenderOptions.BitmapInterpolationMode='HighQuality'/>
                <StackPanel Grid.Column='1' VerticalAlignment='Center' Margin='0,0,16,0'>
                    <TextBlock Text='Audit Log' FontSize='22' FontWeight='Bold' TextTrimming='CharacterEllipsis' Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Name='subtitleTextBlock' Text='What the consoles and the commands changed in the domain' FontSize='12'
                               TextTrimming='CharacterEllipsis' ToolTip.Tip='{Binding Text, RelativeSource={RelativeSource Self}}'
                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,2,0,0'/>
                </StackPanel>
                <Button Grid.Column='2' Name='themeToggleButton' Height='36' Width='140' VerticalAlignment='Center'>
                    <StackPanel Orientation='Horizontal' Spacing='8'>
                        <PathIcon Name='themeToggleIcon' Data='{StaticResource Icon.weather-moon}'/>
                        <TextBlock Name='themeToggleText' Text='Dark mode' VerticalAlignment='Center'/>
                    </StackPanel>
                </Button>
            </Grid>
        </Border>

        <Border Grid.Row='1' Background='{DynamicResource BackgroundBrush}' Margin='16' CornerRadius='8' BorderThickness='1'
                BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000' Padding='16'>
            <Grid RowDefinitions='Auto,Auto,*,Auto,Auto,Auto'>

                <!-- The folder of the log: Audit.Path of the configuration of the domain -->
                <Grid Grid.Row='0' ColumnDefinitions='Auto,*,Auto,Auto' Margin='0,0,0,8'>
                    <TextBlock Grid.Column='0' Text='Audit log in' VerticalAlignment='Center' Margin='0,0,8,0' Foreground='{DynamicResource TextBrush}'/>
                    <TextBox Grid.Column='1' Name='auditFolderTextBox' Watermark='Folder of the audit log (Audit.Path of the configuration)'/>
                    <Button Grid.Column='2' Name='auditFolderBrowseButton' Content='Browse...' Margin='6,0,0,0'/>
                    <Button Grid.Column='3' Name='auditRefreshButton' Margin='6,0,0,0' ToolTip.Tip='Read the audit log again'>
                        <StackPanel Orientation='Horizontal' Spacing='6'>
                            <PathIcon Data='{StaticResource Icon.arrow-sync}'/>
                            <TextBlock Text='Refresh' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                </Grid>

                <!-- The filters and the export -->
                <Grid Grid.Row='1' ColumnDefinitions='Auto,Auto,Auto,*,Auto' Margin='0,0,0,8'>
                    <ComboBox Grid.Column='0' Name='auditPeriodComboBox' MinWidth='170' SelectedIndex='2'>
                        <ComboBoxItem Content='Last 24 hours'/>
                        <ComboBoxItem Content='Last 7 days'/>
                        <ComboBoxItem Content='Last 30 days'/>
                        <ComboBoxItem Content='Everything'/>
                    </ComboBox>
                    <ComboBox Grid.Column='1' Name='auditDomainComboBox' MinWidth='180' Margin='8,0,0,0'/>
                    <ComboBox Grid.Column='2' Name='auditActionComboBox' MinWidth='240' Margin='8,0,0,0'/>
                    <TextBox Grid.Column='3' Name='auditSearchTextBox' Margin='8,0' Watermark='Search an account, a GPO, a computer, a detail...'/>
                    <Button Grid.Column='4' Name='auditExportButton' ToolTip.Tip='Export the changes shown to a CSV file'>
                        <StackPanel Orientation='Horizontal' Spacing='6'>
                            <PathIcon Data='{StaticResource Icon.arrow-export}'/>
                            <TextBlock Text='Export to CSV...' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                </Grid>

                <Grid Grid.Row='2'>
                    <TextBlock Name='auditEmptyTextBlock' Margin='8' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                    <DataGrid Name='auditGrid' IsReadOnly='True' CanUserSortColumns='True' CanUserResizeColumns='True'
                              GridLinesVisibility='Horizontal' HeadersVisibility='Column' SelectionMode='Single' RowHeight='28' FontSize='12'>
                        <DataGrid.Columns>
                            <DataGridTextColumn Header='Time' Binding='{Binding Time}' Width='185'/>
                            <DataGridTextColumn Header='Account' Binding='{Binding Account}' Width='205'/>
                            <DataGridTextColumn Header='Action' Binding='{Binding Action}' Width='250'/>
                            <DataGridTextColumn Header='GPO or object' Binding='{Binding Object}' Width='*'/>
                            <DataGridTextColumn Header='Tier' Binding='{Binding Tier}' Width='75'/>
                            <DataGridTextColumn Header='Check' Binding='{Binding Check}' Width='140'/>
                            <DataGridTextColumn Header='Computer' Binding='{Binding Computer}' Width='95'/>
                            <DataGridTextColumn Header='Domain' Binding='{Binding Domain}' Width='135'/>
                        </DataGrid.Columns>
                    </DataGrid>
                </Grid>

                <TextBlock Grid.Row='3' Name='auditSummaryTextBlock' Margin='0,8,0,0' FontSize='12' TextWrapping='Wrap'
                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                <TextBlock Grid.Row='4' Name='auditStatusTextBlock' Margin='0,4,0,0' FontSize='12' TextWrapping='Wrap'
                           Foreground='{DynamicResource SecondaryTextBrush}' IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>

                <!-- The selected change: everything the log keeps of it -->
                <Border Grid.Row='5' Name='auditDetailsBorder' IsVisible='False' Margin='0,8,0,0' Padding='12' CornerRadius='4' MaxHeight='240'
                        BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
                    <ScrollViewer>
                        <StackPanel Spacing='6' Margin='0,0,12,0'>
                            <TextBlock Name='auditDetailsTitleTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                            <TextBlock Name='auditDetailsWhoTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <TextBlock Name='auditDetailsTargetTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                            <TextBlock Name='auditDetailsTextBlock' FontSize='12' TextWrapping='Wrap' FontFamily='Consolas,Menlo,monospace' Foreground='{DynamicResource TextBrush}'
                                       IsVisible='{Binding `$self.Text, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                        </StackPanel>
                    </ScrollViewer>
                </Border>
            </Grid>
        </Border>
    </Grid>
</Window>
"@
}
