<#
    Private implementation of Show-GPOManagerAvalonia: builds the window, wires its
    handlers and runs the Avalonia loop until the window closes.

    -OnShown exists for the GUI tests: the scriptblock receives a hashtable of the named
    controls, runs inside the loop once the window is shown, and the window is then
    closed. Event handlers keep resolving the local variables below because this
    function scope stays alive for the whole loop.
#>

function Start-PSGPOManagerWindow {
    [CmdletBinding()]
    Param(
        # Domain of the Group Policy Management view; without it the window opens on the ADMX policies.
        [GPOToolsDirectory]$Directory,

        # Why the domain could not be read: shown in the Group Policy Management view.
        [string]$DirectoryError,

        # View shown at launch: the Group Policy Management view, or the policy editor.
        [ValidateSet('Management', 'Editor')]
        [string]$StartView = 'Management',

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime

    $xaml = Get-PSGPOManagerWindowXaml

    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse($xaml)

    $treeView = Get-PSGPOAvaloniaControl $window 'treeView'
    $themeToggleButton = Get-PSGPOAvaloniaControl $window 'themeToggleButton'
    $breadcrumbTextBlock = Get-PSGPOAvaloniaControl $window 'breadcrumbTextBlock'
    $searchTextBox = Get-PSGPOAvaloniaControl $window 'searchTextBox'
    $searchButton = Get-PSGPOAvaloniaControl $window 'searchButton'
    $configuredOnlyCheckBox = Get-PSGPOAvaloniaControl $window 'configuredOnlyCheckBox'
    $displayNameTextBox = Get-PSGPOAvaloniaControl $window 'displayNameTextBox'
    $descriptionTextBox = Get-PSGPOAvaloniaControl $window 'descriptionTextBox'
    $scopeTextBox = Get-PSGPOAvaloniaControl $window 'scopeTextBox'
    $registryPathTextBox = Get-PSGPOAvaloniaControl $window 'registryPathTextBox'
    $registryKeyTextBox = Get-PSGPOAvaloniaControl $window 'registryKeyTextBox'
    $registryValuesList = Get-PSGPOAvaloniaControl $window 'registryValuesList'
    $settingTitleTextBlock = Get-PSGPOAvaloniaControl $window 'settingTitleTextBlock'
    $previewEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'previewEmptyTextBlock'
    $copyNameMenuItem = Get-PSGPOAvaloniaControl $window 'copyNameMenuItem'
    $copyRegistryMenuItem = Get-PSGPOAvaloniaControl $window 'copyRegistryMenuItem'
    $copyCommandMenuItem = Get-PSGPOAvaloniaControl $window 'copyCommandMenuItem'
    $notConfiguredRadio = Get-PSGPOAvaloniaControl $window 'notConfiguredRadio'
    $enabledRadio = Get-PSGPOAvaloniaControl $window 'enabledRadio'
    $disabledRadio = Get-PSGPOAvaloniaControl $window 'disabledRadio'
    $optionsHost = Get-PSGPOAvaloniaControl $window 'optionsHost'
    $settingErrorTextBlock = Get-PSGPOAvaloniaControl $window 'settingErrorTextBlock'
    $registryPreviewList = Get-PSGPOAvaloniaControl $window 'registryPreviewList'

    $subtitleTextBlock = Get-PSGPOAvaloniaControl $window 'subtitleTextBlock'
    $managementButton = Get-PSGPOAvaloniaControl $window 'managementButton'
    $browseAdmxButton = Get-PSGPOAvaloniaControl $window 'browseAdmxButton'
    $searchPanel = Get-PSGPOAvaloniaControl $window 'searchPanel'
    $managementView = Get-PSGPOAvaloniaControl $window 'managementView'
    $editorView = Get-PSGPOAvaloniaControl $window 'editorView'
    $editingBanner = Get-PSGPOAvaloniaControl $window 'editingBanner'
    $editingGpoTextBlock = Get-PSGPOAvaloniaControl $window 'editingGpoTextBlock'
    $domainTreeView = Get-PSGPOAvaloniaControl $window 'domainTreeView'
    $directoryEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'directoryEmptyTextBlock'
    $demoBanner = Get-PSGPOAvaloniaControl $window 'demoBanner'
    $statusBarList = Get-PSGPOAvaloniaControl $window 'statusBarList'
    $directoryBreadcrumbTextBlock = Get-PSGPOAvaloniaControl $window 'directoryBreadcrumbTextBlock'
    $directoryTitleTextBlock = Get-PSGPOAvaloniaControl $window 'directoryTitleTextBlock'
    $directoryPropertiesList = Get-PSGPOAvaloniaControl $window 'directoryPropertiesList'
    $linksHeaderTextBlock = Get-PSGPOAvaloniaControl $window 'linksHeaderTextBlock'
    $linksList = Get-PSGPOAvaloniaControl $window 'linksList'
    $createLinkedGpoMenuItem = Get-PSGPOAvaloniaControl $window 'createLinkedGpoMenuItem'
    $newGpoMenuItem = Get-PSGPOAvaloniaControl $window 'newGpoMenuItem'
    $editGpoMenuItem = Get-PSGPOAvaloniaControl $window 'editGpoMenuItem'
    $editGpoButton = Get-PSGPOAvaloniaControl $window 'editGpoButton'
    $newGpoPanel = Get-PSGPOAvaloniaControl $window 'newGpoPanel'
    $newGpoTitleTextBlock = Get-PSGPOAvaloniaControl $window 'newGpoTitleTextBlock'
    $newGpoNameTextBox = Get-PSGPOAvaloniaControl $window 'newGpoNameTextBox'
    $newGpoErrorTextBlock = Get-PSGPOAvaloniaControl $window 'newGpoErrorTextBlock'
    $newGpoCreateButton = Get-PSGPOAvaloniaControl $window 'newGpoCreateButton'
    $newGpoCancelButton = Get-PSGPOAvaloniaControl $window 'newGpoCancelButton'
    $newGpoStatusComboBox = Get-PSGPOAvaloniaControl $window 'newGpoStatusComboBox'
    $newGpoGroupsCheckBox = Get-PSGPOAvaloniaControl $window 'newGpoGroupsCheckBox'
    $newGpoGroupsPanel = Get-PSGPOAvaloniaControl $window 'newGpoGroupsPanel'
    $newGpoGroupsTextBlock = Get-PSGPOAvaloniaControl $window 'newGpoGroupsTextBlock'
    $newGpoGroupsContainerComboBox = Get-PSGPOAvaloniaControl $window 'newGpoGroupsContainerComboBox'
    $directoryResultTextBlock = Get-PSGPOAvaloniaControl $window 'directoryResultTextBlock'
    $deleteLinkMenuItem = Get-PSGPOAvaloniaControl $window 'deleteLinkMenuItem'
    $deleteLinkPanel = Get-PSGPOAvaloniaControl $window 'deleteLinkPanel'
    $deleteLinkTextBlock = Get-PSGPOAvaloniaControl $window 'deleteLinkTextBlock'
    $deleteLinkConfirmButton = Get-PSGPOAvaloniaControl $window 'deleteLinkConfirmButton'
    $deleteLinkCancelButton = Get-PSGPOAvaloniaControl $window 'deleteLinkCancelButton'

    $applyPanel = Get-PSGPOAvaloniaControl $window 'applyPanel'
    $directoryTabs = Get-PSGPOAvaloniaControl $window 'directoryTabs'
    $settingsTab = Get-PSGPOAvaloniaControl $window 'settingsTab'
    $settingsStatusTextBlock = Get-PSGPOAvaloniaControl $window 'settingsStatusTextBlock'
    $computerSettingsHeader = Get-PSGPOAvaloniaControl $window 'computerSettingsHeader'
    $computerSettingsList = Get-PSGPOAvaloniaControl $window 'computerSettingsList'
    $userSettingsHeader = Get-PSGPOAvaloniaControl $window 'userSettingsHeader'
    $userSettingsList = Get-PSGPOAvaloniaControl $window 'userSettingsList'
    $applySettingButton = Get-PSGPOAvaloniaControl $window 'applySettingButton'
    $applyStatusTextBlock = Get-PSGPOAvaloniaControl $window 'applyStatusTextBlock'

    # Options form of the selected policy (New-PSGPOPolicyEditor), the policy it edits and the
    # GPO opened from the Group Policy Management view ($null: browsing the ADMX policies).
    # Pol: the Registry.pol of the GPO by scope; Saved: the registry values of the setting of the
    # selected policy in it, compared with the form to know whether there is something to apply.
    # Security: the selected security setting, Template: the GptTmpl.inf of the GPO (security
    # settings); Saved is then the raw value of the setting in it.
    $editing = @{ Policy = $null; Security = $null; Editor = $null; Gpo = $null; Pol = @{}; PolError = $null; Template = $null; Saved = $null }
    $previewHeaderTextBlock = Get-PSGPOAvaloniaControl $window 'previewHeaderTextBlock'
    $notDefinedMark = '(not defined)'

    # Raw GptTmpl.inf value of the security setting of the form, or the not defined mark.
    function Get-SecuritySignature {
        if ($enabledRadio.IsChecked) { $editing.Security.ConvertToRaw((& $editing.Editor.GetValue)) } else { $notDefinedMark }
    }

    function Get-SettingState {
        if ($enabledRadio.IsChecked) { 'Enabled' } elseif ($disabledRadio.IsChecked) { 'Disabled' } else { 'NotConfigured' }
    }

    # Registry values of a setting as one text, to compare two settings.
    function Get-SettingSignature {
        param([GPOToolsPolicy]$Policy, [string]$State, [hashtable]$Value)
        (@(Get-PSGPOPolicyRegistryChange -Policy $Policy -State $State -Value $Value) | ForEach-Object { Format-PSGPORegistryValue $_ }) -join "`n"
    }

    # Apply is offered when the form differs from the Registry.pol of the GPO and is valid.
    function Update-ApplyButton {
        $policy = $editing.Policy
        $applyPanel.IsVisible = [bool]$editing.Gpo
        $pol = if ($policy) { $editing.Pol["$($policy.Scope)"] }
        $changed = $false
        if (-not $settingErrorTextBlock.Text) {
            try {
                if ($policy -and $pol) { $changed = (Get-SettingSignature $policy (Get-SettingState) (& $editing.Editor.GetValue)) -ne $editing.Saved }
                elseif ($editing.Security -and $editing.Template) { $changed = (Get-SecuritySignature) -ne $editing.Saved }
            } catch { $changed = $false }
        }
        $applySettingButton.IsEnabled = $changed
    }

    # Registry values the current setting writes (what Registry.pol will contain).
    function Update-RegistryPreview {
        $policy = $editing.Policy
        $state = if ($enabledRadio.IsChecked) { 'Enabled' } elseif ($disabledRadio.IsChecked) { 'Disabled' } else { 'NotConfigured' }
        # Like the Group Policy editor, options can only be edited when the policy is enabled.
        $optionsHost.IsEnabled = $state -eq 'Enabled'
        $settingErrorTextBlock.Text = ''
        if ($editing.Security) {
            # A security setting: its line of GptTmpl.inf.
            $rows = @()
            if ($state -eq 'Enabled') {
                try {
                    $row = [AvaloniaPreviewRow]::new()
                    $row.Title = 'Set in GptTmpl.inf'
                    $row.Key = "[$($editing.Security.Section)]"
                    $row.ValueName = $editing.Security.Key
                    $row.Data = $editing.Security.ConvertToRaw((& $editing.Editor.GetValue))
                    $rows = @($row)
                } catch {
                    $settingErrorTextBlock.Text = $_.Exception.Message
                }
            }
            $registryPreviewList.ItemsSource = $rows
            $previewEmptyTextBlock.IsVisible = $rows.Count -eq 0
            $previewEmptyTextBlock.Text = if ($settingErrorTextBlock.Text) { 'Fix the value above to see the line of GptTmpl.inf.' } else { 'Not defined: nothing is written to GptTmpl.inf.' }
            Update-ApplyButton
            return
        }
        $rows = @()
        if ($policy) {
            try {
                $changes = @(Get-PSGPOPolicyRegistryChange -Policy $policy -State $state -Value (& $editing.Editor.GetValue))
                $rows = @(foreach ($change in $changes) { ConvertTo-PSGPOPreviewRow -Change $change -Scope $policy.Scope })
            } catch {
                $settingErrorTextBlock.Text = $_.Exception.Message
            }
        }
        $registryPreviewList.ItemsSource = $rows
        $previewEmptyTextBlock.IsVisible = $rows.Count -eq 0
        $previewEmptyTextBlock.Text = if (-not $policy) { 'Select a policy in the tree.' }
            elseif ($settingErrorTextBlock.Text) { 'Fix the options above to see the registry values.' }
            else { 'Not configured: nothing is written to the registry.' }
        Update-ApplyButton
    }

    # Saves the setting of the selected policy in the Registry.pol of the GPO. The file is
    # changed on a copy: if the domain refuses it, the setting read before stays.
    $applySettingButton.Add_Click({
        if ($editing.Security) {
            # A security setting: written to a copy of GptTmpl.inf, saved, then kept.
            $setting = $editing.Security
            if (-not $editing.Gpo -or -not $editing.Template) { return }
            $value = if ($enabledRadio.IsChecked) { & $editing.Editor.GetValue } else { $null }
            $copy = [GPOToolsSecurityTemplate]::Parse($editing.Template.ToBytes())
            try {
                Set-PSGPOSecurityValue -Template $copy -Setting $setting -Value $value
                $Directory.WriteSecurityTemplate($editing.Gpo, $copy.ToBytes())
                $editing.Template = $copy
                $editing.Saved = Get-SecuritySignature
                $applyStatusTextBlock.Text = "Saved: $($setting.FormatValue($value)) in GptTmpl.inf (version $($editing.Gpo.GetComputerVersion()))."
            } catch {
                $applyStatusTextBlock.Text = "Not saved: $($_.Exception.GetBaseException().Message)"
            }
            Update-ApplyButton
            return
        }
        $policy = $editing.Policy
        $scope = "$($policy.Scope)"
        if (-not $policy -or -not $editing.Gpo -or -not $editing.Pol[$scope]) { return }
        $state = Get-SettingState
        $value = & $editing.Editor.GetValue
        $copy = [GPOToolsRegistryPol]::Parse($editing.Pol[$scope].ToBytes())
        try {
            Set-PSGPOPolicyState -Policy $policy -Pol $copy -State $state -Value $value
            $Directory.WritePolicyFile($editing.Gpo, $scope, $copy.ToBytes())
            $editing.Pol[$scope] = $copy
            $editing.Saved = Get-SettingSignature $policy $state $value
            $version = if ($scope -eq 'Machine') { $editing.Gpo.GetComputerVersion() } else { $editing.Gpo.GetUserVersion() }
            $applyStatusTextBlock.Text = "Saved: $state in $scope\Registry.pol (version $version)."
        } catch {
            $applyStatusTextBlock.Text = "Not saved: $($_.Exception.GetBaseException().Message)"
        }
        Update-ApplyButton
    })
    foreach ($radio in $notConfiguredRadio, $enabledRadio, $disabledRadio) {
        $radio.add_IsCheckedChanged({ Update-RegistryPreview })
    }

    # Theme management: Avalonia FluentTheme + our ThemeDictionaries swap automatically
    # when RequestedThemeVariant changes, no manual brush-by-brush update needed.
    # The window starts on the OS theme, so the toggle starts from the actual variant.
    $platformSettings = [Avalonia.Application]::Current.PlatformSettings
    $script:isDarkTheme = $null -ne $platformSettings -and
        $platformSettings.GetColorValues().ThemeVariant -eq [Avalonia.Platform.PlatformThemeVariant]::Dark
    $themeToggleIcon = Get-PSGPOAvaloniaControl $window 'themeToggleIcon'
    $themeToggleText = Get-PSGPOAvaloniaControl $window 'themeToggleText'
    $updateThemeButton = {
        $themeToggleText.Text = if ($script:isDarkTheme) { 'Light mode' } else { 'Dark mode' }
        $themeToggleIcon.Data = [Avalonia.Media.Geometry]::Parse((Get-PSGPOIconData -Name $(if ($script:isDarkTheme) { 'weather-sunny' } else { 'weather-moon' })))
    }
    & $updateThemeButton
    $themeToggleButton.Add_Click({
        $script:isDarkTheme = -not $script:isDarkTheme
        $window.RequestedThemeVariant = if ($script:isDarkTheme) { [Avalonia.Styling.ThemeVariant]::Dark } else { [Avalonia.Styling.ThemeVariant]::Light }
        & $updateThemeButton
    })

    # Context menu actions copy information about the selected policy to the clipboard.
    # The last copy task is kept: a failed copy (no clipboard on a Linux session...) is reported
    # instead of being lost, and the tests can wait for it.
    $clipboard = @{ Task = $null; Error = $null; Text = $null }
    function Copy-SelectedPolicyText {
        param([scriptblock]$Text)

        $selected = $treeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsPolicy]) {
            $value = & $Text $selected.Tag
            if ($value) {
                $clipboard.Error = $null
                $clipboard.Text = $value
                try {
                    $clipboard.Task = $window.Clipboard.SetTextAsync($value)
                } catch {
                    $clipboard.Task = $null
                    $clipboard.Error = $_.Exception
                    Write-Warning "Copy to the clipboard failed: $($_.Exception.Message)"
                }
            }
        }
    }
    $copyNameMenuItem.Add_Click({ Copy-SelectedPolicyText { param($p) $p.DisplayName } })
    $copyRegistryMenuItem.Add_Click({ Copy-SelectedPolicyText { param($p) $p.Registry.Path } })
    $copyCommandMenuItem.Add_Click({
        Copy-SelectedPolicyText {
            param($p)
            if ($p.Registry.Key) {
                "Get-ItemProperty -Path '{0}' -Name '{1}'" -f $p.Registry.Path, $p.Registry.Key
            } elseif ($p.Registry.Path) {
                "Get-ItemProperty -Path '{0}'" -f $p.Registry.Path
            }
        }
    })

    # A security setting in the form: Not Defined / Define this policy setting, its value read
    # from the GptTmpl.inf of the edited GPO.
    function Show-SecuritySetting {
        param([GPOToolsSecuritySetting]$Setting)
        $read = [pscustomobject]@{ Defined = $false; Value = $null; Problem = $null; Raw = $null }
        if ($editing.Template) { $read = Get-PSGPOSecurityValue -Template $editing.Template -Setting $Setting }
        $editing.Policy = $null
        $editing.Saved = if ($read.Defined) { $read.Raw } else { $notDefinedMark }
        $notConfiguredRadio.Content = 'Not Defined'
        $enabledRadio.Content = 'Define this policy setting'
        $disabledRadio.IsVisible = $false
        $previewHeaderTextBlock.Text = 'GptTmpl.inf Preview'
        if ($read.Defined -and -not $read.Problem) { $enabledRadio.IsChecked = $true } else { $notConfiguredRadio.IsChecked = $true }
        $applyStatusTextBlock.Text = if ($read.Problem) { $read.Problem }
            elseif ($editing.Template) { "$(if ($read.Defined) { 'Defined' } else { 'Not defined' }) in GptTmpl.inf" }
            elseif ($editing.Gpo -and $editing.PolError) { $editing.PolError } else { '' }

        $editing.Security = $Setting
        $settingTitleTextBlock.Text = $Setting.Name
        $editing.Editor = New-PSGPOSecurityEditor -Setting $Setting -Value $read.Value -OnChange { Update-RegistryPreview }
        $optionsHost.Content = $editing.Editor.Panel

        $displayNameTextBox.Text = $Setting.Name
        $descriptionTextBox.Text = "Security setting of the computer, in GptTmpl.inf (Machine\Microsoft\Windows NT\SecEdit).$(if ($Setting.Reference) { "`n`nReference: $($Setting.Reference)" })"
        $scopeTextBox.Text = 'Machine'
        $registryPathTextBox.Text = "GptTmpl.inf [$($Setting.Section)]"
        $registryKeyTextBox.Text = $Setting.Key
        $registryValuesList.ItemsSource = @(
            foreach ($pair in @(
                    @('Category', ($Setting.Path -join ' > '))
                    @('Value', $(if ($Setting.Kind -eq 'RegistryValue') { "$($Setting.Display), registry type $($Setting.RegistryType)" } else { $Setting.Kind }))
                    @('Range', $(if ($null -ne $Setting.Min -or $null -ne $Setting.Max) { "$($Setting.Min) to $($Setting.Max) $($Setting.Unit)".Trim() }))
                    @('Values', (@($Setting.Choices | ForEach-Object { "$($_.Value): $($_.Text)" }) -join '; ')))) {
                if (-not $pair[1]) { continue }
                $row = [AvaloniaRegistryRow]::new()
                $row.Key = $pair[0]
                $row.Value = $pair[1]
                $row
            })
        Update-RegistryPreview
    }

    $treeView.add_SelectionChanged({
        $selected = $treeView.SelectedItem

        # Breadcrumb: walk the node's own Parent chain (built while populating the tree).
        $pathParts = [System.Collections.Generic.List[string]]::new()
        $current = $selected
        while ($null -ne $current) {
            $pathParts.Insert(0, $current.Header)
            $current = $current.Parent
        }
        $breadcrumbTextBlock.Text = if ($pathParts.Count -gt 0) { $pathParts -join ' > ' } else { 'Select a policy to see its path' }

        $policy = if ($selected) { $selected.Tag } else { $null }
        $editing.Security = $null
        if ($policy -is [GPOToolsSecuritySetting]) {
            Show-SecuritySetting -Setting $policy
            return
        }
        # A policy: Not Configured / Enabled / Disabled.
        $notConfiguredRadio.Content = 'Not Configured'
        $enabledRadio.Content = 'Enabled'
        $disabledRadio.IsVisible = $true
        $previewHeaderTextBlock.Text = 'Registry Preview'
        # The setting of the policy in the Registry.pol of the edited GPO, else not configured.
        $read = [pscustomobject]@{ State = 'NotConfigured'; Value = @{} }
        $pol = if ($policy -is [GPOToolsPolicy]) { $editing.Pol["$($policy.Scope)"] }
        if ($pol) {
            try { $read = Get-PSGPOPolicyState -Policy $policy -Pol $pol } catch { Write-Warning "Setting of $($policy.DisplayName) not read: $($_.Exception.Message)" }
        }
        $editing.Policy = $null
        $editing.Saved = if ($pol) { Get-SettingSignature $policy $read.State $read.Value } else { $null }
        switch ($read.State) {
            'Enabled' { $enabledRadio.IsChecked = $true }
            'Disabled' { $disabledRadio.IsChecked = $true }
            default { $notConfiguredRadio.IsChecked = $true }
        }
        $applyStatusTextBlock.Text = if ($pol) { "$($read.State) in $($policy.Scope)\Registry.pol" } elseif ($editing.Gpo -and $editing.PolError) { $editing.PolError } else { '' }
        if ($policy -is [GPOToolsPolicy]) {
            $editing.Policy = $policy
            $settingTitleTextBlock.Text = $policy.DisplayName
            $editing.Editor = New-PSGPOPolicyEditor -Policy $policy -Value $read.Value -OnChange { Update-RegistryPreview }
            $optionsHost.Content = $editing.Editor.Panel

            $displayNameTextBox.Text = $policy.DisplayName
            $descriptionTextBox.Text = if ($policy.Description) { $policy.Description } else { '(No description available)' }
            $scopeTextBox.Text = $policy.Scope.ToString()

            if ($policy.Registry) {
                $registryPathTextBox.Text = if ($policy.Registry.Path) { $policy.Registry.Path } else { '(No registry path defined)' }
                $registryKeyTextBox.Text = if ($policy.Registry.Key) { $policy.Registry.Key } else { '(No registry value name defined)' }

                $rows = @(Get-PSGPOPolicyRegistryRow -Policy $policy)
                if ($rows.Count -gt 0) {
                    $registryValuesList.ItemsSource = $rows
                } else {
                    $row = [AvaloniaRegistryRow]::new()
                    $row.Key = 'Information'
                    $row.Value = '(No registry value available for this policy)'
                    $registryValuesList.ItemsSource = @($row)
                }
            } else {
                $registryPathTextBox.Text = '(This policy does not use the registry)'
                $registryKeyTextBox.Text = '(No registry value name)'
                $row = [AvaloniaRegistryRow]::new()
                $row.Key = 'Information'
                $row.Value = '(This policy does not store data in the registry)'
                $registryValuesList.ItemsSource = @($row)
            }
        } else {
            $displayNameTextBox.Text = ''
            $descriptionTextBox.Text = ''
            $scopeTextBox.Text = ''
            $registryPathTextBox.Text = ''
            $registryKeyTextBox.Text = ''
            $registryValuesList.ItemsSource = $null
            $editing.Policy = $null
            $editing.Editor = $null
            $optionsHost.Content = $null
            $settingTitleTextBlock.Text = 'Select a policy in the tree'
        }
        Update-RegistryPreview
    })

    # The tree of the policies matching the search; editing a GPO with "Configured settings
    # only", the policies its Registry.pol files configure and the security settings its
    # GptTmpl.inf defines.
    function Update-PolicyTree {
        $only = $null
        if ($configuredOnlyCheckBox.IsChecked -and $editing.Gpo) {
            $only = [System.Collections.Generic.HashSet[object]]::new()
            foreach ($scope in 'Machine', 'User') {
                if (-not $editing.Pol[$scope]) { continue }
                foreach ($configured in @(Get-PSGPOConfiguredPolicy -Pol $editing.Pol[$scope] -Scope $scope)) { [void]$only.Add($configured.Policy) }
            }
            if ($editing.Template) {
                foreach ($setting in Get-PSGPOSecuritySetting) {
                    if ($editing.Template.HasValue($setting.Section, $setting.Key)) { [void]$only.Add($setting) }
                }
            }
        }
        $treeView.ItemsSource = New-PSGPOPolicyTree -Filter $searchTextBox.Text -Only $only
        if ($only -and -not @($treeView.ItemsSource).Count) {
            $breadcrumbTextBlock.Text = if ($searchTextBox.Text) { 'No configured setting matches the search' } else { 'This GPO configures no setting' }
        }
    }
    $configuredOnlyCheckBox.add_IsCheckedChanged({ Update-PolicyTree })

    # The security settings do not come from the ADMX files: the tree always has them.
    Update-PolicyTree
    if ([GPOToolsUtility]::Policies.Count -eq 0) {
        Write-Warning 'No ADMX policy loaded: run Initialize-PSGPOAdmx before Show-GPOManagerAvalonia for the Administrative Templates.'
        $breadcrumbTextBlock.Text = 'No ADMX policy loaded (Initialize-PSGPOAdmx): only the security settings are shown'
    }

    $searchButton.Add_Click({ Update-PolicyTree })
    $searchTextBox.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            Update-PolicyTree
        }
    })

    # --- Group Policy Management view --------------------------------------------------------

    function Show-View {
        param([ValidateSet('Management', 'Editor')][string]$View)
        $managementView.IsVisible = $View -eq 'Management'
        $editorView.IsVisible = $View -eq 'Editor'
        $managementButton.IsVisible = $View -eq 'Editor'
        $browseAdmxButton.IsVisible = $View -eq 'Management'
        $searchPanel.IsVisible = $View -eq 'Editor'
        $subtitleTextBlock.Text = if ($View -eq 'Management') {
            if (-not $Directory) { 'Group Policy Management' }
            elseif ($Directory.IsDemonstration) { "Group Policy Management - $($Directory.DomainName) (demonstration)" }
            elseif ($Directory -is [GPOToolsLdapDirectory]) {
                "Group Policy Management - $($Directory.DomainName) ($($Directory.ServerType))$(if ($Directory.Account) { " - connected as $($Directory.Account)" })"
            }
            elseif ($Directory.IsReadOnly) { "Group Policy Management - $($Directory.DomainName) (read-only)" }
            else { "Group Policy Management - $($Directory.DomainName)" }
        } elseif ($editing.Gpo) { "Editing the GPO $($editing.Gpo.DisplayName)" } else { 'Explore and manage Group Policy Objects' }
    }

    # Opens the policy editor on a GPO ($null: browse the ADMX policies, outside any GPO).
    function Open-GpoEditor {
        param([GPOToolsGpo]$Gpo)
        $editing.Gpo = $Gpo
        # The settings of the GPO: its Registry.pol for each scope (empty when it has none).
        $editing.Pol = @{}
        $editing.Template = $null
        $editing.PolError = $null
        if ($Gpo) {
            try {
                foreach ($scope in 'Machine', 'User') {
                    $editing.Pol[$scope] = [GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($Gpo, $scope))
                }
                # Its security settings: GptTmpl.inf, a new empty template when the GPO has none.
                $editing.Template = [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($Gpo))
            } catch {
                $editing.PolError = "The settings of the GPO cannot be read: $($_.Exception.GetBaseException().Message)"
                $editing.Pol = @{}
                $editing.Template = $null
            }
        }
        $treeView.SelectedItem = $null
        # The filter on the configured settings only applies to a GPO; rebuilt for this one.
        $configuredOnlyCheckBox.IsVisible = $null -ne $Gpo
        if (-not $Gpo -and $configuredOnlyCheckBox.IsChecked) { $configuredOnlyCheckBox.IsChecked = $false }
        elseif ($configuredOnlyCheckBox.IsChecked) { Update-PolicyTree }
        $editingBanner.IsVisible = $null -ne $Gpo
        $editingGpoTextBlock.Text = if (-not $Gpo) { '' }
            elseif ($editing.PolError) { "Editing the GPO '$($Gpo.DisplayName)' [$($Directory.DomainName)]: $($editing.PolError)" }
            else { "Editing the GPO '$($Gpo.DisplayName)' [$($Directory.DomainName)]" }
        Update-ApplyButton
        Show-View 'Editor'
    }

    # Keys of the expanded nodes, to keep them expanded when the tree is rebuilt.
    function Get-ExpandedKey {
        $keys = [System.Collections.Generic.HashSet[string]]::new()
        $stack = [System.Collections.Generic.Stack[object]]::new()
        foreach ($root in @($domainTreeView.ItemsSource)) { if ($root) { $stack.Push($root) } }
        while ($stack.Count) {
            $node = $stack.Pop()
            if ($node.IsExpanded) { [void]$keys.Add("$(Get-PSGPODirectoryNodeKey $node)") }
            foreach ($child in $node.Children) { $stack.Push($child) }
        }
        , $keys
    }

    # Rebuilds the tree and selects the first node whose Tag is $Select, its parents expanded.
    function Update-DirectoryTree {
        param($Select)
        $keys = Get-ExpandedKey
        if ($null -ne $Select) {
            $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys
            $target = $null
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($root in $roots) { $stack.Push($root) }
            while ($stack.Count -and -not $target) {
                $node = $stack.Pop()
                if ([object]::ReferenceEquals($node.Tag, $Select)) { $target = $node }
                foreach ($child in $node.Children) { $stack.Push($child) }
            }
            for ($parent = $target.Parent; $parent; $parent = $parent.Parent) { [void]$keys.Add("$(Get-PSGPODirectoryNodeKey $parent)") }
        }
        $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys
        $domainTreeView.ItemsSource = $roots
        if ($null -ne $Select) {
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($root in $roots) { $stack.Push($root) }
            while ($stack.Count) {
                $node = $stack.Pop()
                if ([object]::ReferenceEquals($node.Tag, $Select)) { $domainTreeView.SelectedItem = $node; break }
                foreach ($child in $node.Children) { $stack.Push($child) }
            }
        }
    }

    # New GPO form: linked to $Som, or only created in the domain when $Som is $null.
    $newGpo = @{ Som = $null }
    function Open-NewGpoForm {
        param([GPOToolsSom]$Som)
        $newGpo.Som = $Som
        $newGpoTitleTextBlock.Text = if ($Som) { "New GPO in $($Directory.DomainName), linked to $($Som.Name)" } else { "New GPO in $($Directory.DomainName)" }
        $newGpoNameTextBox.Text = 'New Group Policy Object'
        $newGpoErrorTextBlock.Text = ''
        $directoryResultTextBlock.Text = ''
        $newGpoStatusComboBox.SelectedIndex = 0
        $newGpoGroupsCheckBox.IsChecked = $false
        # The groups go to the users container by default, or to an OU.
        $containers = [System.Collections.Generic.List[string]]::new()
        $containers.Add($Directory.GetUsersContainer())
        $stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        foreach ($child in @($Directory.Domain.Children | Sort-Object Name -Descending)) { $stack.Push($child) }
        while ($stack.Count) {
            $som = $stack.Pop()
            $containers.Add($som.DistinguishedName)
            foreach ($child in @($som.Children | Sort-Object Name -Descending)) { $stack.Push($child) }
        }
        $newGpoGroupsContainerComboBox.ItemsSource = $containers
        $newGpoGroupsContainerComboBox.SelectedIndex = 0
        Update-NewGpoGroupText
        $newGpoPanel.IsVisible = $true
        [void]$newGpoNameTextBox.Focus()
        $newGpoNameTextBox.SelectAll()
    }

    # What the security filtering groups of the new GPO will be.
    function Update-NewGpoGroupText {
        try {
            $apply = Get-PSGPOFilteringGroupName -Prefix APPLY -GpoName $newGpoNameTextBox.Text
            $deny = Get-PSGPOFilteringGroupName -Prefix DENY -GpoName $newGpoNameTextBox.Text
            $newGpoGroupsTextBlock.Text = "$apply`: only its members apply the GPO (add the computers or users to it). $deny`: its members never apply it. Authenticated Users keep reading the GPO."
        } catch {
            $newGpoGroupsTextBlock.Text = $_.Exception.Message
        }
    }

    # Creates the GPO, then sets its status and its security filtering groups, then links it.
    # It is not linked when its security filtering failed: it would apply to every computer and
    # user. What failed after the creation is said under the details of the GPO.
    function Submit-NewGpo {
        try {
            $gpo = $Directory.NewGpo($newGpoNameTextBox.Text)
        } catch {
            $newGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $done = [System.Collections.Generic.List[string]]::new()
        $problems = [System.Collections.Generic.List[string]]::new()
        $done.Add("GPO '$($gpo.DisplayName)' created.")
        $flags = [int]"$($newGpoStatusComboBox.SelectedItem.Tag)"
        if ($flags) {
            try {
                $Directory.SetGpoStatus($gpo, $flags)
                $done.Add("GPO status: $($gpo.GetStatus()).")
            } catch {
                $problems.Add("Its status is not set: $($_.Exception.GetBaseException().Message)")
            }
        }
        $filtered = $true
        if ($newGpoGroupsCheckBox.IsChecked) {
            try {
                $container = "$($newGpoGroupsContainerComboBox.SelectedItem)"
                $groups = $Directory.NewFilteringGroups($gpo, $container)
                $done.Add("Security filtering groups $(@($groups.Name) -join ' and ') created in $container.")
            } catch {
                $filtered = $false
                $problems.Add("Its security filtering groups are not set: $($_.Exception.GetBaseException().Message)")
            }
        }
        $select = $gpo
        if ($newGpo.Som) {
            if (-not $filtered) {
                $problems.Add("It is not linked to $($newGpo.Som.Name), so that it does not apply to everyone: link it once its security filtering is set.")
            } else {
                try {
                    $select = $Directory.NewLink($newGpo.Som, $gpo)
                    $done.Add("Linked to $($newGpo.Som.Name).")
                } catch {
                    $problems.Add("It is not linked to $($newGpo.Som.Name): $($_.Exception.GetBaseException().Message)")
                }
            }
        }
        $newGpoPanel.IsVisible = $false
        Update-DirectoryTree -Select $select
        Show-DirectoryResult -Text ((@($done) + @($problems)) -join [Environment]::NewLine) -Problem:($problems.Count -gt 0)
    }

    # What a change of the directory did, under the details; in red when something failed.
    function Show-DirectoryResult {
        param([string]$Text, [switch]$Problem)
        $directoryResultTextBlock.Text = $Text
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
        $deleteLinkTextBlock.Text = "Delete the link of the GPO '$($node.Tag.GetDisplayName())' to $($node.Parent.Tag.Name)? " +
            'The GPO itself is not deleted: it stays in Group Policy Objects, with its other links.'
        $newGpoPanel.IsVisible = $false
        $directoryResultTextBlock.Text = ''
        $deleteLinkPanel.IsVisible = $true
    }

    function Submit-DeleteLink {
        $som = $deleteLink.Som
        $link = $deleteLink.Link
        if (-not $som -or -not $link) { return }
        try {
            $Directory.RemoveLink($som, $link)
        } catch {
            $deleteLinkPanel.IsVisible = $false
            Show-DirectoryResult -Text "The link of the GPO '$($link.GetDisplayName())' to $($som.Name) is not deleted: $($_.Exception.GetBaseException().Message)" -Problem
            return
        }
        $deleteLinkPanel.IsVisible = $false
        Update-DirectoryTree -Select $som
        Show-DirectoryResult -Text "Link of the GPO '$($link.GetDisplayName())' to $($som.Name) deleted."
    }

    # Settings tab of the selected GPO: its Registry.pol files read once per version of the GPO.
    $settingsCache = @{}
    function Update-SettingsTab {
        $gpo = Get-SelectedGpo
        $settingsTab.IsVisible = [bool]$gpo
        if (-not $gpo) {
            if ($directoryTabs.SelectedItem -eq $settingsTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $settingsTab) { return }

        $cached = $settingsCache["$($gpo.Id)"]
        if (-not $cached -or $cached.Version -ne $gpo.Version) {
            $cached = @{ Version = $gpo.Version; Machine = @(); User = @(); Error = $null }
            try {
                foreach ($scope in 'Machine', 'User') {
                    $pol = [GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($gpo, $scope))
                    $cached[$scope] = @(Get-PSGPOConfiguredSetting -Pol $pol -Scope $scope)
                }
                # Security settings first, as GPMC lists Windows Settings before Administrative Templates.
                $template = [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($gpo))
                $cached['Machine'] = @(Get-PSGPOConfiguredSecuritySetting -Template $template) + $cached['Machine']
            } catch {
                $cached.Error = "The settings of the GPO cannot be read: $($_.Exception.GetBaseException().Message)"
            }
            $settingsCache["$($gpo.Id)"] = $cached
        }
        $settingsStatusTextBlock.Text = if ($cached.Error) { $cached.Error }
            elseif ([GPOToolsUtility]::Policies.Count -eq 0) { 'No ADMX loaded (Initialize-PSGPOAdmx): the values are shown as Extra Registry Settings.' }
            else { "Settings of $($gpo.DisplayName) (version: computer $($gpo.GetComputerVersion()), user $($gpo.GetUserVersion()))" }
        $computerState = if ($gpo.Flags -band 2) { 'Disabled' } else { 'Enabled' }
        $userState = if ($gpo.Flags -band 1) { 'Disabled' } else { 'Enabled' }
        $computerSettingsHeader.Text = "Computer Configuration ($computerState)$(if (-not $cached.Machine.Count) { ': no settings defined' })"
        $userSettingsHeader.Text = "User Configuration ($userState)$(if (-not $cached.User.Count) { ': no settings defined' })"
        $computerSettingsList.ItemsSource = $cached.Machine
        $userSettingsList.ItemsSource = $cached.User
    }
    $directoryTabs.add_SelectionChanged({
        param($sender, $e)
        # Only the selection of a tab, not of a control inside one.
        if ([object]::ReferenceEquals($e.Source, $directoryTabs)) { Update-SettingsTab }
    })

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

        $detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $item
        $directoryTitleTextBlock.Text = $detail.Title
        $directoryPropertiesList.ItemsSource = $detail.Properties
        $linksHeaderTextBlock.Text = $detail.LinksHeader
        $linksHeaderTextBlock.IsVisible = [bool]$detail.LinksHeader
        $linksList.ItemsSource = $detail.Links
        $editGpoButton.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit
        $newGpoPanel.IsVisible = $false
        $directoryResultTextBlock.Text = ''
        $deleteLinkPanel.IsVisible = $false

        # Context menu of the selected node, as in GPMC.
        # A read-only directory (read over LDAP) cannot create GPOs yet.
        # And what the account may do there (its delegations).
        $createLinkedGpoMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo -and $item.CanLink
        $newGpoMenuItem.IsVisible = $item -eq 'GroupPolicyObjects' -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo
        $editGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit
        $deleteLinkMenuItem.IsVisible = $item -is [GPOToolsGpoLink] -and -not $Directory.IsReadOnly -and $selected.Parent.Tag.CanLink
        Update-SettingsTab
    })
    # Nothing to offer on this node: do not open an empty menu.
    (Get-PSGPOAvaloniaControl $window 'domainContextMenu').add_Opening({
        param($sender, $e)
        if (-not ($createLinkedGpoMenuItem.IsVisible -or $newGpoMenuItem.IsVisible -or $editGpoMenuItem.IsVisible -or $deleteLinkMenuItem.IsVisible) -or
            -not $domainTreeView.SelectedItem) { $e.Cancel = $true }
    })

    $createLinkedGpoMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsSom]) { Open-NewGpoForm -Som $item } })
    $newGpoMenuItem.Add_Click({ Open-NewGpoForm -Som $null })
    $editGpoMenuItem.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $editGpoButton.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $domainTreeView.add_DoubleTapped({ $gpo = Get-SelectedGpo; if ($gpo -and $gpo.CanEdit) { Open-GpoEditor -Gpo $gpo } })
    $newGpoCreateButton.Add_Click({ Submit-NewGpo })
    $newGpoCancelButton.Add_Click({ $newGpoPanel.IsVisible = $false })
    $deleteLinkMenuItem.Add_Click({ Open-DeleteLinkForm })
    $deleteLinkConfirmButton.Add_Click({ Submit-DeleteLink })
    $deleteLinkCancelButton.Add_Click({ $deleteLinkPanel.IsVisible = $false })
    $newGpoGroupsCheckBox.add_IsCheckedChanged({ $newGpoGroupsPanel.IsVisible = [bool]$newGpoGroupsCheckBox.IsChecked })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $newGpoNameTextBox.add_PropertyChanged({
        param($sender, $e)
        if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty) { Update-NewGpoGroupText }
    })
    $newGpoNameTextBox.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-NewGpo }
        elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $newGpoPanel.IsVisible = $false }
    })
    $managementButton.Add_Click({ Show-View 'Management' })
    $browseAdmxButton.Add_Click({ Open-GpoEditor -Gpo $null })

    $directoryHint = if ($Directory.IsReadOnly) { "Read-only: $($Directory.Source)" } else { 'Right-click a domain or an OU to create a GPO' }
    $directoryBreadcrumbTextBlock.Text = $directoryHint
    $directoryEmptyTextBlock.IsVisible = -not $Directory
    $demoBanner.IsVisible = [bool]$Directory.IsDemonstration
    $domainTreeView.IsVisible = [bool]$Directory
    if ($DirectoryError) {
        $directoryEmptyTextBlock.Text = "The domain could not be read.`n`n$DirectoryError"
        $directoryEmptyTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
        $directoryBreadcrumbTextBlock.Text = 'Domain not read'
    }
    if ($Directory) { Update-DirectoryTree }
    Show-View $StartView

    $statusBarList.ItemsSource = @(Get-PSGPOStatusBarItem -Platform (Get-PSGPOPlatform) -Directory $Directory -DirectoryError $DirectoryError)

    # Avalonia's SetupWithoutStarting() does not run a message loop by itself; drive one
    # manually and stop it when the window closes so the call blocks until then.
    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
        [Avalonia.Threading.Dispatcher]::UIThread.Post(
            [System.Action] { $cts.Cancel() },
            [Avalonia.Threading.DispatcherPriority]::Background
        )
    })

    $window.Show()

    # A hashtable, because assigning a variable inside the posted action would only set a child-scope copy.
    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Editing = $editing; Clipboard = $clipboard; Directory = $Directory }
        foreach ($name in 'treeView', 'themeToggleButton', 'breadcrumbTextBlock', 'searchTextBox', 'searchButton', 'configuredOnlyCheckBox',
            'displayNameTextBox', 'descriptionTextBox', 'scopeTextBox', 'registryPathTextBox',
            'registryKeyTextBox', 'registryValuesList', 'settingTitleTextBlock', 'previewEmptyTextBlock', 'detailsTabs', 'copyNameMenuItem', 'copyRegistryMenuItem', 'copyCommandMenuItem',
            'notConfiguredRadio', 'enabledRadio', 'disabledRadio', 'optionsHost', 'settingErrorTextBlock', 'registryPreviewList',
            'themeToggleIcon', 'themeToggleText', 'subtitleTextBlock', 'managementButton', 'browseAdmxButton', 'searchPanel', 'managementView', 'editorView',
            'editingBanner', 'editingGpoTextBlock', 'applyPanel', 'applySettingButton', 'applyStatusTextBlock', 'previewHeaderTextBlock', 'directoryTabs', 'settingsTab', 'settingsStatusTextBlock', 'computerSettingsHeader', 'computerSettingsList', 'userSettingsHeader', 'userSettingsList', 'demoBanner', 'demoBannerTextBlock', 'statusBar', 'statusBarList', 'domainTreeView', 'domainContextMenu', 'directoryEmptyTextBlock', 'directoryBreadcrumbTextBlock',
            'directoryTitleTextBlock', 'directoryPropertiesList', 'linksHeaderTextBlock', 'linksList', 'createLinkedGpoMenuItem',
            'newGpoMenuItem', 'editGpoMenuItem', 'editGpoButton', 'newGpoPanel', 'newGpoTitleTextBlock', 'newGpoNameTextBox',
            'newGpoErrorTextBlock', 'newGpoCreateButton', 'newGpoCancelButton', 'newGpoStatusComboBox', 'newGpoGroupsCheckBox', 'newGpoGroupsPanel',
            'newGpoGroupsTextBlock', 'newGpoGroupsContainerComboBox', 'directoryResultTextBlock', 'deleteLinkMenuItem', 'deleteLinkPanel',
            'deleteLinkTextBlock', 'deleteLinkConfirmButton', 'deleteLinkCancelButton') {
            $controls[$name] = Get-PSGPOAvaloniaControl $window $name
        }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
            try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { $window.Close() }
        })
    }

    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        # Expected: the loop exits by cancellation once the window is closed.
    }

    if ($onShownState.Error) { throw $onShownState.Error }
}
