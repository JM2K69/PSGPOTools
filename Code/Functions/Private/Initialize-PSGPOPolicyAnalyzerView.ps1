<#
    The Policy Analyzer of Show-PolicyAnalyzerAvalonia (Get-PSGPOPolicyAnalyzerViewXaml), as the
    Policy Analyzer of the Security Compliance Toolkit: the rule sets of a folder (its
    .PolicyRules files; Documents\PolicyAnalyzer by default, as Policy Analyzer), with GPOs of the
    domain and GPMC backups added to them; the comparison of those checked, a column per set, with
    the colours of Policy Analyzer; its export to Excel, and a set saved as a .PolicyRules file.

    Dot-sourced by Start-PSGPOPolicyAnalyzerWindow (. Initialize-PSGPOPolicyAnalyzerView): its
    controls, state and functions live in the scope of the window, which stays alive while the
    window is open, so that its handlers find them. It uses $window, $Directory (the domain, or
    $null) and $DomainParameters (how to read it, on the first GPOs of the domain asked for) of the
    window, and names what it defines analyzer* or *Analyzer*.
#>

function Initialize-PSGPOPolicyAnalyzerView {
    $analyzerControlNames = @(
        'analyzerView', 'analyzerFolderTextBox', 'analyzerFolderBrowseButton', 'analyzerFolderReadButton', 'analyzerSetsList', 'analyzerSetsEmptyTextBlock',
        'analyzerAddGposButton', 'analyzerAddGpmcButton', 'analyzerSaveSetButton', 'analyzerRemoveSetButton', 'analyzerCompareButton', 'analyzerSetsStatusTextBlock',
        'analyzerGposPanel', 'analyzerGposFilterTextBox', 'analyzerGposList', 'analyzerGposNameTextBox', 'analyzerGposErrorTextBlock', 'analyzerGposConfirmButton',
        'analyzerGposCancelButton', 'analyzerFilePanel', 'analyzerFileTitleTextBlock', 'analyzerFilePathTextBox', 'analyzerFileBrowseButton', 'analyzerFileAllCheckBox',
        'analyzerFileErrorTextBlock', 'analyzerFileConfirmButton', 'analyzerFileCancelButton', 'analyzerShowComboBox', 'analyzerSearchTextBox', 'analyzerExportButton',
        'analyzerEmptyTextBlock', 'analyzerGrid', 'analyzerSummaryTextBlock', 'analyzerDetailsBorder', 'analyzerDetailsNameTextBlock', 'analyzerDetailsPathTextBlock',
        'analyzerDetailsSettingTextBlock', 'analyzerDetailsValuesList', 'analyzerDetailsExplainTextBlock',
        'analyzerApplySetButton', 'analyzerApplyPanel', 'analyzerApplyTitleTextBlock', 'analyzerApplyGpoComboBox', 'analyzerApplyNewNameTextBox',
        'analyzerApplyPoliciesList', 'analyzerApplyReplaceCheckBox', 'analyzerApplyErrorTextBlock', 'analyzerApplyConfirmButton', 'analyzerApplyCancelButton'
    )
    foreach ($analyzerName in $analyzerControlNames) { Set-Variable -Name $analyzerName -Value (Get-PSGPOAvaloniaControl $window $analyzerName) }

    # Sets: the items of the list; Rows: the comparison; Shown: the rows the filters keep;
    # File: what the file form does (Save, Excel, Gpmc) and the file a second click replaces.
    $analyzer = @{
        Loaded = $false; Sets = [System.Collections.Generic.List[object]]::new(); Rows = @(); Shown = @(); Columns = @()
        FileMode = $null; Replace = $null; SetToSave = $null; SetToApply = $null; Picker = @{ Task = $null; Timer = $null; Done = $null }
        Directory = $Directory; DomainParameters = $DomainParameters
    }
    # The colours of Policy Analyzer, readable in the light and dark themes.
    $analyzerBrush = @{ Conflict = '#80FFE14D'; Absent = '#4D9E9E9E'; Duplicate = '#269E9E9E'; Normal = '#00000000' }

    function Get-AnalyzerDefaultFolder {
        $saved = (Get-PSGPOUserSetting).PolicyAnalyzerPath
        if ($saved) { return $saved }
        $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        if (-not $documents) { $documents = $HOME }
        Join-Path $documents 'PolicyAnalyzer'
    }

    # $GpoCount: the GPOs chosen, those without any setting of a rule set included (a file only
    # names the GPOs it has settings of).
    function Get-AnalyzerSetDetail {
        param([GPOToolsPolicyRuleSet]$RuleSet, [string]$Kind, [int]$GpoCount = -1)
        $gpos = if ($GpoCount -ge 0) { $GpoCount } else { @($RuleSet.GetPolicyNames()).Count }
        switch ($Kind) {
            'Domain' { Get-PSGPOText 'GPOs of the domain: {0} GPO(s), {1} settings' $gpos $RuleSet.Rules.Count }
            'Gpmc' { Get-PSGPOText 'GPMC backups: {0} GPO(s), {1} settings' $gpos $RuleSet.Rules.Count }
            default { Get-PSGPOText '{0} GPO(s), {1} settings' $gpos $RuleSet.Rules.Count }
        }
    }

    function Update-AnalyzerSetsList {
        $analyzerSetsList.ItemsSource = [object[]]$analyzer.Sets.ToArray()
        $analyzerSetsEmptyTextBlock.IsVisible = $analyzer.Sets.Count -eq 0
    }

    # The domain of the GPOs: the one given, else read the first time (-Server, else the domain of
    # the computer); $null, the reason in the form, when it cannot be read.
    function Get-AnalyzerDirectory {
        if ($analyzer.Directory) { return $analyzer.Directory }
        $read = @{}
        if ($analyzer.DomainParameters) { $read = $analyzer.DomainParameters }
        if (-not $read.Server -and -not (Get-PSGPOPlatform).DomainName) {
            $analyzerGposErrorTextBlock.Text = Get-PSGPOText 'No domain: this computer is not in a domain, and no domain controller was given (-Server).'
            return
        }
        try {
            $analyzer.Directory = Get-PSGPODirectory @read -ErrorAction Stop -WarningAction SilentlyContinue
        } catch {
            $analyzerGposErrorTextBlock.Text = Get-PSGPOText 'The domain could not be read: {0}' $_.Exception.GetBaseException().Message
        }
        $analyzer.Directory
    }

    # The .PolicyRules files of the folder, read again; the sets added (GPOs, GPMC backups) are kept,
    # and the files keep their check.
    function Read-AnalyzerFolder {
        $folder = "$($analyzerFolderTextBox.Text)".Trim()
        $checked = @{}
        foreach ($item in $analyzer.Sets) { if ($item.Kind -eq 'File' -and $item.IsChecked) { $checked[$item.Path] = $true } }
        $kept = @($analyzer.Sets | Where-Object Kind -NE 'File')
        $analyzer.Sets.Clear()
        $problems = [System.Collections.Generic.List[string]]::new()
        if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
            foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Filter '*.PolicyRules' | Sort-Object Name)) {
                try {
                    $set = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($file.FullName), [System.IO.Path]::GetFileNameWithoutExtension($file.Name))
                    $set.Path = $file.FullName
                    $analyzer.Sets.Add([AvaloniaPolicyRuleSetItem]@{ Name = $set.Name; Detail = Get-AnalyzerSetDetail -RuleSet $set -Kind File; Path = $file.FullName; Kind = 'File'; RuleSet = $set; IsChecked = [bool]$checked[$file.FullName] })
                } catch {
                    $problems.Add((Get-PSGPOText '{0} is not read: {1}' $file.Name $_.Exception.GetBaseException().Message))
                }
            }
        } elseif ($folder) {
            $problems.Add((Get-PSGPOText 'No folder {0}: it is created when a set is saved there.' $folder))
        }
        foreach ($item in $kept) { $analyzer.Sets.Add($item) }
        $analyzerSetsStatusTextBlock.Text = $problems -join [Environment]::NewLine
        Update-AnalyzerSetsList
    }

    function Set-AnalyzerFolder {
        param([string]$Folder)
        $analyzerFolderTextBox.Text = $Folder
        try { Set-PSGPOUserSetting -Values @{ PolicyAnalyzerPath = $Folder } -Confirm:$false } catch { Write-Verbose "Folder of the rule sets not saved: $($_.Exception.Message)" }
        Read-AnalyzerFolder
    }

    # The first time the view shows: the folder given ($Folder, not kept for the next time), else
    # the one of the last time.
    function Open-AnalyzerView {
        param([string]$Folder)
        if ($analyzer.Loaded) { return }
        $analyzer.Loaded = $true
        $analyzerFolderTextBox.Text = if ($Folder) { $Folder } else { Get-AnalyzerDefaultFolder }
        Read-AnalyzerFolder
    }

    # A file or folder chosen with the picker of the system; $Done gets its path.
    function Start-AnalyzerPicker {
        param([ValidateSet('Open', 'Save', 'Folder')] [string]$Mode, [string]$Title, [string]$Path, [string]$TypeName, [string]$Extension, [Parameter(Mandatory)] [scriptblock]$Done)
        if (-not $window.StorageProvider) { return }
        if ($Mode -eq 'Folder') {
            $options = [Avalonia.Platform.Storage.FolderPickerOpenOptions]::new()
            $options.AllowMultiple = $false
            $analyzer.Picker.Task = $window.StorageProvider.OpenFolderPickerAsync($options)
        } else {
            $type = [Avalonia.Platform.Storage.FilePickerFileType]::new($TypeName)
            $type.Patterns = [string[]]@("*.$Extension")
            if ($Mode -eq 'Save') {
                $options = [Avalonia.Platform.Storage.FilePickerSaveOptions]::new()
                $options.SuggestedFileName = [System.IO.Path]::GetFileName($Path)
                $options.DefaultExtension = $Extension
                $options.FileTypeChoices = [Avalonia.Platform.Storage.FilePickerFileType[]]@($type)
                $options.Title = $Title
                $analyzer.Picker.Task = $window.StorageProvider.SaveFilePickerAsync($options)
            } else {
                $options = [Avalonia.Platform.Storage.FilePickerOpenOptions]::new()
                $options.AllowMultiple = $false
                $options.FileTypeFilter = [Avalonia.Platform.Storage.FilePickerFileType[]]@($type)
                $options.Title = $Title
                $analyzer.Picker.Task = $window.StorageProvider.OpenFilePickerAsync($options)
            }
        }
        $analyzer.Picker.Done = $Done
        $analyzer.Picker.Timer = [Avalonia.Threading.DispatcherTimer]::new()
        $analyzer.Picker.Timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $analyzer.Picker.Timer.Add_Tick({
                if (-not $analyzer.Picker.Task.IsCompleted) { return }
                $analyzer.Picker.Timer.Stop()
                if (-not $analyzer.Picker.Task.IsCompletedSuccessfully) { return }
                $chosen = $analyzer.Picker.Task.Result
                if ($chosen -isnot [Avalonia.Platform.Storage.IStorageItem]) { $chosen = @($chosen) | Select-Object -First 1 }
                if ($chosen) { & $analyzer.Picker.Done $chosen.Path.LocalPath }
            })
        $analyzer.Picker.Timer.Start()
    }

    function Hide-AnalyzerForm {
        $analyzerGposPanel.IsVisible = $false
        $analyzerFilePanel.IsVisible = $false
        $analyzerApplyPanel.IsVisible = $false
    }

    # --- GPOs of the domain as a set ---------------------------------------------------------------

    function Update-AnalyzerGposList {
        $text = "$($analyzerGposFilterTextBox.Text)".Trim()
        # The GPOs themselves: Sort-Object wraps them in PSObjects, which Avalonia cannot bind.
        $analyzerGposList.ItemsSource = [object[]]@(foreach ($gpo in @($analyzer.Directory.Gpos | Sort-Object DisplayName)) {
                if (-not $text -or $gpo.DisplayName.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $gpo.psobject.BaseObject }
            })
    }

    function Open-AnalyzerGposForm {
        Hide-AnalyzerForm
        $analyzerGposFilterTextBox.Text = ''
        $analyzerGposNameTextBox.Text = ''
        $analyzerGposErrorTextBlock.Text = ''
        $null = Get-AnalyzerDirectory
        Update-AnalyzerGposList
        $analyzerGposPanel.IsVisible = $true
        $analyzerGposFilterTextBox.Focus()
    }

    function Submit-AnalyzerGpoSelection {
        if (-not $analyzer.Directory) { return }
        $gpos = @($analyzerGposList.SelectedItems | Where-Object { $_ -is [GPOToolsGpo] })
        if (-not $gpos.Count) { $analyzerGposErrorTextBlock.Text = Get-PSGPOText 'Select one or more GPOs.'; return }
        try {
            $set = New-PSGPOPolicyRuleSetFromGpo -Directory $analyzer.Directory -Gpo $gpos -SetName "$($analyzerGposNameTextBox.Text)".Trim()
        } catch {
            $analyzerGposErrorTextBlock.Text = Get-PSGPOText 'The GPOs are not read: {0}' $_.Exception.GetBaseException().Message
            return
        }
        $analyzer.Sets.Add([AvaloniaPolicyRuleSetItem]@{ Name = $set.Name; Detail = Get-AnalyzerSetDetail -RuleSet $set -Kind Domain -GpoCount $gpos.Count; Path = $set.Path; Kind = 'Domain'; RuleSet = $set; IsChecked = $true })
        $analyzerGposPanel.IsVisible = $false
        Update-AnalyzerSetsList
    }

    # --- The settings of a set written in a GPO of the domain (Import-PSGPOPolicyRuleSet) ----------

    function Open-AnalyzerApplyForm {
        $item = $analyzerSetsList.SelectedItem
        if (-not $item) { $analyzerSetsStatusTextBlock.Text = Get-PSGPOText 'Select the set to write in a GPO.'; return }
        Hide-AnalyzerForm
        $analyzer.SetToApply = $item
        $analyzerApplyTitleTextBlock.Text = Get-PSGPOText "Write the settings of the set '{0}' in a GPO of the domain" $item.Name
        $analyzerApplyErrorTextBlock.Text = ''
        $analyzerApplyNewNameTextBox.Text = ''
        $analyzerApplyReplaceCheckBox.IsChecked = $false
        $analyzerApplyGpoComboBox.ItemsSource = $null
        $analyzerApplyPanel.IsVisible = $true
        # The GPOs the account edits, the domain read the first time.
        $null = Get-AnalyzerDirectory
        if (-not $analyzer.Directory) { $analyzerApplyErrorTextBlock.Text = $analyzerGposErrorTextBlock.Text }
        $analyzerApplyGpoComboBox.ItemsSource = [object[]]@(foreach ($gpo in @($analyzer.Directory.Gpos | Sort-Object DisplayName)) { if ($gpo.CanEdit) { $gpo.psobject.BaseObject } })
        $analyzerApplyPoliciesList.ItemsSource = [string[]]@($item.RuleSet.GetPolicyNames())
        $analyzerApplyPoliciesList.SelectAll()
    }

    function Submit-AnalyzerApply {
        $item = $analyzer.SetToApply
        if (-not $analyzer.Directory) { return }
        $newName = "$($analyzerApplyNewNameTextBox.Text)".Trim()
        $target = if ($newName) { $newName } elseif ($analyzerApplyGpoComboBox.SelectedItem) { $analyzerApplyGpoComboBox.SelectedItem.DisplayName }
        if (-not $target) { $analyzerApplyErrorTextBlock.Text = Get-PSGPOText 'Choose the GPO, or give the name of a new one.'; return }
        $policies = @($analyzerApplyPoliciesList.SelectedItems | ForEach-Object { "$_" })
        if (-not $policies.Count) { $analyzerApplyErrorTextBlock.Text = Get-PSGPOText 'Select the GPOs of the set whose settings are written.'; return }
        if ($newName -and $analyzer.Directory.FindGpo($newName)) { $analyzerApplyErrorTextBlock.Text = Get-PSGPOText "A GPO named '{0}' already exists: choose it in the list." $newName; return }
        try {
            $done = Invoke-PSGPOPolicyRuleImport -Directory $analyzer.Directory -RuleSet $item.RuleSet -TargetName $target -PolicyName $policies -Replace:([bool]$analyzerApplyReplaceCheckBox.IsChecked) -CreateIfNeeded:([bool]$newName) -WarningAction SilentlyContinue
        } catch {
            $analyzerApplyErrorTextBlock.Text = Get-PSGPOText 'The settings are not written: {0}' $_.Exception.GetBaseException().Message
            return
        }
        $analyzerApplyPanel.IsVisible = $false
        $analyzerSetsStatusTextBlock.Text = Get-PSGPOText "Written in the GPO '{0}': {1} registry settings, {2} security settings, {3} audit settings{4}." $done.DisplayName $done.Registry $done.SecurityTemplate $done.Audit $(if (@($done.Skipped).Count) { Get-PSGPOText '; {0} not written (no data in the set)' @($done.Skipped).Count } else { '' })
    }

    # --- The file form: GPMC backups to add, a set to save, the comparison to export ----------------

    function Open-AnalyzerFileForm {
        param([ValidateSet('Gpmc', 'Save', 'Excel')] [string]$Mode)
        $folder = "$($analyzerFolderTextBox.Text)".Trim()
        switch ($Mode) {
            'Gpmc' {
                $analyzerFileTitleTextBlock.Text = Get-PSGPOText 'A rule set of GPMC backups: the folder of the backups (the GPOs folder of a security baseline of Microsoft)'
                $analyzerFilePathTextBox.Text = ''
                $analyzerFileConfirmButton.Content = Get-PSGPOText 'Add'
            }
            'Save' {
                $item = $analyzerSetsList.SelectedItem
                if (-not $item) { $analyzerSetsStatusTextBlock.Text = Get-PSGPOText 'Select the set to save.'; return }
                $analyzer.SetToSave = $item
                $analyzerFileTitleTextBlock.Text = Get-PSGPOText "Save the set '{0}' as a .PolicyRules file, which Policy Analyzer and LGPO.exe read" $item.Name
                $analyzerFilePathTextBox.Text = Join-Path $folder "$(($item.Name -replace '[\\/:*?"<>|]', '_')).PolicyRules"
                $analyzerFileConfirmButton.Content = Get-PSGPOText 'Save'
            }
            'Excel' {
                if (-not @($analyzer.Shown).Count) { $analyzerSummaryTextBlock.Text = Get-PSGPOText 'Nothing to export: compare rule sets first.'; return }
                $analyzerFileTitleTextBlock.Text = Get-PSGPOText 'Export the {0} settings shown to an Excel workbook' @($analyzer.Shown).Count
                $analyzerFilePathTextBox.Text = Join-Path $folder ('Comparison {0}.xlsx' -f (Get-Date).ToString('yyyyMMdd-HHmmss'))
                $analyzerFileConfirmButton.Content = Get-PSGPOText 'Export'
            }
        }
        Hide-AnalyzerForm
        $analyzer.FileMode = $Mode
        $analyzer.Replace = $null
        $analyzerFileAllCheckBox.IsVisible = $Mode -eq 'Excel'
        $analyzerFileBrowseButton.IsVisible = [bool]$window.StorageProvider
        $analyzerFileErrorTextBlock.Text = ''
        $analyzerFilePanel.IsVisible = $true
    }

    function Submit-AnalyzerFile {
        $path = "$($analyzerFilePathTextBox.Text)".Trim()
        if (-not $path) { $analyzerFileErrorTextBlock.Text = Get-PSGPOText 'Give the path.'; return }
        try {
            if ($analyzer.FileMode -eq 'Gpmc') {
                $set = Get-PSGPOPolicyRuleSet -GpmcBackupPath $path -ErrorAction Stop -WarningAction SilentlyContinue
                $analyzer.Sets.Add([AvaloniaPolicyRuleSetItem]@{ Name = $set.Name; Detail = Get-AnalyzerSetDetail -RuleSet $set -Kind Gpmc; Path = $set.Path; Kind = 'Gpmc'; RuleSet = $set; IsChecked = $true })
                $analyzerFilePanel.IsVisible = $false
                Update-AnalyzerSetsList
                return
            }
            # A file there is replaced once confirmed: a second click.
            if ((Test-Path -LiteralPath $path) -and $analyzer.Replace -ne $path) {
                $analyzer.Replace = $path
                $analyzerFileErrorTextBlock.Text = Get-PSGPOText '{0} exists: click again to replace it.' $path
                return
            }
            if ($analyzer.FileMode -eq 'Save') {
                $item = $analyzer.SetToSave
                $file = Export-PSGPOPolicyRuleSet -RuleSet $item.RuleSet -Path $path -Force -Confirm:$false -ErrorAction Stop
                # The set is now this file: listed with the others of the folder when it is there.
                $item.RuleSet.Path = $file.FullName
                $item.Path = $file.FullName
                if ([string]::Equals([System.IO.Path]::GetDirectoryName($file.FullName), [System.IO.Path]::GetFullPath("$($analyzerFolderTextBox.Text)".Trim()), [System.StringComparison]::OrdinalIgnoreCase)) {
                    # A file of the folder, read again with the others; checked if it was.
                    $item.Kind = 'File'
                    Read-AnalyzerFolder
                }
                $analyzerSetsStatusTextBlock.Text = Get-PSGPOText 'Saved: {0}' $file.FullName
            } else {
                $file = Export-PSGPOPolicyRuleComparison -InputObject @($analyzer.Shown | ForEach-Object Source) -Path $path -All:([bool]$analyzerFileAllCheckBox.IsChecked) -Force -Confirm:$false -ErrorAction Stop
                $analyzerSummaryTextBlock.Text = Get-PSGPOText 'Exported: {0}' $file.FullName
            }
            $analyzerFilePanel.IsVisible = $false
        } catch {
            $analyzerFileErrorTextBlock.Text = $_.Exception.GetBaseException().Message
        }
    }

    # --- The comparison ----------------------------------------------------------------------------

    # A column per set, after the setting; each cell with the colour of its state.
    function Update-AnalyzerGridColumn {
        $analyzerGrid.Columns.Clear()
        foreach ($column in @(@{ Header = (Get-PSGPOText 'Scope'); Property = 'Scope'; Width = 110 }, @{ Header = (Get-PSGPOText 'Setting'); Property = 'Name'; Width = 320 }, @{ Header = (Get-PSGPOText 'Option'); Property = 'Option'; Width = 150 })) {
            $text = [Avalonia.Controls.DataGridTextColumn]::new()
            $text.Header = $column.Header
            $text.Binding = [Avalonia.Data.Binding]::new($column.Property)
            $text.Width = [Avalonia.Controls.DataGridLength]::new($column.Width)
            $analyzerGrid.Columns.Add($text)
        }
        for ($index = 0; $index -lt $analyzer.Columns.Count; $index++) {
            $cell = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse(
                "<DataTemplate xmlns='https://github.com/avaloniaui'><Border Background='{Binding Brushes[$index]}' Padding='6,0'>" +
                "<TextBlock Text='{Binding Values[$index]}' VerticalAlignment='Center' TextTrimming='CharacterEllipsis' ToolTip.Tip='{Binding Values[$index]}'/></Border></DataTemplate>")
            $set = [Avalonia.Controls.DataGridTemplateColumn]::new()
            $set.Header = $analyzer.Columns[$index]
            $set.CellTemplate = $cell
            $set.SortMemberPath = "Values[$index]"
            $set.Width = [Avalonia.Controls.DataGridLength]::new(200)
            $analyzerGrid.Columns.Add($set)
        }
        $path = [Avalonia.Controls.DataGridTextColumn]::new()
        $path.Header = Get-PSGPOText 'Path'
        $path.Binding = [Avalonia.Data.Binding]::new('Path')
        $path.Width = [Avalonia.Controls.DataGridLength]::new(360)
        $analyzerGrid.Columns.Add($path)
    }

    function ConvertTo-AnalyzerRow {
        param($Row)
        $item = [AvaloniaPolicyRuleRow]::new()
        $item.Scope = if ($Row.Scope -eq 'User') { Get-PSGPOText 'User' } else { Get-PSGPOText 'Computer' }
        $item.Path = ConvertTo-PSGPODisplayText $Row.Path
        $item.Name = ConvertTo-PSGPODisplayText $Row.Name
        $item.Option = ConvertTo-PSGPODisplayText $Row.Option
        $item.Values = [string[]]@($Row.Cells | ForEach-Object { ConvertTo-PSGPODisplayText $_.Value })
        $item.Brushes = [string[]]@($Row.Cells | ForEach-Object {
                if ($_.State -eq 'Absent') { $analyzerBrush.Absent } elseif ($Row.Conflict) { $analyzerBrush.Conflict } elseif ($_.State -eq 'Duplicate') { $analyzerBrush.Duplicate } else { $analyzerBrush.Normal }
            })
        $item.Source = $Row
        $item.SearchText = (@($item.Name, $item.Path, $item.Option, $Row.Group, $Row.Setting) + $item.Values + @($Row.Cells | ForEach-Object { $_.Values } | ForEach-Object PolicyName)) -join "`n"
        $item
    }

    # The rows the filters keep: all, the differences or the conflicts, and those the search finds.
    function Update-AnalyzerGridRow {
        $text = "$($analyzerSearchTextBox.Text)".Trim()
        $show = $analyzerShowComboBox.SelectedIndex
        # A foreach, not Where-Object: Avalonia cannot bind the PSObjects of a pipeline.
        $analyzer.Shown = [object[]]@(foreach ($item in $analyzer.Rows) {
                if (($show -ne 1 -or $item.Source.Difference) -and ($show -ne 2 -or $item.Source.Conflict) -and
                    (-not $text -or $item.SearchText.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) { $item }
            })
        $analyzerGrid.ItemsSource = [object[]]$analyzer.Shown
        $all = @($analyzer.Rows)
        if ($all.Count) {
            $analyzerSummaryTextBlock.Text = Get-PSGPOText '{0} settings, {1} differences, {2} conflicts; {3} shown' $all.Count @($all | Where-Object { $_.Source.Difference }).Count @($all | Where-Object { $_.Source.Conflict }).Count $analyzer.Shown.Count
        }
        Show-AnalyzerDetail
    }

    function Invoke-AnalyzerCompare {
        $sets = @($analyzer.Sets | Where-Object IsChecked | ForEach-Object RuleSet)
        if (-not $sets.Count) { $analyzerSetsStatusTextBlock.Text = Get-PSGPOText 'Check one or more rule sets to compare.'; return }
        $analyzerSetsStatusTextBlock.Text = Get-PSGPOText 'Comparing {0} rule set(s)...' $sets.Count
        $analyzerCompareButton.IsEnabled = $false
        # Posted: the text shows before the window waits for the comparison.
        $analyzer.Comparing = $sets
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                try {
                    $comparison = @(Get-PSGPOPolicyRuleComparison -RuleSet ([GPOToolsPolicyRuleSet[]]$analyzer.Comparing))
                    $analyzer.Columns = @(if ($comparison.Count) { $comparison[0].Cells | ForEach-Object Set } else { Get-PSGPOPolicyRuleColumnName -RuleSet ([GPOToolsPolicyRuleSet[]]$analyzer.Comparing) })
                    $analyzer.Rows = [object[]]@(foreach ($row in $comparison) { (ConvertTo-AnalyzerRow -Row $row).psobject.BaseObject })
                    Update-AnalyzerGridColumn
                    $analyzerEmptyTextBlock.IsVisible = $false
                    $analyzerGrid.IsVisible = $true
                    Update-AnalyzerGridRow
                    $analyzerSetsStatusTextBlock.Text = ''
                } catch {
                    $analyzerSetsStatusTextBlock.Text = Get-PSGPOText 'The sets are not compared: {0}' $_.Exception.GetBaseException().Message
                } finally {
                    $analyzerCompareButton.IsEnabled = $true
                }
            }, [Avalonia.Threading.DispatcherPriority]::Background)
    }

    # Where GPMC shows the selected setting, the value each GPO of each set gives it, its explanation.
    function Show-AnalyzerDetail {
        $item = $analyzerGrid.SelectedItem
        $analyzerDetailsBorder.IsVisible = $item -is [AvaloniaPolicyRuleRow]
        if ($item -isnot [AvaloniaPolicyRuleRow]) { return }
        $row = $item.Source
        $analyzerDetailsNameTextBlock.Text = if ($item.Option) { "$($item.Name) - $($item.Option)" } else { $item.Name }
        $analyzerDetailsPathTextBlock.Text = "$($item.Scope) > $($item.Path)"
        $analyzerDetailsSettingTextBlock.Text = switch ($row.Kind) {
            'Registry' {
                $type = @($row.Cells | ForEach-Object { $_.Rules } | ForEach-Object RegType | Select-Object -Unique) -join ', '
                "$($row.PolicyType)\$($row.Group)$(if ($row.Setting) { "\$($row.Setting)" }) ($type)"
            }
            default { "$(ConvertTo-PSGPODisplayText $row.PolicyType): [$($row.Group)] $($row.Setting)" }
        }
        $analyzerDetailsValuesList.ItemsSource = [object[]]@(foreach ($cell in $row.Cells) {
                $text = if ($cell.State -eq 'Absent') { Get-PSGPOText '(not configured)' }
                    else { (@($cell.Values) | ForEach-Object { "$($_.PolicyName): $(ConvertTo-PSGPODisplayText $_.Value)" }) -join [Environment]::NewLine }
                [AvaloniaPolicyRuleValueItem]@{ Set = $cell.Set; Text = $text }
            })
        $analyzerDetailsExplainTextBlock.Text = $row.Explain
    }

    # --- Handlers ----------------------------------------------------------------------------------

    $analyzerFolderReadButton.Add_Click({ Set-AnalyzerFolder -Folder "$($analyzerFolderTextBox.Text)".Trim() })
    $analyzerFolderTextBox.Add_KeyDown({
            param($control, $e)
            if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Set-AnalyzerFolder -Folder "$($analyzerFolderTextBox.Text)".Trim() }
        })
    $analyzerFolderBrowseButton.IsVisible = [bool]$window.StorageProvider
    $analyzerFolderBrowseButton.Add_Click({ Start-AnalyzerPicker -Mode Folder -Title (Get-PSGPOText 'Policy Rule sets in') -Done { param($Path) Set-AnalyzerFolder -Folder $Path } })
    $analyzerAddGposButton.Add_Click({ Open-AnalyzerGposForm })
    $analyzerGposFilterTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property.Name -eq 'Text' -and $analyzerGposPanel.IsVisible) { Update-AnalyzerGposList }
    })
    $analyzerGposConfirmButton.Add_Click({ Submit-AnalyzerGpoSelection })
    $analyzerGposCancelButton.Add_Click({ $analyzerGposPanel.IsVisible = $false })
    $analyzerAddGpmcButton.Add_Click({ Open-AnalyzerFileForm -Mode Gpmc })
    $analyzerSaveSetButton.Add_Click({ Open-AnalyzerFileForm -Mode Save })
    $analyzerExportButton.Add_Click({ Open-AnalyzerFileForm -Mode Excel })
    $analyzerRemoveSetButton.Add_Click({
            $item = $analyzerSetsList.SelectedItem
            if (-not $item) { return }
            [void]$analyzer.Sets.Remove($item)
            Update-AnalyzerSetsList
        })
    $analyzerFileBrowseButton.Add_Click({
            switch ($analyzer.FileMode) {
                'Gpmc' { Start-AnalyzerPicker -Mode Folder -Title (Get-PSGPOText 'GPMC backups...') -Done { param($Path) $analyzerFilePathTextBox.Text = $Path } }
                'Save' { Start-AnalyzerPicker -Mode Save -Title (Get-PSGPOText 'Save as .PolicyRules...') -Path $analyzerFilePathTextBox.Text -TypeName (Get-PSGPOText 'Policy Analyzer rule set (.PolicyRules)') -Extension 'PolicyRules' -Done { param($Path) $analyzerFilePathTextBox.Text = $Path } }
                'Excel' { Start-AnalyzerPicker -Mode Save -Title (Get-PSGPOText 'Export to Excel...') -Path $analyzerFilePathTextBox.Text -TypeName (Get-PSGPOText 'Excel workbook (.xlsx)') -Extension 'xlsx' -Done { param($Path) $analyzerFilePathTextBox.Text = $Path } }
            }
        })
    $analyzerFileConfirmButton.Add_Click({ Submit-AnalyzerFile })
    $analyzerFileCancelButton.Add_Click({ $analyzerFilePanel.IsVisible = $false })
    $analyzerCompareButton.Add_Click({ Invoke-AnalyzerCompare })
    $analyzerApplySetButton.Add_Click({ Open-AnalyzerApplyForm })
    $analyzerApplyConfirmButton.Add_Click({ Submit-AnalyzerApply })
    $analyzerApplyCancelButton.Add_Click({ $analyzerApplyPanel.IsVisible = $false })
    $analyzerShowComboBox.Add_SelectionChanged({ Update-AnalyzerGridRow })
    $analyzerSearchTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property.Name -eq 'Text') { Update-AnalyzerGridRow }
    })
    $analyzerGrid.Add_SelectionChanged({ Show-AnalyzerDetail })
}
