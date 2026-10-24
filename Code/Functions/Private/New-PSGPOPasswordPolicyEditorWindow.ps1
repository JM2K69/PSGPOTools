<#
    Window of a fine-grained password policy (PSO), as "Create Password Settings" and the
    properties of a PSO in the Active Directory Administrative Center: its name and precedence,
    the password settings ("Enforce..." boxes: unchecked, no minimum, no history, a password that
    never expires, no lockout), the protection from accidental deletion, the description, and the
    users and groups it directly applies to (searched in the domain). OK checks the settings, then
    creates or changes the PSO in the domain; the window stays open with the reason when the
    domain refuses it.

    Returns @{ Window; Controls; State }: the window is shown by the caller (owned by the console).
#>

function New-PSGPOPasswordPolicyEditorWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPasswordPolicyStore]$Store,
        # The PSO to change; $null creates one.
        [AllowNull()] [GPOToolsPasswordPolicy]$Policy,
        # Called with the PSO once created or changed.
        [scriptblock]$OnSaved
    )

    $xaml = Get-PSGPOPasswordPolicyEditorXaml
    $Window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml $xaml))
    Set-PSGPOWindowIcon -Window $Window
    # The theme of the session, followed while the window is open (PSGPOTheme.ps1).
    Register-PSGPOThemeWindow -Window $Window
    $Controls = @{ Window = $Window }
    foreach ($Name in 'titleTextBlock', 'containerTextBlock', 'nameTextBox', 'precedenceUpDown', 'enforceLengthCheckBox', 'minLengthUpDown', 'enforceHistoryCheckBox',
        'historyUpDown', 'complexityCheckBox', 'reversibleCheckBox', 'protectCheckBox', 'descriptionTextBox', 'enforceMinAgeCheckBox', 'minAgeUpDown',
        'enforceMaxAgeCheckBox', 'maxAgeUpDown', 'enforceLockoutCheckBox', 'lockoutPanel', 'thresholdUpDown', 'observationUpDown', 'lockForDurationRadio',
        'durationUpDown', 'lockUntilUnlockRadio', 'groupRuleTextBlock', 'subjectsList', 'subjectRemoveButton', 'subjectSearchTextBox', 'subjectSearchButton',
        'subjectResultsList', 'subjectAddButton', 'errorTextBlock', 'okButton', 'cancelButton', 'formScrollViewer') {
        $Controls[$Name] = Get-PSGPOAvaloniaControl $Window $Name
    }

    # The functions the handlers call, captured: a closure (GetNewClosure) does not see the
    # private functions of the module, only the variables it holds.
    $T = ${function:Get-PSGPOText}
    $TestPolicy = ${function:Test-PSGPOPasswordPolicy}
    $AccountRow = ${function:ConvertTo-PSGPOPasswordAccountRow}

    $isNew = -not $Policy
    $source = if ($Policy) { $Policy } else { [GPOToolsPasswordPolicy]::NewDefault() }
    # The users and groups it applies to, as edited: their rows (an account, or a distinguished name).
    $State = @{ Store = $Store; Policy = $Policy; Source = $source; Subjects = [System.Collections.Generic.List[object]]::new(); Saved = $null }
    foreach ($dn in $source.AppliesTo) {
        $account = $null
        try { $account = $Store.GetAccount($dn) } catch { Write-Verbose "The subject $dn cannot be read: $($_.Exception.Message)" }
        $State.Subjects.Add($(if ($account) { & $AccountRow -Account $account } else { & $AccountRow -DistinguishedName $dn }))
    }
    $Controls.subjectsList.ItemsSource = @($State.Subjects)

    $Window.Title = if ($isNew) { & $T 'Create Password Settings' } else { & $T 'Password Settings: {0}' $source.Name }
    $Controls.titleTextBlock.Text = if ($isNew) { & $T 'Create Password Settings' } else { $source.Name }
    $Controls.containerTextBlock.Text = & $T 'Password Settings Container of {0}: {1}' $Store.DomainName $Store.GetContainer()
    $Controls.groupRuleTextBlock.Text = if ($Store.GroupRule -eq 'Security') {
        & $T 'Users and groups. With Samba AD, a group passes the password settings on to its members when it is a security group that is not built-in.'
    } else {
        & $T 'Users and groups. A group passes the password settings on to its members when it is a global security group.'
    }

    # The settings of the PSO in the controls; a setting not enforced shows the default of the
    # Administrative Center, ready to be enforced.
    $Controls.nameTextBox.Text = $source.Name
    $Controls.precedenceUpDown.Value = if ($isNew) { $null } else { [decimal]$source.Precedence }
    $Controls.enforceLengthCheckBox.IsChecked = $source.MinPasswordLength -gt 0
    $Controls.minLengthUpDown.Value = [decimal]$(if ($source.MinPasswordLength -gt 0) { $source.MinPasswordLength } else { 7 })
    $Controls.enforceHistoryCheckBox.IsChecked = $source.PasswordHistoryCount -gt 0
    $Controls.historyUpDown.Value = [decimal]$(if ($source.PasswordHistoryCount -gt 0) { $source.PasswordHistoryCount } else { 24 })
    $Controls.complexityCheckBox.IsChecked = $source.ComplexityEnabled
    $Controls.reversibleCheckBox.IsChecked = $source.ReversibleEncryptionEnabled
    $Controls.protectCheckBox.IsChecked = if ($isNew) { $true } else { $source.ProtectedFromAccidentalDeletion }
    $Controls.descriptionTextBox.Text = $source.Description
    $Controls.enforceMinAgeCheckBox.IsChecked = $source.MinPasswordAge -gt [TimeSpan]::Zero
    $Controls.minAgeUpDown.Value = [decimal]$(if ($source.MinPasswordAge -gt [TimeSpan]::Zero) { [Math]::Max(1, [Math]::Round($source.MinPasswordAge.TotalDays)) } else { 1 })
    $Controls.enforceMaxAgeCheckBox.IsChecked = $source.MaxPasswordAge -gt [TimeSpan]::Zero
    $Controls.maxAgeUpDown.Value = [decimal]$(if ($source.MaxPasswordAge -gt [TimeSpan]::Zero) { [Math]::Max(1, [Math]::Round($source.MaxPasswordAge.TotalDays)) } else { 42 })
    $Controls.enforceLockoutCheckBox.IsChecked = $source.LockoutThreshold -gt 0
    $Controls.thresholdUpDown.Value = [decimal]$(if ($source.LockoutThreshold -gt 0) { $source.LockoutThreshold } else { 5 })
    $Controls.observationUpDown.Value = [decimal][Math]::Max(1, [Math]::Round($source.LockoutObservationWindow.TotalMinutes))
    $Controls.lockForDurationRadio.IsChecked = $source.LockoutDuration -gt [TimeSpan]::Zero
    $Controls.lockUntilUnlockRadio.IsChecked = $source.LockoutDuration -eq [TimeSpan]::Zero
    $Controls.durationUpDown.Value = [decimal]$(if ($source.LockoutDuration -gt [TimeSpan]::Zero) { [Math]::Max(1, [Math]::Round($source.LockoutDuration.TotalMinutes)) } else { 30 })

    # A value is entered only for a setting enforced, as in the Administrative Center.
    $UpdateEnabled = {
        $Controls.minLengthUpDown.IsEnabled = [bool]$Controls.enforceLengthCheckBox.IsChecked
        $Controls.historyUpDown.IsEnabled = [bool]$Controls.enforceHistoryCheckBox.IsChecked
        $Controls.minAgeUpDown.IsEnabled = [bool]$Controls.enforceMinAgeCheckBox.IsChecked
        $Controls.maxAgeUpDown.IsEnabled = [bool]$Controls.enforceMaxAgeCheckBox.IsChecked
        $Controls.lockoutPanel.IsEnabled = [bool]$Controls.enforceLockoutCheckBox.IsChecked
        $Controls.durationUpDown.IsEnabled = [bool]$Controls.lockForDurationRadio.IsChecked
    }.GetNewClosure()
    & $UpdateEnabled
    foreach ($box in $Controls.enforceLengthCheckBox, $Controls.enforceHistoryCheckBox, $Controls.enforceMinAgeCheckBox, $Controls.enforceMaxAgeCheckBox,
        $Controls.enforceLockoutCheckBox, $Controls.lockForDurationRadio, $Controls.lockUntilUnlockRadio) {
        $box.add_IsCheckedChanged({ & $UpdateEnabled }.GetNewClosure())
    }

    # Who may save: an account that may create PSOs, or change this one.
    $canSave = if ($isNew) { $Store.CanCreate } else { $source.CanEdit }
    if (-not $canSave) {
        $Controls.okButton.IsEnabled = $false
        $Controls.errorTextBlock.Text = if ($isNew) { & $T 'The account {0} cannot create password settings objects in {1}.' $Store.Account $Store.DomainName }
            else { & $T 'The account {0} cannot change this password settings object.' $Store.Account }
    }

    # The PSO the controls describe. A duration shown rounded keeps its exact value when it is not
    # changed: opening and saving a PSO changes nothing.
    $BuildPolicy = {
        $changed = $State.Source.Clone()
        $changed.Name = "$($Controls.nameTextBox.Text)".Trim()
        $changed.Precedence = if ($null -ne $Controls.precedenceUpDown.Value) { [int]$Controls.precedenceUpDown.Value } else { 0 }
        $changed.MinPasswordLength = if ($Controls.enforceLengthCheckBox.IsChecked) { [int]$Controls.minLengthUpDown.Value } else { 0 }
        $changed.PasswordHistoryCount = if ($Controls.enforceHistoryCheckBox.IsChecked) { [int]$Controls.historyUpDown.Value } else { 0 }
        $changed.ComplexityEnabled = [bool]$Controls.complexityCheckBox.IsChecked
        $changed.ReversibleEncryptionEnabled = [bool]$Controls.reversibleCheckBox.IsChecked
        $changed.ProtectedFromAccidentalDeletion = [bool]$Controls.protectCheckBox.IsChecked
        $changed.Description = "$($Controls.descriptionTextBox.Text)".Trim()
        $keep = {
            param([TimeSpan]$Original, $Value, [switch]$Minutes)
            $shown = if ($Minutes) { [Math]::Round($Original.TotalMinutes) } else { [Math]::Round($Original.TotalDays) }
            if ($Original -gt [TimeSpan]::Zero -and $shown -eq [double]$Value) { return $Original }
            if ($Minutes) { [TimeSpan]::FromMinutes([double]$Value) } else { [TimeSpan]::FromDays([double]$Value) }
        }
        $changed.MinPasswordAge = if ($Controls.enforceMinAgeCheckBox.IsChecked) { & $keep $State.Source.MinPasswordAge $Controls.minAgeUpDown.Value } else { [TimeSpan]::Zero }
        $changed.MaxPasswordAge = if ($Controls.enforceMaxAgeCheckBox.IsChecked) { & $keep $State.Source.MaxPasswordAge $Controls.maxAgeUpDown.Value } else { [TimeSpan]::Zero }
        if ($Controls.enforceLockoutCheckBox.IsChecked) {
            $changed.LockoutThreshold = [int]$Controls.thresholdUpDown.Value
            $changed.LockoutObservationWindow = & $keep $State.Source.LockoutObservationWindow $Controls.observationUpDown.Value -Minutes
            $changed.LockoutDuration = if ($Controls.lockForDurationRadio.IsChecked) { & $keep $State.Source.LockoutDuration $Controls.durationUpDown.Value -Minutes } else { [TimeSpan]::Zero }
        } else {
            # No lockout: the durations stay as they are, used again once a threshold is set.
            $changed.LockoutThreshold = 0
        }
        $changed.AppliesTo.Clear()
        foreach ($row in $State.Subjects) { $changed.AppliesTo.Add($row.DistinguishedName) }
        $changed
    }.GetNewClosure()

    $Controls.subjectSearchButton.Add_Click({
        try {
            $Controls.subjectResultsList.ItemsSource = @($State.Store.FindAccounts("$($Controls.subjectSearchTextBox.Text)".Trim()) | ForEach-Object { & $AccountRow -Account $_ })
            $Controls.errorTextBlock.Text = if (@($Controls.subjectResultsList.ItemsSource).Count) { '' } else { & $T 'No user or group found.' }
        } catch {
            $Controls.errorTextBlock.Text = & $T 'The domain is not searched: {0}' $_.Exception.GetBaseException().Message
        }
    }.GetNewClosure())
    $Controls.subjectSearchTextBox.add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            $Controls.subjectSearchButton.RaiseEvent([Avalonia.Interactivity.RoutedEventArgs]::new([Avalonia.Controls.Button]::ClickEvent))
            $e.Handled = $true
        }
    }.GetNewClosure())
    $Controls.subjectAddButton.Add_Click({
        foreach ($row in @($Controls.subjectResultsList.SelectedItems)) {
            if (-not @($State.Subjects | Where-Object { [string]::Equals($_.DistinguishedName, $row.DistinguishedName, [System.StringComparison]::OrdinalIgnoreCase) }).Count) { $State.Subjects.Add($row) }
        }
        $Controls.subjectsList.ItemsSource = @($State.Subjects)
    }.GetNewClosure())
    $Controls.subjectRemoveButton.Add_Click({
        foreach ($row in @($Controls.subjectsList.SelectedItems)) { [void]$State.Subjects.Remove($row) }
        $Controls.subjectsList.ItemsSource = @($State.Subjects)
    }.GetNewClosure())

    $Controls.okButton.Add_Click({
        $changed = & $BuildPolicy
        $problems = @(& $TestPolicy -Policy $changed -Localized)
        if ($problems.Count) { $Controls.errorTextBlock.Text = $problems -join ' '; return }
        try {
            $State.Saved = if ($State.Policy) { $State.Store.SetPolicy($State.Policy, $changed) } else { $State.Store.NewPolicy($changed) }
        } catch {
            $Controls.errorTextBlock.Text = & $T 'Not saved: {0}' $_.Exception.GetBaseException().Message
            return
        }
        if ($OnSaved) { & $OnSaved $State.Saved }
        $Window.Close()
    }.GetNewClosure())
    $Controls.cancelButton.Add_Click({ $Window.Close() }.GetNewClosure())

    @{ Window = $Window; Controls = $Controls; State = $State }
}

