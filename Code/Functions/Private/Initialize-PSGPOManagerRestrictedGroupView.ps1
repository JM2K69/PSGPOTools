<#
    The Restricted Groups of the GPO edited: the groups of [Group Membership] in its GptTmpl.inf,
    their members and the groups they are a member of.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerRestrictedGroupView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerRestrictedGroupView {
    # Group: the group of the form; Members and MemberOf: its two lists, Items as written in
    # GptTmpl.inf (*S-1-... or DOMAIN\name), Entries as shown; Names: the names of the accounts of
    # the domain by their SID (picked among the suggestions, or read in the domain).
    $restrictedGroups = @{
        Group = $null
        Members = @{ Items = [System.Collections.Generic.List[string]]::new(); Entries = [System.Collections.ObjectModel.ObservableCollection[string]]::new() }
        MemberOf = @{ Items = [System.Collections.Generic.List[string]]::new(); Entries = [System.Collections.ObjectModel.ObservableCollection[string]]::new() }
        Names = @{}
    }
    $restrictedGroupMembersList.ItemsSource = $restrictedGroups.Members.Entries
    $restrictedGroupMemberOfList.ItemsSource = $restrictedGroups.MemberOf.Entries

    # An account as shown: its name and its SID (GPMC shows the name).
    function Format-RestrictedGroupEntry {
        param([string]$Account)
        $sid = $Account.TrimStart('*')
        if ($Account.StartsWith('*') -and $restrictedGroups.Names.ContainsKey($sid)) { return "$($restrictedGroups.Names[$sid]) ($Account)" }
        Format-PSGPORestrictedAccount $Account
    }

    # The names of the accounts of the domain written as their SID, read in the domain once.
    function Resolve-RestrictedGroupName {
        param([string[]]$Account)
        $unknown = @($Account | Where-Object { $_ -match '^\*S-1-5-21-' } | ForEach-Object { $_.Substring(1) } |
                Where-Object { -not $restrictedGroups.Names.ContainsKey($_) -and -not [GPOToolsWellKnownSid]::FindBySid($_) } | Select-Object -Unique)
        if (-not $unknown.Count -or $Directory -isnot [GPOToolsLdapDirectory]) { return }
        $domain = ($Directory.DomainName -split '\.')[0].ToUpperInvariant()
        try {
            $connection = New-PSGPODirectoryConnection -Directory $Directory
            try { $names = Resolve-PSGPODomainSid -Connection $connection -DomainDistinguishedName $Directory.Domain.DistinguishedName -Sid $unknown } finally { $connection.Dispose() }
            foreach ($sid in $unknown) { if ($names[$sid] -and $names[$sid] -ne $sid) { $restrictedGroups.Names[$sid] = "$domain\$($names[$sid])" } }
        } catch {
            Write-PSGPOLogEntry -Level Warning -Source 'Restricted groups' -Message 'The names of the accounts are not read: their SID is shown.' -ErrorRecord $_
        }
    }

    function Set-RestrictedGroupStatus {
        param([string]$Text, [switch]$Problem)
        $restrictedGroupsStatusTextBlock.Text = $Text
        if ($Problem) { $restrictedGroupsStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $restrictedGroupsStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    function Test-RestrictedGroupEditable {
        $editing.Gpo -and $editing.Gpo.CanEdit -and -not $Directory.IsReadOnly -and $editing.Template
    }

    function Update-RestrictedGroupToolbar {
        $editable = Test-RestrictedGroupEditable
        $restrictedGroupsAddButton.IsEnabled = [bool]$editable
        $restrictedGroupsEditButton.IsEnabled = $editable -and $restrictedGroupsList.SelectedItem
        $restrictedGroupsDeleteButton.IsEnabled = $editable -and $restrictedGroupsList.SelectedItem
    }

    # The restricted groups of the edited GPO, the group $Select selected.
    function Show-RestrictedGroupList {
        param([string]$Status, [string]$Select)
        $restrictedGroupsFormBorder.IsVisible = $false
        $restrictedGroupsDeletePanel.IsVisible = $false
        $rows = @()
        if (-not $editing.Gpo) {
            $restrictedGroupsEmptyTextBlock.Text = Get-PSGPOText 'Edit a GPO (Group Policy Management view) to see and configure its restricted groups.'
        } elseif (-not $editing.Template) {
            $restrictedGroupsEmptyTextBlock.Text = ''
            if (-not $Status) { $Status = $editing.PolError }
        } else {
            $groups = @(Get-PSGPORestrictedGroup -Template $editing.Template)
            Resolve-RestrictedGroupName -Account @($groups | ForEach-Object { $_.Group; $_.Members; $_.MemberOf } | Where-Object { $_ })
            $rows = @(foreach ($group in $groups) {
                    $row = [AvaloniaPreferenceRow]::new()
                    $row.Name = Format-RestrictedGroupEntry $group.Group
                    $row.Summary = (@(
                            if ($null -eq $group.Members) { Get-PSGPOText 'Members: not defined' }
                            elseif ($group.Members.Count) { Get-PSGPOText 'Members: {0}' (@($group.Members | ForEach-Object { Format-RestrictedGroupEntry $_ }) -join ', ') }
                            if ($group.MemberOf.Count) { Get-PSGPOText 'Member of: {0}' (@($group.MemberOf | ForEach-Object { Format-RestrictedGroupEntry $_ }) -join ', ') }) -join ' - ')
                    $row.Flags = if ($null -ne $group.Members -and -not $group.Members.Count) { Get-PSGPOText 'No member: the computers remove every member of this group' }
                    $row.Item = $group
                    $row
                })
            $restrictedGroupsEmptyTextBlock.Text = if ($rows.Count) { '' } else { Get-PSGPOText 'This GPO has no restricted group.' }
        }
        $restrictedGroupsEmptyTextBlock.IsVisible = [bool]$restrictedGroupsEmptyTextBlock.Text
        $restrictedGroupsList.ItemsSource = $rows
        if ($Select) { $restrictedGroupsList.SelectedItem = $rows | Where-Object { $_.Item.Group -ieq $Select } | Select-Object -First 1 }
        Set-RestrictedGroupStatus $Status
        Update-RestrictedGroupToolbar
    }

    function Open-RestrictedGroupForm {
        param($Group)
        $restrictedGroups.Group = $Group
        $restrictedGroupsFormTitleTextBlock.Text = if ($Group) { Get-PSGPOText 'Restricted group: {0}' (Format-PSGPORestrictedAccount $Group.Group) } else { Get-PSGPOText 'New restricted group' }
        $restrictedGroupNameTextBox.Text = if ($Group) { $Group.Group } else { '' }
        $restrictedGroupMembersCheckBox.IsChecked = -not $Group -or $null -ne $Group.Members
        foreach ($list in @(@{ State = $restrictedGroups.Members; Accounts = $(if ($Group) { $Group.Members }) }, @{ State = $restrictedGroups.MemberOf; Accounts = $(if ($Group) { $Group.MemberOf }) })) {
            $list.State.Items.Clear()
            $list.State.Entries.Clear()
            foreach ($account in @($list.Accounts | Where-Object { $_ })) {
                $list.State.Items.Add($account)
                $list.State.Entries.Add((Format-RestrictedGroupEntry $account))
            }
        }
        $restrictedGroupMemberBox.Text = ''
        $restrictedGroupMemberOfBox.Text = ''
        $restrictedGroupsFormErrorTextBlock.Text = ''
        $restrictedGroupsDeletePanel.IsVisible = $false
        $restrictedGroupsFormBorder.IsVisible = $true
    }

    # The account of a box (picked among the suggestions: its *S-1-...; or typed) added to its list,
    # once.
    function Add-RestrictedGroupEntry {
        param($Box, [hashtable]$List)
        $account = "$($Box.Text)".Trim()
        if (-not $account) { return }
        $picked = $Box.SelectedItem
        if ($picked -is [AvaloniaSuggestionRow] -and $picked.Value -eq $account -and $picked.Sid) { $restrictedGroups.Names[$picked.Sid] = $picked.Name }
        if (-not @($List.Items | Where-Object { $_ -ieq $account }).Count) {
            $List.Items.Add($account)
            $List.Entries.Add((Format-RestrictedGroupEntry $account))
        }
        Clear-PSGPOSuggestionBox -Box $Box
    }
    function Remove-RestrictedGroupEntry {
        param($ListBox, [hashtable]$List)
        $index = $ListBox.SelectedIndex
        if ($index -lt 0) { return }
        $List.Items.RemoveAt($index)
        $List.Entries.RemoveAt($index)
    }
    $restrictedGroupAddMemberButton.Add_Click({ Add-RestrictedGroupEntry -Box $restrictedGroupMemberBox -List $restrictedGroups.Members })
    $restrictedGroupAddMemberOfButton.Add_Click({ Add-RestrictedGroupEntry -Box $restrictedGroupMemberOfBox -List $restrictedGroups.MemberOf })
    $restrictedGroupRemoveMemberButton.Add_Click({ Remove-RestrictedGroupEntry -ListBox $restrictedGroupMembersList -List $restrictedGroups.Members })
    $restrictedGroupRemoveMemberOfButton.Add_Click({ Remove-RestrictedGroupEntry -ListBox $restrictedGroupMemberOfList -List $restrictedGroups.MemberOf })
    # Enter adds the account, once the suggestions are closed (Enter picks one first).
    $restrictedGroupMemberBox.add_KeyDown({
            param($control, $e)
            if ($e.Key -eq [Avalonia.Input.Key]::Enter -and -not $control.IsDropDownOpen) { Add-RestrictedGroupEntry -Box $control -List $restrictedGroups.Members; $e.Handled = $true }
        })
    $restrictedGroupMemberOfBox.add_KeyDown({
            param($control, $e)
            if ($e.Key -eq [Avalonia.Input.Key]::Enter -and -not $control.IsDropDownOpen) { Add-RestrictedGroupEntry -Box $control -List $restrictedGroups.MemberOf; $e.Handled = $true }
        })
    # The accounts suggested while typing (Register-PSGPOAccountSuggestion): as *S-1-... in
    # GptTmpl.inf, by their name for a permission, the security filtering and an approval.
    foreach ($box in $restrictedGroupNameTextBox, $restrictedGroupMemberBox, $restrictedGroupMemberOfBox) { Register-PSGPOAccountSuggestion -Box $box -Directory $Directory -Insert Sid }
    foreach ($box in $filteringNameTextBox, $delegationNameTextBox, $wmiDelegationNameTextBox, $approveGpoApplyToTextBox, $approveGpoDenyToTextBox) {
        Register-PSGPOAccountSuggestion -Box $box -Directory $Directory -Insert Name
    }

    # A change of the restricted groups: on a copy of GptTmpl.inf, written, then kept.
    function Save-RestrictedGroupChange {
        param([scriptblock]$Change, [string]$Done, [string]$Select)
        $copy = [GPOToolsSecurityTemplate]::Parse($editing.Template.ToBytes())
        try {
            & $Change $copy
            $Directory.WriteSecurityTemplate($editing.Gpo, $copy.ToBytes())
        } catch {
            return $_.Exception.GetBaseException().Message
        }
        $editing.Template = $copy
        $settingsCache.Remove("$($editing.Gpo.Id)")
        Show-RestrictedGroupList -Status (Get-PSGPOText '{0} in GptTmpl.inf (version {1}).' $Done $editing.Gpo.GetComputerVersion()) -Select $Select
        $null
    }

    $restrictedGroupsList.add_SelectionChanged({ Update-RestrictedGroupToolbar })
    $restrictedGroupsAddButton.Add_Click({ Open-RestrictedGroupForm $null })
    $restrictedGroupsEditButton.Add_Click({ if ($restrictedGroupsList.SelectedItem) { Open-RestrictedGroupForm $restrictedGroupsList.SelectedItem.Item } })
    $restrictedGroupsList.add_DoubleTapped({ if ($restrictedGroupsList.SelectedItem -and (Test-RestrictedGroupEditable)) { Open-RestrictedGroupForm $restrictedGroupsList.SelectedItem.Item } })
    $restrictedGroupsCancelButton.Add_Click({ $restrictedGroupsFormBorder.IsVisible = $false })
    $restrictedGroupMembersCheckBox.add_IsCheckedChanged({ $restrictedGroupMembersPanel.IsEnabled = [bool]$restrictedGroupMembersCheckBox.IsChecked })
    $restrictedGroupsSaveButton.Add_Click({
        $name = "$($restrictedGroupNameTextBox.Text)".Trim()
        $restrictedGroupsFormErrorTextBlock.Text = ''
        # An account typed and not added: said, not lost.
        foreach ($box in @($(if ($restrictedGroupMembersCheckBox.IsChecked) { $restrictedGroupMemberBox }), $restrictedGroupMemberOfBox) | Where-Object { $_ }) {
            if ("$($box.Text)".Trim()) {
                $restrictedGroupsFormErrorTextBlock.Text = Get-PSGPOText "'{0}' is typed but not added: click Add (or press Enter), or clear it." "$($box.Text)".Trim()
                return
            }
        }
        $members = if ($restrictedGroupMembersCheckBox.IsChecked) { [string[]]@($restrictedGroups.Members.Items) } else { $null }
        $memberOf = [string[]]@($restrictedGroups.MemberOf.Items)
        $old = $restrictedGroups.Group
        $problem = Save-RestrictedGroupChange -Select $name -Done (Get-PSGPOText $(if ($old) { "Restricted group '{0}' saved" } else { "Restricted group '{0}' added" }) $name) -Change {
            param($Copy)
            if ($old -and $old.Group -ine $name) { Remove-PSGPORestrictedGroup -Template $Copy -Group $old.Group }
            if (-not $old -and @(Get-PSGPORestrictedGroup -Template $Copy | Where-Object { $_.Group -ieq $name }).Count) { throw (Get-PSGPOText "'{0}' is already a restricted group of this GPO: edit it." $name) }
            Set-PSGPORestrictedGroup -Template $Copy -Group $name -Members $members -MemberOf $memberOf
        }
        if ($problem) { $restrictedGroupsFormErrorTextBlock.Text = $problem }
    })
    $restrictedGroupsDeleteButton.Add_Click({
        $row = $restrictedGroupsList.SelectedItem
        if (-not $row) { return }
        $restrictedGroupsDeleteTextBlock.Text = Get-PSGPOText "Delete the restricted group '{0}' from the GPO? The computers stop changing its members; the members it already has stay." $row.Name
        $restrictedGroupsFormBorder.IsVisible = $false
        $restrictedGroupsDeletePanel.IsVisible = $true
    })
    $restrictedGroupsDeleteCancelButton.Add_Click({ $restrictedGroupsDeletePanel.IsVisible = $false })
    $restrictedGroupsDeleteConfirmButton.Add_Click({
        $row = $restrictedGroupsList.SelectedItem
        if (-not $row) { return }
        $group = $row.Item.Group
        $problem = Save-RestrictedGroupChange -Done (Get-PSGPOText "Restricted group '{0}' deleted" $row.Name) -Change { param($Copy) Remove-PSGPORestrictedGroup -Template $Copy -Group $group }
        if ($problem) { Set-RestrictedGroupStatus (Get-PSGPOText 'Not deleted: {0}' $problem) -Problem }
    })
}
