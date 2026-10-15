<#
    Window of the configuration of PSGPOTools (Get-PSGPOConfiguration), opened from the console:
    every setting with its value, its default and where the value comes from. A value is set
    (created or changed) for a setting, or removed (the default applies again); Save writes the
    Configuration.psd1 of the user with the values set, once checked. Only the settings of the
    module can be set: an unknown one would be refused when the configuration is read.

    Returns @{ Window; Controls; State }: the window is shown by the caller (owned by the console).
#>

function New-PSGPOConfigurationWindow {
    [CmdletBinding()]
    param()

    $xaml = @'
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='GPO Policy Manager - Configuration' Width='960' Height='680' WindowStartupLocation='CenterOwner'>
    <Grid RowDefinitions='Auto,*,Auto,Auto' Margin='20'>
        <StackPanel Grid.Row='0' Spacing='4'>
            <TextBlock Text='Configuration' FontSize='20' FontWeight='SemiBold'/>
            <TextBlock Name='pathTextBlock' TextWrapping='Wrap' FontSize='12' Opacity='0.75'/>
        </StackPanel>

        <ListBox Grid.Row='1' Name='settingsList' Margin='0,12,0,12'>
            <ListBox.ItemTemplate>
                <DataTemplate>
                    <Grid ColumnDefinitions='*,Auto' Margin='0,2'>
                        <StackPanel Spacing='2'>
                            <TextBlock Text='{Binding Key}' FontWeight='SemiBold'/>
                            <TextBlock Text='{Binding Value}' TextWrapping='Wrap'/>
                            <TextBlock Text='{Binding Default}' FontSize='11' Opacity='0.7' TextWrapping='Wrap'/>
                        </StackPanel>
                        <Border Grid.Column='1' Background='{Binding SourceBrush}' CornerRadius='3' Padding='6,1' VerticalAlignment='Top' Margin='12,0,0,0'>
                            <TextBlock Text='{Binding Source}' Foreground='White' FontSize='11' FontWeight='SemiBold'/>
                        </Border>
                    </Grid>
                </DataTemplate>
            </ListBox.ItemTemplate>
        </ListBox>

        <!-- The value of the selected setting: set (create or change) or removed -->
        <Border Grid.Row='2' Padding='12' CornerRadius='4' BorderThickness='1' BorderBrush='#0078D4'>
            <StackPanel Spacing='8'>
                <Grid ColumnDefinitions='Auto,*'>
                    <TextBlock Text='Setting' VerticalAlignment='Center' Margin='0,0,12,0' FontWeight='SemiBold'/>
                    <ComboBox Grid.Column='1' Name='keyComboBox' HorizontalAlignment='Stretch'/>
                </Grid>
                <TextBlock Name='descriptionTextBlock' TextWrapping='Wrap' FontSize='12' Opacity='0.8'/>
                <Grid ColumnDefinitions='Auto,*'>
                    <TextBlock Text='Value' VerticalAlignment='Center' Margin='0,0,12,0' FontWeight='SemiBold'/>
                    <Panel Grid.Column='1'>
                        <TextBox Name='valueTextBox'/>
                        <ComboBox Name='valueComboBox' HorizontalAlignment='Stretch' IsVisible='False'/>
                    </Panel>
                </Grid>
                <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                    <Button Name='setButton' Content='Set the value' ToolTip.Tip='Adds the setting to your configuration, or changes its value'/>
                    <Button Name='removeButton' Content='Remove (use the default)'/>
                </StackPanel>
            </StackPanel>
        </Border>

        <Grid Grid.Row='3' ColumnDefinitions='*,Auto' Margin='0,12,0,0'>
            <TextBlock Name='statusTextBlock' TextWrapping='Wrap' VerticalAlignment='Center'/>
            <StackPanel Grid.Column='1' Orientation='Horizontal' Spacing='8'>
                <Button Name='saveButton' Content='Save' Width='100' Classes='accent'/>
                <Button Name='closeButton' Content='Close' Width='100'/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
'@
    $Window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse($xaml)
    $Controls = @{ Window = $Window }
    foreach ($Name in 'pathTextBlock', 'settingsList', 'keyComboBox', 'descriptionTextBlock', 'valueTextBox', 'valueComboBox', 'setButton', 'removeButton', 'statusTextBlock', 'saveButton', 'closeButton') {
        $Controls[$Name] = Get-PSGPOAvaloniaControl $Window $Name
    }

    # The functions the handlers call, captured: a closure (GetNewClosure) does not see the
    # private functions of the module, only the variables it holds.
    $GetSettings = ${function:Get-PSGPOConfigurationSetting}
    $GetPaths = ${function:Get-PSGPOConfigurationPath}
    $TestConfiguration = ${function:Test-PSGPOConfiguration}
    $MergeConfiguration = ${function:Merge-PSGPOConfiguration}
    $Unflatten = ${function:ConvertFrom-PSGPOFlatConfiguration}
    $SaveConfiguration = ${function:Save-PSGPOUserConfiguration}
    $RowType = [AvaloniaConfigurationRow]

    # The values of the configuration of the user, by key, as edited (saved with Save).
    $State = @{ Values = @{}; Dirty = $false; CloseAsked = $false; Settings = @() }
    $paths = Get-PSGPOConfigurationPath
    foreach ($setting in @(Get-PSGPOConfigurationSetting)) { if ($setting.IsSet) { $State.Values[$setting.Key] = $setting.Value } }
    $Controls.pathTextBlock.Text = "Your configuration: $($paths.User)$(if (-not (Test-Path -LiteralPath $paths.User)) { ' (not created yet)' }). Defaults: $($paths.Default)."
    $red = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
    $Text = { param($Value) if ($Value -is [bool]) { if ($Value) { 'True' } else { 'False' } } elseif ("$Value" -eq '') { '(empty)' } else { "$Value" } }

    $SetStatus = {
        param([string]$Message, [switch]$Problem)
        $Controls.statusTextBlock.Text = $Message
        if ($Problem) { $Controls.statusTextBlock.Foreground = $red } else { $Controls.statusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }.GetNewClosure()

    $Refresh = {
        param([string]$Select)
        $State.Settings = @(& $GetSettings -Override $State.Values)
        $Controls.settingsList.ItemsSource = @(foreach ($setting in $State.Settings) {
                $row = $RowType::new()
                $row.Key = $setting.Key
                $row.Value = "Value: $(& $Text $setting.Value)"
                $row.Default = "Default: $(& $Text $setting.Default)$(if ($setting.Description) { " - $($setting.Description)" })"
                $row.Source = if ($setting.IsSet) { 'Set in your configuration' } else { 'Default' }
                $row.SourceBrush = if ($setting.IsSet) { '#0078D4' } else { '#8A8886' }
                $row.Setting = $setting
                $row
            })
        if ($Select) { $Controls.settingsList.SelectedItem = @($Controls.settingsList.ItemsSource) | Where-Object Key -EQ $Select | Select-Object -First 1 }
    }.GetNewClosure()

    # The editor of the value of a setting, by its kind.
    $ShowSetting = {
        param([string]$Key)
        $setting = $State.Settings | Where-Object Key -EQ $Key | Select-Object -First 1
        if (-not $setting) { return }
        $Controls.descriptionTextBlock.Text = "$($setting.Description) Default: $(& $Text $setting.Default)."
        $choice = $setting.Kind -in 'Bool', 'Choice'
        $Controls.valueComboBox.IsVisible = $choice
        $Controls.valueTextBox.IsVisible = -not $choice
        if ($setting.Kind -eq 'Bool') {
            $Controls.valueComboBox.ItemsSource = @('True', 'False')
            $Controls.valueComboBox.SelectedItem = & $Text $setting.Value
        } elseif ($setting.Kind -eq 'Choice') {
            $Controls.valueComboBox.ItemsSource = @($setting.Choices)
            $Controls.valueComboBox.SelectedItem = "$($setting.Value)"
        } else {
            $Controls.valueTextBox.Text = "$($setting.Value)"
        }
        $Controls.removeButton.IsEnabled = $setting.IsSet
    }.GetNewClosure()

    & $Refresh $null
    $Controls.keyComboBox.ItemsSource = @($State.Settings.Key)

    $Controls.settingsList.add_SelectionChanged({
        $row = $Controls.settingsList.SelectedItem
        if ($row) { $Controls.keyComboBox.SelectedItem = $row.Key }
    }.GetNewClosure())
    $Controls.keyComboBox.add_SelectionChanged({ if ($Controls.keyComboBox.SelectedItem) { & $ShowSetting "$($Controls.keyComboBox.SelectedItem)" } }.GetNewClosure())

    # Create or update: the value is checked with the others before it is kept.
    $Controls.setButton.Add_Click({
        $key = "$($Controls.keyComboBox.SelectedItem)"
        $setting = $State.Settings | Where-Object Key -EQ $key | Select-Object -First 1
        if (-not $setting) { & $SetStatus 'Choose a setting.' -Problem; return }
        $value = switch ($setting.Kind) {
            'Bool' { "$($Controls.valueComboBox.SelectedItem)" -eq 'True' }
            'Choice' { "$($Controls.valueComboBox.SelectedItem)" }
            default { "$($Controls.valueTextBox.Text)" }
        }
        $values = @{}
        foreach ($name in $State.Values.Keys) { $values[$name] = $State.Values[$name] }
        $values[$key] = $value
        $defaults = Import-PowerShellDataFile -LiteralPath (& $GetPaths).Default
        $problems = @(& $TestConfiguration -Configuration (& $MergeConfiguration -Base $defaults -Override (& $Unflatten -Flat $values)))
        if ($problems.Count) { & $SetStatus ($problems -join ' ') -Problem; return }
        $State.Values[$key] = $value
        $State.Dirty = $true
        $State.CloseAsked = $false
        & $Refresh $key
        & $SetStatus "$key = $(& $Text $value): not saved yet."
    }.GetNewClosure())

    # Delete: the default applies again.
    $Controls.removeButton.Add_Click({
        $key = "$($Controls.keyComboBox.SelectedItem)"
        if (-not $State.Values.ContainsKey($key)) { return }
        $State.Values.Remove($key)
        $State.Dirty = $true
        $State.CloseAsked = $false
        & $Refresh $key
        & $ShowSetting $key
        & $SetStatus "$key removed from your configuration: the default applies. Not saved yet."
    }.GetNewClosure())

    $Controls.saveButton.Add_Click({
        try {
            & $SaveConfiguration -Values $State.Values -Confirm:$false
            $State.Dirty = $false
            & $SetStatus "Saved: $((& $GetPaths).User)$(if (-not $State.Values.Count) { ' removed, the defaults apply' })."
        } catch {
            & $SetStatus "Not saved: $($_.Exception.Message)" -Problem
        }
    }.GetNewClosure())

    # Closing with changes not saved (Close, or the window frame) asks once more.
    $Window.add_Closing({
        param($Sender, $Arguments)
        if ($State.Dirty -and -not $State.CloseAsked) {
            $Arguments.Cancel = $true
            $State.CloseAsked = $true
            & $SetStatus 'Your changes are not saved: Save them, or Close again to drop them.' -Problem
        }
    }.GetNewClosure())
    $Controls.closeButton.Add_Click({ $Window.Close() }.GetNewClosure())

    @{ Window = $Window; Controls = $Controls; State = $State }
}
