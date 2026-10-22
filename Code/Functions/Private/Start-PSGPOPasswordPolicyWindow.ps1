<#
    Private implementation of Show-PSOManagerAvalonia: builds the window, wires its handlers and
    runs the Avalonia loop until the window closes.

    -OnShown exists for the GUI tests, as for Start-PSGPOManagerWindow: the scriptblock receives a
    hashtable of the named controls, runs inside the loop once the window is shown, and the window
    is then closed. Event handlers keep resolving the local variables below because this function
    scope stays alive for the whole loop.
#>

function Start-PSGPOPasswordPolicyWindow {
    [CmdletBinding()]
    param(
        # The fine-grained password policies of the domain; $null when the domain could not be read.
        [AllowNull()] [GPOToolsPasswordPolicyStore]$Store,

        # Why the domain could not be read.
        [string]$StoreError,

        [ValidateSet('Policies', 'Resultant')]
        [string]$StartView = 'Policies',

        # Language of the interface; English by default, so that the tests do not depend on the
        # language of the computer: Show-PSOManagerAvalonia gives the one of the session.
        [string]$Language = 'en-US',

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime
    $null = Set-PSGPOLanguage -Language $Language

    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml (Get-PSGPOPasswordPolicyWindowXaml)))
    Set-PSGPOWindowIcon -Window $window
    $names = 'logoImage', 'subtitleTextBlock', 'policiesButton', 'resultantButton', 'refreshButton', 'themeToggleButton', 'themeToggleIcon', 'themeToggleText',
    'demoBanner', 'errorBanner', 'errorBannerTextBlock', 'policiesView', 'policiesHeaderTextBlock', 'newPolicyButton', 'editPolicyButton', 'deletePolicyButton',
    'policiesList', 'policiesEmptyTextBlock', 'domainPolicyTextBlock', 'policyTitleTextBlock', 'policyDescriptionTextBlock', 'policyResultTextBlock',
    'deletePolicyPanel', 'deletePolicyTextBlock', 'deletePolicyConfirmButton', 'deletePolicyCancelButton', 'policyEmptyTextBlock', 'policySettingsList',
    'appliesToHeaderTextBlock', 'appliesToList', 'resultantView', 'identitySearchTextBox', 'identitySearchButton', 'identityStatusTextBlock', 'identitiesList',
    'resultEmptyTextBlock', 'resultPanel', 'resultTitleTextBlock', 'resultSubtitleTextBlock', 'appliedCaptionTextBlock', 'appliedNameTextBlock',
    'appliedSourceTextBlock', 'differsTextBlock', 'resultSettingsList', 'candidatesList', 'groupRuleTextBlock', 'statusBar', 'statusBarList'
    $ui = @{}
    foreach ($name in $names) { $ui[$name] = Get-PSGPOAvaloniaControl $window $name }
    $ui.logoImage.Source = New-PSGPOLogoBitmap
    $red = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
    $green = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#107C10'))

    # The editor of a PSO (New-PSGPOPasswordPolicyEditorWindow), one at a time, owned by the console.
    $editor = @{ Ui = $null }
    # The account shown in the Resultant Password Settings view.
    $resultant = @{ Account = $null; Result = $null }

    function Show-View {
        param([string]$View)
        $ui.policiesView.IsVisible = $View -eq 'Policies'
        $ui.resultantView.IsVisible = $View -eq 'Resultant'
        foreach ($pair in @(@($ui.policiesButton, 'Policies'), @($ui.resultantButton, 'Resultant'))) {
            if ($pair[1] -ne $View) { [void]$pair[0].Classes.Remove('active') }
            elseif (-not $pair[0].Classes.Contains('active')) { $pair[0].Classes.Add('active') }
        }
    }

    function Show-PolicyResult {
        param([string]$Text, [switch]$Problem)
        $ui.policyResultTextBlock.Text = $Text
        $ui.policyResultTextBlock.IsVisible = [bool]$Text
        $ui.policyResultTextBlock.Foreground = if ($Problem) { $red } else { $green }
    }

    # The selected PSO in the details: its settings and the users and groups it applies to.
    function Show-Policy {
        param([GPOToolsPasswordPolicy]$Policy)
        $ui.deletePolicyPanel.IsVisible = $false
        $ui.policyEmptyTextBlock.IsVisible = -not $Policy
        $ui.editPolicyButton.IsEnabled = [bool]$Policy
        $ui.deletePolicyButton.IsEnabled = $Policy -and $Policy.CanEdit
        if (-not $Policy) {
            $ui.policyTitleTextBlock.Text = ''
            $ui.policyDescriptionTextBlock.Text = ''
            $ui.policySettingsList.ItemsSource = @()
            $ui.appliesToHeaderTextBlock.Text = ''
            $ui.appliesToList.ItemsSource = @()
            return
        }
        $ui.policyTitleTextBlock.Text = $Policy.Name
        $ui.policyDescriptionTextBlock.Text = $Policy.Description
        $ui.policySettingsList.ItemsSource = @(Get-PSGPOPasswordPolicySettingRow -Policy $Policy)
        $ui.appliesToHeaderTextBlock.Text = Get-PSGPOText 'Directly Applies To ({0})' $Policy.AppliesTo.Count
        $ui.appliesToList.ItemsSource = @(foreach ($dn in $Policy.AppliesTo) {
                $account = $null
                try { $account = $Store.GetAccount($dn) } catch { Write-Verbose "The subject $dn cannot be read: $($_.Exception.Message)" }
                if ($account) { ConvertTo-PSGPOPasswordAccountRow -Account $account } else { ConvertTo-PSGPOPasswordAccountRow -DistinguishedName $dn }
            })
    }

    # The list of the PSOs, by order of priority, and the password policy of the domain.
    function Update-PolicyList {
        param([GPOToolsPasswordPolicy]$Select)
        $rows = @(foreach ($policy in $Store.Policies) { ConvertTo-PSGPOPasswordPolicyRow -Policy $policy })
        $ui.policiesList.ItemsSource = $rows
        $ui.policiesHeaderTextBlock.Text = Get-PSGPOText '{0} password settings objects, by order of priority (the lowest precedence first)' $rows.Count
        $ui.policiesEmptyTextBlock.IsVisible = -not $rows.Count
        $ui.policiesEmptyTextBlock.Text = Get-PSGPOText 'No password settings object in {0}, or the account {1} cannot read them (by default, only the administrators of the domain do).' $Store.DomainName $Store.Account
        $ui.domainPolicyTextBlock.Text = Get-PSGPOPasswordPolicySummary -Policy $Store.DomainPolicy
        $selected = if ($Select) { $rows | Where-Object { [object]::ReferenceEquals($_.Policy, $Select) } | Select-Object -First 1 }
        $ui.policiesList.SelectedItem = $selected
        Show-Policy -Policy $(if ($selected) { $selected.Policy })
    }

    function Open-PolicyEditor {
        param([GPOToolsPasswordPolicy]$Policy)
        if ($editor.Ui -and $editor.Ui.Window.IsVisible) { $editor.Ui.Window.Activate(); return }
        $saved = {
            param($Saved)
            Update-PolicyList -Select $Saved
            Show-PolicyResult -Text (Get-PSGPOText 'Saved: {0}.' $Saved.Name)
            if ($resultant.Account) { Show-Resultant -Account $resultant.Account }
        }
        $editor.Ui = New-PSGPOPasswordPolicyEditorWindow -Store $Store -Policy $Policy -OnSaved $saved
        $editor.Ui.Window.RequestedThemeVariant = $window.RequestedThemeVariant
        $editor.Ui.Window.Show($window)
    }

    # What applies to a user or a group, and why.
    function Show-Resultant {
        param([GPOToolsPasswordAccount]$Account)
        $resultant.Account = $Account
        $ui.resultEmptyTextBlock.IsVisible = -not $Account
        $ui.resultPanel.IsVisible = [bool]$Account
        if (-not $Account) { return }
        try {
            $result = Resolve-PSGPOPasswordPolicy -Store $Store -Account $Account
        } catch {
            $ui.resultPanel.IsVisible = $false
            $ui.resultEmptyTextBlock.IsVisible = $true
            $ui.resultEmptyTextBlock.Text = Get-PSGPOText 'What applies to {0} cannot be read: {1}' $Account.Name $_.Exception.GetBaseException().Message
            return
        }
        $resultant.Result = $result
        $ui.resultTitleTextBlock.Text = '{0} ({1})' -f $Account.Name, (Get-PSGPOPasswordAccountKindText -Account $Account)
        $ui.resultSubtitleTextBlock.Text = $Account.DistinguishedName
        $ui.appliedCaptionTextBlock.Text = Get-PSGPOText $(if ($Account.Kind -eq 'Group') { 'Password settings its members get through this group' } else { 'Resultant password settings' })
        $ui.appliedNameTextBlock.Text = if ($result.Settings -and $result.Settings.IsDefault) { Get-PSGPOText 'Default domain password policy' } else { $result.AppliedPolicy }
        $ui.appliedSourceTextBlock.Text = if ($result.Source -eq 'DomainController') {
            Get-PSGPOText 'Given by the domain controller {0} (msDS-ResultantPSO).' $Store.Server
        } elseif ($Account.Kind -eq 'Group') {
            Get-PSGPOText 'For the members of the group that no closer password settings object concerns: one applied to them directly, or with a lower precedence through another group.'
        } else {
            Get-PSGPOText 'Computed from the password settings objects and the groups of the account.'
        }
        $ui.differsTextBlock.IsVisible = [bool]$result.Differs
        $ui.differsTextBlock.Text = Get-PSGPOText 'The domain controller applies {0}; the order of priority of the password settings objects this account reads gives {1}. The domain controller has the last word: the account may not read every password settings object.' $result.AppliedPolicy $result.ComputedPolicy
        $ui.resultSettingsList.ItemsSource = if ($result.Settings) { @(Get-PSGPOPasswordPolicySettingRow -Policy $result.Settings) } else {
            $row = [AvaloniaRegistryRow]::new(); $row.Key = Get-PSGPOText 'Settings'; $row.Value = Get-PSGPOText 'This account cannot read this password settings object.'; @($row)
        }
        $ui.candidatesList.ItemsSource = @(foreach ($candidate in $result.Candidates) { ConvertTo-PSGPOPasswordCandidateRow -Candidate $candidate -Result $result -Store $Store })
        $ui.groupRuleTextBlock.Text = if ($Store.GroupRule -eq 'Security') {
            Get-PSGPOText 'Samba AD: a password settings object applied to a group reaches its members through every security group but the built-in ones (Windows: global security groups only). One applied directly to a user wins over those of its groups; of several, the lowest precedence wins, then the smallest GUID.'
        } else {
            Get-PSGPOText 'A password settings object applied to a group reaches its members through global security groups only. One applied directly to a user wins over those of its groups; of several, the lowest precedence wins, then the smallest GUID.'
        }
    }

    function Invoke-IdentitySearch {
        $text = "$($ui.identitySearchTextBox.Text)".Trim()
        try {
            $found = @($Store.FindAccounts($text))
        } catch {
            $ui.identityStatusTextBlock.Text = Get-PSGPOText 'The domain is not searched: {0}' $_.Exception.GetBaseException().Message
            return
        }
        $ui.identitiesList.ItemsSource = @(foreach ($account in $found) { ConvertTo-PSGPOPasswordAccountRow -Account $account })
        $ui.identityStatusTextBlock.Text = if ($found.Count) { Get-PSGPOText '{0} users and groups found.' $found.Count } else { Get-PSGPOText 'No user or group found.' }
    }

    # Refresh (F5): the PSOs read again; the selection stays.
    function Invoke-StoreRefresh {
        if (-not $Store) { return }
        $selected = if ($ui.policiesList.SelectedItem) { $ui.policiesList.SelectedItem.Policy.DistinguishedName }
        try {
            $Store.Refresh()
        } catch {
            Show-PolicyResult -Text (Get-PSGPOText 'The domain is not read again: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        Update-PolicyList -Select ($Store.Policies | Where-Object DistinguishedName -EQ $selected | Select-Object -First 1)
        if ($resultant.Account) { Show-Resultant -Account $resultant.Account }
        Show-PolicyResult -Text (Get-PSGPOText 'The domain is read again from {0}, at {1}.' $(if ($Store -is [GPOToolsLdapPasswordPolicyStore]) { $Store.Server } else { $Store.Source }) (Get-Date).ToString('T'))
    }

    # Theme: the window starts on the theme of the system.
    $platformSettings = [Avalonia.Application]::Current.PlatformSettings
    $theme = @{ Dark = $null -ne $platformSettings -and $platformSettings.GetColorValues().ThemeVariant -eq [Avalonia.Platform.PlatformThemeVariant]::Dark }
    function Update-ThemeButton {
        $ui.themeToggleText.Text = Get-PSGPOText $(if ($theme.Dark) { 'Light mode' } else { 'Dark mode' })
        $ui.themeToggleIcon.Data = [Avalonia.Media.Geometry]::Parse((Get-PSGPOIconData -Name $(if ($theme.Dark) { 'weather-sunny' } else { 'weather-moon' })))
    }
    Update-ThemeButton
    $ui.themeToggleButton.Add_Click({
        $theme.Dark = -not $theme.Dark
        $window.RequestedThemeVariant = if ($theme.Dark) { [Avalonia.Styling.ThemeVariant]::Dark } else { [Avalonia.Styling.ThemeVariant]::Light }
        Update-ThemeButton
    })

    $ui.policiesButton.Add_Click({ Show-View 'Policies' })
    $ui.resultantButton.Add_Click({ Show-View 'Resultant' })
    $ui.refreshButton.Add_Click({ Invoke-StoreRefresh })
    $window.add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::F5) { Invoke-StoreRefresh; $e.Handled = $true }
    })
    $ui.policiesList.add_SelectionChanged({
        $row = $ui.policiesList.SelectedItem
        Show-Policy -Policy $(if ($row) { $row.Policy })
    })
    $ui.policiesList.add_DoubleTapped({ if ($ui.policiesList.SelectedItem) { Open-PolicyEditor -Policy $ui.policiesList.SelectedItem.Policy } })
    $ui.newPolicyButton.Add_Click({ Open-PolicyEditor -Policy $null })
    $ui.editPolicyButton.Add_Click({ if ($ui.policiesList.SelectedItem) { Open-PolicyEditor -Policy $ui.policiesList.SelectedItem.Policy } })
    $ui.deletePolicyButton.Add_Click({
        $row = $ui.policiesList.SelectedItem
        if (-not $row) { return }
        if ($row.Policy.ProtectedFromAccidentalDeletion) {
            Show-PolicyResult -Text (Get-PSGPOText '{0} is protected from accidental deletion: clear the protection in its properties first.' $row.Name) -Problem
            return
        }
        $ui.deletePolicyTextBlock.Text = Get-PSGPOText 'Delete the password settings object {0}? The users it applies to get the next password settings object that concerns them, or the password policy of the domain.' $row.Name
        $ui.deletePolicyPanel.IsVisible = $true
    })
    $ui.deletePolicyCancelButton.Add_Click({ $ui.deletePolicyPanel.IsVisible = $false })
    $ui.deletePolicyConfirmButton.Add_Click({
        $row = $ui.policiesList.SelectedItem
        $ui.deletePolicyPanel.IsVisible = $false
        if (-not $row) { return }
        try {
            $Store.RemovePolicy($row.Policy)
        } catch {
            Show-PolicyResult -Text (Get-PSGPOText '{0} is not deleted: {1}' $row.Name $_.Exception.GetBaseException().Message) -Problem
            return
        }
        Update-PolicyList
        if ($resultant.Account) { Show-Resultant -Account $resultant.Account }
        Show-PolicyResult -Text (Get-PSGPOText '{0} deleted.' $row.Name)
    })
    $ui.identitySearchButton.Add_Click({ Invoke-IdentitySearch })
    $ui.identitySearchTextBox.add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Invoke-IdentitySearch; $e.Handled = $true }
    })
    $ui.identitiesList.add_SelectionChanged({
        $row = $ui.identitiesList.SelectedItem
        Show-Resultant -Account $(if ($row) { $row.Account })
    })

    # The domain, or why it is not there.
    $ui.demoBanner.IsVisible = $Store -and $Store.IsDemonstration
    $ui.errorBanner.IsVisible = [bool]$StoreError
    $ui.errorBannerTextBlock.Text = (Get-PSGPOText 'The domain could not be read.') + " $StoreError"
    foreach ($control in $ui.newPolicyButton, $ui.editPolicyButton, $ui.deletePolicyButton, $ui.refreshButton, $ui.identitySearchButton, $ui.identitySearchTextBox) { $control.IsEnabled = [bool]$Store }
    if ($Store) {
        $ui.subtitleTextBlock.Text = Get-PSGPOText 'Fine-grained password policies of {0}' $Store.DomainName
        $ui.newPolicyButton.IsEnabled = $Store.CanCreate
        if (-not $Store.CanCreate) {
            [Avalonia.Controls.ToolTip]::SetTip($ui.newPolicyButton, (Get-PSGPOText 'The account {0} cannot create password settings objects in {1}.' $Store.Account $Store.DomainName))
            [Avalonia.Controls.ToolTip]::SetShowOnDisabled($ui.newPolicyButton, $true)
        }
        $ui.refreshButton.IsEnabled = $Store -is [GPOToolsLdapPasswordPolicyStore]
        Update-PolicyList
    }
    Show-Resultant -Account $null
    Show-View $StartView

    # The status bar: this computer, its addresses, its domain (as the GPO console), then the
    # domain controller and the account the policies are read with.
    $statusItems = [System.Collections.Generic.List[object]]::new()
    # The objects themselves: a binding of Avalonia does not see the properties of a PSObject.
    foreach ($item in @(Get-PSGPOStatusBarItem -Platform (Get-PSGPOPlatform))[0..2]) { $statusItems.Add($item.PSObject.BaseObject) }
    $newItem = {
        param($Icon, $Text, $ToolTip)
        $item = [AvaloniaStatusItem]::new(); $item.IconData = Get-PSGPOIconData -Name $Icon; $item.Text = $Text; $item.ToolTip = if ($ToolTip) { $ToolTip } else { $Text }; $item
    }
    if ($Store -is [GPOToolsLdapPasswordPolicyStore]) {
        $statusItems.Add((& $newItem 'server' "DC $($Store.Server) ($($Store.ServerType))" (Get-PSGPOText 'Directory {0}' $Store.Source)))
        if ($Store.Account) { $statusItems.Add((& $newItem 'person' (Get-PSGPOText 'Connected as {0}' $Store.Account))) }
    } elseif ($Store) {
        $statusItems.Add((& $newItem 'server' (Get-PSGPOText 'No domain controller: demonstration directory') (Get-PSGPOText 'No Active Directory or Samba AD domain was discovered: the directory shown is sample data.')))
    } else {
        $statusItems.Add((& $newItem 'server' (Get-PSGPOText 'Domain controller not reached') $StoreError))
    }
    # Then the version of HGPM, and whether a newer one is on the PowerShell Gallery.
    $statusItems.Add((Get-PSGPOVersionStatusItem).PSObject.BaseObject)
    $ui.statusBarList.ItemsSource = @($statusItems)

    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { $cts.Cancel() }, [Avalonia.Threading.DispatcherPriority]::Background)
    })
    $window.Show()

    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Store = $Store; Editor = $editor; Resultant = $resultant } + $ui
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally {
                    if ($editor.Ui -and $editor.Ui.Window.IsVisible) { $editor.Ui.Window.Close() }
                    $window.Close()
                }
            })
    }

    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        Write-Verbose 'The window is closed.'
    }

    if ($onShownState.Error) { throw $onShownState.Error }
}
