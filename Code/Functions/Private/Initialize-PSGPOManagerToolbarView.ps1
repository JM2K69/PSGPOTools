<#
    The toolbar of the console: its views, the configuration of HGPM for the domain, Refresh (F5)
    and Change Domain Controller... (the domain read again).

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerToolbarView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerToolbarView {
    $managementButton.Add_Click({ Show-View 'Management' })
    # The configuration window (New-PSGPOConfigurationWindow), one at a time, owned by the console;
    # for the administrators of the domain only, who change the configuration every console reads.
    $configurationWindow = @{ Ui = $null }
    $configurationButton.IsEnabled = $Directory -and -not $Directory.IsReadOnly -and $Directory.IsDomainAdministrator
    if (-not $configurationButton.IsEnabled) {
        [Avalonia.Controls.ToolTip]::SetTip($configurationButton, (Get-PSGPOText $(if ($Directory) { 'Only the administrators of the domain change the configuration of HGPM' } else { 'No domain: the defaults of the module apply.' })))
        [Avalonia.Controls.ToolTip]::SetShowOnDisabled($configurationButton, $true)
    }
    $configurationButton.Add_Click({
        if ($configurationWindow.Ui -and $configurationWindow.Ui.Window.IsVisible) { $configurationWindow.Ui.Window.Activate(); return }
        $configurationWindow.Ui = New-PSGPOConfigurationWindow -Directory $Directory
        # A configuration saved may change the view (View.ShowUnmanaged): the tree built again.
        $configurationWindow.Ui.Window.add_Closed({ if ($configurationWindow.Ui.State.Saved) { Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag } })
        $configurationWindow.Ui.Window.Show($window)
    })
    $browseAdmxButton.Add_Click({ Open-GpoEditor -Gpo $null })

    # Refresh (F5): the domain read again, as GPMC does; the tree keeps what is expanded and
    # selected. The changes of the other consoles and of GPMC show, and a GPO read again can be
    # saved again (its version is the one of the domain).
    # What was selected: the operation ends once this function returned.
    $refresh = @{ Item = $null; LinkSom = $null; Server = $null }
    # -Server: from another domain controller (Change Domain Controller...).
    function Invoke-DirectoryRefresh {
        param([string]$Server)
        if ($Directory -isnot [GPOToolsLdapDirectory] -or -not $refreshButton.IsEnabled) { return }
        $selected = $domainTreeView.SelectedItem
        $refresh.Item = if ($selected) { $selected.Tag }
        $refresh.LinkSom = if ($refresh.Item -is [GPOToolsGpoLink] -and $selected.Parent.Tag -is [GPOToolsSom]) { $selected.Parent.Tag.DistinguishedName }
        $refresh.Server = $Server
        $text = if ($Server) { Get-PSGPOText 'Reading the domain from {0}...' $Server } else { Get-PSGPOText 'Reading the domain again from {0}...' $Directory.Server }
        Show-DirectoryResult -Text $text
        # Read in the background, put in place on the thread of the window: what holds the
        # directory keeps it.
        $null = Start-ConsoleOperation -Text $text -ScriptBlock { param($Directory, $Server) Read-PSGPODirectoryFromDomain -Directory $Directory -Server $Server } -ArgumentList $Directory, $Server -Done {
            param($Result)
            try {
                Update-PSGPODirectoryFromDomain -Directory $Directory -Server $refresh.Server -Read $Result[0]
            } catch {
                Show-DirectoryResult -Text (Get-PSGPOText 'The domain is not read again: {0}' $_.Exception.GetBaseException().Message) -Problem
                return
            }
            $settingsCache.Clear()
            $gpoComment.Cache.Clear()
            # The Starter GPOs: read again when their node is selected.
            $starterGpos.List = $null
            $history.Current = @{}
            $backupLists.Root = $null
            Update-DirectoryTree -Select (Find-PSGPODirectoryItem -Directory $Directory -Item $refresh.Item -LinkSom $refresh.LinkSom)
            # The domain controller and its role in the status bar.
            $statusBarList.ItemsSource = @(Get-PSGPOStatusBarItem -Platform (Get-PSGPOPlatform) -Directory $Directory) + $versionStatusItems
            Show-DirectoryResult -Text $(if ($refresh.Server) { Get-PSGPOText 'The domain is read from {0}, at {1}.' $Directory.Server (Get-Date).ToString('T') } else { Get-PSGPOText 'The domain is read again from {0}, at {1}.' $Directory.Server (Get-Date).ToString('T') })
        } -Failed {
            param($ErrorRecord)
            Show-DirectoryResult -Text (Get-PSGPOText 'The domain is not read again: {0}' $ErrorRecord.Exception.GetBaseException().Message) -Problem
        }
    }

    # Change Domain Controller..., as GPMC: the domain controllers of the domain, the PDC emulator
    # first; the domain read again from the one chosen, where its changes go from then on.
    $changeDc = @{ Names = @() }
    function Open-ChangeDcForm {
        if ($Directory -isnot [GPOToolsLdapDirectory]) { return }
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $changeDcErrorTextBlock.Text = ''
        $changeDcTitleTextBlock.Text = Get-PSGPOText 'Domain controller of {0}: {1} now' $Directory.DomainName $Directory.Server
        try {
            $changeDc.Names = @(Get-PSGPODomainController -Directory $Directory)
        } catch {
            $changeDc.Names = @()
            $changeDcErrorTextBlock.Text = Get-PSGPOText 'The domain controllers of the domain cannot be read: {0}' $_.Exception.GetBaseException().Message
        }
        $changeDcList.ItemsSource = @(foreach ($name in $changeDc.Names) {
                $roles = @()
                if ([string]::Equals($name, $Directory.PdcEmulator, [System.StringComparison]::OrdinalIgnoreCase)) { $roles += Get-PSGPOText 'PDC emulator' }
                if ([string]::Equals($name, $Directory.Server, [System.StringComparison]::OrdinalIgnoreCase)) { $roles += Get-PSGPOText 'current' }
                if ($roles.Count) { '{0} ({1})' -f $name, ($roles -join ', ') } else { $name }
            })
        $changeDcList.SelectedIndex = -1
        $changeDcConfirmButton.IsEnabled = $false
        Show-DirectoryForm $changeDcPanel
    }
    $changeDcList.add_SelectionChanged({
        $index = $changeDcList.SelectedIndex
        $changeDcConfirmButton.IsEnabled = $index -ge 0 -and $index -lt $changeDc.Names.Count -and
            -not [string]::Equals($changeDc.Names[$index], $Directory.Server, [System.StringComparison]::OrdinalIgnoreCase)
    })
    $changeDcConfirmButton.Add_Click({
        $server = $changeDc.Names[$changeDcList.SelectedIndex]
        $changeDcPanel.IsVisible = $false
        Invoke-DirectoryRefresh -Server $server
    })
    $changeDcCancelButton.Add_Click({ $changeDcPanel.IsVisible = $false })
    $changeDcMenuItem.Add_Click({ Open-ChangeDcForm })
    $refreshButton.Add_Click({ Invoke-DirectoryRefresh })
    $window.add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::F5 -and $managementView.IsVisible) { Invoke-DirectoryRefresh; $e.Handled = $true }
    })
}
