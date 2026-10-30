<#
    The Scripts of the GPO edited: the scripts of a kind (Startup, Shutdown, Logon, Logoff) in its
    scripts.ini and psscripts.ini, their order, their content, a file copied into its folder.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerScriptView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerScriptView {
    # Scope and Kind of the node; Lists: scripts.ini and psscripts.ini of each scope, read once per
    # GPO edited (Script, PowerShell); Editing: the script of the form; Filling: the order list set.
    $scripts = @{ Scope = $null; Kind = $null; Lists = @{}; Editing = $null; Filling = $false }
    function Set-ScriptStatus {
        param([string]$Text, [switch]$Problem)
        $scriptsStatusTextBlock.Text = $Text
        if ($Problem) { $scriptsStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $scriptsStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # scripts.ini and psscripts.ini of a scope of the edited GPO.
    function Get-ScriptList {
        param([string]$Scope)
        if (-not $scripts.Lists.ContainsKey($Scope)) {
            $scripts.Lists[$Scope] = @{
                Script = [GPOToolsScriptsFile]::Parse($Directory.ReadGpoFile($editing.Gpo, (Get-PSGPOScriptFilePath -Scope $Scope)))
                PowerShell = [GPOToolsScriptsFile]::Parse($Directory.ReadGpoFile($editing.Gpo, (Get-PSGPOScriptFilePath -Scope $Scope -PowerShell)))
            }
        }
        $scripts.Lists[$Scope]
    }

    function Test-ScriptEditable {
        $editing.Gpo -and $editing.Gpo.CanEdit -and -not $Directory.IsReadOnly -and $scripts.Lists.ContainsKey("$($scripts.Scope)")
    }

    function Update-ScriptToolbar {
        $editable = [bool](Test-ScriptEditable)
        $row = $scriptsList.SelectedItem
        $scriptsAddButton.IsEnabled = $editable
        $scriptsEditButton.IsEnabled = $editable -and $row
        $scriptsDeleteButton.IsEnabled = $editable -and $row
        # Within its type: the scripts of scripts.ini, then those of psscripts.ini.
        $scriptsUpButton.IsEnabled = $editable -and $row -and $row.Item.Index -gt 0
        $scriptsDownButton.IsEnabled = $editable -and $row -and $row.Item.Index -lt $row.Item.Count - 1
        $scriptsOrderComboBox.IsEnabled = $editable
    }

    # The scripts of the kind of the node, the one at $Select (Type|Index) selected.
    function Show-ScriptList {
        param([string]$Status, [switch]$Problem, [string]$Select)
        $scriptsFormBorder.IsVisible = $false
        $scriptsDeletePanel.IsVisible = $false
        $scope = $scripts.Scope
        $kind = $scripts.Kind
        $scriptsTitleTextBlock.Text = Get-PSGPOText '{0} ({1})' (Get-PSGPOText $kind) (Get-PSGPOText $(if ($scope -eq 'Machine') { 'Computer Configuration' } else { 'User Configuration' }))
        $scriptsInfoTextBlock.Text = switch ($kind) {
            'Startup' { Get-PSGPOText 'The computers run these scripts when they start, as SYSTEM, in this order: scripts.ini and psscripts.ini of the GPO, in Machine\Scripts.' }
            'Shutdown' { Get-PSGPOText 'The computers run these scripts when they shut down, as SYSTEM, in this order: scripts.ini and psscripts.ini of the GPO, in Machine\Scripts.' }
            'Logon' { Get-PSGPOText 'The users run these scripts when they log on, with their own rights, in this order: scripts.ini and psscripts.ini of the GPO, in User\Scripts.' }
            default { Get-PSGPOText 'The users run these scripts when they log off, with their own rights, in this order: scripts.ini and psscripts.ini of the GPO, in User\Scripts.' }
        }
        $rows = [System.Collections.Generic.List[object]]::new()
        $lists = $null
        if (-not $editing.Gpo) {
            $scriptsEmptyTextBlock.Text = Get-PSGPOText 'Edit a GPO (Group Policy Management view) to see and configure its scripts.'
        } else {
            try { $lists = Get-ScriptList -Scope $scope } catch { $Status = Get-PSGPOText 'The scripts of the GPO cannot be read: {0}' $_.Exception.GetBaseException().Message; $Problem = $true }
        }
        if ($lists) {
            foreach ($type in 'Script', 'PowerShell') {
                $items = @($lists[$type].GetScripts($kind))
                for ($index = 0; $index -lt $items.Count; $index++) {
                    $item = $items[$index]
                    $row = [AvaloniaPreferenceRow]::new()
                    $row.Name = $item.CmdLine
                    $row.Summary = (@((Get-PSGPOText $(if ($type -eq 'PowerShell') { 'Windows PowerShell script' } else { 'Script' })); if ($item.Parameters) { Get-PSGPOText 'Parameters: {0}' $item.Parameters }) -join ' - ')
                    $path = Get-PSGPOScriptGpoPath -Scope $scope -Kind $kind -CmdLine $item.CmdLine
                    $row.Flags = if (-not $path) { Get-PSGPOText 'Outside the GPO: the computers run it from there' }
                    $row.Item = [pscustomobject]@{ Type = $type; Index = $index; Count = $items.Count; CmdLine = $item.CmdLine; Parameters = $item.Parameters; Path = $path }
                    $rows.Add($row)
                }
            }
            $scripts.Filling = $true
            $order = Get-PSGPOScriptOrder -PowerShellFile $lists.PowerShell -Kind $kind
            $scriptsOrderComboBox.SelectedIndex = if ($order -eq 'First') { 1 } elseif ($order -eq 'Last') { 2 } else { 0 }
            $scripts.Filling = $false
            $scriptsEmptyTextBlock.Text = if ($rows.Count) { '' } else { Get-PSGPOText 'This GPO has no script of this kind.' }
        } elseif ($editing.Gpo) {
            $scriptsEmptyTextBlock.Text = ''
        }
        $scriptsEmptyTextBlock.IsVisible = [bool]$scriptsEmptyTextBlock.Text
        $scriptsList.ItemsSource = $rows.ToArray()
        if ($Select) { $scriptsList.SelectedItem = $rows | Where-Object { "$($_.Item.Type)|$($_.Item.Index)" -eq $Select } | Select-Object -First 1 }
        Set-ScriptStatus $Status -Problem:$Problem
        Update-ScriptToolbar
        Show-ScriptContent
    }

    # The content of the selected script when its file is in the GPO: what the computers run.
    function Show-ScriptContent {
        $row = $scriptsList.SelectedItem
        $scriptsContentPanel.IsVisible = $row -and $row.Item.Path
        if (-not $scriptsContentPanel.IsVisible) { return }
        try {
            $bytes = $Directory.ReadGpoFile($editing.Gpo, $row.Item.Path)
        } catch {
            $scriptsContentTitleTextBlock.Text = Get-PSGPOText '{0} cannot be read: {1}' $row.Item.Path $_.Exception.GetBaseException().Message
            $scriptsContentTextBox.Text = ''
            return
        }
        if ($null -eq $bytes) {
            $scriptsContentTitleTextBlock.Text = Get-PSGPOText 'Not in the GPO: {0} is not in its folder, the computers cannot run it.' $row.Item.Path
            $scriptsContentTextBox.Text = ''
            return
        }
        $scriptsContentTitleTextBlock.Text = Get-PSGPOText '{0}: {1} bytes, SHA-256 {2}' $row.Item.Path $bytes.Length (Get-PSGPOFileHash -Bytes $bytes)
        $text = ConvertFrom-PSGPOScriptContent -Bytes $bytes
        $scriptsContentTextBox.Text = if ($null -ne $text) { $text } else { Get-PSGPOText '(not text: a program or a binary file)' }
    }

    function Open-ScriptForm {
        param($Item)
        $scripts.Editing = $Item
        $scriptsFormTitleTextBlock.Text = if ($Item) { Get-PSGPOText 'Script: {0}' $Item.CmdLine } else { Get-PSGPOText 'New script' }
        $scriptsTypeComboBox.SelectedIndex = if ($Item -and $Item.Type -eq 'Script') { 0 } else { 1 }
        $scriptsNameTextBox.Text = if ($Item) { $Item.CmdLine } else { '' }
        $scriptsParametersTextBox.Text = if ($Item) { $Item.Parameters } else { '' }
        $scriptsCopyPathTextBox.Text = ''
        $scriptsFormErrorTextBlock.Text = ''
        $scriptsDeletePanel.IsVisible = $false
        $scriptsFormBorder.IsVisible = $true
    }

    # A change of the scripts: on copies of scripts.ini and psscripts.ini, the files that changed
    # written with the files copied into the GPO ($Copy), in one increase of the version.
    function Save-ScriptChange {
        param([scriptblock]$Change, [string]$Done, [System.Collections.IDictionary]$Copy, [string]$Select)
        $scope = $scripts.Scope
        $lists = Get-ScriptList -Scope $scope
        $copies = @{ Script = [GPOToolsScriptsFile]::Parse($lists.Script.ToBytes()); PowerShell = [GPOToolsScriptsFile]::Parse($lists.PowerShell.ToBytes()) }
        $files = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
        try {
            & $Change $copies.Script $copies.PowerShell
            if ($Copy) { foreach ($path in $Copy.Keys) { $files[$path] = $Copy[$path] } }
            foreach ($type in 'Script', 'PowerShell') {
                $after = $copies[$type].ToBytes()
                if ([Convert]::ToBase64String($lists[$type].ToBytes()) -ne [Convert]::ToBase64String($after)) { $files[(Get-PSGPOScriptFilePath -Scope $scope -PowerShell:($type -eq 'PowerShell'))] = $after }
            }
            if (-not $files.Count) { return $null }
            $Directory.WriteScriptFiles($editing.Gpo, $scope, $files)
        } catch {
            return $_.Exception.GetBaseException().Message
        }
        $scripts.Lists[$scope] = $copies
        $settingsCache.Remove("$($editing.Gpo.Id)")
        $version = if ($scope -eq 'Machine') { $editing.Gpo.GetComputerVersion() } else { $editing.Gpo.GetUserVersion() }
        Show-ScriptList -Status (Get-PSGPOText '{0} in {1} (version {2}).' $Done (@($files.Keys) -join ', ') $version) -Select $Select
        $null
    }

    # Moves the selected script up (-1) or down (+1) among the scripts of its type.
    function Move-SelectedScript {
        param([int]$Offset)
        $row = $scriptsList.SelectedItem
        if (-not $row) { return }
        $item = $row.Item
        $kind = $scripts.Kind
        $problem = Save-ScriptChange -Select "$($item.Type)|$($item.Index + $Offset)" -Done (Get-PSGPOText "Script '{0}' moved" $item.CmdLine) -Change {
            param($Script, $PowerShell)
            $file = if ($item.Type -eq 'PowerShell') { $PowerShell } else { $Script }
            $list = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in @($file.GetScripts($kind))) { $list.Add($entry) }
            $moved = $list[$item.Index]
            $list.RemoveAt($item.Index)
            $list.Insert($item.Index + $Offset, $moved)
            $file.SetScripts($kind, $list.ToArray())
        }
        if ($problem) { Set-ScriptStatus (Get-PSGPOText 'Not moved: {0}' $problem) -Problem }
    }

    $scriptsList.add_SelectionChanged({ Update-ScriptToolbar; Show-ScriptContent })
    $scriptsAddButton.Add_Click({ Open-ScriptForm $null })
    $scriptsEditButton.Add_Click({ if ($scriptsList.SelectedItem) { Open-ScriptForm $scriptsList.SelectedItem.Item } })
    $scriptsList.add_DoubleTapped({ if ($scriptsList.SelectedItem -and (Test-ScriptEditable)) { Open-ScriptForm $scriptsList.SelectedItem.Item } })
    $scriptsCancelButton.Add_Click({ $scriptsFormBorder.IsVisible = $false })
    $scriptsUpButton.Add_Click({ Move-SelectedScript -Offset -1 })
    $scriptsDownButton.Add_Click({ Move-SelectedScript -Offset 1 })
    $scriptsCopyBrowseButton.IsVisible = $null -ne $window.StorageProvider -and $window.StorageProvider.CanOpen
    $scriptsCopyBrowseButton.Add_Click({
        Start-FilePicker -Title (Get-PSGPOText 'A script to copy into the GPO') -TypeName (Get-PSGPOText 'Scripts') -Patterns '*.ps1', '*.cmd', '*.bat', '*.vbs', '*.js', '*.exe' -Done {
            param($Path)
            $scriptsCopyPathTextBox.Text = $Path
            if (-not "$($scriptsNameTextBox.Text)".Trim()) { $scriptsNameTextBox.Text = [System.IO.Path]::GetFileName($Path) }
        }
    })
    $scriptsOrderComboBox.add_SelectionChanged({
        if ($scripts.Filling -or -not (Test-ScriptEditable)) { return }
        $order = "$($scriptsOrderComboBox.SelectedItem.Tag)"
        $kind = $scripts.Kind
        $problem = Save-ScriptChange -Done (Get-PSGPOText 'Order of the PowerShell scripts saved') -Change { param($Script, $PowerShell) Set-PSGPOScriptOrder -PowerShellFile $PowerShell -Kind $kind -Order $order }
        if ($problem) { Show-ScriptList -Status (Get-PSGPOText 'Not saved: {0}' $problem) -Problem }
    })
    $scriptsSaveButton.Add_Click({
        $name = "$($scriptsNameTextBox.Text)".Trim()
        $parameters = "$($scriptsParametersTextBox.Text)".Trim()
        $copyPath = "$($scriptsCopyPathTextBox.Text)".Trim()
        $type = "$($scriptsTypeComboBox.SelectedItem.Tag)"
        $kind = $scripts.Kind
        $copy = $null
        if ($copyPath) {
            if (-not $name) { $name = [System.IO.Path]::GetFileName($copyPath) }
            if ($name -match '[\\/:*?"<>|]') { $scriptsFormErrorTextBlock.Text = Get-PSGPOText 'A file copied into the GPO has a name without a folder: {0}' $name; return }
            if (-not (Test-Path -LiteralPath $copyPath -PathType Leaf)) { $scriptsFormErrorTextBlock.Text = Get-PSGPOText 'The file {0} is not found.' $copyPath; return }
            $copy = [System.Collections.Specialized.OrderedDictionary]::new()
            $copy["$($scripts.Scope)\Scripts\$kind\$name"] = [System.IO.File]::ReadAllBytes($copyPath)
        }
        if (-not $name) { $scriptsFormErrorTextBlock.Text = Get-PSGPOText 'Give the script name: a file of the folder of the scripts of the GPO, or its path.'; return }
        $old = $scripts.Editing
        $at = if ($old -and $old.Type -eq $type) { $old.Index } else { -1 }
        $problem = Save-ScriptChange -Copy $copy -Select "$type|$(if ($at -ge 0) { $at } else { 'last' })" -Done (Get-PSGPOText "Script '{0}' saved" $name) -Change {
            param($Script, $PowerShell)
            $files = @{ Script = $Script; PowerShell = $PowerShell }
            # Out of its place, then at the same place when its type is the same, else last.
            if ($old) {
                $list = [System.Collections.Generic.List[object]]::new()
                foreach ($entry in @($files[$old.Type].GetScripts($kind))) { $list.Add($entry) }
                $list.RemoveAt($old.Index)
                $files[$old.Type].SetScripts($kind, $list.ToArray())
            }
            $list = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in @($files[$type].GetScripts($kind))) { $list.Add($entry) }
            $added = [pscustomobject]@{ CmdLine = $name; Parameters = $parameters }
            if ($at -ge 0) { $list.Insert($at, $added) } else { $list.Add($added) }
            $files[$type].SetScripts($kind, $list.ToArray())
        }
        if ($problem) { $scriptsFormErrorTextBlock.Text = $problem; return }
        # A new script, or one of another type: the last of its type.
        if ($at -lt 0) { $scriptsList.SelectedItem = @($scriptsList.ItemsSource | Where-Object { $_.Item.Type -eq $type }) | Select-Object -Last 1 }
    })
    $scriptsDeleteButton.Add_Click({
        $row = $scriptsList.SelectedItem
        if (-not $row) { return }
        $scriptsDeleteTextBlock.Text = Get-PSGPOText "Delete the script '{0}' from the GPO? The computers stop running it; its file, if it is in the GPO, stays in its folder." $row.Name
        $scriptsFormBorder.IsVisible = $false
        $scriptsDeletePanel.IsVisible = $true
    })
    $scriptsDeleteCancelButton.Add_Click({ $scriptsDeletePanel.IsVisible = $false })
    $scriptsDeleteConfirmButton.Add_Click({
        $row = $scriptsList.SelectedItem
        if (-not $row) { return }
        $item = $row.Item
        $kind = $scripts.Kind
        $problem = Save-ScriptChange -Done (Get-PSGPOText "Script '{0}' deleted" $row.Name) -Change {
            param($Script, $PowerShell)
            $file = if ($item.Type -eq 'PowerShell') { $PowerShell } else { $Script }
            $list = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in @($file.GetScripts($kind))) { $list.Add($entry) }
            $list.RemoveAt($item.Index)
            $file.SetScripts($kind, $list.ToArray())
        }
        if ($problem) { Set-ScriptStatus (Get-PSGPOText 'Not deleted: {0}' $problem) -Problem }
    })
}
