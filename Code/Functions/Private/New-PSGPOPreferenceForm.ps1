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

    Suggestions while typing: the keys and value names of the loaded ADMX files for a registry
    item (with a warning when a policy manages the key), the groups of every computer for the name
    of a local group (its SID filled), the well-known accounts and those of the domain ($Directory)
    for its members.
#>

function New-PSGPOPreferenceForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Type,
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope,
        # The item edited; a new item of the type when $null.
        $Item,
        # The domain whose accounts are suggested (a member of a local group).
        [AllowNull()] $Directory
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
                $Panel.Children.Add((& $NewLabel (Get-PSGPOText $Property.Label)))
                $Combo = [Avalonia.Controls.ComboBox]::new()
                # Shown in the language of the interface; the value is taken by its index.
                $Combo.ItemsSource = @('Create', 'Replace', 'Update', 'Delete' | ForEach-Object { Get-PSGPOText $_ })
                $Combo.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
                $Combo.SelectedIndex = [Math]::Max(0, [array]::IndexOf(@('C', 'R', 'U', 'D'), (& $ValueOf $Property)))
                $Panel.Children.Add($Combo)
                $Controls[$Name] = $Combo
                $Getters[$Name] = { @('C', 'R', 'U', 'D')[$Combo.SelectedIndex] }.GetNewClosure()
            }
            'Bool' {
                $Check = [Avalonia.Controls.CheckBox]::new()
                $Check.Content = Get-PSGPOText $Property.Label
                $Check.IsChecked = (& $ValueOf $Property) -eq '1'
                $Panel.Children.Add($Check)
                $Controls[$Name] = $Check
                $Getters[$Name] = { if ($Check.IsChecked) { '1' } else { '0' } }.GetNewClosure()
            }
            'Choice' {
                $Panel.Children.Add((& $NewLabel (Get-PSGPOText $Property.Label)))
                $None = Get-PSGPOText '(none)'
                $Choices = @($Property.Choices)
                $Combo = [Avalonia.Controls.ComboBox]::new()
                $Combo.ItemsSource = @($Choices | ForEach-Object { if ($_) { $_ } else { $None } })
                $Combo.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
                $Current = & $ValueOf $Property
                $Index = [array]::IndexOf($Choices, $Current)
                if ($Index -lt 0 -and $Current) {
                    # A value of another editor: kept as a choice.
                    $Choices += $Current
                    $Combo.ItemsSource = @($Choices | ForEach-Object { if ($_) { $_ } else { $None } })
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
                $Panel.Children.Add((& $NewLabel "$(Get-PSGPOText $Property.Label)$(if ($Property.Roots) { ": <$($Property.Roots -join '>, <')>" })"))
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
                $Panel.Children.Add((& $NewLabel (Get-PSGPOText '{0}: one per line, ADD or REMOVE then the name (and its SID, S-1-...)' (Get-PSGPOText $Property.Label))))
                # Translated here: the closure of the getter no longer sees the functions of the module.
                $NotAddRemove = Get-PSGPOText "{0}: '{1}' does not start with ADD or REMOVE." (Get-PSGPOText $Property.Label) '{0}'
                $Box = [Avalonia.Controls.TextBox]::new()
                $Box.AcceptsReturn = $true
                $Box.TextWrapping = [Avalonia.Media.TextWrapping]::NoWrap
                $Box.MinHeight = 80
                $Box.Text = (@($(if ($Item) { $Item.Members }) | ForEach-Object { (@($_.Action, $_.Name, $_.Sid) | Where-Object { $_ }) -join ' ' }) -join [Environment]::NewLine)
                $Panel.Children.Add($Box)
                $Controls[$Name] = $Box
                # A member picked: ADD, its name and its SID.
                $Row = [Avalonia.Controls.Grid]::new()
                $Row.ColumnDefinitions = [Avalonia.Controls.ColumnDefinitions]::Parse('*,Auto')
                $Picker = [Avalonia.Controls.AutoCompleteBox]::new()
                $Picker.Watermark = Get-PSGPOText 'A member to add: Administrators, Domain Admins, a name of the domain...'
                Register-PSGPOAccountSuggestion -Box $Picker -Directory $Directory -Insert Name
                $AddMember = [Avalonia.Controls.Button]::new()
                $AddMember.Content = Get-PSGPOText 'Add'
                $AddMember.Margin = [Avalonia.Thickness]::new(8, 0, 0, 0)
                [Avalonia.Controls.Grid]::SetColumn($AddMember, 1)
                $Row.Children.Add($Picker)
                $Row.Children.Add($AddMember)
                $Panel.Children.Add($Row)
                $Controls["$($Name)Picker"] = $Picker
                $Controls["$($Name)Add"] = $AddMember
                $AddMember.add_Click({
                    $Text = "$($Picker.Text)".Trim()
                    if (-not $Text) { return }
                    $Picked = $Picker.SelectedItem
                    $Line = if ($Picked -and $Picked.Value -eq $Text) { (@('ADD', $Picked.Name, $Picked.Sid) | Where-Object { $_ }) -join ' ' } else { "ADD $Text" }
                    $Box.Text = (@(@("$($Box.Text)" -split '\r?\n' | Where-Object { $_.Trim() }) + $Line) -join [Environment]::NewLine)
                    # As Clear-PSGPOSuggestionBox, which this handler does not see: its Text alone comes back.
                    $Picker.IsDropDownOpen = $false
                    $Picker.SelectedItem = $null
                    $Picker.Text = ''
                    $Inner = [Avalonia.VisualTree.VisualExtensions]::GetVisualDescendants($Picker) | Where-Object { $_ -is [Avalonia.Controls.TextBox] } | Select-Object -First 1
                    if ($Inner) { $Inner.Text = '' }
                }.GetNewClosure())
                $Getters[$Name] = {
                    @(foreach ($Line in @("$($Box.Text)" -split '\r?\n' | Where-Object { $_.Trim() })) {
                            $Parts = @($Line.Trim() -split '\s+')
                            $Action = if ($Parts[0] -in 'ADD', 'REMOVE') { $Parts[0].ToUpperInvariant() } else { throw ($NotAddRemove -f $Line) }
                            $Rest = @($Parts | Select-Object -Skip 1)
                            $Sid = if ($Rest.Count -and $Rest[-1] -match '^\*?S-1-[\d-]+$') { $Rest[-1].TrimStart('*'); $Rest = @($Rest | Select-Object -SkipLast 1) } else { '' }
                            [pscustomobject]@{ Action = $Action; Name = ($Rest -join ' '); Sid = $Sid }
                        })
                }.GetNewClosure()
            }
            default {
                $Panel.Children.Add((& $NewLabel "$(Get-PSGPOText $Property.Label)$(if ($Property.Required) { ' *' })"))
                # Suggested while typing: the key and value name of a registry item, the name of a local group.
                $Suggested = ($Type.Element -eq 'Registry' -and $Name -in 'key', 'name') -or ($Type.Element -eq 'Group' -and $Name -eq 'groupName')
                $Box = if ($Suggested) { [Avalonia.Controls.AutoCompleteBox]::new() } else { [Avalonia.Controls.TextBox]::new() }
                $Box.Text = & $ValueOf $Property
                if ($Property.Hint) { $Box.Watermark = Get-PSGPOText $Property.Hint }
                $Panel.Children.Add($Box)
                $Controls[$Name] = $Box
                $Getters[$Name] = { "$($Box.Text)".Trim() }.GetNewClosure()
                if ($Type.Element -eq 'Registry' -and $Name -eq 'key') {
                    $Warning = & $NewLabel ''
                    $Warning.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#CA5010'))
                    $Warning.FontSize = 12
                    $Panel.Children.Add($Warning)
                    $Controls['keyWarning'] = $Warning
                }
            }
        }
    }

    if ($Type.Element -eq 'Registry' -and $Controls.Contains('hive') -and $Controls.Contains('key')) {
        Register-PSGPORegistrySuggestion -Hive $Controls['hive'] -KeyBox $Controls['key'] -ValueBox $Controls['name'] -Warning $Controls['keyWarning']
    }
    if ($Type.Element -eq 'Group' -and $Controls.Contains('groupName')) {
        # A group of every computer picked: its SID too, as GPMC writes it.
        Register-PSGPOAccountSuggestion -Box $Controls['groupName'] -Directory $Directory -Kind BuiltinGroup
        $Controls['groupName'].Tag.SidBox = $Controls['groupSid']
        $Controls['groupName'].add_SelectionChanged({
                param($control, $e)
                if ($control.SelectedItem -and $control.Tag.SidBox) { $control.Tag.SidBox.Text = $control.SelectedItem.Sid }
            })
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
