<#
    The Preferences ([MS-GPPREF]) of the GPO edited: the items of a type, the form of an item,
    their order, saved in the XML file of the type.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerPreferenceView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerPreferenceView {
    # The type shown, the item edited and its form; the files read once per GPO edited.
    $preferences = @{ Node = $null; File = $null; Item = $null; Type = $null; Form = $null }

    function Set-PreferenceStatus {
        param([string]$Text, [switch]$Problem)
        $preferencesStatusTextBlock.Text = $Text
        if ($Problem) { $preferencesStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $preferencesStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # The file of a preference type of the GPO: read once; an empty one when the GPO has none.
    function Get-PreferenceFile {
        param([GPOToolsPreferenceNode]$Node)
        $key = "$($Node.Scope)|$($Node.Extension.Id)"
        if (-not $editing.Preferences.ContainsKey($key)) {
            $bytes = $Directory.ReadPreferenceFile($editing.Gpo, $Node.Scope, $Node.Extension.Path)
            $editing.Preferences[$key] = if ($bytes) { [GPOToolsPreferenceFile]::Parse($bytes) } else { [GPOToolsPreferenceFile]::Create($Node.Extension.Root, $Node.Extension.RootClsid) }
        }
        $editing.Preferences[$key]
    }

    function Test-PreferenceEditable {
        $editing.Gpo -and $editing.Gpo.CanEdit -and -not $Directory.IsReadOnly -and $preferences.File
    }

    function Update-PreferenceToolbar {
        $row = $preferencesList.SelectedItem
        $editable = Test-PreferenceEditable
        $preferencesNewButton.IsEnabled = $editable -and $null -ne $preferencesNewTypeComboBox.SelectedItem
        $preferencesEditButton.IsEnabled = $editable -and $row -and $row.Item.Editable
        $preferencesDeleteButton.IsEnabled = $editable -and $row
        $preferencesUpButton.IsEnabled = $editable -and $row -and -not $row.Item.Collection
        $preferencesDownButton.IsEnabled = $editable -and $row -and -not $row.Item.Collection
    }

    # The items of the type selected in the tree, for the edited GPO.
    function Show-PreferenceType {
        param([GPOToolsPreferenceNode]$Node, [string]$Status, [string]$SelectUid)
        $preferences.Node = $Node
        $preferences.File = $null
        $extension = $Node.Extension
        $scopeLabel = Get-PSGPOText $(if ($Node.Scope -eq 'Machine') { 'Computer Configuration' } else { 'User Configuration' })
        $preferencesTitleTextBlock.Text = "$(Get-PSGPOText $extension.Name) ($scopeLabel)"
        $types = @($extension.Items | Where-Object { $_.Properties -and -not $_.IsCollection })
        $preferencesInfoTextBlock.Text = (Get-PSGPOText 'Preferences > {0} > {1}: Preferences\{2} in the {3} folder of the GPO, client-side extension {4}.' (Get-PSGPOText $extension.Group) (Get-PSGPOText $extension.Name) $extension.Path (Get-PSGPOText $Node.Scope) $extension.Cse) +
            $(if (-not $types.Count) { Get-PSGPOText ' Its items are created with GPMC: the console shows them, keeps them as they are and deletes them.' })
        $preferencesFormBorder.IsVisible = $false
        $preferencesDeletePanel.IsVisible = $false
        $preferencesNewTypeComboBox.ItemsSource = @($types | ForEach-Object { Get-PSGPOText $_.Label })
        $preferencesNewTypeComboBox.SelectedIndex = if ($types.Count) { 0 } else { -1 }
        $preferencesNewTypeComboBox.IsVisible = $types.Count -gt 0
        $preferencesNewButton.IsVisible = $types.Count -gt 0
        $rows = @()
        $problem = $null
        if (-not $editing.Gpo) {
            $preferencesEmptyTextBlock.Text = Get-PSGPOText 'Edit a GPO (Group Policy Management view) to see and configure its preferences.'
        } else {
            try {
                $preferences.File = Get-PreferenceFile $Node
                $rows = @(foreach ($item in @(Get-PSGPOPreferenceItem -File $preferences.File -Extension $extension)) {
                        $row = [AvaloniaPreferenceRow]::new()
                        $row.Name = "$(if ($item.Collection) { "$($item.Collection) > " })$(if ($item.Name) { $item.Name } else { Get-PSGPOText $item.Label })"
                        $row.Summary = Get-PSGPOPreferenceSummary -Item $item
                        $row.Flags = (@(
                                if ($item.Disabled) { Get-PSGPOText 'Disabled' }
                                if ($item.FilterCount) { Get-PSGPOText '{0} targeting filter(s)' $item.FilterCount }
                                if ($item.HasPassword) { Get-PSGPOText 'Stores a password readable by any user of the domain (MS14-025)' }
                                if (-not $item.Editable) { Get-PSGPOText 'Edited with GPMC' }) -join ' - ')
                        $row.Item = $item
                        $row
                    })
                $preferencesEmptyTextBlock.Text = if ($rows.Count) { '' } else { Get-PSGPOText $(if ($Node.Scope -eq 'Machine') { 'This GPO has no {0} item for the computers.' } else { 'This GPO has no {0} item for the users.' }) (Get-PSGPOText $extension.Name) }
            } catch {
                $problem = Get-PSGPOText 'The preferences cannot be read: {0}' $_.Exception.GetBaseException().Message
                $preferencesEmptyTextBlock.Text = ''
            }
        }
        $preferencesEmptyTextBlock.IsVisible = [bool]$preferencesEmptyTextBlock.Text
        $preferencesList.ItemsSource = $rows
        if ($SelectUid) { $preferencesList.SelectedItem = $rows | Where-Object { $_.Item.Uid -eq $SelectUid } | Select-Object -First 1 }
        if ($problem) { Set-PreferenceStatus $problem -Problem } else { Set-PreferenceStatus $Status }
        Update-PreferenceToolbar
    }

    # Applies a change to a copy of the file, writes it to the GPO, then shows the items again;
    # returns the error message when the change or the write failed (nothing is kept then).
    function Save-PreferenceFile {
        param([scriptblock]$Change, [string]$Done, [string]$SelectUid)
        $node = $preferences.Node
        $copy = [GPOToolsPreferenceFile]::Parse($preferences.File.ToBytes())
        try {
            $uid = & $Change $copy
            $Directory.WritePreferenceFile($editing.Gpo, $node.Scope, $node.Extension.Path, $copy.ToBytes(), $node.Extension.Cse, $node.Extension.Tool)
        } catch {
            return $_.Exception.GetBaseException().Message
        }
        $editing.Preferences["$($node.Scope)|$($node.Extension.Id)"] = $copy
        $settingsCache.Remove("$($editing.Gpo.Id)")
        $version = if ($node.Scope -eq 'Machine') { $editing.Gpo.GetComputerVersion() } else { $editing.Gpo.GetUserVersion() }
        Show-PreferenceType -Node $node -Status (Get-PSGPOText '{0} in Preferences\{1} ({2} version {3}).' $Done $node.Extension.Path (Get-PSGPOText $node.Scope) $version) -SelectUid $(if ($uid) { $uid } else { $SelectUid })
        $null
    }

    function Find-PreferenceElement {
        param([GPOToolsPreferenceFile]$File, [string]$Uid)
        $File.Document.SelectSingleNode("//*[@uid='$Uid']")
    }

    function Open-PreferenceForm {
        param($Type, $Item)
        $preferences.Type = $Type
        $preferences.Item = $Item
        $preferences.Form = New-PSGPOPreferenceForm -Type $Type -Scope $preferences.Node.Scope -Item $Item -Directory $Directory
        $preferencesFormHost.Content = $preferences.Form.Panel
        $preferencesFormTitleTextBlock.Text = if ($Item) { "$(Get-PSGPOText $Type.Label): $($Item.Name)" } else { Get-PSGPOText 'New {0}' (Get-PSGPOText $Type.Label) }
        $preferencesFormErrorTextBlock.Text = ''
        $preferencesDeletePanel.IsVisible = $false
        $preferencesFormBorder.IsVisible = $true
    }

    $preferencesList.add_SelectionChanged({ Update-PreferenceToolbar })
    $preferencesNewTypeComboBox.add_SelectionChanged({ Update-PreferenceToolbar })
    $preferencesNewButton.Add_Click({
        $type = @($preferences.Node.Extension.Items | Where-Object { $_.Properties -and -not $_.IsCollection })[$preferencesNewTypeComboBox.SelectedIndex]
        if ($type) { Open-PreferenceForm -Type $type -Item $null }
    })
    $preferencesEditButton.Add_Click({
        $row = $preferencesList.SelectedItem
        if ($row -and $row.Item.Editable) { Open-PreferenceForm -Type $row.Item.Type -Item $row.Item }
    })
    $preferencesList.add_DoubleTapped({
        $row = $preferencesList.SelectedItem
        if ($row -and $row.Item.Editable -and (Test-PreferenceEditable)) { Open-PreferenceForm -Type $row.Item.Type -Item $row.Item }
    })
    $preferencesCancelButton.Add_Click({ $preferencesFormBorder.IsVisible = $false })
    $preferencesSaveButton.Add_Click({
        $type = $preferences.Type
        $item = $preferences.Item
        try {
            $values = & $preferences.Form.GetValues
            $common = & $preferences.Form.GetCommon
        } catch {
            $preferencesFormErrorTextBlock.Text = $_.Exception.Message
            return
        }
        $problem = if ($item) {
            Save-PreferenceFile -Done (Get-PSGPOText '{0} saved' (Get-PSGPOText $type.Label)) -SelectUid $item.Uid -Change {
                param($Copy)
                Set-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $item.Uid) -Type $type -Values $values -Common $common
            }
        } else {
            Save-PreferenceFile -Done (Get-PSGPOText '{0} created' (Get-PSGPOText $type.Label)) -Change {
                param($Copy)
                (New-PSGPOPreferenceItem -File $Copy -Type $type -Values $values -Common $common).GetAttribute('uid')
            }
        }
        if ($problem) { $preferencesFormErrorTextBlock.Text = $problem } else { $preferencesFormBorder.IsVisible = $false }
    })
    $preferencesDeleteButton.Add_Click({
        $row = $preferencesList.SelectedItem
        if (-not $row) { return }
        $preferencesDeleteTextBlock.Text = Get-PSGPOText "Delete the item '{0}' from the GPO? The computers and users stop applying it; what it already changed stays, unless it removes itself (Remove this item when it is no longer applied)." $row.Name
        $preferencesFormBorder.IsVisible = $false
        $preferencesDeletePanel.IsVisible = $true
    })
    $preferencesDeleteCancelButton.Add_Click({ $preferencesDeletePanel.IsVisible = $false })
    $preferencesDeleteConfirmButton.Add_Click({
        $row = $preferencesList.SelectedItem
        $preferencesDeletePanel.IsVisible = $false
        if (-not $row) { return }
        $problem = Save-PreferenceFile -Done (Get-PSGPOText "'{0}' deleted" $row.Name) -Change {
            param($Copy)
            Remove-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $row.Item.Uid)
            $null
        }
        if ($problem) { Set-PreferenceStatus (Get-PSGPOText 'Not deleted: {0}' $problem) -Problem }
    })
    # Not GetNewClosure for the handlers: the functions of this window would not be found.
    function Move-PreferenceItem {
        param([string]$Direction)
        $row = $preferencesList.SelectedItem
        if (-not $row) { return }
        $problem = Save-PreferenceFile -Done (Get-PSGPOText $(if ($Direction -eq 'Up') { "'{0}' moved up" } else { "'{0}' moved down" }) $row.Name) -SelectUid $row.Item.Uid -Change {
            param($Copy)
            Move-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $row.Item.Uid) -Direction $Direction
            $null
        }
        if ($problem) { Set-PreferenceStatus (Get-PSGPOText 'Not moved: {0}' $problem) -Problem }
    }
    $preferencesUpButton.Add_Click({ Move-PreferenceItem -Direction Up })
    $preferencesDownButton.Add_Click({ Move-PreferenceItem -Direction Down })
}
