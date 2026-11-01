<#
    The tree of the domain: what its selection shows, its context menu and its commands (the links,
    their order, the inheritance, the status of a GPO), and the buttons of the forms they open; a
    change written to the domain at once (Invoke-DirectoryChange).

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerDomainTreeView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerDomainTreeView {
    function Get-SelectedGpo {
        $item = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($item -is [GPOToolsGpoLink]) { $item.Gpo } elseif ($item -is [GPOToolsGpo]) { $item }
    }

    $domainTreeView.add_SelectionChanged({
        $selected = $domainTreeView.SelectedItem
        $item = if ($selected) { $selected.Tag }

        $pathParts = [System.Collections.Generic.List[string]]::new()
        for ($current = $selected; $current; $current = $current.Parent) { $pathParts.Insert(0, $current.Header) }
        $directoryBreadcrumbTextBlock.Text = if ($pathParts.Count) { $pathParts -join ' > ' } else { $directoryHint }

        $detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $item -DeletedGpo $backupLists.Deleted
        $directoryTitleTextBlock.Text = $detail.Title
        $directoryPropertiesList.ItemsSource = $detail.Properties
        $linksHeaderTextBlock.Text = $detail.LinksHeader
        $linksHeaderTextBlock.IsVisible = [bool]$detail.LinksHeader
        $linksList.ItemsSource = $detail.Links
        $editGpoButton.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit
        # Its comment (GPO.cmt), read after the click.
        Update-GpoComment -Gpo $detail.Gpo
        $directoryResultTextBlock.Text = ''
        Hide-DirectoryForm
        $canRestore = $null -ne $detail.Deleted -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo
        $restoreDeletedGpoButton.IsVisible = $canRestore
        $purgeDeletedGpoButton.IsVisible = $canRestore

        # Context menu of the selected node, as in GPMC.
        # A read-only directory (read over LDAP) cannot create GPOs yet.
        # And what the account may do there (its delegations).
        $createLinkedGpoMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo -and $item.CanLink
        $linkGpoMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $item.CanLink -and $Directory.Gpos.Count -gt 0
        $newGpoMenuItem.IsVisible = $item -eq 'GroupPolicyObjects' -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo
        # Search..., as GPMC: on the domain and on Group Policy Objects.
        $gpoSearchMenuItem.IsVisible = [object]::ReferenceEquals($item, $Directory.Domain) -or $item -eq 'GroupPolicyObjects'
        $editGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit
        $deleteLinkMenuItem.IsVisible = $item -is [GPOToolsGpoLink] -and -not $Directory.IsReadOnly -and $selected.Parent.Tag.CanLink
        # A link: Enforced, Link Enabled and its order, as GPMC; a SOM: Block Inheritance.
        $onLink = $deleteLinkMenuItem.IsVisible
        $enforcedLinkMenuItem.IsVisible = $onLink
        $enforcedLinkMenuItem.IsChecked = $onLink -and $item.Enforced
        $enabledLinkMenuItem.IsVisible = $onLink
        $enabledLinkMenuItem.IsChecked = $onLink -and $item.Enabled
        $moveLinkUpMenuItem.IsVisible = $onLink -and $item.Order -gt 1
        $moveLinkDownMenuItem.IsVisible = $onLink -and $item.Order -lt $selected.Parent.Tag.Links.Count
        $blockInheritanceMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $item.CanLink
        $blockInheritanceMenuItem.IsChecked = $item -is [GPOToolsSom] -and $item.BlockInheritance
        # The domain read from another domain controller, as GPMC.
        $changeDcMenuItem.IsVisible = $Directory -is [GPOToolsLdapDirectory] -and [object]::ReferenceEquals($item, $Directory.Domain)
        $gpoStatusMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit -and -not $Directory.IsReadOnly
        foreach ($statusItem in $gpoStatusEnabledMenuItem, $gpoStatusUserDisabledMenuItem, $gpoStatusComputerDisabledMenuItem, $gpoStatusAllDisabledMenuItem) {
            $statusItem.IsChecked = $null -ne $detail.Gpo -and [int]$statusItem.Tag -eq ($detail.Gpo.Flags -band 3)
        }
        # WMI Filters: a new filter, the change or the deletion of one.
        $newWmiFilterMenuItem.IsVisible = $item -eq 'WmiFilters' -and -not $Directory.IsReadOnly -and $Directory.CanCreateWmiFilter
        $editWmiFilterMenuItem.IsVisible = $item -is [GPOToolsWmiFilter] -and -not $Directory.IsReadOnly -and $item.CanEdit
        $editWmiFilterButton.IsVisible = $editWmiFilterMenuItem.IsVisible
        $deleteWmiFilterMenuItem.IsVisible = $editWmiFilterMenuItem.IsVisible
        # Rename a GPO (its node or a link to it) or a WMI filter, as GPMC.
        $renameMenuItem.IsVisible = $editWmiFilterMenuItem.IsVisible -or $gpoStatusMenuItem.IsVisible
        # WMI Filter: the filters of the domain, as the WMI Filtering of the Scope tab of GPMC.
        $wmiFilterMenuItem.IsVisible = $gpoStatusMenuItem.IsVisible -and ($Directory.WmiFilters.Count -or $null -ne $detail.Gpo.WmiFilterId)
        if ($wmiFilterMenuItem.IsVisible) { Update-WmiFilterMenu -Gpo $detail.Gpo }
        # And in the details of the GPO.
        $gpoWmiFilterPanel.IsVisible = $wmiFilterMenuItem.IsVisible
        if ($gpoWmiFilterPanel.IsVisible) { Update-GpoWmiFilterComboBox -Gpo $detail.Gpo }
        # A filter: exported by anyone who reads it, used in the GPOs the account edits; WMI
        # Filters: a filter imported where the account creates them.
        $exportWmiFilterMenuItem.IsVisible = $item -is [GPOToolsWmiFilter]
        $useWmiFilterMenuItem.IsVisible = $item -is [GPOToolsWmiFilter] -and -not $Directory.IsReadOnly -and @($Directory.Gpos | Where-Object CanEdit).Count -gt 0
        $importWmiFilterMenuItem.IsVisible = $newWmiFilterMenuItem.IsVisible
        # Delete a GPO from Group Policy Objects, as GPMC; never a default GPO of the domain.
        $importGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit -and -not $Directory.IsReadOnly
        $deleteGpoMenuItem.IsVisible = $item -is [GPOToolsGpo] -and -not $Directory.IsReadOnly -and $item.CanEdit -and [GPOToolsDirectory]::DefaultGpoIds -notcontains $item.Id
        $restoreDeletedGpoMenuItem.IsVisible = $canRestore
        $purgeDeletedGpoMenuItem.IsVisible = $canRestore
        $approveGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.ApprovalState -eq 'Pending' -and -not $Directory.IsReadOnly -and
            $Directory.Workflow -and $Directory.Workflow.IsApprover
        # Save report... of any GPO the account reads, as GPMC.
        $saveReportGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $settingsReportButton.IsVisible
        Update-SomTab
        Update-SettingsTab
        Update-DelegationTab
        Update-WmiDelegationTab
        Update-HistoryTab
        Update-StatusTab
    })
    # Nothing to offer on this node: do not open an empty menu.
    (Get-PSGPOAvaloniaControl $window 'domainContextMenu').add_Opening({
        param($control, $e)
        if (-not ($createLinkedGpoMenuItem.IsVisible -or $linkGpoMenuItem.IsVisible -or $newGpoMenuItem.IsVisible -or $editGpoMenuItem.IsVisible -or $renameMenuItem.IsVisible -or $purgeDeletedGpoMenuItem.IsVisible -or $deleteLinkMenuItem.IsVisible -or
                $exportWmiFilterMenuItem.IsVisible -or $importWmiFilterMenuItem.IsVisible -or $useWmiFilterMenuItem.IsVisible -or
                $blockInheritanceMenuItem.IsVisible -or $changeDcMenuItem.IsVisible -or $gpoStatusMenuItem.IsVisible -or $wmiFilterMenuItem.IsVisible -or $newWmiFilterMenuItem.IsVisible -or $editWmiFilterMenuItem.IsVisible -or $deleteWmiFilterMenuItem.IsVisible -or
                $deleteGpoMenuItem.IsVisible -or $restoreDeletedGpoMenuItem.IsVisible -or $approveGpoMenuItem.IsVisible -or $importGpoMenuItem.IsVisible -or
                $saveReportGpoMenuItem.IsVisible) -or
            -not $domainTreeView.SelectedItem) { $e.Cancel = $true }
    })

    $createLinkedGpoMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsSom]) { Open-NewGpoForm -Som $item } })
    $newGpoMenuItem.Add_Click({ Open-NewGpoForm -Som $null })
    $linkGpoMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsSom]) { Open-LinkGpoForm -Som $item } })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $linkGpoFilterTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property.Name -eq 'Text' -and $linkGpoPanel.IsVisible) { Update-LinkGpoList }
    })
    $linkGpoList.add_SelectionChanged({ $linkGpoConfirmButton.IsEnabled = $null -ne $linkGpoList.SelectedItem })
    $linkGpoList.add_DoubleTapped({ Submit-LinkGpo })
    $linkGpoConfirmButton.Add_Click({ Submit-LinkGpo })
    $linkGpoCancelButton.Add_Click({ $linkGpoPanel.IsVisible = $false })
    $editGpoMenuItem.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $editGpoButton.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $domainTreeView.add_DoubleTapped({ $gpo = Get-SelectedGpo; if ($gpo -and $gpo.CanEdit) { Open-GpoEditor -Gpo $gpo } })
    $newGpoCreateButton.Add_Click({ Submit-NewGpo })
    $newGpoCancelButton.Add_Click({ $newGpoPanel.IsVisible = $false })
    $deleteLinkMenuItem.Add_Click({ Open-DeleteLinkForm })

    # Links, inheritance and status, written to the domain at once, as GPMC does: the tree shows
    # them as the domain has them, and the result says what changed or why not.
    function Invoke-DirectoryChange {
        param([Parameter(Mandatory)] [scriptblock]$Change, [Parameter(Mandatory)] [string]$Done, $Select)
        try {
            & $Change
        } catch {
            Update-DirectoryTree -Select $Select
            Show-DirectoryDetailsTab
            Show-DirectoryResult -Text $_.Exception.GetBaseException().Message -Problem
            return
        }
        Update-DirectoryTree -Select $Select
        # The result in the Details tab, whatever tab the context menu was opened on.
        Show-DirectoryDetailsTab
        Show-DirectoryResult -Text $Done
    }

    function Get-SelectedLink {
        $selected = $domainTreeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsGpoLink] -and $selected.Parent.Tag -is [GPOToolsSom]) { [pscustomobject]@{ Som = $selected.Parent.Tag; Link = $selected.Tag } }
    }
    $enforcedLinkMenuItem.Add_Click({
        $pair = Get-SelectedLink
        if (-not $pair) { return }
        $enforced = -not $pair.Link.Enforced
        Invoke-DirectoryChange -Select $pair.Link -Done (Get-PSGPOText $(if ($enforced) { "The link of '{0}' to {1} is enforced: it applies even where the inheritance is blocked." } else { "The link of '{0}' to {1} is no longer enforced." }) $pair.Link.GetDisplayName() $pair.Som.Name) `
            -Change { $Directory.SetLink($pair.Som, $pair.Link, $pair.Link.Enabled, $enforced) }
    })
    $enabledLinkMenuItem.Add_Click({
        $pair = Get-SelectedLink
        if (-not $pair) { return }
        $enabled = -not $pair.Link.Enabled
        Invoke-DirectoryChange -Select $pair.Link -Done (Get-PSGPOText $(if ($enabled) { "The link of '{0}' to {1} is enabled." } else { "The link of '{0}' to {1} is disabled: the GPO no longer applies there." }) $pair.Link.GetDisplayName() $pair.Som.Name) `
            -Change { $Directory.SetLink($pair.Som, $pair.Link, $enabled, $pair.Link.Enforced) }
    })
    # Not GetNewClosure: the closure would not see the functions of the window.
    function Move-SelectedLink {
        param([int]$Step)
        $pair = Get-SelectedLink
        if (-not $pair) { return }
        $order = $pair.Link.Order + $Step
        Invoke-DirectoryChange -Select $pair.Link -Done (Get-PSGPOText "The link of '{0}' to {1} has the link order {2}." $pair.Link.GetDisplayName() $pair.Som.Name $order) `
            -Change { $Directory.MoveLink($pair.Som, $pair.Link, $order) }
    }
    $moveLinkUpMenuItem.Add_Click({ Move-SelectedLink -Step -1 })
    $moveLinkDownMenuItem.Add_Click({ Move-SelectedLink -Step 1 })
    $blockInheritanceMenuItem.Add_Click({
        $som = $domainTreeView.SelectedItem.Tag
        if ($som -isnot [GPOToolsSom]) { return }
        $blocked = -not $som.BlockInheritance
        Invoke-DirectoryChange -Select $som -Done (Get-PSGPOText $(if ($blocked) { 'The inheritance of {0} is blocked: the GPOs linked above apply there only when their link is enforced.' } else { 'The inheritance of {0} is no longer blocked.' }) $som.Name) `
            -Change { $Directory.SetBlockInheritance($som, $blocked) }
    })
    foreach ($statusItem in $gpoStatusEnabledMenuItem, $gpoStatusUserDisabledMenuItem, $gpoStatusComputerDisabledMenuItem, $gpoStatusAllDisabledMenuItem) {
        $statusItem.Add_Click({
            param($control)
            $gpo = Get-SelectedGpo
            if (-not $gpo) { return }
            $flags = [int]$control.Tag
            $select = $domainTreeView.SelectedItem.Tag
            if (($gpo.Flags -band 3) -eq $flags) { return }
            Invoke-DirectoryChange -Select $select -Done (Get-PSGPOText "The status of '{0}' is: {1}." $gpo.DisplayName (Get-PSGPOText @('Enabled', 'User configuration settings disabled', 'Computer configuration settings disabled', 'All settings disabled')[$flags])) `
                -Change { $Directory.SetGpoStatus($gpo, $flags) }
        })
    }
    $deleteGpoMenuItem.Add_Click({ Open-DeleteGpoForm })
    $importGpoMenuItem.Add_Click({ Open-ImportGpoForm })
    $importGpoReadButton.Add_Click({ Read-ImportSource })
    $importGpoPathTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Read-ImportSource }
    })
    $importGpoConfirmButton.Add_Click({ Submit-ImportGpo })
    $importGpoCancelButton.Add_Click({ $importGpoPanel.IsVisible = $false })
    $approveGpoMenuItem.Add_Click({ Open-ApproveGpoForm })
    $approveGpoConfirmButton.Add_Click({ Submit-ApproveGpo })
    $approveGpoGroupsCheckBox.add_IsCheckedChanged({ Update-ApproveGpoGroupState })
    $approveGpoCancelButton.Add_Click({ $approveGpoPanel.IsVisible = $false })
    $deleteGpoConfirmButton.Add_Click({ Submit-DeleteGpo })
    $deleteGpoCancelButton.Add_Click({ $deleteGpoPanel.IsVisible = $false })
    $restoreDeletedGpoMenuItem.Add_Click({ Open-RestoreGpoForm })
    $restoreDeletedGpoButton.Add_Click({ Open-RestoreGpoForm })
    $restoreGpoConfirmButton.Add_Click({ Submit-RestoreGpo })
    $restoreGpoCancelButton.Add_Click({ $restoreGpoPanel.IsVisible = $false })
    $purgeDeletedGpoMenuItem.Add_Click({ Open-PurgeDeletedGpoForm })
    $purgeDeletedGpoButton.Add_Click({ Open-PurgeDeletedGpoForm })
    $purgeDeletedGpoConfirmButton.Add_Click({ Submit-PurgeDeletedGpo })
    $purgeDeletedGpoCancelButton.Add_Click({ $purgeDeletedGpoPanel.IsVisible = $false })
    $renameMenuItem.Add_Click({ Open-RenameForm })
    $renameConfirmButton.Add_Click({ Submit-Rename })
    $renameCancelButton.Add_Click({ $renamePanel.IsVisible = $false })
    $renameTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-Rename }
        elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $renamePanel.IsVisible = $false }
    })
    # F2 on the tree, as in GPMC and the file managers.
    $domainTreeView.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::F2 -and $renameMenuItem.IsVisible) { Open-RenameForm; $e.Handled = $true }
    })
    $deleteLinkConfirmButton.Add_Click({ Submit-DeleteLink })
    $deleteLinkCancelButton.Add_Click({ $deleteLinkPanel.IsVisible = $false })
    $newGpoGroupsCheckBox.add_IsCheckedChanged({ $newGpoGroupsPanel.IsVisible = [bool]$newGpoGroupsCheckBox.IsChecked })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $newGpoNameTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty) { Update-NewGpoGroupText }
    })
    $newGpoNameTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-NewGpo }
        elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $newGpoPanel.IsVisible = $false }
    })
}
