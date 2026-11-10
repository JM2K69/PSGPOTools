<#
    The forms of the Group Policy Management view: New GPO, Approve, Import, Delete, Restore and
    Purge a deleted GPO, Rename, Link an existing GPO, Delete a link.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerGpoFormView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerGpoFormView {
    # New GPO form: linked to $Som, or only created in the domain when $Som is $null; it starts
    # empty, from a template (a backup), or from a Starter GPO ($StarterGpo: chosen already).
    $newGpo = @{ Som = $null; Groups = $null; Templates = @(); Starters = @() }
    function Open-NewGpoForm {
        param([GPOToolsSom]$Som, $StarterGpo)
        $newGpo.Som = $Som
        $newGpoTitleTextBlock.Text = if ($Som) { Get-PSGPOText 'New GPO in {0}, linked to {1}' $Directory.DomainName $Som.Name } else { Get-PSGPOText 'New GPO in {0}' $Directory.DomainName }
        # What the configuration proposes (Get-PSGPOConfiguration): name, status, groups.
        $configuration = (Get-PSGPOConfigurationData).NewGpo
        $newGpo.Groups = $configuration.SecurityFilteringGroups
        $newGpoNameTextBox.Text = $configuration.DefaultName
        $newGpoErrorTextBlock.Text = ''
        $directoryResultTextBlock.Text = ''
        Hide-DirectoryForm
        # The templates: the backups with the template label, newest first.
        Update-BackupList -Force
        $newGpo.Templates = @($backupLists.Templates)
        # The Starter GPOs of the domain, read now when they are not yet: those that can be read.
        if ($null -eq $starterGpos.List) {
            try { $starterGpos.List = @(Get-PSGPOStarterGpoData -Directory $Directory) } catch { $starterGpos.List = @(); $starterGpos.Problem = $_.Exception.GetBaseException().Message }
        }
        $newGpo.Starters = @($starterGpos.List | Where-Object { $_ -and -not $_.Problem })
        $newGpoTemplateComboBox.ItemsSource = @(Get-PSGPOText 'Empty GPO') + @(foreach ($template in $newGpo.Templates) {
                (Get-PSGPOText '{0}, backup of {1}' $template.DisplayName (Format-HistoryDate $template.BackedUp)) + $(if ($template.Domain -and $template.Domain -ne $Directory.DomainName) { " ($($template.Domain))" })
            }) + @(foreach ($starter in $newGpo.Starters) { Get-PSGPOText 'Starter GPO: {0}' $starter.DisplayName })
        $newGpoTemplateComboBox.SelectedIndex = 0
        if ($StarterGpo) {
            $index = @($newGpo.Starters.Id).IndexOf($StarterGpo.Id)
            if ($index -ge 0) { $newGpoTemplateComboBox.SelectedIndex = 1 + $newGpo.Templates.Count + $index }
        }
        $newGpoStatusComboBox.SelectedIndex = [array]::IndexOf(@('Enabled', 'ComputerOnly', 'UserOnly'), $configuration.Status)
        # A GPO of a creator waits for its approval: its security filtering is set then.
        $creator = $Directory.IsWorkflowCreator()
        $newGpoGroupsCheckBox.IsVisible = -not $creator
        $newGpoGroupsCheckBox.IsChecked = [bool]$newGpo.Groups.Create -and -not $creator
        $newGpoGroupsPanel.IsVisible = [bool]$newGpoGroupsCheckBox.IsChecked
        if ($creator) { $newGpoTitleTextBlock.Text += Get-PSGPOText ': it waits for the approval of an approver, and applies to nobody until then' }
        # The groups go to the container of the configuration, else the users container, or to an OU.
        $configured = Resolve-PSGPOGroupContainer -Directory $Directory -Container $newGpo.Groups.Container
        $containers = [System.Collections.Generic.List[string]]::new()
        $containers.Add($configured)
        if ($configured -ne $Directory.GetUsersContainer()) { $containers.Add($Directory.GetUsersContainer()) }
        $stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        foreach ($child in @($Directory.Domain.Children | Sort-Object Name -Descending)) { $stack.Push($child) }
        while ($stack.Count) {
            $som = $stack.Pop()
            if ($som.DistinguishedName -ne $configured) { $containers.Add($som.DistinguishedName) }
            foreach ($child in @($som.Children | Sort-Object Name -Descending)) { $stack.Push($child) }
        }
        $newGpoGroupsContainerComboBox.ItemsSource = $containers
        $newGpoGroupsContainerComboBox.SelectedIndex = 0
        Update-NewGpoGroupText
        Show-DirectoryForm $newGpoPanel
        [void]$newGpoNameTextBox.Focus()
        $newGpoNameTextBox.SelectAll()
    }

    # What the security filtering groups of the new GPO will be.
    function Update-NewGpoGroupText {
        try {
            $settings = if ($newGpo.Groups) { $newGpo.Groups } else { (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups }
            $apply = Get-PSGPOFilteringGroupName -Role Apply -GpoName $newGpoNameTextBox.Text -Settings $settings
            $deny = Get-PSGPOFilteringGroupName -Role Deny -GpoName $newGpoNameTextBox.Text -Settings $settings
            $newGpoGroupsTextBlock.Text = Get-PSGPOText '{0}: only its members apply the GPO (add the computers or users to it). {1}: its members never apply it. Authenticated Users keep reading the GPO.' $apply $deny
        } catch {
            $newGpoGroupsTextBlock.Text = $_.Exception.Message
        }
    }

    # Creates the GPO, then sets its status and its security filtering groups, then links it.
    # It is not linked when its security filtering failed: it would apply to every computer and
    # user. What failed after the creation is said under the details of the GPO.
    function Submit-NewGpo {
        $index = $newGpoTemplateComboBox.SelectedIndex
        $template = if ($index -gt 0 -and $index -le $newGpo.Templates.Count) { $newGpo.Templates[$index - 1] }
        $starter = if ($index -gt $newGpo.Templates.Count) { $newGpo.Starters[$index - 1 - $newGpo.Templates.Count] }
        try {
            # A template checked before the GPO is created.
            if ($template) { $null = Get-PSGPOVerifiedBackupFile -Backup $template }
            $gpo = $Directory.NewGpo($newGpoNameTextBox.Text)
        } catch {
            $newGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $done = [System.Collections.Generic.List[string]]::new()
        $problems = [System.Collections.Generic.List[string]]::new()
        $done.Add((Get-PSGPOText "GPO '{0}' created." $gpo.DisplayName))
        if ($gpo.ApprovalState -eq 'Pending') { $done.Add((Get-PSGPOText 'It waits for the approval of {0}: it applies to nobody until then.' ($Directory.Workflow.Approvers -join ', '))) }
        if ($template) {
            try {
                Copy-PSGPOBackupSetting -Directory $Directory -Gpo $gpo -Backup $template
                $done.Add((Get-PSGPOText "Settings of the template '{0}' copied." $template.DisplayName))
            } catch {
                $problems.Add((Get-PSGPOText 'The settings of the template are not copied: {0}' $_.Exception.GetBaseException().Message))
            }
        }
        if ($starter) {
            try {
                Copy-PSGPOStarterSetting -Directory $Directory -Gpo $gpo -StarterGpo $starter
                $done.Add((Get-PSGPOText "Settings of the Starter GPO '{0}' copied." $starter.DisplayName))
            } catch {
                $problems.Add((Get-PSGPOText 'The settings of the Starter GPO are not copied: {0}' $_.Exception.GetBaseException().Message))
            }
        }
        $flags = [int]"$($newGpoStatusComboBox.SelectedItem.Tag)"
        if ($flags) {
            try {
                $Directory.SetGpoStatus($gpo, $flags)
                $done.Add((Get-PSGPOText 'GPO status: {0}.' (Get-PSGPOText $gpo.GetStatus())))
            } catch {
                $problems.Add((Get-PSGPOText 'Its status is not set: {0}' $_.Exception.GetBaseException().Message))
            }
        }
        $filtered = $true
        if ($newGpoGroupsCheckBox.IsChecked) {
            try {
                $container = "$($newGpoGroupsContainerComboBox.SelectedItem)"
                $groups = $Directory.NewFilteringGroups($gpo, $container)
                $done.Add((Get-PSGPOText 'Security filtering groups {0} created in {1}.' (@($groups.Name) -join (Get-PSGPOText ' and ')) $container))
            } catch {
                $filtered = $false
                $problems.Add((Get-PSGPOText 'Its security filtering groups are not set: {0}' $_.Exception.GetBaseException().Message))
            }
        }
        $select = $gpo
        if ($newGpo.Som) {
            if (-not $filtered) {
                $problems.Add((Get-PSGPOText 'It is not linked to {0}, so that it does not apply to everyone: link it once its security filtering is set.' $newGpo.Som.Name))
            } else {
                try {
                    $select = $Directory.NewLink($newGpo.Som, $gpo)
                    $done.Add((Get-PSGPOText 'Linked to {0}.' $newGpo.Som.Name))
                } catch {
                    $problems.Add((Get-PSGPOText 'It is not linked to {0}: {1}' $newGpo.Som.Name $_.Exception.GetBaseException().Message))
                }
            }
        }
        $newGpoPanel.IsVisible = $false
        Update-DirectoryTree -Select $select
        Show-DirectoryResult -Text ((@($done) + @($problems)) -join [Environment]::NewLine) -Problem:($problems.Count -gt 0)
    }

    # A form of the context menu: in the Details tab, shown whatever tab is open (from the History
    # tab, Approve... opened its form in the hidden Details tab, and seemed to do nothing).
    function Show-DirectoryForm {
        param([Parameter(Mandatory)] $Panel)
        Show-DirectoryDetailsTab
        $Panel.IsVisible = $true
    }

    # The Details tab, at its top: where the forms of the context menu and their results are.
    function Show-DirectoryDetailsTab {
        $directoryTabs.SelectedIndex = 0
        $directoryDetailsScrollViewer.ScrollToHome()
    }

    # What a change of the directory did, under the details; in red when something failed.
    function Show-DirectoryResult {
        param([string]$Text, [switch]$Problem)
        $directoryResultTextBlock.Text = $Text
        # A problem shown is kept in the technical log, to find its cause afterwards.
        if ($Problem) { Write-PSGPOLogEntry -Level Error -Source 'GPO console' -Message $Text }
        if ($Problem) {
            $directoryResultTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
        } else {
            $directoryResultTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty)
        }
    }

    # Deletion of the selected link, once confirmed, as GPMC: the GPO itself is kept.
    $deleteLink = @{ Som = $null; Link = $null }
    function Open-DeleteLinkForm {
        $node = $domainTreeView.SelectedItem
        if (-not $node -or $node.Tag -isnot [GPOToolsGpoLink] -or $node.Parent.Tag -isnot [GPOToolsSom]) { return }
        $deleteLink.Link = $node.Tag
        $deleteLink.Som = $node.Parent.Tag
        $deleteLinkTextBlock.Text = Get-PSGPOText "Delete the link of the GPO '{0}' to {1}? The GPO itself is not deleted: it stays in Group Policy Objects, with its other links." $node.Tag.GetDisplayName() $node.Parent.Tag.Name
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $deleteLinkPanel
    }

    # The forms of the details, one at a time.
    function Hide-DirectoryForm {
        foreach ($panel in $newGpoPanel, $deleteLinkPanel, $linkGpoPanel, $deleteGpoPanel, $restoreGpoPanel, $purgeDeletedGpoPanel, $renamePanel, $approveGpoPanel, $newWmiFilterPanel, $deleteWmiFilterPanel,
            $exportWmiFilterPanel, $importWmiFilterPanel, $useWmiFilterPanel, $importGpoPanel, $changeDcPanel, $gpoCopyPanel, $starterGpoPanel, $deleteStarterGpoPanel) { $panel.IsVisible = $false }
    }

    # Approval of the selected GPO (approval workflow): what the creators may still do, who
    # applies it; backed up with the approved label in the folder of the History tab.
    $approveGpo = @{ Gpo = $null; Groups = $null; Stamp = $null; Uninterpreted = @() }
    function Open-ApproveGpoForm {
        $gpo = Get-SelectedGpo
        if (-not $gpo -or $gpo.ApprovalState -ne 'Pending') { return }
        $approveGpo.Gpo = $gpo
        # What the approver approves: where it is linked, and whether someone made it apply already.
        $links = @($Directory.GetLinksOf($gpo))
        $approveGpoTextBlock.Text = $(if ($gpo.Owner) { Get-PSGPOText "Approve the GPO '{0}', created by {1}? " $gpo.DisplayName $gpo.Owner } else { Get-PSGPOText "Approve the GPO '{0}'? " $gpo.DisplayName }) +
            (Get-PSGPOText 'Its owner becomes {0}, in the directory and in SYSVOL, and its permissions are rebuilt: its creator cannot give itself its rights back. ' $Directory.Workflow.ApprovedOwner) +
            (Get-PSGPOText 'It applies to the group below from then on, and is backed up as its approved version. ') +
            $(if ($links.Count) { Get-PSGPOText 'It is linked to {0}.' (@($links | ForEach-Object { $_.Som.Name }) -join ', ') } else { Get-PSGPOText 'It is not linked.' }) +
            $(if ($gpo.AppliesWhilePending()) { Get-PSGPOText " Warning: it applies already, to {0}: someone gave 'Apply Group Policy' back while it was pending." ($gpo.SecurityFiltering -join ', ') })
        $approveGpoRightsComboBox.SelectedIndex = if ($Directory.Workflow.CreatorRights -eq 'EditSettings') { 1 } else { 0 }
        # Its own groups when they exist; else the approver may create them, as the New GPO form.
        $existing = Find-PSGPOFilteringGroup -Directory $Directory -Gpo $gpo
        $approveGpo.Groups = (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups
        # A group of its name someone else made: not proposed, nor Authenticated Users in its place.
        $approveGpoApplyToTextBox.Text = if ($existing.Apply) { $existing.Apply.Name } elseif ($existing.Problem) { '' } else { 'Authenticated Users' }
        $approveGpoDenyToTextBox.Text = if ($existing.Deny) { $existing.Deny.Name } else { '' }
        $approveGpoGroupsCheckBox.IsVisible = -not ($existing.Apply -or $existing.Deny -or $existing.Problem)
        $approveGpoGroupsCheckBox.IsChecked = $approveGpoGroupsCheckBox.IsVisible -and [bool]$approveGpo.Groups.Create
        $approveGpoGroupsTextBlock.Text = if ($approveGpoGroupsCheckBox.IsVisible) {
            Get-PSGPOText '{0} applies it, {1} is denied it; created in {2} ({3}).' (Get-PSGPOFilteringGroupName -Role Apply -GpoName $gpo.DisplayName -Settings $approveGpo.Groups) (Get-PSGPOFilteringGroupName -Role Deny -GpoName $gpo.DisplayName -Settings $approveGpo.Groups) (Resolve-PSGPOGroupContainer -Directory $Directory -Container $approveGpo.Groups.Container) $approveGpo.Groups.Scope
        } else { Get-PSGPOText 'Its groups exist: {0}.' (@($existing.Apply, $existing.Deny | Where-Object { $_ } | ForEach-Object Name) -join ', ') }
        Update-ApproveGpoGroupState
        $approveGpoErrorTextBlock.Text = if ($existing.Problem) { $existing.Problem } else { '' }
        # What the approver reviews: the GPO as it is now; its approval is refused if it changes.
        # What the console does not interpret in it is said, and the approver says it was reviewed.
        $approveGpo.Stamp = $null
        $approveGpo.Uninterpreted = @()
        try {
            $content = Read-PSGPOReviewContent -Directory $Directory -Gpo $gpo
            $approveGpo.Uninterpreted = @(Get-PSGPOReviewUninterpreted -Content $content)
            $approveGpo.Stamp = Get-PSGPOReviewStamp -Directory $Directory -Gpo $gpo -Content $content
        } catch { $approveGpoErrorTextBlock.Text = Get-PSGPOText 'The GPO cannot be read: {0}' $_.Exception.GetBaseException().Message }
        $approveGpoUninterpretedPanel.IsVisible = $approveGpo.Uninterpreted.Count -gt 0
        $approveGpoUninterpretedCheckBox.IsChecked = $false
        $approveGpoUninterpretedTextBlock.Text = Get-PSGPOText 'The console does not interpret {0} setting(s) of this GPO, which the computers apply: {1}. See them in the Settings tab.' $approveGpo.Uninterpreted.Count (@($approveGpo.Uninterpreted | ForEach-Object { ConvertTo-PSGPODisplayText $_.Name }) -join ', ')
        # What the add-ons tell the approver (the request of the change, its ticket...).
        $approveGpoAddOnTextBlock.Text = @(Get-PSGPOAddOnApprovalNote -Directory $Directory -Gpo $gpo) -join [Environment]::NewLine
        $approveGpoAddOnBorder.IsVisible = [bool]$approveGpoAddOnTextBlock.Text
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $approveGpoPanel
    }

    # The groups to create replace who applies it and who is denied it.
    function Update-ApproveGpoGroupState {
        $create = [bool]($approveGpoGroupsCheckBox.IsVisible -and $approveGpoGroupsCheckBox.IsChecked)
        $approveGpoFilteringGrid.IsEnabled = -not $create
        $approveGpoGroupsTextBlock.Opacity = if ($create -or -not $approveGpoGroupsCheckBox.IsVisible) { 1 } else { 0.6 }
    }

    function Submit-ApproveGpo {
        $gpo = $approveGpo.Gpo
        if (-not $gpo) { return }
        $rights = "$($approveGpoRightsComboBox.SelectedItem.Tag)"
        $create = [bool]($approveGpoGroupsCheckBox.IsVisible -and $approveGpoGroupsCheckBox.IsChecked)
        if (-not $approveGpo.Stamp) { $approveGpoErrorTextBlock.Text = Get-PSGPOText 'The GPO could not be read when the form opened: open the form again.'; return }
        if ($approveGpo.Uninterpreted.Count -and -not $approveGpoUninterpretedCheckBox.IsChecked) {
            $approveGpoErrorTextBlock.Text = Get-PSGPOText 'Review the settings the console does not interpret, then check the box above: it approves what it does not show.'
            return
        }
        try {
            $approval = @{ Directory = $Directory; Gpo = $gpo; CreatorRights = $rights; BackupPath = (Get-HistoryRoot); ReviewStamp = $approveGpo.Stamp }
            if ($create) {
                $approval.CreateFilteringGroups = $true
            } else {
                $approval.ApplyTo = Resolve-PSGPOApplyTo -Directory $Directory -Name "$($approveGpoApplyToTextBox.Text)"
                if ("$($approveGpoDenyToTextBox.Text)".Trim()) { $approval.DenyTo = Resolve-PSGPOApplyTo -Directory $Directory -Name "$($approveGpoDenyToTextBox.Text)" }
            }
            $result = Invoke-PSGPOApproval @approval
        } catch {
            $approveGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $approveGpoPanel.IsVisible = $false
        $settingsCache.Remove("$($gpo.Id)")
        $history.Current = @{}
        Update-DirectoryTree -Select $gpo
        $creators = Get-PSGPOText $(if ($rights -eq 'EditSettings') { 'the creators edit its settings' } else { 'the creators read it' })
        $lines = @($(if ($result.DeniedTo) { Get-PSGPOText "GPO '{0}' approved: owned by {1}, applied by {2}, denied to {3}, {4}." $gpo.DisplayName $result.Owner $result.AppliedBy $result.DeniedTo $creators }
                else { Get-PSGPOText "GPO '{0}' approved: owned by {1}, applied by {2}, {3}." $gpo.DisplayName $result.Owner $result.AppliedBy $creators }))
        if ($result.GroupsCreated.Count) { $lines += Get-PSGPOText 'Security filtering groups created: {0}.' ($result.GroupsCreated -join '; ') }
        if ($result.RemovedPermissions.Count) { $lines += Get-PSGPOText 'Permissions added while it was pending, removed: {0}. Find out who added them.' ($result.RemovedPermissions -join ' ') }
        if ($result.Backup) { $lines += Get-PSGPOText 'Backed up as its approved version.' }
        if ($result.Problem) { $lines += $result.Problem }
        Show-DirectoryResult -Text ($lines -join [Environment]::NewLine) -Problem:([bool]($result.Problem -or $result.RemovedPermissions.Count))
    }

    # Import Settings... of a GPO, as GPMC: the settings of a backup of GPMC or of HGPM, of this
    # domain or another, with a migration table; the GPO backed up first in the folder of the History tab.
    $importGpo = @{ Gpo = $null; Sources = @() }
    function Open-ImportGpoForm {
        $gpo = Get-SelectedGpo
        if (-not $gpo) { return }
        $importGpo.Gpo = $gpo
        $importGpoTitleTextBlock.Text = Get-PSGPOText "Import settings into the GPO '{0}'" $gpo.DisplayName
        if (-not "$($importGpoPathTextBox.Text)".Trim()) { $importGpoPathTextBox.Text = Get-HistoryRoot }
        $importGpoTextBlock.Text = Get-PSGPOText 'Its settings are replaced by those of the backup, with the migration table applied; it is backed up first in {0}. Its links, permissions, status and WMI filter do not change.' (Get-HistoryRoot)
        $importGpoErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $importGpoPanel
        Read-ImportSource
    }

    # The backups of the folder typed, to choose the one to import.
    function Read-ImportSource {
        $importGpo.Sources = @()
        $importGpoErrorTextBlock.Text = ''
        try {
            $importGpo.Sources = @(Get-PSGPOImportSource -Path "$($importGpoPathTextBox.Text)".Trim() 3>$null)
        } catch {
            $importGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
        }
        $importGpoSourceComboBox.ItemsSource = @(foreach ($source in $importGpo.Sources) {
                Get-PSGPOText '{0} - {1} backup of {2} ({3})' $source.DisplayName $source.Kind (Format-HistoryDate $source.BackedUp) $source.Domain
            })
        $importGpoSourceComboBox.SelectedIndex = if ($importGpo.Sources.Count) { 0 } else { -1 }
        $importGpoConfirmButton.IsEnabled = $importGpo.Sources.Count -gt 0
        if (-not $importGpo.Sources.Count -and -not $importGpoErrorTextBlock.Text) { $importGpoErrorTextBlock.Text = Get-PSGPOText 'No backup of GPMC or of HGPM in this folder.' }
    }

    function Submit-ImportGpo {
        $gpo = $importGpo.Gpo
        $source = if ($importGpoSourceComboBox.SelectedIndex -ge 0) { $importGpo.Sources[$importGpoSourceComboBox.SelectedIndex] }
        if (-not $gpo -or -not $source) { return }
        $table = "$($importGpoTableTextBox.Text)".Trim()
        try {
            $import = @{ Directory = $Directory; Source = $source; Gpo = $gpo; Exclusive = [bool]$importGpoExclusiveCheckBox.IsChecked; BackupPath = (Get-HistoryRoot) }
            if ($table) { $import.MigrationTable = $table }
            $result = Invoke-PSGPOImport @import
        } catch {
            $importGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $importGpoPanel.IsVisible = $false
        $settingsCache.Remove("$($gpo.Id)")
        $history.Current = @{}
        Update-BackupList -Force
        Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add((Get-PSGPOText "Settings of '{0}' imported into '{1}' (version {2})." $source.DisplayName $gpo.DisplayName $gpo.Version))
        foreach ($item in @($result.Migration | Where-Object Mode -In 'ByRelativeName', 'Explicit')) { $lines.Add((Get-PSGPOText '{0} -> {1}' $item.Source $item.Destination.QualifiedName)) }
        foreach ($item in @($result.Migration | Where-Object Mode -EQ 'None')) { $lines.Add((Get-PSGPOText '{0}: removed' $item.Source)) }
        $kept = @($result.Migration | Where-Object Mode -EQ 'NotInTable' | ForEach-Object Source)
        if ($kept.Count) { $lines.Add((Get-PSGPOText 'Kept as they are (not in the migration table): {0}' ($kept -join ', '))) }
        Show-DirectoryResult -Text ($lines -join [Environment]::NewLine)
    }

    # Deletion of the selected GPO, once confirmed, as GPMC: its links too; backed up first in
    # the folder of the History tab, so that Deleted GPOs keeps it.
    $deleteGpo = @{ Gpo = $null }
    function Open-DeleteGpoForm {
        $gpo = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($gpo -isnot [GPOToolsGpo]) { return }
        $deleteGpo.Gpo = $gpo
        $links = @($Directory.GetLinksOf($gpo))
        $linkNames = @($links | ForEach-Object { $_.Som.Name }) -join ', '
        # The links of the sites are not the domain's: they stay, to a GPO not found.
        $siteNames = @($Directory.GetSiteLinksOf($gpo) | ForEach-Object { $_.Som.Name }) -join ', '
        $deleteGpoTextBlock.Text = (Get-PSGPOText "Delete the GPO '{0}'? " $gpo.DisplayName) +
            $(if ($links.Count -gt 1) { Get-PSGPOText 'Its {0} links ({1}) are deleted too. ' $links.Count $linkNames } elseif ($links.Count) { Get-PSGPOText 'Its 1 link ({0}) is deleted too. ' $linkNames } else { Get-PSGPOText 'It is not linked. ' }) +
            $(if ($siteNames) { Get-PSGPOText 'Its links to the sites {0} stay: the administrators of the forest delete them with GPMC. ' $siteNames }) +
            (Get-PSGPOText 'It is backed up first in {0}: Deleted GPOs keeps it, to restore it.' (Get-HistoryRoot))
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $deleteGpoPanel
    }

    function Submit-DeleteGpo {
        $gpo = $deleteGpo.Gpo
        $deleteGpoPanel.IsVisible = $false
        if (-not $gpo) { return }
        try {
            $removed = Remove-PSGPOWithBackup -Directory $Directory -Gpo $gpo -Path (Get-HistoryRoot)
        } catch {
            # Some links may be gone already.
            Update-DirectoryTree -Select $gpo
            Show-DirectoryResult -Text (Get-PSGPOText "The GPO '{0}' is not deleted: {1}" $gpo.DisplayName $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $settingsCache.Remove("$($gpo.Id)")
        Update-BackupList -Force
        Update-DirectoryTree -Select $Directory.Domain
        $count = @($removed.Links).Count
        Show-DirectoryResult -Text $(if ($count -gt 1) { Get-PSGPOText "GPO '{0}' deleted, with its {1} links. Its backup is in Deleted GPOs, to restore it." $gpo.DisplayName $count }
            elseif ($count) { Get-PSGPOText "GPO '{0}' deleted, with its 1 link. Its backup is in Deleted GPOs, to restore it." $gpo.DisplayName }
            else { Get-PSGPOText "GPO '{0}' deleted. Its backup is in Deleted GPOs, to restore it." $gpo.DisplayName })
    }

    # A deleted GPO created again from its newest backup; linked again where it was, when its
    # security filtering allows it.
    $restoreGpo = @{ Backup = $null }
    function Open-RestoreGpoForm {
        $backup = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if (-not $backup -or $backup.PSObject.TypeNames -notcontains 'PSGPOTools.Backup') { return }
        $restoreGpo.Backup = $backup
        $restoreGpoTextBlock.Text = Get-PSGPOText "Create the deleted GPO '{0}' again from its backup of {1}? It gets a new unique ID from the domain, and the settings, status and client-side extensions of the backup. Its security filtering is not restored: it applies to Authenticated Users." $backup.DisplayName (Format-HistoryDate $backup.BackedUp)
        $links = @($backup.Links).Count
        $filtering = (@($backup.SecurityFiltering) -join '|') -eq 'Authenticated Users' -and -not @($backup.DeniedTo | Where-Object { $_ }).Count
        $restoreGpoLinkCheckBox.IsVisible = $links -gt 0
        $restoreGpoLinkCheckBox.IsEnabled = $filtering
        $restoreGpoLinkCheckBox.IsChecked = $filtering
        $restoreGpoLinkCheckBox.Content = if ($filtering) { Get-PSGPOText $(if ($links -gt 1) { 'Link it again where it was ({0} links)' } else { 'Link it again where it was ({0} link)' }) $links }
            else { Get-PSGPOText 'Not linked again: its security filtering was {0}, set it first' (@($backup.SecurityFiltering) -join ', ') }
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $restoreGpoPanel
    }

    function Submit-RestoreGpo {
        $backup = $restoreGpo.Backup
        $restoreGpoPanel.IsVisible = $false
        if (-not $backup) { return }
        try {
            $files = Get-PSGPOVerifiedBackupFile -Backup $backup
            $result = Restore-PSGPODeletedGpo -Directory $Directory -Backup $backup -Files $files -RestoreLink:([bool]($restoreGpoLinkCheckBox.IsVisible -and $restoreGpoLinkCheckBox.IsChecked))
        } catch {
            Show-DirectoryResult -Text (Get-PSGPOText "The GPO '{0}' is not restored: {1}" $backup.DisplayName $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $gpo = $Directory.Gpos | Where-Object Id -EQ $result.Id | Select-Object -First 1
        Update-BackupList -Force
        Update-DirectoryTree -Select $gpo
        $lines = @(Get-PSGPOText "GPO '{0}' restored from its backup of {1}, as {2}." $result.DisplayName (Format-HistoryDate $backup.BackedUp) "{$($result.Id.ToString().ToUpperInvariant())}")
        if ($result.Linked.Count) { $lines += Get-PSGPOText 'Linked again to {0}.' (@($result.Linked | ForEach-Object { $Directory.FindSom($_).Name }) -join ', ') }
        Show-DirectoryResult -Text ((@($lines) + @($result.Problems)) -join [Environment]::NewLine) -Problem:($result.Problems.Count -gt 0)
    }

    # A deleted GPO deleted for good, once confirmed: all its backups in the folder of the History
    # tab, its templates too; it leaves Deleted GPOs and cannot be restored anymore.
    $purgeDeletedGpo = @{ Backup = $null }
    function Open-PurgeDeletedGpoForm {
        $backup = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if (-not $backup -or $backup.PSObject.TypeNames -notcontains 'PSGPOTools.Backup') { return }
        $purgeDeletedGpo.Backup = $backup
        $backups = @(Get-PSGPOBackupEntry -Path (Get-HistoryRoot) -Id $backup.Id 3>$null)
        $label = Get-PSGPOTemplateLabel
        $templates = @($backups | Where-Object { $_.Labels -contains $label }).Count
        $purgeDeletedGpoTextBlock.Text = (Get-PSGPOText $(if ($backups.Count -gt 1) { "Delete the GPO '{0}' for good? Its {1} backups in {2} are deleted: it cannot be restored afterwards." } else { "Delete the GPO '{0}' for good? Its backup in {2} is deleted: it cannot be restored afterwards." }) $backup.DisplayName $backups.Count (Get-HistoryRoot)) +
            $(if ($templates) { ' ' + (Get-PSGPOText 'Templates of new GPOs made from it: {0}, deleted too.' $templates) })
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $purgeDeletedGpoPanel
    }

    function Submit-PurgeDeletedGpo {
        $backup = $purgeDeletedGpo.Backup
        $purgeDeletedGpoPanel.IsVisible = $false
        if (-not $backup) { return }
        try {
            $removed = Remove-PSGPODeletedGpoBackup -Directory $Directory -Path (Get-HistoryRoot) -Id $backup.Id
        } catch {
            Update-BackupList -Force
            Update-DirectoryTree -Select 'DeletedGpos'
            Show-DirectoryResult -Text (Get-PSGPOText "The GPO '{0}' is not deleted for good: {1}" $backup.DisplayName $_.Exception.GetBaseException().Message) -Problem
            return
        }
        Update-BackupList -Force
        Update-DirectoryTree -Select 'DeletedGpos'
        Show-DirectoryResult -Text (Get-PSGPOText $(if ($removed.Backups -gt 1) { "GPO '{0}' deleted for good: its {1} backups are deleted." } else { "GPO '{0}' deleted for good: its backup is deleted." }) $removed.DisplayName $removed.Backups)
    }

    # Rename... on a GPO (or a link to it) or on a WMI filter, as GPMC: its name only.
    $rename = @{ Target = $null; Select = $null }
    function Open-RenameForm {
        if (-not $renameMenuItem.IsVisible) { return }
        $item = $domainTreeView.SelectedItem.Tag
        $target = if ($item -is [GPOToolsWmiFilter]) { $item } else { Get-SelectedGpo }
        if (-not $target) { return }
        $rename.Target = $target
        $rename.Select = $item
        $renameTitleTextBlock.Text = if ($target -is [GPOToolsWmiFilter]) { Get-PSGPOText "Rename the WMI filter '{0}'" $target.Name } else { Get-PSGPOText "Rename the GPO '{0}'" $target.DisplayName }
        $renameTextBox.Text = "$target"
        $renameErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        Show-DirectoryForm $renamePanel
        $renameTextBox.Focus()
        $renameTextBox.SelectAll()
    }

    function Submit-Rename {
        $target = $rename.Target
        if (-not $target) { return }
        $old = "$target"
        $name = "$($renameTextBox.Text)".Trim()
        try {
            if ($target -is [GPOToolsWmiFilter]) { $Directory.EditWmiFilter($target, $name, $target.Description, $target.Queries) }
            else { $Directory.RenameGpo($target, $name) }
        } catch {
            $renameErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $renamePanel.IsVisible = $false
        if ("$target" -ceq $old) { return }
        Update-DirectoryTree -Select $rename.Select
        Show-DirectoryResult -Text (Get-PSGPOText $(if ($target -is [GPOToolsWmiFilter]) { "WMI filter '{0}' renamed '{1}'." } else { "GPO '{0}' renamed '{1}': its links, its settings and its history are kept." }) $old "$target")
    }

    function Submit-DeleteLink {
        $som = $deleteLink.Som
        $link = $deleteLink.Link
        if (-not $som -or -not $link) { return }
        try {
            $Directory.RemoveLink($som, $link)
        } catch {
            $deleteLinkPanel.IsVisible = $false
            Show-DirectoryResult -Text (Get-PSGPOText "The link of the GPO '{0}' to {1} is not deleted: {2}" $link.GetDisplayName() $som.Name $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $deleteLinkPanel.IsVisible = $false
        Update-DirectoryTree -Select $som
        Show-DirectoryResult -Text (Get-PSGPOText "Link of the GPO '{0}' to {1} deleted." $link.GetDisplayName() $som.Name)
    }

    # Link of an existing GPO to the selected domain or OU, as GPMC "Link an Existing GPO...": the
    # GPOs of the domain not linked there yet, by name.
    $linkGpo = @{ Som = $null }
    function Open-LinkGpoForm {
        param([GPOToolsSom]$Som)
        $linkGpo.Som = $Som
        $linkGpoTitleTextBlock.Text = Get-PSGPOText 'Link an existing GPO of {0} to {1}' $Directory.DomainName $Som.Name
        $linkGpoErrorTextBlock.Text = ''
        $directoryResultTextBlock.Text = ''
        Hide-DirectoryForm
        $linkGpoFilterTextBox.Text = ''
        Update-LinkGpoList
        Show-DirectoryForm $linkGpoPanel
        [void]$linkGpoFilterTextBox.Focus()
    }

    function Update-LinkGpoList {
        $som = $linkGpo.Som
        if (-not $som) { return }
        $filter = "$($linkGpoFilterTextBox.Text)".Trim()
        $linked = [System.Collections.Generic.HashSet[object]]::new()
        foreach ($link in $som.Links) { if ($link.Gpo) { [void]$linked.Add($link.Gpo) } }
        $gpos = [System.Collections.Generic.List[GPOToolsGpo]]::new()
        foreach ($gpo in @($Directory.Gpos | Sort-Object DisplayName)) {
            if ($linked.Contains($gpo)) { continue }
            if ($filter -and $gpo.DisplayName.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            $gpos.Add($gpo)
        }
        $linkGpoList.ItemsSource = $gpos
        $linkGpoList.SelectedIndex = if ($gpos.Count -eq 1) { 0 } else { -1 }
        $linkGpoConfirmButton.IsEnabled = $null -ne $linkGpoList.SelectedItem
        $linkGpoErrorTextBlock.Text = if ($gpos.Count) { '' }
            elseif ($filter) { Get-PSGPOText "No GPO named like '{0}' can be linked to {1}." $filter $som.Name }
            else { Get-PSGPOText 'Every GPO of {0} is already linked to {1}.' $Directory.DomainName $som.Name }
    }

    function Submit-LinkGpo {
        $som = $linkGpo.Som
        $gpo = $linkGpoList.SelectedItem
        if (-not $som -or $gpo -isnot [GPOToolsGpo]) { return }
        try {
            $link = $Directory.NewLink($som, $gpo)
        } catch {
            $linkGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $linkGpoPanel.IsVisible = $false
        Update-DirectoryTree -Select $link
        Show-DirectoryResult -Text (Get-PSGPOText "GPO '{0}' linked to {1}, link order {2}." $gpo.DisplayName $som.Name $link.Order)
    }
}
