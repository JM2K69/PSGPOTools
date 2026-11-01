<#
    The Linked Group Policy Objects and Group Policy Inheritance tabs of the domain or an OU, as
    GPMC: its links by link order, moved with the arrows, and the GPOs that apply there by
    precedence.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerSomView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerSomView {
    # The WMI filter of a GPO: its name, or None.
    function Get-GpoWmiFilterName {
        param([GPOToolsGpo]$Gpo)
        if (-not $Gpo -or -not $Gpo.WmiFilterId) { return (Get-PSGPOText 'None') }
        $filter = @($Directory.WmiFilters | Where-Object { $_.Id -eq $Gpo.WmiFilterId })[0]
        if ($filter) { $filter.Name } else { "{$($Gpo.WmiFilterId)}" }
    }

    # Both tabs of the domain or OU selected: its links by link order, the GPOs that apply there by
    # precedence. -Select: the link to select (the distinguished name of its GPO).
    function Update-SomTab {
        param([string]$Status, [switch]$Problem, [string]$Select)
        $item = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        $som = if ($item -is [GPOToolsSom]) { $item }
        # A site: its links, read only; its inheritance depends on the OU of each computer.
        $site = $som -and $som.Kind -eq [GPOToolsSomKind]::Site
        $linkedGposTab.IsVisible = $null -ne $som
        $inheritanceTab.IsVisible = $null -ne $som -and -not $site
        if ($site -and $directoryTabs.SelectedItem -eq $inheritanceTab) { $directoryTabs.SelectedIndex = 0 }
        if (-not $som) {
            if ($directoryTabs.SelectedItem -eq $linkedGposTab -or $directoryTabs.SelectedItem -eq $inheritanceTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        $yesNo = { param($Value) if ($Value) { Get-PSGPOText 'Yes' } else { Get-PSGPOText 'No' } }
        # What the account does not manage: greyed, or not shown (View.ShowUnmanaged).
        $shown = $som.CanLink -or $site -or (Test-PSGPOUnmanagedShown)
        $notShown = Get-PSGPOText 'Not shown: this account has no delegation here.'

        $rows = @(if ($shown) {
                foreach ($link in @($som.Links | Sort-Object Order)) {
                    $row = [AvaloniaLinkedGpoRow]::new()
                    $row.Order = $link.Order
                    $row.Name = $link.GetDisplayName()
                    $row.Enforced = & $yesNo $link.Enforced
                    $row.LinkEnabled = & $yesNo $link.Enabled
                    $row.Status = Get-PSGPOText $link.GetStatus()
                    $row.WmiFilter = Get-GpoWmiFilterName -Gpo $link.Gpo
                    $row.Link = $link
                    $row
                }
            })
        $linkedGposList.ItemsSource = $rows
        $linkedGposEmptyTextBlock.Text = if (-not $shown) { $notShown } elseif (-not $rows.Count) { Get-PSGPOText 'No GPO is linked here.' } else { '' }
        $linkedGposEmptyTextBlock.IsVisible = [bool]$linkedGposEmptyTextBlock.Text
        $linkedGposInfoTextBlock.Text = Get-PSGPOText $(if ($site) { 'Link order 1 is applied last: it wins over the others. The links of a site are read here: change them with GPMC.' } elseif ($Directory.IsReadOnly -or -not $som.CanLink) { 'Link order 1 is applied last: it wins over the others. This account cannot change the links here.' } else { 'Link order 1 is applied last: it wins over the others. Select a link, then move it.' })
        if ($Select) { $linkedGposList.SelectedItem = $rows | Where-Object { $_.Link.GpoDistinguishedName -eq $Select } | Select-Object -First 1 }
        $linkedGposStatusTextBlock.Text = $Status
        if ($Problem) { $linkedGposStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $linkedGposStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
        Update-LinkedGpoButton

        $inheritanceBlockedBorder.IsVisible = $som.BlockInheritance
        $inheritanceBlockedTextBlock.Text = if ($som.BlockInheritance) { Get-PSGPOText '{0} blocks the inheritance: the GPOs linked above it apply here only when their link is enforced.' $som.Name } else { '' }
        $inherited = @(if ($shown) {
                foreach ($entry in @(Get-PSGPOSomPrecedence -Som $som -IncludeDisabledGpo)) {
                    $row = [AvaloniaInheritanceRow]::new()
                    $row.Precedence = $entry.Precedence
                    $row.Name = $entry.Gpo.DisplayName
                    $row.Location = $entry.Som.Name
                    $row.Enforced = & $yesNo $entry.Enforced
                    $row.Status = Get-PSGPOText $entry.Gpo.GetStatus()
                    $row.WmiFilter = Get-GpoWmiFilterName -Gpo $entry.Gpo
                    $row
                }
            })
        $inheritanceList.ItemsSource = $inherited
        $inheritanceEmptyTextBlock.Text = if (-not $shown) { $notShown } elseif (-not $inherited.Count) { Get-PSGPOText 'No GPO applies here.' } else { '' }
        $inheritanceEmptyTextBlock.IsVisible = [bool]$inheritanceEmptyTextBlock.Text
    }

    # The arrows: a link selected that can move that way, where the account links GPOs.
    function Update-LinkedGpoButton {
        $row = $linkedGposList.SelectedItem
        $som = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        $can = $null -ne $row -and $som -is [GPOToolsSom] -and $som.CanLink -and -not $Directory.IsReadOnly
        $count = if ($som -is [GPOToolsSom]) { $som.Links.Count } else { 0 }
        $linkedGposTopButton.IsEnabled = $can -and $row.Order -gt 1
        $linkedGposUpButton.IsEnabled = $can -and $row.Order -gt 1
        $linkedGposDownButton.IsEnabled = $can -and $row.Order -lt $count
        $linkedGposBottomButton.IsEnabled = $can -and $row.Order -lt $count
    }

    # The selected link moved to another link order, as the arrows of GPMC: written to the gPLink of
    # the domain or OU (a change another console made meanwhile kept), audited, the tree read again.
    function Move-LinkedGpo {
        param([ValidateSet('Top', 'Up', 'Down', 'Bottom')] [string]$To)
        $row = $linkedGposList.SelectedItem
        $som = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if (-not $row -or $som -isnot [GPOToolsSom]) { return }
        $link = $row.Link
        $order = switch ($To) { 'Top' { 1 } 'Up' { $link.Order - 1 } 'Down' { $link.Order + 1 } default { $som.Links.Count } }
        $select = $link.GpoDistinguishedName
        try {
            $Directory.MoveLink($som, $link, $order)
        } catch {
            Update-SomTab -Status (Get-PSGPOText 'Not moved: {0}' $_.Exception.GetBaseException().Message) -Problem -Select $select
            return
        }
        Update-DirectoryTree -Select $som
        Update-SomTab -Status (Get-PSGPOText "The link of '{0}' to {1} has the link order {2}." $link.GetDisplayName() $som.Name $link.Order) -Select $select
    }
    $linkedGposList.add_SelectionChanged({ Update-LinkedGpoButton })
    $linkedGposTopButton.Add_Click({ Move-LinkedGpo -To Top })
    $linkedGposUpButton.Add_Click({ Move-LinkedGpo -To Up })
    $linkedGposDownButton.Add_Click({ Move-LinkedGpo -To Down })
    $linkedGposBottomButton.Add_Click({ Move-LinkedGpo -To Bottom })
}
