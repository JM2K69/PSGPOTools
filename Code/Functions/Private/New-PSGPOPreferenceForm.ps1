<#
    Builds the form of a preference item from its type in the catalog (Resources/
    Preferences.json), as the GPMC dialog of the item shows it:
      Action      Create / Replace / Update / Delete
      Text        TextBox (Number: digits only)
      Bool        CheckBox
      Choice      ComboBox of the values ("(none)" for an empty value)
      Password    a warning when the item stores one: it is kept, never written (MS14-025)
      Members     one member per line: ADD or REMOVE, the name, and the SID if known
      Xml         the elements the item holds (a task definition, Reg values), checked when saved
    then the options of the Common tab: description, continue after an error, run in the
    security context of the user, remove the item when it no longer applies.

    Returns @{ Panel; GetValues; GetCommon; Controls }: GetValues the attributes of Properties
    (and Members), GetCommon the common attributes, for Set-PSGPOPreferenceElement.
#>

function New-PSGPOPreferenceForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Type,
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope,
        # The item edited; a new item of the type when $null.
        $Item
    )

    $Panel = [Avalonia.Controls.StackPanel]::new()
    $Panel.Spacing = 6
    $Controls = [ordered]@{}
    $Getters = [ordered]@{}
    $Values = if ($Item) { $Item.Properties } else { @{} }

    $NewLabel = {
        param([string]$Text)
        $Block = [Avalonia.Controls.TextBlock]::new()
        $Block.Text = $Text
        $Block.TextWrapping = [Avalonia.Media.TextWrapping]::Wrap
        $Block.Margin = [Avalonia.Thickness]::new(0, 4, 0, 0)
        $Block
    }
    $ValueOf = {
        param($Property)
        if ($Item) { return "$($Values[$Property.Name])" }
        if ($Scope -eq 'User' -and $null -ne $Property.UserDefault) { return "$($Property.UserDefault)" }
        if ($null -ne $Property.Default) { return "$($Property.Default)" }
        ''
    }

    foreach ($Property in @($Type.Properties)) {
        $Name = $Property.Name
        switch ($Property.Type) {
            'Action' {
                $Panel.Children.Add((& $NewLabel $Property.Label))
                $Combo = [Avalonia.Controls.ComboBox]::new()
                $Combo.ItemsSource = @('Create', 'Replace', 'Update', 'Delete')
                $Combo.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
                $Combo.SelectedIndex = [Math]::Max(0, [array]::IndexOf(@('C', 'R', 'U', 'D'), (& $ValueOf $Property)))
                $Panel.Children.Add($Combo)
                $Controls[$Name] = $Combo
                $Getters[$Name] = { @('C', 'R', 'U', 'D')[$Combo.SelectedIndex] }.GetNewClosure()
            }
            'Bool' {
                $Check = [Avalonia.Controls.CheckBox]::new()
                $Check.Content = $Property.Label
                $Check.IsChecked = (& $ValueOf $Property) -eq '1'
                $Panel.Children.Add($Check)
                $Controls[$Name] = $Check
                $Getters[$Name] = { if ($Check.IsChecked) { '1' } else { '0' } }.GetNewClosure()
            }
            'Choice' {
                $Panel.Children.Add((& $NewLabel $Property.Label))
                $Choices = @($Property.Choices)
                $Combo = [Avalonia.Controls.ComboBox]::new()
                $Combo.ItemsSource = @($Choices | ForEach-Object { if ($_) { $_ } else { '(none)' } })
                $Combo.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
                $Current = & $ValueOf $Property
                $Index = [array]::IndexOf($Choices, $Current)
                if ($Index -lt 0 -and $Current) {
                    # A value of another editor: kept as a choice.
                    $Choices += $Current
                    $Combo.ItemsSource = @($Choices | ForEach-Object { if ($_) { $_ } else { '(none)' } })
                    $Index = $Choices.Count - 1
                }
                $Combo.SelectedIndex = [Math]::Max(0, $Index)
                $Panel.Children.Add($Combo)
                $Controls[$Name] = $Combo
                $Getters[$Name] = { $Choices[$Combo.SelectedIndex] }.GetNewClosure()
            }
            'Password' {
                if ($Item -and $Item.HasPassword) {
                    $Warning = & $NewLabel (Get-PSGPOText 'A password is stored in this item. Any user of the domain can read it (MS14-025): it is kept as it is, and this console never writes passwords. Remove it with GPMC, or delete the item.')
                    $Warning.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
                    $Panel.Children.Add($Warning)
                }
            }
            'Xml' {
                $Panel.Children.Add((& $NewLabel "$($Property.Label)$(if ($Property.Roots) { ": <$($Property.Roots -join '>, <')>" })"))
                $Box = [Avalonia.Controls.TextBox]::new()
                $Box.AcceptsReturn = $true
                $Box.TextWrapping = [Avalonia.Media.TextWrapping]::NoWrap
                $Box.MinHeight = 160
                $Box.MaxHeight = 420
                $Box.FontFamily = [Avalonia.Media.FontFamily]::new('Consolas, DejaVu Sans Mono, monospace')
                $Box.FontSize = 12
                $Box.Text = if ($Item) { "$($Item.Xml[$Name])" } else { Format-PSGPOXmlText "$($Property.Default)" }
                $Panel.Children.Add($Box)
                $Controls[$Name] = $Box
                $Getters[$Name] = { "$($Box.Text)" }.GetNewClosure()
            }
            'Members' {
                $Panel.Children.Add((& $NewLabel (Get-PSGPOText '{0}: one per line, ADD or REMOVE then the name (and its SID, S-1-...)' $Property.Label)))
                $Box = [Avalonia.Controls.TextBox]::new()
                $Box.AcceptsReturn = $true
                $Box.TextWrapping = [Avalonia.Media.TextWrapping]::NoWrap
                $Box.MinHeight = 80
                $Box.Text = (@($(if ($Item) { $Item.Members }) | ForEach-Object { (@($_.Action, $_.Name, $_.Sid) | Where-Object { $_ }) -join ' ' }) -join [Environment]::NewLine)
                $Panel.Children.Add($Box)
                $Controls[$Name] = $Box
                $Getters[$Name] = {
                    @(foreach ($Line in @("$($Box.Text)" -split '\r?\n' | Where-Object { $_.Trim() })) {
                            $Parts = @($Line.Trim() -split '\s+')
                            $Action = if ($Parts[0] -in 'ADD', 'REMOVE') { $Parts[0].ToUpperInvariant() } else { throw "Members: '$Line' does not start with ADD or REMOVE." }
                            $Rest = @($Parts | Select-Object -Skip 1)
                            $Sid = if ($Rest.Count -and $Rest[-1] -match '^\*?S-1-[\d-]+$') { $Rest[-1].TrimStart('*'); $Rest = @($Rest | Select-Object -SkipLast 1) } else { '' }
                            [pscustomobject]@{ Action = $Action; Name = ($Rest -join ' '); Sid = $Sid }
                        })
                }.GetNewClosure()
            }
            default {
                $Panel.Children.Add((& $NewLabel "$($Property.Label)$(if ($Property.Required) { ' *' })"))
                $Box = [Avalonia.Controls.TextBox]::new()
                $Box.Text = & $ValueOf $Property
                if ($Property.Hint) { $Box.Watermark = $Property.Hint }
                $Panel.Children.Add($Box)
                $Controls[$Name] = $Box
                $Getters[$Name] = { "$($Box.Text)".Trim() }.GetNewClosure()
            }
        }
    }

    # Common tab
    $Header = & $NewLabel (Get-PSGPOText 'Common options')
    $Header.FontWeight = [Avalonia.Media.FontWeight]::SemiBold
    $Header.Margin = [Avalonia.Thickness]::new(0, 12, 0, 0)
    $Panel.Children.Add($Header)
    $Common = [ordered]@{}
    foreach ($Option in @(
            @{ Name = 'bypassErrors'; Label = 'Continue processing the other items of this type after an error' }
            @{ Name = 'userContext'; Label = "Run in the logged-on user's security context" }
            @{ Name = 'removePolicy'; Label = 'Remove this item when it is no longer applied' })) {
        $Check = [Avalonia.Controls.CheckBox]::new()
        $Check.Content = Get-PSGPOText $Option.Label
        $Check.IsChecked = if ($Item) { [bool]$Item.PSObject.Properties[$Option.Name.Substring(0, 1).ToUpperInvariant() + $Option.Name.Substring(1)].Value } else { $false }
        $Panel.Children.Add($Check)
        $Controls[$Option.Name] = $Check
        $Common[$Option.Name] = { if ($Check.IsChecked) { '1' } else { '0' } }.GetNewClosure()
    }
    $Panel.Children.Add((& $NewLabel (Get-PSGPOText 'Description')))
    $Description = [Avalonia.Controls.TextBox]::new()
    $Description.Text = if ($Item) { $Item.Description } else { '' }
    $Panel.Children.Add($Description)
    $Controls['desc'] = $Description
    $Common['desc'] = { "$($Description.Text)".Trim() }.GetNewClosure()
    if ($Item -and $Item.FilterCount) {
        $Panel.Children.Add((& $NewLabel (Get-PSGPOText 'Item-level targeting: {0} filter(s), kept as they are (edit them with GPMC).' $Item.FilterCount)))
    }

    $GetValues = {
        $Result = [ordered]@{}
        foreach ($Key in $Getters.Keys) { $Result[$Key] = & $Getters[$Key] }
        $Result
    }.GetNewClosure()
    $GetCommon = {
        $Result = [ordered]@{}
        foreach ($Key in $Common.Keys) { $Result[$Key] = & $Common[$Key] }
        $Result
    }.GetNewClosure()
    @{ Panel = $Panel; GetValues = $GetValues; GetCommon = $GetCommon; Controls = $Controls }
}
