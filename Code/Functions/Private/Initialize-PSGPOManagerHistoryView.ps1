<#
    The History tab of the GPO selected: its backups as a timeline, what changed at each one, the
    drift since its approval, a note, a backup, a restore.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerHistoryView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerHistoryView {
    # Reports of the backups read once (by folder), and of the current state of each GPO (by its
    # version and last change); the GPO compared to its approved version (Get-PSGPODriftState).
    $history = @{ Reports = @{}; Current = @{}; Drift = $null; Backup = $null }
    # The central backups of the domain: their folder, not another one.
    $historyPathTextBox.IsReadOnly = [bool]"$((Get-PSGPOConfigurationData).Backup.Path)".Trim()

    # The folder of the backups; empty when the central backups are not reached (the share not
    # mounted on Linux): $backupLists.RootProblem says why.
    function Get-HistoryRoot {
        $path = "$($historyPathTextBox.Text)".Trim()
        if (-not $path) {
            try {
                $path = Get-PSGPODefaultBackupPath
                $backupLists.RootProblem = $null
            } catch {
                $backupLists.RootProblem = $_.Exception.Message
                return ''
            }
            $historyPathTextBox.Text = $path
        }
        $path
    }

    function Set-HistoryStatus {
        param([string]$Text, [switch]$Problem)
        $historyStatusTextBlock.Text = $Text
        if ($Problem) { Write-PSGPOLogEntry -Level Error -Source 'History tab' -Message $Text }
        if ($Problem) { $historyStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $historyStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    function Format-HistoryDate {
        param($Date)
        if ($null -eq $Date) { return Get-PSGPOText 'unknown date' }
        ([datetime]$Date).ToLocalTime().ToString('g')
    }

    function Get-ChangeSummary {
        param([object[]]$Changes)
        $count = { param($Kind) @($Changes | Where-Object Change -EQ $Kind).Count }
        if (-not $Changes.Count) { return Get-PSGPOText 'no setting changed' }
        '+{0}  ~{1}  -{2}' -f (& $count 'Added'), (& $count 'Changed'), (& $count 'Removed')
    }

    # The timeline of the selected GPO; the backup in $SelectPath selected, else the newest node.
    function Update-HistoryTab {
        param([string]$SelectPath)
        $gpo = Get-SelectedGpo
        # Central backups, for Tier 0 only.
        $historyTab.IsVisible = [bool]$gpo -and (Test-PSGPOBackupAllowed -Directory $Directory)
        if (-not $historyTab.IsVisible) {
            if ($directoryTabs.SelectedItem -eq $historyTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $historyTab) { return }
        # The settings of the backups are named by the ADMX files: the tab once they are loaded.
        if (Wait-ConsoleAdmx -Then ${function:Update-HistoryTab} -ArgumentList $SelectPath) {
            Set-HistoryStatus (Get-PSGPOText 'Loading the administrative templates (ADMX)...')
            return
        }

        $root = Get-HistoryRoot
        if (-not $root) {
            $historyTimelineList.ItemsSource = @()
            Set-HistoryStatus $backupLists.RootProblem -Problem
            return
        }
        $nodes = [System.Collections.Generic.List[AvaloniaHistoryNode]]::new()
        $problem = $null
        $history.Drift = $null
        $approvedLabel = Get-PSGPOApprovedLabel
        try {
            # Oldest first, as the branch of a git graph.
            $backups = @(Get-PSGPOBackupEntry -Path $root -Id $gpo.Id)
            [array]::Reverse($backups)
            $previous = @()
            $previousDate = $null
            foreach ($backup in $backups) {
                if (-not $history.Reports.ContainsKey($backup.Path)) { $history.Reports[$backup.Path] = @(Get-PSGPOBackupSetting -Backup $backup) }
                $report = $history.Reports[$backup.Path]
                $node = [AvaloniaHistoryNode]::new()
                $node.Backup = $backup
                $node.Title = Format-HistoryDate $(if ($backup.Modified) { $backup.Modified } else { $backup.BackedUp })
                $node.Subtitle = Get-PSGPOText 'computer {0}, user {1}' $backup.ComputerVersion $backup.UserVersion
                $node.Changes = @(Compare-PSGPOSettingReport -Reference $previous -Difference $report)
                $node.Summary = if ($nodes.Count) { Get-ChangeSummary $node.Changes } else { Get-PSGPOText 'first backup' }
                $node.Previous = $previousDate
                # The approved version in green, its labels under it, its comment as its tool tip.
                $node.IsApproved = $backup.Labels -contains $approvedLabel
                $node.NodeFill = if ($node.IsApproved) { '#107C10' } else { '#0078D4' }
                $node.NodeStroke = $node.NodeFill
                $node.LineBrush = '#8A8886'
                $node.LabelsText = @($backup.Labels) -join ', '
                $node.HasLabels = [bool]@($backup.Labels).Count
                $node.LabelBrush = if ($node.IsApproved) { '#3BA55C' } else { '#3A96DD' }
                if ($backup.Comment) { $node.Comment = $backup.Comment }
                $nodes.Add($node)
                $previous = $report
                $previousDate = $node.Title
            }

            # The GPO as it is now, when it changed since its last backup.
            $Directory.RefreshGpo($gpo)
            $key = "$($gpo.Id)|$($gpo.Version)|$($gpo.Modified)|$($gpo.Flags)"
            if (-not $history.Current.ContainsKey($key)) {
                $files = $Directory.ReadGpoFolder($gpo)
                $history.Current[$key] = @(Get-PSGPOSettingReport -Files $files -Property (Get-PSGPOBackupProperty -Directory $Directory -Gpo $gpo))
            }
            $changes = @(Compare-PSGPOSettingReport -Reference $previous -Difference $history.Current[$key])
            # Its approved version: the newest backup with the label.
            $approvedNode = @($nodes | Where-Object IsApproved) | Select-Object -Last 1
            $history.Drift = if ($approvedNode) {
                Get-PSGPODriftState -Directory $Directory -Gpo $gpo -Backups @($approvedNode.Backup) -Current $history.Current[$key] `
                    -ApprovedSetting $history.Reports[$approvedNode.Backup.Path] -Label $approvedLabel
            }
            if ($changes.Count -or -not $nodes.Count) {
                $node = [AvaloniaHistoryNode]::new()
                $node.IsCurrent = $true
                $node.Title = Get-PSGPOText 'Now'
                $node.Subtitle = Get-PSGPOText 'computer {0}, user {1}' $gpo.GetComputerVersion() $gpo.GetUserVersion()
                $node.Changes = $changes
                $node.Summary = if ($nodes.Count) { Get-PSGPOText '{0}, not backed up' (Get-ChangeSummary $changes) } else { Get-PSGPOText 'not backed up' }
                $node.Previous = $previousDate
                $node.NodeFill = 'Transparent'
                $node.NodeStroke = '#CA5010'
                $node.LineBrush = '#8A8886'
                $nodes.Add($node)
            }
        } catch {
            $problem = Get-PSGPOText 'The history cannot be read: {0}' $_.Exception.GetBaseException().Message
        }

        $historyTimelineList.ItemsSource = $nodes
        $backed = @($nodes | Where-Object { -not $_.IsCurrent }).Count
        if ($problem) { Set-HistoryStatus $problem -Problem }
        elseif (-not $backed) { Set-HistoryStatus (Get-PSGPOText 'No backup of this GPO in {0} yet: Back up now keeps its settings as they are.' $root) }
        else {
            $count = Get-PSGPOText $(if ($backed -gt 1) { '{0} backups in {1}.' } else { '{0} backup in {1}.' }) $backed $root
            Set-HistoryStatus ($count + ' ' + (Get-PSGPOText $(if ($nodes[-1].IsCurrent) { 'The GPO changed since the last one (Now).' } else { 'The last one is up to date.' })))
        }
        Update-HistoryDrift -Backed $backed -Label $approvedLabel
        # The node asked for, else the newest one; the branch scrolled to it.
        $index = $nodes.Count - 1
        if ($SelectPath) {
            for ($i = 0; $i -lt $nodes.Count; $i++) { if ($nodes[$i].Backup -and $nodes[$i].Backup.Path -eq $SelectPath) { $index = $i } }
        }
        if ($nodes.Count) {
            # Selecting the node it is already on would not show it again.
            if ($historyTimelineList.SelectedIndex -eq $index) { Show-HistoryChange $nodes[$index] } else { $historyTimelineList.SelectedIndex = $index }
        } else { Show-HistoryChange $null }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { $historyTimelineScrollViewer.ScrollToEnd() }, [Avalonia.Threading.DispatcherPriority]::Background)
    }

    # The GPO compared to its approved version, over the timeline: in orange when it changed since.
    function Update-HistoryDrift {
        param([int]$Backed, [string]$Label)
        $drift = $history.Drift
        $historyDriftButton.IsVisible = $drift -and $drift.State -eq 'Drifted'
        $historyDriftBorder.IsVisible = $Backed -gt 0
        if (-not $Backed) { return }
        $brush = '#8A8886'
        $historyDriftTextBlock.Text = if (-not $drift) {
            Get-PSGPOText "No approved version yet: check '{0}' in the notes of a backup to see what changes after it." $Label
        } else {
            $approved = if ($drift.ApprovedBy) { Get-PSGPOText '{0}, by {1}' (Format-HistoryDate $drift.Approved) $drift.ApprovedBy } else { Format-HistoryDate $drift.Approved }
            if ($drift.State -eq 'Drifted') {
                $brush = '#CA5010'
                Get-PSGPOText 'Changed since its approved version of {0} ({1}).' $approved (Get-ChangeSummary $drift.Changes)
            } else {
                $brush = '#107C10'
                Get-PSGPOText 'The GPO is its approved version of {0}.' $approved
            }
        }
        $historyDriftBorder.BorderBrush = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse($brush))
    }

    # What changed at the selected node, from the node before it; or what $Title says, for the
    # changes since the approved version.
    function Show-HistoryChange {
        param([AvaloniaHistoryNode]$Node, [string]$Title)
        # A backup can be restored, by an account that may edit the GPO.
        $gpo = Get-SelectedGpo
        $historyRestorePanel.IsVisible = $false
        $historyRestoreButton.IsVisible = $Node -and -not $Node.IsCurrent -and -not $Title -and $gpo -and $gpo.CanEdit -and -not $Directory.IsReadOnly
        Show-HistoryNote $(if (-not $Title) { $Node })
        if (-not $Node) {
            $historyCompareTextBlock.Text = ''
            $historyChangesList.ItemsSource = $null
            return
        }
        $historyCompareTextBlock.Text = if ($Title) { $Title }
            elseif ($Node.IsCurrent -and $Node.Previous) { Get-PSGPOText 'Changes since the backup of {0}, not backed up yet' $Node.Previous }
            elseif ($Node.IsCurrent) { Get-PSGPOText 'The settings of the GPO now, never backed up' }
            elseif ($Node.Previous) { Get-PSGPOText 'Changes from {0} to {1}' $Node.Previous $Node.Title }
            else { Get-PSGPOText 'First backup, {0}: the settings of the GPO then' $Node.Title }
        if (-not $Node.Changes.Count) { $historyCompareTextBlock.Text += Get-PSGPOText ': no setting changed (the version or the files did)' }
        $scopes = @{ GPO = 'GPO'; Computer = Get-PSGPOText 'Computer Configuration'; User = Get-PSGPOText 'User Configuration'; Files = Get-PSGPOText 'Files' }
        $brushes = @{ Added = '#107C10'; Removed = '#D13438'; Changed = '#CA5010' }
        $historyChangesList.ItemsSource = @(foreach ($change in $Node.Changes) {
                $row = [AvaloniaChangeRow]::new()
                $row.Change = Get-PSGPOText $change.Change
                $row.ChangeBrush = $brushes[$change.Change]
                # The report of the changes is in English (Compare-PSGPOBackup shares it).
                $row.Location = "$($scopes[$change.Scope]) > $(ConvertTo-PSGPODisplayText $change.Path)"
                $row.Name = ConvertTo-PSGPODisplayText $change.Name
                $row.Before = ConvertTo-PSGPODisplayText $change.Before
                $row.After = ConvertTo-PSGPODisplayText $change.After
                $row.HasBefore = [bool]$change.Before
                $row.HasAfter = [bool]$change.After
                $row
            })
    }

    # The notes of the backup of a node, to change them; hidden for the GPO now.
    $historyNote = @{ Backup = $null }
    function Show-HistoryNote {
        param([AvaloniaHistoryNode]$Node)
        $backup = if ($Node -and -not $Node.IsCurrent) { $Node.Backup }
        $historyNote.Backup = $backup
        $historyNotesPanel.IsVisible = [bool]$backup
        if (-not $backup) { return }
        $label = Get-PSGPOApprovedLabel
        $info = if ($backup.BackedUpBy) { Get-PSGPOText 'Backed up by {0} on {1}.' $backup.BackedUpBy (Format-HistoryDate $backup.BackedUp) } else { Get-PSGPOText 'Backed up on {0}.' (Format-HistoryDate $backup.BackedUp) }
        if ($backup.NotesUpdated) {
            $info += ' ' + $(if ($backup.NotesUpdatedBy) { Get-PSGPOText 'Notes changed by {0} on {1}.' $backup.NotesUpdatedBy (Format-HistoryDate $backup.NotesUpdated) } else { Get-PSGPOText 'Notes changed on {0}.' (Format-HistoryDate $backup.NotesUpdated) })
        }
        $historyNotesInfoTextBlock.Text = $info
        $historyNotesCommentTextBox.Text = $backup.Comment
        $template = Get-PSGPOTemplateLabel
        $historyNotesLabelsTextBox.Text = @($backup.Labels | Where-Object { $_ -ne $label -and $_ -ne $template }) -join ', '
        $historyNotesApprovedCheckBox.Content = Get-PSGPOText '{0} version' $label
        $historyNotesApprovedCheckBox.IsChecked = $backup.Labels -contains $label
        $historyNotesTemplateCheckBox.Content = $template
        $historyNotesTemplateCheckBox.IsChecked = $backup.Labels -contains $template
    }

    function Save-HistoryNote {
        $backup = $historyNote.Backup
        if (-not $backup) { return }
        $label = Get-PSGPOApprovedLabel
        $template = Get-PSGPOTemplateLabel
        $labels = @("$($historyNotesLabelsTextBox.Text)" -split ',' | Where-Object { $_.Trim() -and $_.Trim() -ne $label -and $_.Trim() -ne $template })
        if ($historyNotesApprovedCheckBox.IsChecked) { $labels += $label }
        if ($historyNotesTemplateCheckBox.IsChecked) { $labels += $template }
        try {
            $saved = Save-PSGPOBackupNote -Backup $backup -Comment $historyNotesCommentTextBox.Text -Label $labels -Account $Directory.Account
        } catch {
            Set-HistoryStatus (Get-PSGPOText 'The notes are not saved: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        Update-HistoryTab -SelectPath $saved.Path
        Set-HistoryStatus (Get-PSGPOText 'Notes of the backup of {0} saved.' (Format-HistoryDate $(if ($saved.Modified) { $saved.Modified } else { $saved.BackedUp })))
    }

    # Backs up GPOs in the folder of the history, with the comment typed; what was done in the status.
    function Invoke-HistoryBackup {
        param([GPOToolsGpo[]]$Gpos)
        $root = Get-HistoryRoot
        $comment = "$($historyCommentTextBox.Text)".Trim()
        try { New-PSGPOFolder -Path $root }
        catch { Set-HistoryStatus (Get-PSGPOText 'The folder of the backups cannot be created: {0}' $_.Exception.GetBaseException().Message) -Problem; return }
        # The folder of the account, kept for the next time; not the central backups of the domain.
        if (-not "$((Get-PSGPOConfigurationData).Backup.Path)".Trim()) { Set-PSGPOUserSetting -Values @{ BackupPath = $root } }
        $history.Backup = @{ Root = $root; Count = $Gpos.Count }
        # In the background, not cancelled: a backup stopped half-way would be left in the folder.
        $null = Start-ConsoleOperation -NoCancel -Text (Get-PSGPOText 'Backing up {0} GPO(s) in {1}...' $Gpos.Count $root) -ScriptBlock {
            param($Directory, $Gpos, $Root, $Comment)
            $counts = @{ Created = 0; Unchanged = 0 }
            $errors = [System.Collections.Generic.List[string]]::new()
            foreach ($gpo in $Gpos) {
                try {
                    $result = Save-PSGPOBackup -Directory $Directory -Gpo $gpo -Path $Root -Comment $Comment
                    $counts[$result.Result]++
                } catch {
                    $errors.Add("$($gpo.DisplayName): $($_.Exception.GetBaseException().Message)")
                }
            }
            [pscustomobject]@{ Created = $counts.Created; Unchanged = $counts.Unchanged; Errors = $errors.ToArray(); Comment = $Comment }
        } -ArgumentList $Directory, $Gpos, $root, $comment -Done {
            param($Result)
            Complete-HistoryBackup -Result $Result[0]
        } -Failed {
            param($ErrorRecord)
            Set-HistoryStatus (Get-PSGPOText 'Not backed up: {0}' $ErrorRecord.Exception.GetBaseException().Message) -Problem
        }
    }

    # What the backups gave: the timeline read again, and what was backed up.
    function Complete-HistoryBackup {
        param([Parameter(Mandatory)] $Result)
        $root = $history.Backup.Root
        $comment = $Result.Comment
        $counts = @{ Created = $Result.Created; Unchanged = $Result.Unchanged }
        $errors = @($Result.Errors)
        $history.Current = @{}
        Update-HistoryTab
        # The comment went with the new backups.
        if ($counts.Created) { $historyCommentTextBox.Text = '' }
        $text = if ($history.Backup.Count -eq 1 -and -not $errors.Count) {
            if ($counts.Created) { Get-PSGPOText 'Backed up in {0}.' $root }
            elseif ($comment) { Get-PSGPOText 'Not backed up again: the GPO did not change since its last backup. Its comment is in the notes of that backup.' }
            else { Get-PSGPOText 'Not backed up again: the GPO did not change since its last backup.' }
        } else {
            Get-PSGPOText '{0} GPO(s) backed up, {1} unchanged since their last backup, in {2}.' $counts.Created $counts.Unchanged $root
        }
        if ($errors.Count) { Set-HistoryStatus ($text + ' ' + (Get-PSGPOText 'Not backed up: {0}' ($errors -join '; '))) -Problem } else { Set-HistoryStatus $text }
    }

    # Restore of the selected backup, once confirmed; the GPO as it is now is backed up first.
    $historyRestoreButton.Add_Click({
        $node = $historyTimelineList.SelectedItem
        $gpo = Get-SelectedGpo
        if (-not $node -or $node.IsCurrent -or -not $gpo) { return }
        $historyRestoreTextBlock.Text = Get-PSGPOText "Restore the GPO '{0}' as it was on {1}? Its files, status and client-side extensions are replaced, and its version increases so that the computers apply it again. Its links and security filtering do not change. The GPO as it is now is backed up first." $gpo.DisplayName $node.Title
        $historyRestorePanel.IsVisible = $true
    })
    $historyRestoreCancelButton.Add_Click({ $historyRestorePanel.IsVisible = $false })
    $historyRestoreConfirmButton.Add_Click({
        $node = $historyTimelineList.SelectedItem
        $gpo = Get-SelectedGpo
        $historyRestorePanel.IsVisible = $false
        if (-not $node -or $node.IsCurrent -or -not $gpo) { return }
        try {
            $result = Restore-PSGPO -Backup $node.Backup -Directory $Directory -Confirm:$false
        } catch {
            Set-HistoryStatus (Get-PSGPOText 'The GPO is not restored: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        # Its settings, details and history as they are now.
        $settingsCache.Remove("$($gpo.Id)")
        $history.Current = @{}
        Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag
        $directoryTabs.SelectedItem = $historyTab
        Update-HistoryTab
        Set-HistoryStatus (Get-PSGPOText 'GPO restored as it was on {0} (version {1}); its state before was backed up.' $node.Title $result.Version)
    })
    $historyTimelineList.add_SelectionChanged({ Show-HistoryChange $historyTimelineList.SelectedItem })
    $historyNotesSaveButton.Add_Click({ Save-HistoryNote })
    # The changes from the approved version to the GPO now, under the timeline.
    $historyDriftButton.Add_Click({
        $drift = $history.Drift
        if (-not $drift) { return }
        $node = [AvaloniaHistoryNode]::new()
        $node.IsCurrent = $true
        $node.Changes = $drift.Changes
        Show-HistoryChange $node -Title (Get-PSGPOText 'Changes since the approved version of {0}' (Format-HistoryDate $drift.Approved))
    })
    $historyBackupButton.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Invoke-HistoryBackup -Gpos @($gpo) } })
    $historyBackupAllButton.Add_Click({ Invoke-HistoryBackup -Gpos @($Directory.GetVisibleGpos()) })
    # Another folder: its backups, remembered for the next time.
    $historyPathTextBox.add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            if (-not $historyPathTextBox.IsReadOnly) { Set-PSGPOUserSetting -Values @{ BackupPath = (Get-HistoryRoot) } }
            Update-HistoryTab
            # Its deleted GPOs in the tree.
            Update-BackupList -Force
            $tag = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
            if ($tag -is [GPOToolsGpo] -or $tag -is [GPOToolsSom]) { Update-DirectoryTree -Select $tag } else { Update-DirectoryTree -Select $Directory.Domain }
        }
    })
}
