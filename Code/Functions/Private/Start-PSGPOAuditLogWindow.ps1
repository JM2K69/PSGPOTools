<#
    Private implementation of Show-AuditLogAvalonia: the changes of the audit log (Get-PSGPOAuditLog)
    in a window, newest first, filtered by period, domain, action and a search, the details of the
    selected one, the changes shown exported to CSV.

    The folder is the one given (-Path), else Audit.Path of the configuration of the domain: the
    domain given, else read once the window is shown (-DomainParameters, else the domain of the
    computer); without a domain, the folder Audit of the backups of the account.

    -OnShown exists for the GUI tests, as for Start-PSGPOManagerWindow: the scriptblock receives a
    hashtable of the named controls, runs inside the loop once the window is shown, and the window
    is then closed.
#>

function Start-PSGPOAuditLogWindow {
    [CmdletBinding()]
    param(
        # The domain whose configuration gives the folder of the log.
        [AllowNull()] [GPOToolsDirectory]$Directory,

        # Parameters of Get-PSGPODirectory (Server, Credential, UseSsl), to read the domain.
        [hashtable]$DomainParameters = @{},

        # The folder of the log, instead of Audit.Path of the configuration.
        [string]$Path,

        # Language of the interface; English by default, so that the tests do not depend on the
        # language of the computer: Show-AuditLogAvalonia gives the one of the session.
        [string]$Language = 'en-US',

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime
    $null = Set-PSGPOLanguage -Language $Language

    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml (Get-PSGPOAuditLogWindowXaml)))
    Set-PSGPOWindowIcon -Window $window
    $controlNames = @(
        'logoImage', 'subtitleTextBlock', 'themeToggleButton', 'themeToggleIcon', 'themeToggleText',
        'auditFolderTextBox', 'auditFolderBrowseButton', 'auditRefreshButton', 'auditPeriodComboBox', 'auditDomainComboBox',
        'auditActionComboBox', 'auditSearchTextBox', 'auditExportButton', 'auditEmptyTextBlock', 'auditGrid',
        'auditSummaryTextBlock', 'auditStatusTextBlock', 'auditDetailsBorder', 'auditDetailsTitleTextBlock',
        'auditDetailsWhoTextBlock', 'auditDetailsTargetTextBlock', 'auditDetailsTextBlock'
    )
    $ui = @{}
    foreach ($name in $controlNames) { $ui[$name] = Get-PSGPOAvaloniaControl $window $name }
    $ui.logoImage.Source = New-PSGPOLogoBitmap

    # Theme: the one of the session, the same in every window (PSGPOTheme.ps1).
    Register-PSGPOThemeWindow -Window $window -ToggleText $ui.themeToggleText -ToggleIcon $ui.themeToggleIcon
    $ui.themeToggleButton.Add_Click({ Switch-PSGPOTheme })

    # Entries: the log as read; Rows: all of them as rows; Shown: those the filters keep; Domains,
    # Actions: what the lists offer after "all" (an action by its name in the log).
    $audit = @{
        Entries = @(); Rows = @(); Shown = @(); Domains = @(); Actions = @(); Filling = $false
        Directory = $Directory; DomainParameters = $DomainParameters; Picker = @{ Task = $null; Timer = $null; Done = $null }
    }

    function Set-AuditStatus {
        param([string]$Text)
        $ui.auditStatusTextBlock.Text = $Text
    }

    # The folder of the log: Audit.Path of the configuration of the domain, else the default one.
    function Get-AuditDefaultFolder {
        if ($audit.Directory) { Use-PSGPODomainConfiguration -Directory $audit.Directory }
        Get-PSGPOAuditPath
    }

    # What the subtitle says of the domain: who reads the log (the account of the directory, its
    # tier in the central log), or that the log is the one of the account only.
    function Get-AuditDomainText {
        $text = Get-PSGPOText 'What the consoles and the commands changed in the domain - {0}' $audit.Directory.DomainName
        $account = if ($audit.Directory.Account) { $audit.Directory.Account } else { [Environment]::UserName }
        $text += ' - ' + (Get-PSGPOText 'Connected as {0}' $account)
        if ("$((Get-PSGPOConfigurationData).Audit.Path)".Trim()) {
            if ($audit.Directory.AuditTier) { $text += " ($(Get-PSGPOAuditTierText -Tier $audit.Directory.AuditTier))" }
            return $text
        }
        $text + ' - ' + (Get-PSGPOText 'the log of your account only: Audit.Path of the configuration sets no central log')
    }

    # The log read again from the folder of the text box: its domains and actions in the lists.
    function Read-AuditLog {
        $folder = "$($ui.auditFolderTextBox.Text)".Trim()
        $audit.Entries = @()
        Set-AuditStatus ''
        $exists = $false
        if ($folder) {
            try { $exists = Test-PSGPOAuditFolder -Path $folder } catch { Set-AuditStatus (Get-PSGPOText 'The audit log is not read: {0}' $_.Exception.GetBaseException().Message) }
        }
        if (-not $folder) {
            Set-AuditStatus (Get-PSGPOText 'Choose the folder of the audit log.')
        } elseif ($ui.auditStatusTextBlock.Text) {
            # The folder could not be reached: said above.
        } elseif (-not $exists) {
            Set-AuditStatus (Get-PSGPOText 'No audit log in {0}: the folder does not exist yet, nothing was changed or written there.' $folder)
        } else {
            try {
                # The warnings of the lines that are not entries, with the entries (-WarningVariable
                # does not get those of the functions it calls).
                $read = @(Read-PSGPOAuditEntry -Path $folder 3>&1)
                $warnings = @($read | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
                $audit.Entries = @($read | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
                if ($warnings.Count) { Set-AuditStatus (Get-PSGPOText '{0} line(s) of the log are not entries of the audit log: left out.' @($warnings).Count) }
            } catch {
                Set-AuditStatus (Get-PSGPOText 'The audit log is not read: {0}' $_.Exception.GetBaseException().Message)
            }
        }
        $audit.Rows = [object[]]@(foreach ($entry in $audit.Entries) {
                $row = [AvaloniaAuditRow]::new()
                $row.Time = $entry.Time.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
                $row.Account = $entry.Account
                $row.Action = Get-PSGPOAuditActionText -Action "$($entry.Action)"
                $row.Object = if ($entry.GpoName) { $entry.GpoName } else { $entry.Target }
                $row.Computer = $entry.Computer
                $row.Domain = $entry.Domain
                $row.Tier = Get-PSGPOAuditTierText -Tier "$($entry.Tier)"
                $row.Entry = $entry
                $row.SearchText = (@($entry.Account, $entry.Computer, $entry.Server, $entry.Action, $row.Action, $entry.Target, $entry.GpoName, "$($entry.GpoId)", (Format-PSGPOAuditDetail -Details $entry.Details)) -join ' ').ToLowerInvariant()
                $row
            })

        # The lists keep their choice when it is still there.
        $audit.Filling = $true
        try {
            $domain = if ($ui.auditDomainComboBox.SelectedIndex -gt 0) { $audit.Domains[$ui.auditDomainComboBox.SelectedIndex - 1] }
            $action = if ($ui.auditActionComboBox.SelectedIndex -gt 0) { $audit.Actions[$ui.auditActionComboBox.SelectedIndex - 1] }
            $audit.Domains = @($audit.Entries | ForEach-Object Domain | Where-Object { $_ } | Sort-Object -Unique)
            $audit.Actions = @($audit.Entries | ForEach-Object Action | Where-Object { $_ } | Sort-Object -Unique | Sort-Object { Get-PSGPOAuditActionText -Action $_ })
            $ui.auditDomainComboBox.ItemsSource = [string[]]@(@(Get-PSGPOText 'All the domains') + $audit.Domains)
            $ui.auditDomainComboBox.SelectedIndex = [Math]::Max(0, [array]::IndexOf([string[]]$audit.Domains, [string]$domain) + 1)
            $ui.auditActionComboBox.ItemsSource = [string[]]@(@(Get-PSGPOText 'All the actions') + @($audit.Actions | ForEach-Object { Get-PSGPOAuditActionText -Action $_ }))
            $ui.auditActionComboBox.SelectedIndex = [Math]::Max(0, [array]::IndexOf([string[]]$audit.Actions, [string]$action) + 1)
        } finally {
            $audit.Filling = $false
        }
        Update-AuditGridRow
    }

    # The rows the filters keep: the period, the domain, the action, the words of the search.
    function Update-AuditGridRow {
        if ($audit.Filling) { return }
        $after = switch ($ui.auditPeriodComboBox.SelectedIndex) {
            0 { [datetime]::UtcNow.AddDays(-1) }
            1 { [datetime]::UtcNow.AddDays(-7) }
            2 { [datetime]::UtcNow.AddDays(-30) }
            default { [datetime]::MinValue }
        }
        $domain = if ($ui.auditDomainComboBox.SelectedIndex -gt 0) { $audit.Domains[$ui.auditDomainComboBox.SelectedIndex - 1] }
        $action = if ($ui.auditActionComboBox.SelectedIndex -gt 0) { $audit.Actions[$ui.auditActionComboBox.SelectedIndex - 1] }
        $words = @("$($ui.auditSearchTextBox.Text)".ToLowerInvariant() -split '\s+' | Where-Object { $_ })
        $audit.Shown = [object[]]@(foreach ($row in $audit.Rows) {
                if ($row.Entry.Time.ToUniversalTime() -lt $after) { continue }
                if ($domain -and $row.Entry.Domain -ne $domain) { continue }
                if ($action -and $row.Entry.Action -ne $action) { continue }
                $kept = $true
                foreach ($word in $words) { if (-not $row.SearchText.Contains($word)) { $kept = $false; break } }
                if ($kept) { $row }
            })
        $ui.auditGrid.ItemsSource = $audit.Shown
        $ui.auditGrid.IsVisible = $audit.Shown.Count -gt 0
        $ui.auditEmptyTextBlock.IsVisible = $audit.Shown.Count -eq 0
        $ui.auditEmptyTextBlock.Text = if ($audit.Rows.Count) { Get-PSGPOText 'No change matches the filters.' } else { Get-PSGPOText 'No change in this audit log yet.' }
        $ui.auditSummaryTextBlock.Text = Get-PSGPOText '{0} change(s) shown, {1} in the log' $audit.Shown.Count $audit.Rows.Count
        $ui.auditExportButton.IsEnabled = $audit.Shown.Count -gt 0
        Show-AuditDetail
    }

    function Show-AuditDetail {
        $row = $ui.auditGrid.SelectedItem
        $ui.auditDetailsBorder.IsVisible = $row -is [AvaloniaAuditRow]
        if ($row -isnot [AvaloniaAuditRow]) { return }
        $entry = $row.Entry
        $ui.auditDetailsTitleTextBlock.Text = "$($row.Action) - $($row.Object)"
        $ui.auditDetailsWhoTextBlock.Text = Get-PSGPOText '{0} by {1} from {2}, on {3} ({4})' $row.Time $entry.Account $entry.Computer $(if ($entry.Server) { $entry.Server } else { '-' }) $entry.Domain
        $target = @(
            if ($entry.GpoName) { Get-PSGPOText 'GPO: {0} {1}' $entry.GpoName $(if ($entry.GpoId) { "{$($entry.GpoId.ToString().ToUpperInvariant())}" }) }
            if ($entry.Target) { Get-PSGPOText 'Target: {0}' $entry.Target }
            Get-PSGPOText 'Action: {0}' $entry.Action
        )
        $ui.auditDetailsTargetTextBlock.Text = $target -join [Environment]::NewLine
        $ui.auditDetailsTextBlock.Text = Format-PSGPOAuditDetail -Details $entry.Details
    }

    # A file or folder chosen with the picker of the system; $Done gets its path.
    function Start-AuditPicker {
        param([ValidateSet('Save', 'Folder')] [string]$Mode, [string]$Title, [string]$FileName, [Parameter(Mandatory)] [scriptblock]$Done)
        if (-not $window.StorageProvider) { return }
        if ($Mode -eq 'Folder') {
            $options = [Avalonia.Platform.Storage.FolderPickerOpenOptions]::new()
            $options.AllowMultiple = $false
            $options.Title = $Title
            $audit.Picker.Task = $window.StorageProvider.OpenFolderPickerAsync($options)
        } else {
            $type = [Avalonia.Platform.Storage.FilePickerFileType]::new((Get-PSGPOText 'CSV file'))
            $type.Patterns = [string[]]@('*.csv')
            $options = [Avalonia.Platform.Storage.FilePickerSaveOptions]::new()
            $options.SuggestedFileName = $FileName
            $options.DefaultExtension = 'csv'
            $options.FileTypeChoices = [Avalonia.Platform.Storage.FilePickerFileType[]]@($type)
            $options.Title = $Title
            $audit.Picker.Task = $window.StorageProvider.SaveFilePickerAsync($options)
        }
        $audit.Picker.Done = $Done
        $audit.Picker.Timer = [Avalonia.Threading.DispatcherTimer]::new()
        $audit.Picker.Timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $audit.Picker.Timer.Add_Tick({
                if (-not $audit.Picker.Task.IsCompleted) { return }
                $audit.Picker.Timer.Stop()
                if (-not $audit.Picker.Task.IsCompletedSuccessfully) { return }
                $chosen = $audit.Picker.Task.Result
                if ($chosen -isnot [Avalonia.Platform.Storage.IStorageItem]) { $chosen = @($chosen) | Select-Object -First 1 }
                if ($chosen) { & $audit.Picker.Done $chosen.Path.LocalPath }
            })
        $audit.Picker.Timer.Start()
    }

    # The changes shown, as they are filtered, in a CSV file.
    function Export-AuditShown {
        param([string]$File)
        try {
            $saved = Export-PSGPOAuditLogCsv -Entry @($audit.Shown | ForEach-Object Entry) -Path $File
            Set-AuditStatus (Get-PSGPOText '{0} change(s) exported to {1}.' $audit.Shown.Count $saved.FullName)
        } catch {
            Set-AuditStatus (Get-PSGPOText 'Not exported: {0}' $_.Exception.GetBaseException().Message)
        }
    }

    $ui.auditRefreshButton.Add_Click({ Read-AuditLog })
    $ui.auditFolderTextBox.add_KeyDown({ param($source, $e) if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Read-AuditLog } })
    $ui.auditFolderBrowseButton.Add_Click({ Start-AuditPicker -Mode Folder -Title (Get-PSGPOText 'Folder of the audit log') -Done { param($Chosen) $ui.auditFolderTextBox.Text = $Chosen; Read-AuditLog } })
    $ui.auditPeriodComboBox.add_SelectionChanged({ Update-AuditGridRow })
    $ui.auditDomainComboBox.add_SelectionChanged({ Update-AuditGridRow })
    $ui.auditActionComboBox.add_SelectionChanged({ Update-AuditGridRow })
    $ui.auditSearchTextBox.add_PropertyChanged({
            param($source, $e)
            if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty) { Update-AuditGridRow }
        })
    $ui.auditGrid.add_SelectionChanged({ Show-AuditDetail })
    $ui.auditExportButton.Add_Click({
            $name = 'AuditLog_{0}.csv' -f [datetime]::Now.ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture)
            Start-AuditPicker -Mode Save -Title (Get-PSGPOText 'Export to CSV...') -FileName $name -Done { param($Chosen) Export-AuditShown -File $Chosen }
        })

    # The folder at start: the one given, else the one of the configuration of the domain, read once
    # the window is shown.
    if ($Path) {
        $ui.auditFolderTextBox.Text = $Path
        $ui.subtitleTextBlock.Text = Get-PSGPOText 'What the consoles and the commands changed in the domain - {0}' $Path
        Read-AuditLog
    } elseif ($Directory) {
        $ui.auditFolderTextBox.Text = Get-AuditDefaultFolder
        $ui.subtitleTextBlock.Text = Get-AuditDomainText
        Read-AuditLog
    } else {
        $ui.auditEmptyTextBlock.Text = Get-PSGPOText 'Reading the configuration of the domain...'
        $ui.auditGrid.IsVisible = $false
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                $read = $audit.DomainParameters
                if ($read.Server -or (Get-PSGPOPlatform).DomainName) {
                    try {
                        $audit.Directory = Get-PSGPODirectory @read -ErrorAction Stop -WarningAction SilentlyContinue
                        $ui.auditFolderTextBox.Text = Get-AuditDefaultFolder
                        $ui.subtitleTextBlock.Text = Get-AuditDomainText
                    } catch {
                        $ui.subtitleTextBlock.Text = Get-PSGPOText 'The domain could not be read ({0}): the folder Audit of your backups.' $_.Exception.GetBaseException().Message
                    }
                } else {
                    $ui.subtitleTextBlock.Text = Get-PSGPOText 'No domain: the folder Audit of your backups.'
                }
                $ui.auditFolderTextBox.Text = Get-AuditDefaultFolder
                Read-AuditLog
            }, [Avalonia.Threading.DispatcherPriority]::Background)
    }

    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
            [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { $cts.Cancel() }, [Avalonia.Threading.DispatcherPriority]::Background)
        })
    Show-PSGPOWindow -Window $window

    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Audit = $audit; Export = ${function:Export-AuditShown} } + $ui
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { $window.Close() }
            })
    }

    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        Write-Verbose 'The window is closed.'
    }

    if ($onShownState.Error) { throw $onShownState.Error }
}
