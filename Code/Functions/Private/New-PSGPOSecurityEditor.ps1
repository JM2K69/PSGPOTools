<#
    Builds the form of a security setting (GPOToolsSecuritySetting), as the Group Policy editor
    shows it once "Define this policy setting" is checked:
      Number                 NumericUpDown with its unit, its special values as a hint
      Boolean                Enabled / Disabled
      Text                   TextBox
      Choice                 ComboBox of the choices
      Audit                  Success and Failure check boxes
      Accounts               editable list of accounts (names, or SIDs written *S-1-...)
      RegistryValue          by its display: Boolean, Number, Text, Choice, MultiText (one
                             value per line), Bitmask (one check box per flag)

    Returns @{ Panel; GetValue; Controls } like New-PSGPOPolicyEditor: GetValue returns the value
    of the setting (Set-PSGPOSecurityValue -Value). -OnChange runs after every edit; the handlers
    are closures that only call it.
#>

function New-PSGPOSecurityEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsSecuritySetting]$Setting,
        # Value shown; the default of its kind when $null.
        [AllowNull()] $Value,
        [scriptblock]$OnChange = {}
    )

    $Panel = [Avalonia.Controls.StackPanel]::new()
    $Panel.Spacing = 8
    $Controls = @{}
    $Display = if ($Setting.Kind -eq 'RegistryValue') { $Setting.Display } else { $Setting.Kind }

    $NewText = {
        param([string]$Text)
        $Block = [Avalonia.Controls.TextBlock]::new()
        $Block.Text = $Text
        $Block.TextWrapping = [Avalonia.Media.TextWrapping]::Wrap
        $Block
    }
    $NewCombo = {
        param([string[]]$Texts, [int]$Selected)
        $Combo = [Avalonia.Controls.ComboBox]::new()
        $Combo.ItemsSource = $Texts
        $Combo.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
        $Combo.SelectedIndex = [Math]::Max(0, $Selected)
        $Combo.add_SelectionChanged({ & $OnChange }.GetNewClosure())
        $Combo
    }

    switch ($Display) {
        'Boolean' {
            $Combo = & $NewCombo @('Enabled', 'Disabled') $(if ($null -eq $Value -or $Value) { 0 } else { 1 })
            $Panel.Children.Add($Combo)
            $Controls['Value'] = $Combo
            $GetValue = { $Combo.SelectedIndex -eq 0 }.GetNewClosure()
        }
        { $_ -in 'Number' } {
            $Row = [Avalonia.Controls.StackPanel]::new()
            $Row.Orientation = [Avalonia.Layout.Orientation]::Horizontal
            $Row.Spacing = 8
            $Numeric = [Avalonia.Controls.NumericUpDown]::new()
            # Special values (-1: never...) are below the minimum: the range allows them.
            $Special = @($Setting.Choices | ForEach-Object { [decimal]$_.Value })
            $Minimum = if ($null -ne $Setting.Min) { [decimal]$Setting.Min } else { [decimal]0 }
            if ($Special.Count) { $Minimum = [Math]::Min($Minimum, ($Special | Measure-Object -Minimum).Minimum) }
            $Numeric.Minimum = $Minimum
            $Numeric.Maximum = if ($null -ne $Setting.Max) { [decimal]$Setting.Max } else { [decimal][uint32]::MaxValue }
            $Numeric.FormatString = '0'
            $Numeric.ParsingNumberStyle = [System.Globalization.NumberStyles]::Integer
            $Numeric.MinWidth = 160
            $Numeric.Value = if ($null -ne $Value) { [decimal]$Value } elseif ($null -ne $Setting.Min) { [decimal]$Setting.Min } else { [decimal]0 }
            $Numeric.add_ValueChanged({ & $OnChange }.GetNewClosure())
            $Row.Children.Add($Numeric)
            if ($Setting.Unit) { $Row.Children.Add((& $NewText $Setting.Unit)) }
            $Panel.Children.Add($Row)
            if ($Setting.Choices) {
                $Panel.Children.Add((& $NewText ((@($Setting.Choices | ForEach-Object { "$($_.Value): $($_.Text)" }) -join [Environment]::NewLine))))
            }
            $Controls['Value'] = $Numeric
            $GetValue = { if ($null -ne $Numeric.Value) { [long]$Numeric.Value } }.GetNewClosure()
        }
        'Text' {
            $TextBox = [Avalonia.Controls.TextBox]::new()
            $TextBox.Text = "$Value"
            $TextBox.add_TextChanged({ & $OnChange }.GetNewClosure())
            $Panel.Children.Add($TextBox)
            $Controls['Value'] = $TextBox
            $GetValue = { "$($TextBox.Text)" }.GetNewClosure()
        }
        'Choice' {
            $Choices = @($Setting.Choices)
            $Selected = [array]::FindIndex([object[]]$Choices, [Predicate[object]] { param($c) $c.Value -eq "$Value" }.GetNewClosure())
            $Combo = & $NewCombo ([string[]]$Choices.Text) $Selected
            $Panel.Children.Add($Combo)
            $Controls['Value'] = $Combo
            $GetValue = { if ($Combo.SelectedIndex -ge 0) { [long]$Choices[$Combo.SelectedIndex].Value } }.GetNewClosure()
        }
        'Audit' {
            $Panel.Children.Add((& $NewText (Get-PSGPOText 'Audit these attempts:')))
            $Success = [Avalonia.Controls.CheckBox]::new()
            $Success.Content = Get-PSGPOText 'Success'
            $Success.IsChecked = ([long]$Value -band 1) -eq 1
            $Failure = [Avalonia.Controls.CheckBox]::new()
            $Failure.Content = Get-PSGPOText 'Failure'
            $Failure.IsChecked = ([long]$Value -band 2) -eq 2
            foreach ($Box in $Success, $Failure) {
                $Box.add_IsCheckedChanged({ & $OnChange }.GetNewClosure())
                $Panel.Children.Add($Box)
            }
            $Controls['Success'] = $Success
            $Controls['Failure'] = $Failure
            $GetValue = { $(if ($Success.IsChecked) { 1 } else { 0 }) + $(if ($Failure.IsChecked) { 2 } else { 0 }) }.GetNewClosure()
        }
        'Bitmask' {
            $Boxes = @(foreach ($Choice in $Setting.Choices) {
                    $Box = [Avalonia.Controls.CheckBox]::new()
                    $Box.Content = $Choice.Text
                    $Box.Tag = [long]$Choice.Value
                    $Box.IsChecked = ([long]$Value -band [long]$Choice.Value) -eq [long]$Choice.Value -and [long]$Choice.Value -ne 0
                    $Box.add_IsCheckedChanged({ & $OnChange }.GetNewClosure())
                    $Panel.Children.Add($Box)
                    $Box
                })
            $Controls['Flags'] = $Boxes
            $GetValue = { [long]((@($Boxes | Where-Object IsChecked | ForEach-Object Tag) + 0 | Measure-Object -Sum).Sum) }.GetNewClosure()
        }
        { $_ -in 'Accounts', 'MultiText' } {
            # One entry per line in a list: accounts of a user right, values of a REG_MULTI_SZ.
            # Items: the values as written; Entries: as shown (an account with its name).
            $Items = [System.Collections.Generic.List[string]]::new()
            $Entries = [System.Collections.ObjectModel.ObservableCollection[string]]::new()
            $Show = if ($Display -eq 'Accounts') {
                {
                    param([string]$Account)
                    $Name = [GPOToolsSecuritySetting]::FormatAccount($Account)
                    if ($Name -ne $Account.TrimStart('*')) { "$Name ($Account)" } else { $Account }
                }
            } else { { param([string]$Item) $Item } }
            foreach ($Item in @($Value | Where-Object { "$_" -ne '' })) {
                $Items.Add("$Item")
                $Entries.Add((& $Show "$Item"))
            }
            $ListBox = [Avalonia.Controls.ListBox]::new()
            $ListBox.ItemsSource = $Entries
            $ListBox.MinHeight = 60
            $ListBox.MaxHeight = 220
            $InputRow = [Avalonia.Controls.StackPanel]::new()
            $InputRow.Orientation = [Avalonia.Layout.Orientation]::Horizontal
            $InputRow.Spacing = 6
            $NameInput = [Avalonia.Controls.TextBox]::new()
            $NameInput.MinWidth = 260
            $NameInput.Watermark = Get-PSGPOText $(if ($Display -eq 'Accounts') { 'DOMAIN\account or *S-1-5-32-544' } else { 'New value' })
            $AddButton = [Avalonia.Controls.Button]::new()
            $AddButton.Content = Get-PSGPOText 'Add'
            $RemoveButton = [Avalonia.Controls.Button]::new()
            $RemoveButton.Content = Get-PSGPOText 'Remove'
            foreach ($Child in $NameInput, $AddButton, $RemoveButton) { $InputRow.Children.Add($Child) }
            $AddButton.add_Click({
                $Entry = "$($NameInput.Text)".Trim()
                if ($Entry -eq '' -or $Items.Contains($Entry)) { return }
                $Items.Add($Entry)
                $Entries.Add((& $Show $Entry))
                $NameInput.Text = ''
                & $OnChange
            }.GetNewClosure())
            $RemoveButton.add_Click({
                $Index = $ListBox.SelectedIndex
                if ($Index -lt 0) { return }
                $Items.RemoveAt($Index)
                $Entries.RemoveAt($Index)
                & $OnChange
            }.GetNewClosure())
            $Panel.Children.Add($ListBox)
            $Panel.Children.Add($InputRow)
            $Controls['Value'] = @{ ListBox = $ListBox; Entries = $Entries; Items = $Items; NameInput = $NameInput; Add = $AddButton; Remove = $RemoveButton }
            $GetValue = { [string[]]@($Items) }.GetNewClosure()
        }
        default {
            $Panel.Children.Add((& $NewText (Get-PSGPOText 'This setting ({0}) cannot be edited here.' $Display)))
            $GetValue = { $Value }.GetNewClosure()
        }
    }

    [pscustomobject]@{ Panel = $Panel; GetValue = $GetValue; Controls = $Controls }
}
