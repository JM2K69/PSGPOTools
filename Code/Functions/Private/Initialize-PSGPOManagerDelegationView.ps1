<#
    The Delegation tabs: the permissions of the GPO selected and its security filtering, as the
    Scope and Delegation tabs of GPMC, and those of the WMI filters.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerDelegationView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerDelegationView {
    $delegation = @{ Gpo = $null; Editable = $false }
    function Update-DelegationTab {
        param([string]$Status, [switch]$Problem)
        $gpo = Get-SelectedGpo
        $delegationTab.IsVisible = [bool]$gpo
        if (-not $gpo) {
            if ($directoryTabs.SelectedItem -eq $delegationTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $delegationTab) { return }
        $delegation.Gpo = $gpo
        $delegation.Editable = $gpo.CanEdit -and -not $Directory.IsReadOnly -and $gpo.ApprovalState -ne 'Pending'
        $rows = @()
        $lines = [System.Collections.Generic.List[string]]::new()
        try {
            $rows = @($Directory.GetGpoPermissions($gpo))
        } catch {
            $lines.Add((Get-PSGPOText 'The permissions of the GPO cannot be read: {0}' $_.Exception.GetBaseException().Message))
            $Problem = $true
        }
        $permissionRows = @(foreach ($row in $rows) {
                $item = [AvaloniaPermissionRow]::new()
                $item.Name = $row.Name
                $item.Sid = $row.Sid
                $item.Permission = $row.Permission
                $item.PermissionText = Get-PSGPOText (Get-PSGPOPermissionText -Permission $row.Permission)
                $item.Applies = $row.Applies -and -not $row.Denied
                $item.Inherited = $row.Inherited
                $item.InheritedText = Get-PSGPOText $(if ($row.Inherited) { 'Yes' } else { 'No' })
                $item
            })
        $delegationList.ItemsSource = $permissionRows
        # The security filtering: who applies the GPO (an inherited right counts too). Not through
        # the pipeline: it wraps the rows in PSObjects, which Avalonia cannot show.
        $filtering = [System.Collections.Generic.List[AvaloniaPermissionRow]]::new()
        foreach ($item in $permissionRows) {
            $applies = @($rows | Where-Object { $_.Sid -eq $item.Sid -and $_.Applies -and -not $_.Denied }).Count
            if ($applies -and -not @($filtering | Where-Object Sid -EQ $item.Sid).Count) { $filtering.Add($item) }
        }
        $filteringList.ItemsSource = $filtering
        foreach ($control in $filteringNameTextBox, $filteringAddButton, $delegationNameTextBox, $delegationPermissionComboBox, $delegationSetButton) { $control.IsEnabled = $delegation.Editable }
        Update-DelegationButton
        if ($gpo.ApprovalState -eq 'Pending') { $lines.Add((Get-PSGPOText 'The GPO waits for its approval: its permissions are set when it is approved.')) }
        elseif (-not $delegation.Editable) { $lines.Add((Get-PSGPOText 'Read only: the account cannot change the permissions of this GPO.')) }
        if ($rows.Count -and -not (Test-PSGPOComputerReadable -Permission $rows)) {
            $lines.Add((Get-PSGPOText 'Warning: neither Authenticated Users nor Domain Computers read this GPO, so no computer applies it (MS16-072). Give one of them Read in the delegation.'))
            $Problem = $true
        }
        if ($Status) { $lines.Insert(0, $Status) }
        $delegationStatusTextBlock.Text = $lines -join [Environment]::NewLine
        if ($Problem) { $delegationStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $delegationStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # Remove is for an account of the GPO itself: the inherited permissions come from CN=Policies.
    function Update-DelegationButton {
        $filteringRemoveButton.IsEnabled = $delegation.Editable -and $null -ne $filteringList.SelectedItem
        $delegationRemoveButton.IsEnabled = $delegation.Editable -and $delegationList.SelectedItem -and -not $delegationList.SelectedItem.Inherited
    }

    # One change of the permissions of the GPO: an account by its name (or its row), then the tab and
    # the details shown again, with what was done or why not.
    function Invoke-PermissionChange {
        param([string]$Account, [AvaloniaPermissionRow]$Row, [ValidateSet('Permission', 'Filtering')] [string]$Operation, [string]$Value)
        $gpo = $delegation.Gpo
        if (-not $gpo) { return }
        try {
            $principal = if ($Row) { [pscustomobject]@{ Name = $Row.Name; Sid = $Row.Sid } }
                elseif ("$Account".Trim()) { Resolve-PSGPOApplyTo -Directory $Directory -Name $Account }
                else { throw (Get-PSGPOText 'Give a group, a user or a computer.') }
            if ($Operation -eq 'Filtering') { $Directory.SetGpoSecurityFiltering($gpo, $principal.Sid, $Value -eq 'True') }
            else { $Directory.SetGpoPermission($gpo, $principal.Sid, $Value) }
        } catch {
            Update-DelegationTab -Status (Get-PSGPOText 'Not changed: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $done = if ($Operation -eq 'Filtering') { Get-PSGPOText $(if ($Value -eq 'True') { "'{0}' applies the GPO now." } else { "'{0}' no longer applies the GPO." }) $principal.Name }
            elseif ($Value -eq 'None') { Get-PSGPOText "The permissions of '{0}' are removed." $principal.Name }
            else { Get-PSGPOText "'{0}' has the permission {1} now." $principal.Name (Get-PSGPOText (Get-PSGPOPermissionText -Permission $Value)) }
        # The details (security filtering) and the history (the GPO now) show the change.
        $history.Current = @{}
        $filteringNameTextBox.Text = ''
        $delegationNameTextBox.Text = ''
        Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag
        $directoryTabs.SelectedItem = $delegationTab
        Update-DelegationTab -Status $done
    }

    $filteringList.add_SelectionChanged({ Update-DelegationButton })
    $delegationList.add_SelectionChanged({
        $row = $delegationList.SelectedItem
        if ($row) {
            # The account and its level, to change them.
            $delegationNameTextBox.Text = $row.Name
            $index = @('GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity').IndexOf($row.Permission)
            if ($index -ge 0) { $delegationPermissionComboBox.SelectedIndex = $index }
        }
        Update-DelegationButton
    })
    $filteringAddButton.Add_Click({ Invoke-PermissionChange -Account $filteringNameTextBox.Text -Operation Filtering -Value 'True' })
    $filteringRemoveButton.Add_Click({ if ($filteringList.SelectedItem) { Invoke-PermissionChange -Row $filteringList.SelectedItem -Operation Filtering -Value 'False' } })
    $delegationSetButton.Add_Click({
        $level = "$($delegationPermissionComboBox.SelectedItem.Tag)"
        $row = $delegationList.SelectedItem
        # The selected account when its name is the one typed (its SID, a name may not resolve).
        if ($row -and $row.Name -eq "$($delegationNameTextBox.Text)".Trim() -and -not $row.Inherited) { Invoke-PermissionChange -Row $row -Operation Permission -Value $level }
        else { Invoke-PermissionChange -Account $delegationNameTextBox.Text -Operation Permission -Value $level }
    })
    $delegationRemoveButton.Add_Click({ if ($delegationList.SelectedItem) { Invoke-PermissionChange -Row $delegationList.SelectedItem -Operation Permission -Value 'None' } })

    # --- Delegation of the WMI filters, as GPMC: on WMI Filters who creates filters, on a filter
    # who changes it ----------------------------------------------------------------------------

    $wmiDelegation = @{ Target = $null; Filter = $null; Editable = $false }
    function Update-WmiDelegationTab {
        param([string]$Status, [switch]$Problem)
        $item = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        $onContainer = $item -is [string] -and $item -eq 'WmiFilters'
        $wmiDelegationTab.IsVisible = $onContainer -or $item -is [GPOToolsWmiFilter]
        if (-not $wmiDelegationTab.IsVisible) {
            if ($directoryTabs.SelectedItem -eq $wmiDelegationTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $wmiDelegationTab) { return }
        $filter = if ($onContainer) { $null } else { $item }
        $wmiDelegation.Filter = $filter
        $wmiDelegation.Editable = -not $Directory.IsReadOnly -and $(if ($filter) { $filter.CanEdit } else { $Directory.IsDomainAdministrator })
        $wmiDelegationTitleTextBlock.Text = if ($filter) { Get-PSGPOText "Delegation of the WMI filter '{0}'" $filter.Name } else { Get-PSGPOText 'Delegation of the WMI filters of {0}' $Directory.DomainName }
        $wmiDelegationInfoTextBlock.Text = if ($filter) { Get-PSGPOText 'These groups and users have the specified permission for this WMI filter: Edit changes its name, description and queries; Full control also deletes it and changes its permissions.' }
            else { Get-PSGPOText 'These groups and users create WMI filters: Creator owner creates filters and changes those it created; Full control creates filters and changes all of them.' }
        # The levels of the target, the one chosen kept when it is one of them.
        $levels = if ($filter) { 'WmiEdit', 'WmiFullControl' } else { 'WmiCreate', 'WmiFullControl' }
        $chosen = if ($wmiDelegationPermissionComboBox.SelectedItem) { "$($wmiDelegationPermissionComboBox.SelectedItem.Tag)" }
        $choices = foreach ($level in $levels) {
            $choice = [Avalonia.Controls.ComboBoxItem]::new()
            $choice.Content = Get-PSGPOText (Get-PSGPOWmiFilterPermissionText -Permission $level)
            $choice.Tag = $level
            $choice
        }
        $wmiDelegationPermissionComboBox.ItemsSource = @($choices)
        $wmiDelegationPermissionComboBox.SelectedIndex = [Math]::Max(0, [array]::IndexOf($levels, $chosen))
        $rows = @()
        $lines = [System.Collections.Generic.List[string]]::new()
        try {
            $rows = @($Directory.GetWmiFilterPermissions($filter))
        } catch {
            $lines.Add((Get-PSGPOText 'The permissions cannot be read: {0}' $_.Exception.GetBaseException().Message))
            $Problem = $true
        }
        $wmiDelegationList.ItemsSource = @(foreach ($row in $rows) {
                $entry = [AvaloniaPermissionRow]::new()
                $entry.Name = $row.Name
                $entry.Sid = $row.Sid
                $entry.Permission = $row.Permission
                $entry.PermissionText = Get-PSGPOText (Get-PSGPOWmiFilterPermissionText -Permission $row.Permission)
                $entry.Inherited = $row.Inherited
                $entry.InheritedText = Get-PSGPOText $(if ($row.Inherited) { 'Yes' } else { 'No' })
                $entry
            })
        foreach ($control in $wmiDelegationNameTextBox, $wmiDelegationPermissionComboBox, $wmiDelegationSetButton) { $control.IsEnabled = $wmiDelegation.Editable }
        Update-WmiDelegationButton
        if (-not $wmiDelegation.Editable) { $lines.Add((Get-PSGPOText $(if ($filter) { 'Read only: the account cannot change the permissions of this WMI filter.' } else { 'Read only: only the administrators of the domain change who creates WMI filters.' }))) }
        if ($Status) { $lines.Insert(0, $Status) }
        $wmiDelegationStatusTextBlock.Text = $lines -join [Environment]::NewLine
        if ($Problem) { $wmiDelegationStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $wmiDelegationStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # Remove is for an account of the filter or the container itself, not an inherited one.
    function Update-WmiDelegationButton {
        $wmiDelegationRemoveButton.IsEnabled = $wmiDelegation.Editable -and $wmiDelegationList.SelectedItem -and -not $wmiDelegationList.SelectedItem.Inherited
    }

    function Invoke-WmiPermissionChange {
        param([string]$Account, [AvaloniaPermissionRow]$Row, [string]$Value)
        $filter = $wmiDelegation.Filter
        try {
            $principal = if ($Row) { [pscustomobject]@{ Name = $Row.Name; Sid = $Row.Sid } }
                elseif ("$Account".Trim()) { Resolve-PSGPOApplyTo -Directory $Directory -Name $Account }
                else { throw (Get-PSGPOText 'Give a group or a user.') }
            $Directory.SetWmiFilterPermission($filter, $principal.Sid, $Value)
        } catch {
            Update-WmiDelegationTab -Status (Get-PSGPOText 'Not changed: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $done = if ($Value -eq 'None') { Get-PSGPOText "The permissions of '{0}' are removed." $principal.Name }
            else { Get-PSGPOText "'{0}' has the permission {1} now." $principal.Name (Get-PSGPOText (Get-PSGPOWmiFilterPermissionText -Permission $Value)) }
        $wmiDelegationNameTextBox.Text = ''
        Update-WmiDelegationTab -Status $done
    }

    $wmiDelegationList.add_SelectionChanged({
        $row = $wmiDelegationList.SelectedItem
        if ($row) {
            $wmiDelegationNameTextBox.Text = $row.Name
            $index = [array]::IndexOf(@($wmiDelegationPermissionComboBox.ItemsSource | ForEach-Object { "$($_.Tag)" }), $row.Permission)
            if ($index -ge 0) { $wmiDelegationPermissionComboBox.SelectedIndex = $index }
        }
        Update-WmiDelegationButton
    })
    $wmiDelegationSetButton.Add_Click({
        $level = "$($wmiDelegationPermissionComboBox.SelectedItem.Tag)"
        $row = $wmiDelegationList.SelectedItem
        # The selected account when its name is the one typed (its SID, a name may not resolve).
        if ($row -and $row.Name -eq "$($wmiDelegationNameTextBox.Text)".Trim() -and -not $row.Inherited) { Invoke-WmiPermissionChange -Row $row -Value $level }
        else { Invoke-WmiPermissionChange -Account $wmiDelegationNameTextBox.Text -Value $level }
    })
    $wmiDelegationRemoveButton.Add_Click({ if ($wmiDelegationList.SelectedItem) { Invoke-WmiPermissionChange -Row $wmiDelegationList.SelectedItem -Value 'None' } })

    $directoryTabs.add_SelectionChanged({
        param($control, $e)
        # Only the selection of a tab, not of a control inside one.
        if ([object]::ReferenceEquals($e.Source, $directoryTabs)) { Update-SomTab; Update-SettingsTab; Update-DelegationTab; Update-WmiDelegationTab; Update-HistoryTab; Update-StatusTab }
    })
}
