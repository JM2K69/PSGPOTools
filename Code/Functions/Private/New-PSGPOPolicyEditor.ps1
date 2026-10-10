<#
    Builds the options form of a policy from its ADMX elements, in the ADML presentation
    order, like the Group Policy editor:
      checkBox -> CheckBox, dropdownList -> ComboBox, decimalTextBox -> NumericUpDown,
      textBox -> TextBox, multiTextBox -> multi-line TextBox, listBox -> editable list,
      text -> TextBlock.

    Returns @{ Panel; GetValue; Controls }:
      Panel     the StackPanel to display;
      GetValue  scriptblock returning the hashtable expected by Get-PSGPOPolicyRegistryChange;
      Controls  element Id -> its control(s), for the tests.
    -OnChange runs after every edit. The handlers are closures because they fire after this
    function has returned; they only call -OnChange, never module functions.
#>

function New-PSGPOPolicyEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicy]$Policy,
        [scriptblock]$OnChange = {}
    )

    $Panel = [Avalonia.Controls.StackPanel]::new()
    $Panel.Spacing = 10
    $Getters = @{}
    $Controls = @{}

    $NewLabel = {
        param([string]$Text)
        $Block = [Avalonia.Controls.TextBlock]::new()
        $Block.Text = $Text
        $Block.TextWrapping = [Avalonia.Media.TextWrapping]::Wrap
        $Block
    }

    # Elements in presentation order, then those the ADML does not present.
    $Ordered = [System.Collections.Generic.List[object]]::new()
    $Placed = @{}
    foreach ($Item in $Policy.Layout) {
        $Element = if ($Item.RefId) { $Policy.Elements | Where-Object Id -EQ $Item.RefId | Select-Object -First 1 }
        if ($Element) {
            $Ordered.Add($Element)
            $Placed[$Element.Id] = $true
        } elseif (-not $Item.RefId -and $Item.Label) {
            $Ordered.Add($Item.Label)
        }
    }
    foreach ($Element in $Policy.Elements) {
        if (-not $Placed.ContainsKey($Element.Id)) { $Ordered.Add($Element) }
    }

    foreach ($Entry in $Ordered) {
        if ($Entry -is [string]) {
            $Panel.Children.Add((& $NewLabel $Entry))
            continue
        }
        $Element = $Entry
        $Label = if ($Element.Label) { $Element.Label } else { $Element.Id }
        $Default = Get-PSGPOElementDefault -Element $Element
        $Box = [Avalonia.Controls.StackPanel]::new()
        $Box.Spacing = 4

        switch ($Element.Type) {
            'Boolean' {
                $CheckBox = [Avalonia.Controls.CheckBox]::new()
                $CheckBox.Content = $Label
                $CheckBox.IsChecked = [bool]$Default
                $CheckBox.add_IsCheckedChanged({ & $OnChange }.GetNewClosure())
                $Box.Children.Add($CheckBox)
                $Getters[$Element.Id] = { [bool]$CheckBox.IsChecked }.GetNewClosure()
                $Controls[$Element.Id] = $CheckBox
            }
            'Enum' {
                $Box.Children.Add((& $NewLabel $Label))
                # Display order: sorted by label unless noSort; ItemIndex keeps the ADMX index.
                $Choices = for ($i = 0; $i -lt $Element.Items.Count; $i++) {
                    [pscustomobject]@{ ItemIndex = $i; Text = "$($Element.Items[$i].DisplayName)" }
                }
                if (-not $Element.NoSort) { $Choices = $Choices | Sort-Object Text }
                $Choices = @($Choices)
                $ComboBox = [Avalonia.Controls.ComboBox]::new()
                $ComboBox.ItemsSource = [string[]]$Choices.Text
                $ComboBox.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
                $Selected = [array]::FindIndex([object[]]$Choices, [Predicate[object]] { param($c) $c.ItemIndex -eq $Default }.GetNewClosure())
                $ComboBox.SelectedIndex = [Math]::Max(0, $Selected)
                $ComboBox.add_SelectionChanged({ & $OnChange }.GetNewClosure())
                $Box.Children.Add($ComboBox)
                $Getters[$Element.Id] = { if ($ComboBox.SelectedIndex -ge 0) { $Choices[$ComboBox.SelectedIndex].ItemIndex } else { -1 } }.GetNewClosure()
                $Controls[$Element.Id] = $ComboBox
            }
            { $_ -in 'Decimal', 'LongDecimal' } {
                $Box.Children.Add((& $NewLabel $Label))
                $Numeric = [Avalonia.Controls.NumericUpDown]::new()
                $Numeric.Minimum = [decimal]$Element.MinValue
                $Numeric.Maximum = [decimal]$Element.MaxValue
                $Numeric.Increment = [decimal]$Element.SpinStep
                $Numeric.FormatString = '0'
                $Numeric.ParsingNumberStyle = [System.Globalization.NumberStyles]::Integer
                $Numeric.Value = [decimal][Math]::Min([Math]::Max([decimal]$Default, [decimal]$Element.MinValue), [decimal]$Element.MaxValue)
                $Numeric.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Left
                $Numeric.MinWidth = 160
                $Numeric.add_ValueChanged({ & $OnChange }.GetNewClosure())
                $Box.Children.Add($Numeric)
                $Getters[$Element.Id] = { if ($null -ne $Numeric.Value) { [uint64]$Numeric.Value } else { '' } }.GetNewClosure()
                $Controls[$Element.Id] = $Numeric
            }
            { $_ -in 'Text', 'MultiText' } {
                $Box.Children.Add((& $NewLabel $Label))
                $TextBox = [Avalonia.Controls.TextBox]::new()
                if ($Element.Type -eq 'MultiText') {
                    $TextBox.AcceptsReturn = $true
                    $TextBox.TextWrapping = [Avalonia.Media.TextWrapping]::Wrap
                    $TextBox.MinHeight = 80
                    $TextBox.Watermark = 'One entry per line'
                } else {
                    $TextBox.MaxLength = [int][Math]::Min($Element.MaxLength, [int]::MaxValue)
                    $TextBox.Text = "$Default"
                }
                $TextBox.add_TextChanged({ & $OnChange }.GetNewClosure())
                $Box.Children.Add($TextBox)
                $Getters[$Element.Id] = if ($Element.Type -eq 'MultiText') {
                    { [string[]]("$($TextBox.Text)" -split '\r?\n' | Where-Object { $_ -ne '' }) }.GetNewClosure()
                } else {
                    { "$($TextBox.Text)" }.GetNewClosure()
                }
                $Controls[$Element.Id] = $TextBox
            }
            'List' {
                $Box.Children.Add((& $NewLabel $Label))
                # Entries shown in the ListBox; Pairs keeps names and values for explicitValue lists.
                $Entries = [System.Collections.ObjectModel.ObservableCollection[string]]::new()
                $Pairs = [System.Collections.Generic.List[object]]::new()
                $Explicit = $Element.ExplicitValue

                $ListBox = [Avalonia.Controls.ListBox]::new()
                $ListBox.ItemsSource = $Entries
                $ListBox.MinHeight = 60
                $ListBox.MaxHeight = 180

                $InputRow = [Avalonia.Controls.StackPanel]::new()
                $InputRow.Orientation = [Avalonia.Layout.Orientation]::Horizontal
                $InputRow.Spacing = 6
                $NameInput = [Avalonia.Controls.TextBox]::new()
                $NameInput.MinWidth = 220
                $NameInput.Watermark = if ($Explicit) { 'Value name' } else { 'New entry' }
                $ValueInput = [Avalonia.Controls.TextBox]::new()
                $ValueInput.MinWidth = 220
                $ValueInput.Watermark = 'Value'
                $ValueInput.IsVisible = $Explicit
                $AddButton = [Avalonia.Controls.Button]::new()
                $AddButton.Content = 'Add'
                $RemoveButton = [Avalonia.Controls.Button]::new()
                $RemoveButton.Content = 'Remove'
                foreach ($Child in $NameInput, $ValueInput, $AddButton, $RemoveButton) { $InputRow.Children.Add($Child) }

                $AddButton.add_Click({
                    $Name = "$($NameInput.Text)".Trim()
                    if ($Name -eq '') { return }
                    $Data = if ($Explicit) { "$($ValueInput.Text)" } else { $Name }
                    $Pairs.Add(@{ Name = $Name; Value = $Data })
                    $Entries.Add($(if ($Explicit) { "$Name = $Data" } else { $Name }))
                    $NameInput.Text = ''
                    $ValueInput.Text = ''
                    & $OnChange
                }.GetNewClosure())
                $RemoveButton.add_Click({
                    $Index = $ListBox.SelectedIndex
                    if ($Index -lt 0) { return }
                    $Pairs.RemoveAt($Index)
                    $Entries.RemoveAt($Index)
                    & $OnChange
                }.GetNewClosure())

                $Box.Children.Add($ListBox)
                $Box.Children.Add($InputRow)
                $Getters[$Element.Id] = if ($Explicit) {
                    { @($Pairs | ForEach-Object { @{ Name = $_.Name; Value = $_.Value } }) }.GetNewClosure()
                } else {
                    { [string[]]@($Pairs | ForEach-Object { $_.Value }) }.GetNewClosure()
                }
                $Controls[$Element.Id] = @{ ListBox = $ListBox; Entries = $Entries; NameInput = $NameInput; ValueInput = $ValueInput; Add = $AddButton; Remove = $RemoveButton }
            }
        }
        $Panel.Children.Add($Box)
    }

    if ($Policy.Elements.Count -eq 0) {
        $Panel.Children.Add((& $NewLabel 'This policy has no option: enable or disable it.'))
    }

    [pscustomobject]@{
        Panel = $Panel
        GetValue = {
            $Result = @{}
            foreach ($Id in $Getters.Keys) { $Result[$Id] = & $Getters[$Id] }
            $Result
        }.GetNewClosure()
        Controls = $Controls
    }
}
