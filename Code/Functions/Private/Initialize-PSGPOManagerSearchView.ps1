<#
    Search... (the context menu of the domain and of Group Policy Objects, Ctrl+F), as the Search of
    GPMC: the GPOs of the domain that match every criterion given (Find-PSGPOMatch, as Find-PSGPO),
    found in the background (the permissions, the settings and the comments are read for each
    GPO). The results stay while one of them is selected in the tree (double-click or Enter), until
    the search is closed.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerSearchView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerSearchView {
    # Filters: the WMI filters of the WMI filter list (after Any), by index.
    $gpoSearch = @{ Filters = @() }

    function Open-GpoSearchForm {
        if (-not $Directory) { return }
        Hide-DirectoryForm
        $gpoSearchTitleTextBlock.Text = Get-PSGPOText 'Search the GPOs of {0}: every criterion given must match' $Directory.DomainName
        $gpoSearch.Filters = @($Directory.WmiFilters | Sort-Object Name)
        $gpoSearchWmiFilterComboBox.ItemsSource = @(Get-PSGPOText 'Any') + @($gpoSearch.Filters | ForEach-Object Name)
        $gpoSearchWmiFilterComboBox.SelectedIndex = 0
        $gpoSearchErrorTextBlock.Text = ''
        Show-DirectoryForm -Panel $gpoSearchPanel
        $null = $gpoSearchNameTextBox.Focus()
    }

    # The criteria of the form, as Find-PSGPOMatch takes them; $null when none is given.
    function Read-GpoSearchForm {
        $criteria = @{
            Name = "$($gpoSearchNameTextBox.Text)".Trim()
            Linked = $gpoSearchLinksComboBox.SelectedIndex -eq 1
            NotLinked = $gpoSearchLinksComboBox.SelectedIndex -eq 2
            WmiFilter = if ($gpoSearchWmiFilterComboBox.SelectedIndex -gt 0) { $gpoSearch.Filters[$gpoSearchWmiFilterComboBox.SelectedIndex - 1] }
            Account = "$($gpoSearchAccountTextBox.Text)".Trim()
            Permission = @($null, 'GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity', 'GpoCustom')[[Math]::Max(0, $gpoSearchPermissionComboBox.SelectedIndex)]
            Extension = "$($gpoSearchExtensionTextBox.Text)".Trim()
            Setting = "$($gpoSearchSettingTextBox.Text)".Trim()
            Status = @($null, 'Enabled', 'ComputerOnly', 'UserOnly', 'Disabled')[[Math]::Max(0, $gpoSearchStatusComboBox.SelectedIndex)]
            ApprovalState = @($null, 'Pending', 'Approved')[[Math]::Max(0, $gpoSearchApprovalComboBox.SelectedIndex)]
            Comment = "$($gpoSearchCommentTextBox.Text)".Trim()
        }
        # A permission says whose: without an account, any account that has it is no criterion.
        if (-not $criteria.Account) { $criteria.Permission = $null }
        $given = @($criteria.Values | Where-Object { $_ }).Count
        if ($given) { $criteria }
    }

    function Submit-GpoSearch {
        $criteria = Read-GpoSearchForm
        if (-not $criteria) { $gpoSearchErrorTextBlock.Text = Get-PSGPOText 'Give at least one criterion.'; return }
        $gpoSearchErrorTextBlock.Text = ''
        $gpoSearchResultTextBlock.Text = ''
        $gpoSearchList.ItemsSource = @()
        $null = Start-ConsoleOperation -Text (Get-PSGPOText 'Searching the GPOs of {0}...' $Directory.DomainName) -ScriptBlock {
            param($Directory, $Criteria)
            Find-PSGPOMatch -Directory $Directory -Criteria $Criteria
        } -ArgumentList $Directory, $criteria -Done {
            param($Result)
            $found = [System.Collections.Generic.List[GPOToolsGpo]]::new()
            foreach ($item in $Result) { if ($item) { $found.Add($item.PSObject.BaseObject) } }
            $gpoSearchList.ItemsSource = $found
            $gpoSearchResultTextBlock.Text = if ($found.Count) { Get-PSGPOText '{0} GPO(s) found: double-click one to see it in the tree.' $found.Count } else { Get-PSGPOText 'No GPO matches.' }
        } -Failed {
            param($ErrorRecord)
            $gpoSearchErrorTextBlock.Text = Get-PSGPOText 'The search failed: {0}' $ErrorRecord.Exception.GetBaseException().Message
        } -Cancelled {
            $gpoSearchErrorTextBlock.Text = Get-PSGPOText 'The search was cancelled.'
        }
    }

    # The GPO chosen in the results, in the tree: its details below the search, which stays.
    function Show-GpoSearchResult {
        $gpo = $gpoSearchList.SelectedItem
        if ($gpo) { Update-DirectoryTree -Select $gpo }
    }

    $gpoSearchMenuItem.Add_Click({ Open-GpoSearchForm })
    $gpoSearchConfirmButton.Add_Click({ Submit-GpoSearch })
    $gpoSearchCancelButton.Add_Click({ $gpoSearchPanel.IsVisible = $false })
    $gpoSearchList.add_DoubleTapped({ Show-GpoSearchResult })
    $gpoSearchList.Add_KeyDown({
            param($control, $e)
            if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Show-GpoSearchResult; $e.Handled = $true }
        })
    # Enter in a box of text searches; Escape closes.
    foreach ($box in $gpoSearchNameTextBox, $gpoSearchAccountTextBox, $gpoSearchExtensionTextBox, $gpoSearchSettingTextBox, $gpoSearchCommentTextBox) {
        $box.Add_KeyDown({
                param($control, $e)
                if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-GpoSearch; $e.Handled = $true }
                elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $gpoSearchPanel.IsVisible = $false; $e.Handled = $true }
            })
    }
    # Ctrl+F in the Group Policy Management view.
    $window.add_KeyDown({
            param($control, $e)
            if ($e.Key -eq [Avalonia.Input.Key]::F -and $e.KeyModifiers -eq [Avalonia.Input.KeyModifiers]::Control -and $managementView.IsVisible -and $Directory) {
                Open-GpoSearchForm
                $e.Handled = $true
            }
        })
}