# XAML of the window of a PSO.
function Get-PSGPOPasswordPolicyEditorXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @'
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Password Settings' Width='1000' Height='760' MinWidth='760' MinHeight='560' WindowStartupLocation='CenterOwner'>
    <Grid RowDefinitions='Auto,*,Auto' Margin='20'>
        <StackPanel Grid.Row='0' Spacing='2'>
            <TextBlock Name='titleTextBlock' FontSize='20' FontWeight='SemiBold'/>
            <TextBlock Name='containerTextBlock' FontSize='12' Opacity='0.75' TextWrapping='Wrap'/>
        </StackPanel>

        <ScrollViewer Grid.Row='1' Name='formScrollViewer' Margin='0,12,0,12'>
            <StackPanel Spacing='16'>
                <Grid ColumnDefinitions='*,24,*'>
                    <!-- Password Settings -->
                    <StackPanel Grid.Column='0' Spacing='8'>
                        <TextBlock Text='Password Settings' FontSize='15' FontWeight='SemiBold'/>
                        <TextBlock Text='Name:'/>
                        <TextBox Name='nameTextBox'/>
                        <TextBlock Text='Precedence:'/>
                        <NumericUpDown Name='precedenceUpDown' Minimum='1' Maximum='2147483647' Increment='1' FormatString='0' HorizontalAlignment='Left' Width='180'/>
                        <CheckBox Name='enforceLengthCheckBox' Content='Enforce minimum password length'/>
                        <Grid ColumnDefinitions='*,Auto' Margin='28,0,0,0'>
                            <TextBlock Text='Minimum password length (characters):' TextWrapping='Wrap' VerticalAlignment='Center' Margin='0,0,8,0'/>
                            <NumericUpDown Grid.Column='1' Name='minLengthUpDown' Minimum='1' Maximum='255' Increment='1' FormatString='0' Width='130'/>
                        </Grid>
                        <CheckBox Name='enforceHistoryCheckBox' Content='Enforce password history'/>
                        <Grid ColumnDefinitions='*,Auto' Margin='28,0,0,0'>
                            <TextBlock Text='Number of passwords remembered:' TextWrapping='Wrap' VerticalAlignment='Center' Margin='0,0,8,0'/>
                            <NumericUpDown Grid.Column='1' Name='historyUpDown' Minimum='1' Maximum='1024' Increment='1' FormatString='0' Width='130'/>
                        </Grid>
                        <CheckBox Name='complexityCheckBox'><TextBlock Text='Password must meet complexity requirements' TextWrapping='Wrap'/></CheckBox>
                        <CheckBox Name='reversibleCheckBox'><TextBlock Text='Store password using reversible encryption' TextWrapping='Wrap'/></CheckBox>
                        <CheckBox Name='protectCheckBox' Content='Protect from accidental deletion'/>
                        <TextBlock Text='Description:'/>
                        <TextBox Name='descriptionTextBox' AcceptsReturn='True' TextWrapping='Wrap' Height='64'/>
                    </StackPanel>

                    <!-- Password age and lockout -->
                    <StackPanel Grid.Column='2' Spacing='8'>
                        <TextBlock Text='Password age options:' FontSize='15' FontWeight='SemiBold'/>
                        <CheckBox Name='enforceMinAgeCheckBox' Content='Enforce minimum password age'/>
                        <Grid ColumnDefinitions='*,Auto' Margin='28,0,0,0'>
                            <TextBlock Text='User cannot change the password within (days):' TextWrapping='Wrap' VerticalAlignment='Center' Margin='0,0,8,0'/>
                            <NumericUpDown Grid.Column='1' Name='minAgeUpDown' Minimum='1' Maximum='998' Increment='1' FormatString='0' Width='130'/>
                        </Grid>
                        <CheckBox Name='enforceMaxAgeCheckBox' Content='Enforce maximum password age'/>
                        <Grid ColumnDefinitions='*,Auto' Margin='28,0,0,0'>
                            <TextBlock Text='User must change the password after (days):' TextWrapping='Wrap' VerticalAlignment='Center' Margin='0,0,8,0'/>
                            <NumericUpDown Grid.Column='1' Name='maxAgeUpDown' Minimum='1' Maximum='999' Increment='1' FormatString='0' Width='130'/>
                        </Grid>
                        <CheckBox Name='enforceLockoutCheckBox' Content='Enforce account lockout policy:' Margin='0,8,0,0'/>
                        <StackPanel Name='lockoutPanel' Spacing='8' Margin='28,0,0,0'>
                            <Grid ColumnDefinitions='*,Auto'>
                                <TextBlock Text='Number of failed logon attempts allowed:' TextWrapping='Wrap' VerticalAlignment='Center' Margin='0,0,8,0'/>
                                <NumericUpDown Grid.Column='1' Name='thresholdUpDown' Minimum='1' Maximum='65535' Increment='1' FormatString='0' Width='130'/>
                            </Grid>
                            <Grid ColumnDefinitions='*,Auto'>
                                <TextBlock Text='Reset failed logon attempts count after (mins):' TextWrapping='Wrap' VerticalAlignment='Center' Margin='0,0,8,0'/>
                                <NumericUpDown Grid.Column='1' Name='observationUpDown' Minimum='1' Maximum='99999' Increment='1' FormatString='0' Width='130'/>
                            </Grid>
                            <TextBlock Text='Account will be locked out'/>
                            <Grid ColumnDefinitions='*,Auto'>
                                <RadioButton Name='lockForDurationRadio' GroupName='lockout' Content='For a duration of (mins):' Margin='0,0,8,0'/>
                                <NumericUpDown Grid.Column='1' Name='durationUpDown' Minimum='1' Maximum='99999' Increment='1' FormatString='0' Width='130'/>
                            </Grid>
                            <RadioButton Name='lockUntilUnlockRadio' GroupName='lockout'>
                                <TextBlock Text='Until an administrator manually unlocks the account' TextWrapping='Wrap'/>
                            </RadioButton>
                        </StackPanel>
                    </StackPanel>
                </Grid>

                <!-- Directly Applies To -->
                <Border Padding='12' CornerRadius='4' BorderThickness='1' BorderBrush='#0078D4'>
                    <StackPanel Spacing='8'>
                        <TextBlock Text='Directly Applies To' FontSize='15' FontWeight='SemiBold'/>
                        <TextBlock Name='groupRuleTextBlock' FontSize='12' TextWrapping='Wrap' Opacity='0.75'/>
                        <Grid ColumnDefinitions='*,16,*'>
                            <StackPanel Grid.Column='0' Spacing='6'>
                                <ListBox Name='subjectsList' Height='170' SelectionMode='Multiple'>
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <StackPanel>
                                                <TextBlock Text='{Binding Name}' FontWeight='SemiBold'/>
                                                <TextBlock Text='{Binding Kind}' FontSize='11' Opacity='0.75'/>
                                            </StackPanel>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                                <Button Name='subjectRemoveButton' Content='Remove'/>
                            </StackPanel>
                            <StackPanel Grid.Column='2' Spacing='6'>
                                <Grid ColumnDefinitions='*,Auto'>
                                    <TextBox Grid.Column='0' Name='subjectSearchTextBox' Watermark='Search a user or a group...'/>
                                    <Button Grid.Column='1' Name='subjectSearchButton' Content='Search' Margin='8,0,0,0'/>
                                </Grid>
                                <ListBox Name='subjectResultsList' Height='128' SelectionMode='Multiple'>
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <StackPanel>
                                                <TextBlock Text='{Binding Name}' FontWeight='SemiBold'/>
                                                <TextBlock Text='{Binding Kind}' FontSize='11' Opacity='0.75'/>
                                            </StackPanel>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                                <Button Name='subjectAddButton' Content='Add'/>
                            </StackPanel>
                        </Grid>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>

        <Grid Grid.Row='2' ColumnDefinitions='*,Auto'>
            <TextBlock Name='errorTextBlock' TextWrapping='Wrap' VerticalAlignment='Center' Foreground='#D13438' Margin='0,0,12,0'/>
            <StackPanel Grid.Column='1' Orientation='Horizontal' Spacing='8'>
                <Button Name='okButton' Content='OK' Width='100' Classes='accent'/>
                <Button Name='cancelButton' Content='Cancel' Width='100'/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
'@
}
