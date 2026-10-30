<#
    The WMI filters: New, Edit, Delete, Export and Import (.mof files of GPMC), Use it in a GPO, the
    filter of a GPO in its details; the file pickers of the system (Start-FilePicker).

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerWmiFilterView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerWmiFilterView {
    # The items of WMI Filter: none, then each filter of the domain, the one of the GPO checked.
    function Update-WmiFilterMenu {
        param([GPOToolsGpo]$Gpo)
        $wmiFilterMenuItem.Items.Clear()
        foreach ($choice in @($null) + @($Directory.WmiFilters)) {
            $item = [Avalonia.Controls.MenuItem]::new()
            $item.Header = if ($choice) { $choice.Name } else { Get-PSGPOText '(none)' }
            $item.ToggleType = [Avalonia.Controls.MenuItemToggleType]::Radio
            $item.GroupName = 'wmiFilter'
            $item.IsChecked = if ($choice) { $Gpo.WmiFilterId -eq $choice.Id } else { $null -eq $Gpo.WmiFilterId }
            $item.Tag = $choice
            if ($choice) { [Avalonia.Controls.ToolTip]::SetTip($item, $choice.GetQueryText()) }
            $item.Add_Click({ param($control) Set-SelectedWmiFilter -Filter $control.Tag })
            [void]$wmiFilterMenuItem.Items.Add($item)
        }
    }
    function Set-SelectedWmiFilter {
        param([GPOToolsWmiFilter]$Filter)
        $gpo = Get-SelectedGpo
        if (-not $gpo) { return }
        if ("$($gpo.WmiFilterId)" -eq "$(if ($Filter) { $Filter.Id })") { return }
        $select = $domainTreeView.SelectedItem.Tag
        Invoke-DirectoryChange -Select $select -Done $(if ($Filter) { Get-PSGPOText "'{0}' is linked to the WMI filter '{1}': the computers apply it only when each of its queries returns something ({2})." $gpo.DisplayName $Filter.Name $Filter.GetQueryText() } else { Get-PSGPOText "'{0}' is linked to no WMI filter." $gpo.DisplayName }) `
            -Change { $Directory.SetWmiFilter($gpo, $Filter) }
    }
    # New WMI Filter... on WMI Filters, as GPMC; Edit WMI filter... on a filter, in the same form.
    $wmiFilterForm = @{ Filter = $null }
    function Open-NewWmiFilterForm {
        param([GPOToolsWmiFilter]$Filter)
        $wmiFilterForm.Filter = $Filter
        $newWmiFilterTitleTextBlock.Text = if ($Filter) { Get-PSGPOText 'Edit WMI filter' } else { Get-PSGPOText 'New WMI filter' }
        $newWmiFilterCreateButton.Content = if ($Filter) { Get-PSGPOText 'Save' } else { Get-PSGPOText 'Create' }
        $newWmiFilterNameTextBox.Text = if ($Filter) { $Filter.Name } else { '' }
        $newWmiFilterDescriptionTextBox.Text = if ($Filter) { "$($Filter.Description)" } else { '' }
        # The namespace of the first query; a query of another namespace is a line namespace: query.
        $namespace = if ($Filter -and @($Filter.Queries).Count) { $Filter.Queries[0].Namespace } else { 'root\CIMv2' }
        $newWmiFilterNamespaceTextBox.Text = $namespace
        $newWmiFilterQueryTextBox.Text = if ($Filter) {
            @($Filter.Queries | ForEach-Object { if ($_.Namespace -eq $namespace) { $_.Query } else { "$($_.Namespace): $($_.Query)" } }) -join [Environment]::NewLine
        } else { '' }
        $newWmiFilterErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $newWmiFilterPanel
        $newWmiFilterNameTextBox.Focus()
    }
    function Submit-NewWmiFilter {
        $namespace = "$($newWmiFilterNamespaceTextBox.Text)".Trim()
        if (-not $namespace) { $namespace = 'root\CIMv2' }
        $queries = @("$($newWmiFilterQueryTextBox.Text)" -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
                # A WQL query starts with its verb (SELECT): a line that starts with root names its namespace.
                if ($_ -match '^(root(\\[^\\:\s]+)*)\s*:\s*(\S.*)$') { [pscustomobject]@{ Namespace = $Matches[1]; Query = $Matches[3] } }
                else { [pscustomobject]@{ Namespace = $namespace; Query = $_ } }
            })
        $filter = $wmiFilterForm.Filter
        $users = @()
        try {
            if ($filter) {
                $users = @($Directory.Gpos | Where-Object { $_.WmiFilterId -eq $filter.Id } | ForEach-Object DisplayName)
                $Directory.EditWmiFilter($filter, $newWmiFilterNameTextBox.Text, "$($newWmiFilterDescriptionTextBox.Text)".Trim(), $queries)
            } else {
                $filter = $Directory.NewWmiFilter($newWmiFilterNameTextBox.Text, "$($newWmiFilterDescriptionTextBox.Text)".Trim(), $queries)
            }
        } catch {
            $newWmiFilterErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $newWmiFilterPanel.IsVisible = $false
        Update-DirectoryTree -Select $filter
        Show-DirectoryResult -Text $(
            if (-not $wmiFilterForm.Filter) { Get-PSGPOText "WMI filter '{0}' created. Link a GPO to it with WMI Filter in the context menu of the GPO." $filter.Name }
            elseif ($users.Count) { Get-PSGPOText "WMI filter '{0}' saved: {1} apply it with its new queries." $filter.Name ($users -join ', ') }
            else { Get-PSGPOText "WMI filter '{0}' saved." $filter.Name })
    }
    # Delete WMI filter... on a filter, once confirmed; refused while a GPO uses it.
    $deleteWmiFilter = @{ Filter = $null }
    function Open-DeleteWmiFilterForm {
        $filter = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($filter -isnot [GPOToolsWmiFilter]) { return }
        $deleteWmiFilter.Filter = $filter
        $users = @($Directory.Gpos | Where-Object { $_.WmiFilterId -eq $filter.Id } | ForEach-Object DisplayName)
        $deleteWmiFilterTextBlock.Text = (Get-PSGPOText "Delete the WMI filter '{0}'? " $filter.Name) +
            $(if ($users.Count) { Get-PSGPOText 'It is used by {0}: unlink them first (WMI Filter > (none)), it is not deleted otherwise.' ($users -join ', ') } else { Get-PSGPOText 'No GPO uses it.' })
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $deleteWmiFilterPanel
    }
    function Submit-DeleteWmiFilter {
        $filter = $deleteWmiFilter.Filter
        if (-not $filter) { return }
        $deleteWmiFilterPanel.IsVisible = $false
        Invoke-DirectoryChange -Select 'WmiFilters' -Done (Get-PSGPOText "WMI filter '{0}' deleted." $filter.Name) -Change { $Directory.RemoveWmiFilter($filter) }
    }
    $newWmiFilterMenuItem.Add_Click({ Open-NewWmiFilterForm })
    $editWmiFilterMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsWmiFilter]) { Open-NewWmiFilterForm -Filter $item } })
    $editWmiFilterButton.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsWmiFilter]) { Open-NewWmiFilterForm -Filter $item } })
    $newWmiFilterCreateButton.Add_Click({ Submit-NewWmiFilter })
    $newWmiFilterCancelButton.Add_Click({ $newWmiFilterPanel.IsVisible = $false })
    $deleteWmiFilterMenuItem.Add_Click({ Open-DeleteWmiFilterForm })
    $deleteWmiFilterConfirmButton.Add_Click({ Submit-DeleteWmiFilter })
    $deleteWmiFilterCancelButton.Add_Click({ $deleteWmiFilterPanel.IsVisible = $false })

    # File pickers of the system (xdg-desktop-portal on Linux), when there is one, for the .mof
    # files: the result is awaited by a timer, as the UI thread cannot block on it; $Done gets the
    # path chosen.
    $filePicker = @{ Task = $null; Timer = $null; Done = $null }
    # A file chosen with the picker of the system: a .mof file by default, else the type given
    # (-TypeName, -Patterns: *.ps1...); $Done gets its path.
    function Start-FilePicker {
        param(
            [switch]$Save, [string]$Title, [string]$Path, [Parameter(Mandatory)] [scriptblock]$Done,
            [string]$TypeName = (Get-PSGPOText 'WMI filter (.mof)'), [string[]]$Patterns = @('*.mof')
        )
        $type = [Avalonia.Platform.Storage.FilePickerFileType]::new($TypeName)
        $type.Patterns = [string[]]$Patterns
        if ($Save) {
            $options = [Avalonia.Platform.Storage.FilePickerSaveOptions]::new()
            $options.SuggestedFileName = [System.IO.Path]::GetFileName($Path)
            $options.DefaultExtension = $Patterns[0].TrimStart('*', '.')
            $options.FileTypeChoices = [Avalonia.Platform.Storage.FilePickerFileType[]]@($type)
        } else {
            $options = [Avalonia.Platform.Storage.FilePickerOpenOptions]::new()
            $options.AllowMultiple = $false
            $options.FileTypeFilter = [Avalonia.Platform.Storage.FilePickerFileType[]]@($type)
        }
        $options.Title = $Title
        $filePicker.Done = $Done
        $filePicker.Task = if ($Save) { $window.StorageProvider.SaveFilePickerAsync($options) } else { $window.StorageProvider.OpenFilePickerAsync($options) }
        $filePicker.Timer = [Avalonia.Threading.DispatcherTimer]::new()
        $filePicker.Timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $filePicker.Timer.Add_Tick({
            if (-not $filePicker.Task.IsCompleted) { return }
            $filePicker.Timer.Stop()
            if (-not $filePicker.Task.IsCompletedSuccessfully) { return }
            $chosen = $filePicker.Task.Result
            if ($chosen -isnot [Avalonia.Platform.Storage.IStorageFile]) { $chosen = @($chosen) | Select-Object -First 1 }
            if ($chosen) { & $filePicker.Done $chosen.Path.LocalPath }
        })
        $filePicker.Timer.Start()
    }
    $canPick = $null -ne $window.StorageProvider
    $exportWmiFilterBrowseButton.IsVisible = $canPick -and $window.StorageProvider.CanSave
    $importWmiFilterBrowseButton.IsVisible = $canPick -and $window.StorageProvider.CanOpen

    # Export... on a WMI filter, as GPMC: a .mof file in the format of GPMC, by default in the
    # folder WMI filters of the folder of the backups. A file there is replaced once confirmed.
    $exportWmiFilter = @{ Filter = $null; Replace = $null }
    function Open-ExportWmiFilterForm {
        $filter = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($filter -isnot [GPOToolsWmiFilter]) { return }
        $exportWmiFilter.Filter = $filter
        $exportWmiFilter.Replace = $null
        $exportWmiFilterTitleTextBlock.Text = Get-PSGPOText "Export the WMI filter '{0}'" $filter.Name
        # The folder of the account: the central backups are for Tier 0.
        $exportWmiFilterPathTextBox.Text = Join-Path (Join-Path (Get-PSGPOLocalBackupPath) 'WMI filters') (Get-PSGPOWmiFilterFileName -Name $filter.Name)
        $exportWmiFilterErrorTextBlock.Text = ''
        $exportWmiFilterConfirmButton.Content = Get-PSGPOText 'Export'
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $exportWmiFilterPanel
    }
    function Submit-ExportWmiFilter {
        $filter = $exportWmiFilter.Filter
        if (-not $filter) { return }
        $file = "$($exportWmiFilterPathTextBox.Text)".Trim()
        if (-not $file) { $exportWmiFilterErrorTextBlock.Text = Get-PSGPOText 'Give the file of the export.'; return }
        if (-not $file.EndsWith('.mof', [System.StringComparison]::OrdinalIgnoreCase)) { $file += '.mof' }
        if ((Test-Path -LiteralPath $file) -and $exportWmiFilter.Replace -ne $file) {
            $exportWmiFilter.Replace = $file
            $exportWmiFilterErrorTextBlock.Text = Get-PSGPOText '{0} exists: Replace writes the filter over it.' $file
            $exportWmiFilterConfirmButton.Content = Get-PSGPOText 'Replace'
            return
        }
        try {
            $folder = [System.IO.Path]::GetDirectoryName($file)
            if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop }
            [System.IO.File]::WriteAllBytes($file, (ConvertTo-PSGPOWmiFilterMofByte -Filter $filter -Domain $Directory.DomainName))
        } catch {
            $exportWmiFilterErrorTextBlock.Text = Get-PSGPOText 'The WMI filter is not exported: {0}' $_.Exception.GetBaseException().Message
            return
        }
        $exportWmiFilterPanel.IsVisible = $false
        Show-DirectoryResult -Text (Get-PSGPOText "WMI filter '{0}' exported to {1}: GPMC imports it in another domain, as Import... in the context menu of WMI Filters does." $filter.Name $file)
    }
    $exportWmiFilterPathTextBox.add_PropertyChanged({
        param($control, $e)
        # Another file: confirmed again before it is replaced.
        if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty -and $exportWmiFilter.Replace) {
            $exportWmiFilter.Replace = $null
            $exportWmiFilterErrorTextBlock.Text = ''
            $exportWmiFilterConfirmButton.Content = Get-PSGPOText 'Export'
        }
    })

    # Import... on WMI Filters, as GPMC: a .mof file of GPMC or HGPM read first, its filter shown,
    # then created in the domain with a new Id, under its name or the one given.
    $importWmiFilter = @{ Source = $null; File = $null }
    function Open-ImportWmiFilterForm {
        $importWmiFilter.Source = $null
        $importWmiFilter.File = $null
        $importWmiFilterTitleTextBlock.Text = Get-PSGPOText 'Import a WMI filter into {0}' $Directory.DomainName
        $importWmiFilterInfoTextBlock.Text = ''
        $importWmiFilterNameTextBox.Text = ''
        $importWmiFilterErrorTextBlock.Text = ''
        $importWmiFilterConfirmButton.IsEnabled = $false
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $importWmiFilterPanel
        [void]$importWmiFilterPathTextBox.Focus()
    }
    function Read-ImportWmiFilterFile {
        $importWmiFilter.Source = $null
        $importWmiFilterConfirmButton.IsEnabled = $false
        $importWmiFilterInfoTextBlock.Text = ''
        $importWmiFilterErrorTextBlock.Text = ''
        $file = "$($importWmiFilterPathTextBox.Text)".Trim()
        if (-not $file) { $importWmiFilterErrorTextBlock.Text = Get-PSGPOText 'Give the .mof file to import.'; return }
        try {
            $read = @(ConvertFrom-PSGPOWmiFilterMof -Bytes ([System.IO.File]::ReadAllBytes($file)))
        } catch {
            $importWmiFilterErrorTextBlock.Text = Get-PSGPOText 'The file cannot be imported: {0}' $_.Exception.GetBaseException().Message
            return
        }
        # As GPMC: one filter in a file; Import-PSGPOWmiFilter imports them all.
        if ($read.Count -gt 1) { $importWmiFilterErrorTextBlock.Text = Get-PSGPOText 'The file holds {0} WMI filters: the console imports a file of one, Import-PSGPOWmiFilter imports them all.' $read.Count; return }
        $source = $read[0]
        $importWmiFilter.Source = $source
        $importWmiFilter.File = $file
        $importWmiFilterInfoTextBlock.Text = ((@(
                    Get-PSGPOText "'{0}', exported from {1}" $source.Name $(if ($source.Domain) { $source.Domain } else { '?' })
                    if ($source.Description) { $source.Description }
                    @($source.Queries | ForEach-Object { "$($_.Namespace): $($_.Query)" })
                )) -join [Environment]::NewLine)
        $importWmiFilterNameTextBox.Text = $source.Name
        if ($Directory.FindWmiFilter($source.Name)) { $importWmiFilterErrorTextBlock.Text = Get-PSGPOText "A WMI filter named '{0}' exists in {1}: give the imported one another name." $source.Name $Directory.DomainName }
        $importWmiFilterConfirmButton.IsEnabled = $true
    }
    function Submit-ImportWmiFilter {
        $source = $importWmiFilter.Source
        if (-not $source) { return }
        try {
            $filter = $Directory.NewWmiFilter($importWmiFilterNameTextBox.Text, $source.Description, $source.Queries)
        } catch {
            $importWmiFilterErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $importWmiFilterPanel.IsVisible = $false
        Update-DirectoryTree -Select $filter
        Show-DirectoryResult -Text (Get-PSGPOText "WMI filter '{0}' imported from {1}. Link a GPO to it with WMI Filter in the context menu of the GPO, or Use it in a GPO... here." $filter.Name $importWmiFilter.File)
    }

    # Use it in a GPO... on a WMI filter: the GPOs the account edits that do not use it; the one
    # chosen is linked to the filter (its former filter replaced), as its Scope tab in GPMC.
    $useWmiFilter = @{ Filter = $null }
    function Open-UseWmiFilterForm {
        $filter = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($filter -isnot [GPOToolsWmiFilter]) { return }
        $useWmiFilter.Filter = $filter
        $useWmiFilterTitleTextBlock.Text = Get-PSGPOText "Use the WMI filter '{0}' in a GPO: the computers apply it only when each of its queries returns something ({1})" $filter.Name $filter.GetQueryText()
        $useWmiFilterErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $useWmiFilterSearchTextBox.Text = ''
        Update-UseWmiFilterList
        Show-DirectoryForm $useWmiFilterPanel
        [void]$useWmiFilterSearchTextBox.Focus()
    }
    function Update-UseWmiFilterList {
        $filter = $useWmiFilter.Filter
        if (-not $filter) { return }
        $search = "$($useWmiFilterSearchTextBox.Text)".Trim()
        $gpos = [System.Collections.Generic.List[GPOToolsGpo]]::new()
        foreach ($gpo in @($Directory.Gpos | Sort-Object DisplayName)) {
            if (-not $gpo.CanEdit -or $gpo.WmiFilterId -eq $filter.Id) { continue }
            if ($search -and $gpo.DisplayName.IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            $gpos.Add($gpo)
        }
        $useWmiFilterList.ItemsSource = $gpos
        $useWmiFilterList.SelectedIndex = if ($gpos.Count -eq 1) { 0 } else { -1 }
        $useWmiFilterConfirmButton.IsEnabled = $null -ne $useWmiFilterList.SelectedItem
        $useWmiFilterErrorTextBlock.Text = if ($gpos.Count) { '' }
            elseif ($search) { Get-PSGPOText "No GPO named like '{0}' can use the WMI filter '{1}'." $search $filter.Name }
            else { Get-PSGPOText "Every GPO you edit uses the WMI filter '{0}' already." $filter.Name }
    }
    function Submit-UseWmiFilter {
        $filter = $useWmiFilter.Filter
        $gpo = $useWmiFilterList.SelectedItem
        if (-not $filter -or $gpo -isnot [GPOToolsGpo]) { return }
        $former = $Directory.GetWmiFilter($gpo)
        try {
            $Directory.SetWmiFilter($gpo, $filter)
        } catch {
            $useWmiFilterErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $useWmiFilterPanel.IsVisible = $false
        Update-DirectoryTree -Select $filter
        Show-DirectoryResult -Text $(if ($former) { Get-PSGPOText "'{0}' is linked to the WMI filter '{1}', instead of '{2}'." $gpo.DisplayName $filter.Name $former.Name }
            else { Get-PSGPOText "'{0}' is linked to the WMI filter '{1}': the computers apply it only when each of its queries returns something ({2})." $gpo.DisplayName $filter.Name $filter.GetQueryText() })
    }

    # The WMI filter of the selected GPO in its details, as the Scope tab of GPMC: (none), the
    # filters of the domain, and a filter the domain does not have anymore.
    $gpoWmiFilter = @{ Updating = $false }
    function Update-GpoWmiFilterComboBox {
        param([GPOToolsGpo]$Gpo)
        $gpoWmiFilter.Updating = $true
        try {
            $items = [System.Collections.Generic.List[object]]::new()
            $selected = $null
            foreach ($choice in @($null) + @($Directory.WmiFilters)) {
                $item = [Avalonia.Controls.ComboBoxItem]::new()
                $item.Content = if ($choice) { $choice.Name } else { Get-PSGPOText '(none)' }
                $item.Tag = $choice
                if ($choice) { [Avalonia.Controls.ToolTip]::SetTip($item, $choice.GetQueryText()) }
                $items.Add($item)
                if (($choice -and $Gpo.WmiFilterId -eq $choice.Id) -or (-not $choice -and $null -eq $Gpo.WmiFilterId)) { $selected = $item }
            }
            if (-not $selected) {
                $selected = [Avalonia.Controls.ComboBoxItem]::new()
                $selected.Content = Get-PSGPOText '{0}: not in the domain anymore, the computers ignore the GPO' ('{' + $Gpo.WmiFilterId.ToString().ToUpperInvariant() + '}')
                $selected.Tag = 'Missing'
                $items.Add($selected)
            }
            $gpoWmiFilterComboBox.ItemsSource = $items
            $gpoWmiFilterComboBox.SelectedItem = $selected
        } finally {
            $gpoWmiFilter.Updating = $false
        }
    }
    $gpoWmiFilterComboBox.add_SelectionChanged({
        if ($gpoWmiFilter.Updating) { return }
        $item = $gpoWmiFilterComboBox.SelectedItem
        if (-not $item -or "$($item.Tag)" -eq 'Missing') { return }
        Set-SelectedWmiFilter -Filter $item.Tag
    })

    $exportWmiFilterMenuItem.Add_Click({ Open-ExportWmiFilterForm })
    $exportWmiFilterBrowseButton.Add_Click({ Start-FilePicker -Save -Title (Get-PSGPOText 'Export the WMI filter') -Path $exportWmiFilterPathTextBox.Text -Done { param($Path) $exportWmiFilterPathTextBox.Text = $Path } })
    $exportWmiFilterConfirmButton.Add_Click({ Submit-ExportWmiFilter })
    $exportWmiFilterCancelButton.Add_Click({ $exportWmiFilterPanel.IsVisible = $false })
    $importWmiFilterMenuItem.Add_Click({ Open-ImportWmiFilterForm })
    $importWmiFilterBrowseButton.Add_Click({ Start-FilePicker -Title (Get-PSGPOText 'Import a WMI filter') -Done { param($Path) $importWmiFilterPathTextBox.Text = $Path; Read-ImportWmiFilterFile } })
    $importWmiFilterReadButton.Add_Click({ Read-ImportWmiFilterFile })
    $importWmiFilterPathTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Read-ImportWmiFilterFile }
    })
    $importWmiFilterConfirmButton.Add_Click({ Submit-ImportWmiFilter })
    $importWmiFilterCancelButton.Add_Click({ $importWmiFilterPanel.IsVisible = $false })
    $useWmiFilterMenuItem.Add_Click({ Open-UseWmiFilterForm })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $useWmiFilterSearchTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property.Name -eq 'Text' -and $useWmiFilterPanel.IsVisible) { Update-UseWmiFilterList }
    })
    $useWmiFilterList.add_SelectionChanged({ $useWmiFilterConfirmButton.IsEnabled = $null -ne $useWmiFilterList.SelectedItem })
    $useWmiFilterList.add_DoubleTapped({ Submit-UseWmiFilter })
    $useWmiFilterConfirmButton.Add_Click({ Submit-UseWmiFilter })
    $useWmiFilterCancelButton.Add_Click({ $useWmiFilterPanel.IsVisible = $false })
}
