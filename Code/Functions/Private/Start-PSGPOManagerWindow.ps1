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

    # The configuration of PSGPOTools for the domain shown (SYSVOL of its domain controller).
    Use-PSGPODomainConfiguration -Directory $Directory -Force
    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse($xaml)

    $treeView = Get-PSGPOAvaloniaControl $window 'treeView'
    $themeToggleButton = Get-PSGPOAvaloniaControl $window 'themeToggleButton'
    $configurationButton = Get-PSGPOAvaloniaControl $window 'configurationButton'
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
    $linkGpoMenuItem = Get-PSGPOAvaloniaControl $window 'linkGpoMenuItem'
    $deleteGpoMenuItem = Get-PSGPOAvaloniaControl $window 'deleteGpoMenuItem'
    $deleteGpoPanel = Get-PSGPOAvaloniaControl $window 'deleteGpoPanel'
    $deleteGpoTextBlock = Get-PSGPOAvaloniaControl $window 'deleteGpoTextBlock'
    $deleteGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'deleteGpoConfirmButton'
    $deleteGpoCancelButton = Get-PSGPOAvaloniaControl $window 'deleteGpoCancelButton'
    $restoreDeletedGpoMenuItem = Get-PSGPOAvaloniaControl $window 'restoreDeletedGpoMenuItem'
    $restoreDeletedGpoButton = Get-PSGPOAvaloniaControl $window 'restoreDeletedGpoButton'
    $restoreGpoPanel = Get-PSGPOAvaloniaControl $window 'restoreGpoPanel'
    $restoreGpoTextBlock = Get-PSGPOAvaloniaControl $window 'restoreGpoTextBlock'
    $restoreGpoLinkCheckBox = Get-PSGPOAvaloniaControl $window 'restoreGpoLinkCheckBox'
    $restoreGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'restoreGpoConfirmButton'
    $restoreGpoCancelButton = Get-PSGPOAvaloniaControl $window 'restoreGpoCancelButton'
    $newGpoTemplateComboBox = Get-PSGPOAvaloniaControl $window 'newGpoTemplateComboBox'
    $historyNotesTemplateCheckBox = Get-PSGPOAvaloniaControl $window 'historyNotesTemplateCheckBox'
    $linkGpoPanel = Get-PSGPOAvaloniaControl $window 'linkGpoPanel'
    $linkGpoTitleTextBlock = Get-PSGPOAvaloniaControl $window 'linkGpoTitleTextBlock'
    $linkGpoFilterTextBox = Get-PSGPOAvaloniaControl $window 'linkGpoFilterTextBox'
    $linkGpoList = Get-PSGPOAvaloniaControl $window 'linkGpoList'
    $linkGpoErrorTextBlock = Get-PSGPOAvaloniaControl $window 'linkGpoErrorTextBlock'
    $linkGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'linkGpoConfirmButton'
    $linkGpoCancelButton = Get-PSGPOAvaloniaControl $window 'linkGpoCancelButton'

    $applyPanel = Get-PSGPOAvaloniaControl $window 'applyPanel'
    $directoryTabs = Get-PSGPOAvaloniaControl $window 'directoryTabs'
    $settingsTab = Get-PSGPOAvaloniaControl $window 'settingsTab'
    $historyTab = Get-PSGPOAvaloniaControl $window 'historyTab'
    $historyPathTextBox = Get-PSGPOAvaloniaControl $window 'historyPathTextBox'
    $historyBackupButton = Get-PSGPOAvaloniaControl $window 'historyBackupButton'
    $historyBackupAllButton = Get-PSGPOAvaloniaControl $window 'historyBackupAllButton'
    $historyStatusTextBlock = Get-PSGPOAvaloniaControl $window 'historyStatusTextBlock'
    $historyTimelineScrollViewer = Get-PSGPOAvaloniaControl $window 'historyTimelineScrollViewer'
    $historyTimelineList = Get-PSGPOAvaloniaControl $window 'historyTimelineList'
    $historyCompareTextBlock = Get-PSGPOAvaloniaControl $window 'historyCompareTextBlock'
    $historyChangesList = Get-PSGPOAvaloniaControl $window 'historyChangesList'
    $historyRestoreButton = Get-PSGPOAvaloniaControl $window 'historyRestoreButton'
    $historyRestorePanel = Get-PSGPOAvaloniaControl $window 'historyRestorePanel'
    $historyRestoreTextBlock = Get-PSGPOAvaloniaControl $window 'historyRestoreTextBlock'
    $historyRestoreConfirmButton = Get-PSGPOAvaloniaControl $window 'historyRestoreConfirmButton'
    $historyRestoreCancelButton = Get-PSGPOAvaloniaControl $window 'historyRestoreCancelButton'
    $historyCommentTextBox = Get-PSGPOAvaloniaControl $window 'historyCommentTextBox'
    $historyDriftBorder = Get-PSGPOAvaloniaControl $window 'historyDriftBorder'
    $historyDriftTextBlock = Get-PSGPOAvaloniaControl $window 'historyDriftTextBlock'
    $historyDriftButton = Get-PSGPOAvaloniaControl $window 'historyDriftButton'
    $historyNotesPanel = Get-PSGPOAvaloniaControl $window 'historyNotesPanel'
    $historyNotesInfoTextBlock = Get-PSGPOAvaloniaControl $window 'historyNotesInfoTextBlock'
    $historyNotesCommentTextBox = Get-PSGPOAvaloniaControl $window 'historyNotesCommentTextBox'
    $historyNotesLabelsTextBox = Get-PSGPOAvaloniaControl $window 'historyNotesLabelsTextBox'
    $historyNotesApprovedCheckBox = Get-PSGPOAvaloniaControl $window 'historyNotesApprovedCheckBox'
    $historyNotesSaveButton = Get-PSGPOAvaloniaControl $window 'historyNotesSaveButton'
    $settingsStatusTextBlock = Get-PSGPOAvaloniaControl $window 'settingsStatusTextBlock'
    $computerSettingsHeader = Get-PSGPOAvaloniaControl $window 'computerSettingsHeader'
    $computerSettingsList = Get-PSGPOAvaloniaControl $window 'computerSettingsList'
    $userSettingsHeader = Get-PSGPOAvaloniaControl $window 'userSettingsHeader'
    $userSettingsList = Get-PSGPOAvaloniaControl $window 'userSettingsList'
    $applySettingButton = Get-PSGPOAvaloniaControl $window 'applySettingButton'
    $applyStatusTextBlock = Get-PSGPOAvaloniaControl $window 'applyStatusTextBlock'

    $detailsTabs = Get-PSGPOAvaloniaControl $window 'detailsTabs'
    $detailsTitleTextBlock = Get-PSGPOAvaloniaControl $window 'detailsTitleTextBlock'
    $preferencesPanel = Get-PSGPOAvaloniaControl $window 'preferencesPanel'
    $preferencesTitleTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesTitleTextBlock'
    $preferencesInfoTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesInfoTextBlock'
    $preferencesToolbar = Get-PSGPOAvaloniaControl $window 'preferencesToolbar'
    $preferencesNewTypeComboBox = Get-PSGPOAvaloniaControl $window 'preferencesNewTypeComboBox'
    $preferencesNewButton = Get-PSGPOAvaloniaControl $window 'preferencesNewButton'
    $preferencesEditButton = Get-PSGPOAvaloniaControl $window 'preferencesEditButton'
    $preferencesDeleteButton = Get-PSGPOAvaloniaControl $window 'preferencesDeleteButton'
    $preferencesUpButton = Get-PSGPOAvaloniaControl $window 'preferencesUpButton'
    $preferencesDownButton = Get-PSGPOAvaloniaControl $window 'preferencesDownButton'
    $preferencesStatusTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesStatusTextBlock'
    $preferencesEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesEmptyTextBlock'
    $preferencesList = Get-PSGPOAvaloniaControl $window 'preferencesList'
    $preferencesDeletePanel = Get-PSGPOAvaloniaControl $window 'preferencesDeletePanel'
    $preferencesDeleteTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesDeleteTextBlock'
    $preferencesDeleteConfirmButton = Get-PSGPOAvaloniaControl $window 'preferencesDeleteConfirmButton'
    $preferencesDeleteCancelButton = Get-PSGPOAvaloniaControl $window 'preferencesDeleteCancelButton'
    $preferencesFormBorder = Get-PSGPOAvaloniaControl $window 'preferencesFormBorder'
    $preferencesFormTitleTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesFormTitleTextBlock'
    $preferencesFormHost = Get-PSGPOAvaloniaControl $window 'preferencesFormHost'
    $preferencesFormErrorTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesFormErrorTextBlock'
    $preferencesSaveButton = Get-PSGPOAvaloniaControl $window 'preferencesSaveButton'
    $preferencesCancelButton = Get-PSGPOAvaloniaControl $window 'preferencesCancelButton'

    # Options form of the selected policy (New-PSGPOPolicyEditor), the policy it edits and the
    # GPO opened from the Group Policy Management view ($null: browsing the ADMX policies).
    # Pol: the Registry.pol of the GPO by scope; Saved: the registry values of the setting of the
    # selected policy in it, compared with the form to know whether there is something to apply.
    # Security: the selected security setting, Template: the GptTmpl.inf of the GPO (security
    # settings); Saved is then the raw value of the setting in it.
    $editing = @{ Policy = $null; Security = $null; Editor = $null; Gpo = $null; Pol = @{}; PolError = $null; Template = $null; Saved = $null; Preferences = @{} }
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

    # --- Preferences ([MS-GPPREF]) of the edited GPO --------------------------------------------

    # The type shown, the item edited and its form; the files read once per GPO edited.
    $preferences = @{ Node = $null; File = $null; Item = $null; Type = $null; Form = $null }

    function Set-PreferenceStatus {
        param([string]$Text, [switch]$Problem)
        $preferencesStatusTextBlock.Text = $Text
        if ($Problem) { $preferencesStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $preferencesStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # The file of a preference type of the GPO: read once; an empty one when the GPO has none.
    function Get-PreferenceFile {
        param([GPOToolsPreferenceNode]$Node)
        $key = "$($Node.Scope)|$($Node.Extension.Id)"
        if (-not $editing.Preferences.ContainsKey($key)) {
            $bytes = $Directory.ReadPreferenceFile($editing.Gpo, $Node.Scope, $Node.Extension.Path)
            $editing.Preferences[$key] = if ($bytes) { [GPOToolsPreferenceFile]::Parse($bytes) } else { [GPOToolsPreferenceFile]::Create($Node.Extension.Root, $Node.Extension.RootClsid) }
        }
        $editing.Preferences[$key]
    }

    function Test-PreferenceEditable {
        $editing.Gpo -and $editing.Gpo.CanEdit -and -not $Directory.IsReadOnly -and $preferences.File
    }

    function Update-PreferenceButtons {
        $row = $preferencesList.SelectedItem
        $editable = Test-PreferenceEditable
        $preferencesNewButton.IsEnabled = $editable -and $null -ne $preferencesNewTypeComboBox.SelectedItem
        $preferencesEditButton.IsEnabled = $editable -and $row -and $row.Item.Editable
        $preferencesDeleteButton.IsEnabled = $editable -and $row
        $preferencesUpButton.IsEnabled = $editable -and $row -and -not $row.Item.Collection
        $preferencesDownButton.IsEnabled = $editable -and $row -and -not $row.Item.Collection
    }

    # The items of the type selected in the tree, for the edited GPO.
    function Show-PreferenceType {
        param([GPOToolsPreferenceNode]$Node, [string]$Status, [string]$SelectUid)
        $preferences.Node = $Node
        $preferences.File = $null
        $extension = $Node.Extension
        $scopeLabel = if ($Node.Scope -eq 'Machine') { 'Computer Configuration' } else { 'User Configuration' }
        $preferencesTitleTextBlock.Text = "$($extension.Name) ($scopeLabel)"
        $types = @($extension.Items | Where-Object { $_.Properties -and -not $_.IsCollection })
        $preferencesInfoTextBlock.Text = "Preferences > $($extension.Group) > $($extension.Name): Preferences\$($extension.Path) in the $($Node.Scope) folder of the GPO, client-side extension $($extension.Cse)." +
            $(if (-not $types.Count) { ' Its items are created with GPMC: the console shows them, keeps them as they are and deletes them.' })
        $preferencesFormBorder.IsVisible = $false
        $preferencesDeletePanel.IsVisible = $false
        $preferencesNewTypeComboBox.ItemsSource = @($types.Label)
        $preferencesNewTypeComboBox.SelectedIndex = if ($types.Count) { 0 } else { -1 }
        $preferencesNewTypeComboBox.IsVisible = $types.Count -gt 0
        $preferencesNewButton.IsVisible = $types.Count -gt 0
        $rows = @()
        $problem = $null
        if (-not $editing.Gpo) {
            $preferencesEmptyTextBlock.Text = 'Edit a GPO (Group Policy Management view) to see and configure its preferences.'
        } else {
            try {
                $preferences.File = Get-PreferenceFile $Node
                $rows = @(foreach ($item in @(Get-PSGPOPreferenceItem -File $preferences.File -Extension $extension)) {
                        $row = [AvaloniaPreferenceRow]::new()
                        $row.Name = "$(if ($item.Collection) { "$($item.Collection) > " })$(if ($item.Name) { $item.Name } else { $item.Label })"
                        $row.Summary = Get-PSGPOPreferenceSummary -Item $item
                        $row.Flags = (@(
                                if ($item.Disabled) { 'Disabled' }
                                if ($item.FilterCount) { "$($item.FilterCount) targeting filter(s)" }
                                if ($item.HasPassword) { 'Stores a password readable by any user of the domain (MS14-025)' }
                                if (-not $item.Editable) { 'Edited with GPMC' }) -join ' - ')
                        $row.Item = $item
                        $row
                    })
                $preferencesEmptyTextBlock.Text = if ($rows.Count) { '' } else { "This GPO has no $($extension.Name) item for the $(if ($Node.Scope -eq 'Machine') { 'computers' } else { 'users' })." }
            } catch {
                $problem = "The preferences cannot be read: $($_.Exception.GetBaseException().Message)"
                $preferencesEmptyTextBlock.Text = ''
            }
        }
        $preferencesEmptyTextBlock.IsVisible = [bool]$preferencesEmptyTextBlock.Text
        $preferencesList.ItemsSource = $rows
        if ($SelectUid) { $preferencesList.SelectedItem = $rows | Where-Object { $_.Item.Uid -eq $SelectUid } | Select-Object -First 1 }
        if ($problem) { Set-PreferenceStatus $problem -Problem } else { Set-PreferenceStatus $Status }
        Update-PreferenceButtons
    }

    # Applies a change to a copy of the file, writes it to the GPO, then shows the items again;
    # returns the error message when the change or the write failed (nothing is kept then).
    function Save-PreferenceFile {
        param([scriptblock]$Change, [string]$Done, [string]$SelectUid)
        $node = $preferences.Node
        $copy = [GPOToolsPreferenceFile]::Parse($preferences.File.ToBytes())
        try {
            $uid = & $Change $copy
            $Directory.WritePreferenceFile($editing.Gpo, $node.Scope, $node.Extension.Path, $copy.ToBytes(), $node.Extension.Cse, $node.Extension.Tool)
        } catch {
            return $_.Exception.GetBaseException().Message
        }
        $editing.Preferences["$($node.Scope)|$($node.Extension.Id)"] = $copy
        $settingsCache.Remove("$($editing.Gpo.Id)")
        $version = if ($node.Scope -eq 'Machine') { $editing.Gpo.GetComputerVersion() } else { $editing.Gpo.GetUserVersion() }
        Show-PreferenceType -Node $node -Status "$Done in Preferences\$($node.Extension.Path) ($($node.Scope) version $version)." -SelectUid $(if ($uid) { $uid } else { $SelectUid })
        $null
    }

    function Find-PreferenceElement {
        param([GPOToolsPreferenceFile]$File, [string]$Uid)
        $File.Document.SelectSingleNode("//*[@uid='$Uid']")
    }

    function Open-PreferenceForm {
        param($Type, $Item)
        $preferences.Type = $Type
        $preferences.Item = $Item
        $preferences.Form = New-PSGPOPreferenceForm -Type $Type -Scope $preferences.Node.Scope -Item $Item
        $preferencesFormHost.Content = $preferences.Form.Panel
        $preferencesFormTitleTextBlock.Text = if ($Item) { "$($Type.Label): $($Item.Name)" } else { "New $($Type.Label)" }
        $preferencesFormErrorTextBlock.Text = ''
        $preferencesDeletePanel.IsVisible = $false
        $preferencesFormBorder.IsVisible = $true
    }

    $preferencesList.add_SelectionChanged({ Update-PreferenceButtons })
    $preferencesNewTypeComboBox.add_SelectionChanged({ Update-PreferenceButtons })
    $preferencesNewButton.Add_Click({
        $type = @($preferences.Node.Extension.Items | Where-Object { $_.Properties -and -not $_.IsCollection })[$preferencesNewTypeComboBox.SelectedIndex]
        if ($type) { Open-PreferenceForm -Type $type -Item $null }
    })
    $preferencesEditButton.Add_Click({
        $row = $preferencesList.SelectedItem
        if ($row -and $row.Item.Editable) { Open-PreferenceForm -Type $row.Item.Type -Item $row.Item }
    })
    $preferencesList.add_DoubleTapped({
        $row = $preferencesList.SelectedItem
        if ($row -and $row.Item.Editable -and (Test-PreferenceEditable)) { Open-PreferenceForm -Type $row.Item.Type -Item $row.Item }
    })
    $preferencesCancelButton.Add_Click({ $preferencesFormBorder.IsVisible = $false })
    $preferencesSaveButton.Add_Click({
        $type = $preferences.Type
        $item = $preferences.Item
        try {
            $values = & $preferences.Form.GetValues
            $common = & $preferences.Form.GetCommon
        } catch {
            $preferencesFormErrorTextBlock.Text = $_.Exception.Message
            return
        }
        $problem = if ($item) {
            Save-PreferenceFile -Done "$($type.Label) saved" -SelectUid $item.Uid -Change {
                param($Copy)
                Set-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $item.Uid) -Type $type -Values $values -Common $common
            }
        } else {
            Save-PreferenceFile -Done "$($type.Label) created" -Change {
                param($Copy)
                (New-PSGPOPreferenceItem -File $Copy -Type $type -Values $values -Common $common).GetAttribute('uid')
            }
        }
        if ($problem) { $preferencesFormErrorTextBlock.Text = $problem } else { $preferencesFormBorder.IsVisible = $false }
    })
    $preferencesDeleteButton.Add_Click({
        $row = $preferencesList.SelectedItem
        if (-not $row) { return }
        $preferencesDeleteTextBlock.Text = "Delete the item '$($row.Name)' from the GPO? The computers and users stop applying it; what it already changed stays, unless it removes itself (Remove this item when it is no longer applied)."
        $preferencesFormBorder.IsVisible = $false
        $preferencesDeletePanel.IsVisible = $true
    })
    $preferencesDeleteCancelButton.Add_Click({ $preferencesDeletePanel.IsVisible = $false })
    $preferencesDeleteConfirmButton.Add_Click({
        $row = $preferencesList.SelectedItem
        $preferencesDeletePanel.IsVisible = $false
        if (-not $row) { return }
        $problem = Save-PreferenceFile -Done "'$($row.Name)' deleted" -Change {
            param($Copy)
            Remove-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $row.Item.Uid)
            $null
        }
        if ($problem) { Set-PreferenceStatus "Not deleted: $problem" -Problem }
    })
    # Not GetNewClosure for the handlers: the functions of this window would not be found.
    function Move-PreferenceItem {
        param([string]$Direction)
        $row = $preferencesList.SelectedItem
        if (-not $row) { return }
        $problem = Save-PreferenceFile -Done "'$($row.Name)' moved $($Direction.ToLowerInvariant())" -SelectUid $row.Item.Uid -Change {
            param($Copy)
            Move-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $row.Item.Uid) -Direction $Direction
            $null
        }
        if ($problem) { Set-PreferenceStatus "Not moved: $problem" -Problem }
    }
    $preferencesUpButton.Add_Click({ Move-PreferenceItem -Direction Up })
    $preferencesDownButton.Add_Click({ Move-PreferenceItem -Direction Down })

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
        # A preference type: its items instead of the form of a policy.
        $isPreference = $policy -is [GPOToolsPreferenceNode]
        $preferencesPanel.IsVisible = $isPreference
        $detailsTabs.IsVisible = -not $isPreference
        $detailsTitleTextBlock.Text = if ($isPreference) { 'Preference Items' } else { 'Policy Details' }
        if ($isPreference) {
            $editing.Policy = $null
            $editing.Editor = $null
            Show-PreferenceType -Node $policy
            return
        }
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
            # The preference types the GPO declares (its client-side extensions).
            foreach ($scope in 'Machine', 'User') {
                $names = if ($scope -eq 'Machine') { "$($editing.Gpo.MachineExtensionNames)" } else { "$($editing.Gpo.UserExtensionNames)" }
                foreach ($extension in @(Get-PSGPOPreferenceExtension -Scope $scope)) {
                    if ($names.IndexOf($extension.Cse, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { [void]$only.Add("Preference:$scope|$($extension.Id)") }
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
        $editing.Preferences = @{}
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

    # The recycle bin and the templates: from the backups of the folder of the History tab, read
    # again when that folder changes or with -Force (after a deletion, a restore, new notes).
    $backupLists = @{ Root = $null; Deleted = @(); Templates = @() }
    function Update-BackupList {
        param([switch]$Force)
        $root = Get-HistoryRoot
        if (-not $Force -and $backupLists.Root -eq $root) { return }
        $backupLists.Root = $root
        try {
            $backupLists.Deleted = @(Get-PSGPODeletedGpoBackup -Directory $Directory -Path $root)
            $backupLists.Templates = @(Get-PSGPOTemplateBackup -Path $root)
        } catch {
            $backupLists.Deleted = @()
            $backupLists.Templates = @()
        }
    }

    # Rebuilds the tree and selects the first node whose Tag is $Select, its parents expanded.
    function Update-DirectoryTree {
        param($Select)
        Update-BackupList
        $keys = Get-ExpandedKey
        if ($null -ne $Select) {
            $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys -DeletedGpo $backupLists.Deleted
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
        $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys -DeletedGpo $backupLists.Deleted
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
    $newGpo = @{ Som = $null; Groups = $null; Templates = @() }
    function Open-NewGpoForm {
        param([GPOToolsSom]$Som)
        $newGpo.Som = $Som
        $newGpoTitleTextBlock.Text = if ($Som) { "New GPO in $($Directory.DomainName), linked to $($Som.Name)" } else { "New GPO in $($Directory.DomainName)" }
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
        $newGpoTemplateComboBox.ItemsSource = @('Empty GPO') + @(foreach ($template in $newGpo.Templates) {
                "$($template.DisplayName), backup of $(Format-HistoryDate $template.BackedUp)$(if ($template.Domain -and $template.Domain -ne $Directory.DomainName) { " ($($template.Domain))" })"
            })
        $newGpoTemplateComboBox.SelectedIndex = 0
        $newGpoStatusComboBox.SelectedIndex = [array]::IndexOf(@('Enabled', 'ComputerOnly', 'UserOnly'), $configuration.Status)
        $newGpoGroupsCheckBox.IsChecked = [bool]$newGpo.Groups.Create
        $newGpoGroupsPanel.IsVisible = [bool]$newGpo.Groups.Create
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
        $newGpoPanel.IsVisible = $true
        [void]$newGpoNameTextBox.Focus()
        $newGpoNameTextBox.SelectAll()
    }

    # What the security filtering groups of the new GPO will be.
    function Update-NewGpoGroupText {
        try {
            $settings = if ($newGpo.Groups) { $newGpo.Groups } else { (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups }
            $apply = Get-PSGPOFilteringGroupName -Role Apply -GpoName $newGpoNameTextBox.Text -Settings $settings
            $deny = Get-PSGPOFilteringGroupName -Role Deny -GpoName $newGpoNameTextBox.Text -Settings $settings
            $newGpoGroupsTextBlock.Text = "$apply`: only its members apply the GPO (add the computers or users to it). $deny`: its members never apply it. Authenticated Users keep reading the GPO."
        } catch {
            $newGpoGroupsTextBlock.Text = $_.Exception.Message
        }
    }

    # Creates the GPO, then sets its status and its security filtering groups, then links it.
    # It is not linked when its security filtering failed: it would apply to every computer and
    # user. What failed after the creation is said under the details of the GPO.
    function Submit-NewGpo {
        $template = if ($newGpoTemplateComboBox.SelectedIndex -gt 0) { $newGpo.Templates[$newGpoTemplateComboBox.SelectedIndex - 1] }
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
        $done.Add("GPO '$($gpo.DisplayName)' created.")
        if ($template) {
            try {
                Copy-PSGPOBackupSetting -Directory $Directory -Gpo $gpo -Backup $template
                $done.Add("Settings of the template '$($template.DisplayName)' copied.")
            } catch {
                $problems.Add("The settings of the template are not copied: $($_.Exception.GetBaseException().Message)")
            }
        }
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
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $deleteLinkPanel.IsVisible = $true
    }

    # The forms of the details, one at a time.
    function Hide-DirectoryForm {
        foreach ($panel in $newGpoPanel, $deleteLinkPanel, $linkGpoPanel, $deleteGpoPanel, $restoreGpoPanel) { $panel.IsVisible = $false }
    }

    # Deletion of the selected GPO, once confirmed, as GPMC: its links too; backed up first in
    # the folder of the History tab, so that Deleted GPOs keeps it.
    $deleteGpo = @{ Gpo = $null }
    function Open-DeleteGpoForm {
        $gpo = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($gpo -isnot [GPOToolsGpo]) { return }
        $deleteGpo.Gpo = $gpo
        $links = @($Directory.GetLinksOf($gpo))
        $deleteGpoTextBlock.Text = "Delete the GPO '$($gpo.DisplayName)'? " +
            $(if ($links.Count) { "Its $($links.Count) link$(if ($links.Count -gt 1) { 's' }) ($(@($links | ForEach-Object { $_.Som.Name }) -join ', ')) $(if ($links.Count -gt 1) { 'are' } else { 'is' }) deleted too. " } else { 'It is not linked. ' }) +
            "It is backed up first in $(Get-HistoryRoot): Deleted GPOs keeps it, to restore it."
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $deleteGpoPanel.IsVisible = $true
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
            Show-DirectoryResult -Text "The GPO '$($gpo.DisplayName)' is not deleted: $($_.Exception.GetBaseException().Message)" -Problem
            return
        }
        $settingsCache.Remove("$($gpo.Id)")
        Update-BackupList -Force
        Update-DirectoryTree -Select $Directory.Domain
        $count = @($removed.Links).Count
        Show-DirectoryResult -Text "GPO '$($gpo.DisplayName)' deleted$(if ($count) { ", with its $count link$(if ($count -gt 1) { 's' })" }). Its backup is in Deleted GPOs, to restore it."
    }

    # A deleted GPO created again from its newest backup; linked again where it was, when its
    # security filtering allows it.
    $restoreGpo = @{ Backup = $null }
    function Open-RestoreGpoForm {
        $backup = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if (-not $backup -or $backup.PSObject.TypeNames -notcontains 'PSGPOTools.Backup') { return }
        $restoreGpo.Backup = $backup
        $restoreGpoTextBlock.Text = "Create the deleted GPO '$($backup.DisplayName)' again from its backup of $(Format-HistoryDate $backup.BackedUp)? " +
            'It gets a new unique ID from the domain, and the settings, status and client-side extensions of the backup. Its security filtering is not restored: it applies to Authenticated Users.'
        $links = @($backup.Links).Count
        $filtering = (@($backup.SecurityFiltering) -join '|') -eq 'Authenticated Users' -and -not @($backup.DeniedTo | Where-Object { $_ }).Count
        $restoreGpoLinkCheckBox.IsVisible = $links -gt 0
        $restoreGpoLinkCheckBox.IsEnabled = $filtering
        $restoreGpoLinkCheckBox.IsChecked = $filtering
        $restoreGpoLinkCheckBox.Content = if ($filtering) { "Link it again where it was ($links link$(if ($links -gt 1) { 's' }))" }
            else { "Not linked again: its security filtering was $(@($backup.SecurityFiltering) -join ', '), set it first" }
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $restoreGpoPanel.IsVisible = $true
    }

    function Submit-RestoreGpo {
        $backup = $restoreGpo.Backup
        $restoreGpoPanel.IsVisible = $false
        if (-not $backup) { return }
        try {
            $files = Get-PSGPOVerifiedBackupFile -Backup $backup
            $result = Restore-PSGPODeletedGpo -Directory $Directory -Backup $backup -Files $files -RestoreLink:([bool]($restoreGpoLinkCheckBox.IsVisible -and $restoreGpoLinkCheckBox.IsChecked))
        } catch {
            Show-DirectoryResult -Text "The GPO '$($backup.DisplayName)' is not restored: $($_.Exception.GetBaseException().Message)" -Problem
            return
        }
        $gpo = $Directory.Gpos | Where-Object Id -EQ $result.Id | Select-Object -First 1
        Update-BackupList -Force
        Update-DirectoryTree -Select $gpo
        $lines = @("GPO '$($result.DisplayName)' restored from its backup of $(Format-HistoryDate $backup.BackedUp), as {$($result.Id.ToString().ToUpperInvariant())}.")
        if ($result.Linked.Count) { $lines += "Linked again to $(@($result.Linked | ForEach-Object { $Directory.FindSom($_).Name }) -join ', ')." }
        Show-DirectoryResult -Text ((@($lines) + @($result.Problems)) -join [Environment]::NewLine) -Problem:($result.Problems.Count -gt 0)
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

    # Link of an existing GPO to the selected domain or OU, as GPMC "Link an Existing GPO...": the
    # GPOs of the domain not linked there yet, by name.
    $linkGpo = @{ Som = $null }
    function Open-LinkGpoForm {
        param([GPOToolsSom]$Som)
        $linkGpo.Som = $Som
        $linkGpoTitleTextBlock.Text = "Link an existing GPO of $($Directory.DomainName) to $($Som.Name)"
        $linkGpoErrorTextBlock.Text = ''
        $directoryResultTextBlock.Text = ''
        Hide-DirectoryForm
        $linkGpoFilterTextBox.Text = ''
        Update-LinkGpoList
        $linkGpoPanel.IsVisible = $true
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
            elseif ($filter) { "No GPO named like '$filter' can be linked to $($som.Name)." }
            else { "Every GPO of $($Directory.DomainName) is already linked to $($som.Name)." }
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
        Show-DirectoryResult -Text "GPO '$($gpo.DisplayName)' linked to $($som.Name), link order $($link.Order)."
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
                # Preferences last, as GPMC lists them after the policies: their files, read in one
                # copy of the folder, only when the GPO declares a preference type.
                $declared = "$($gpo.MachineExtensionNames)$($gpo.UserExtensionNames)"
                if (@(Get-PSGPOPreferenceCatalog | Where-Object { $declared.IndexOf($_.Cse, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count) {
                    $files = $Directory.ReadGpoFolder($gpo)
                    foreach ($scope in 'Machine', 'User') {
                        # Not through the pipeline: it wraps the rows in PSObjects, which Avalonia cannot bind.
                        $rows = [System.Collections.Generic.List[object]]::new()
                        foreach ($row in @($cached[$scope])) { $rows.Add($row) }
                        foreach ($preference in @(Get-PSGPOConfiguredPreference -Files $files -Scope $scope)) { if ($preference.Row) { $rows.Add($preference.Row) } }
                        $cached[$scope] = $rows.ToArray()
                    }
                }
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
    # --- History tab: the backups of the GPO as a timeline, and what changed at each one ---------

    # Reports of the backups read once (by folder), and of the current state of each GPO (by its
    # version and last change); the GPO compared to its approved version (Get-PSGPODriftState).
    $history = @{ Reports = @{}; Current = @{}; Drift = $null }
    $historyPathTextBox.Text = Get-PSGPODefaultBackupPath

    function Get-HistoryRoot {
        $path = "$($historyPathTextBox.Text)".Trim()
        if (-not $path) { $path = Get-PSGPODefaultBackupPath; $historyPathTextBox.Text = $path }
        $path
    }

    function Set-HistoryStatus {
        param([string]$Text, [switch]$Problem)
        $historyStatusTextBlock.Text = $Text
        if ($Problem) { $historyStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $historyStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    function Format-HistoryDate {
        param($Date)
        if ($null -eq $Date) { return 'unknown date' }
        ([datetime]$Date).ToLocalTime().ToString('g')
    }

    function Get-ChangeSummary {
        param([object[]]$Changes)
        $count = { param($Kind) @($Changes | Where-Object Change -EQ $Kind).Count }
        if (-not $Changes.Count) { return 'no setting changed' }
        '+{0}  ~{1}  -{2}' -f (& $count 'Added'), (& $count 'Changed'), (& $count 'Removed')
    }

    # The timeline of the selected GPO; the backup in $SelectPath selected, else the newest node.
    function Update-HistoryTab {
        param([string]$SelectPath)
        $gpo = Get-SelectedGpo
        $historyTab.IsVisible = [bool]$gpo
        if (-not $gpo) {
            if ($directoryTabs.SelectedItem -eq $historyTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $historyTab) { return }

        $root = Get-HistoryRoot
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
                $node.Subtitle = "version $($backup.ComputerVersion) / $($backup.UserVersion)"
                $node.Changes = @(Compare-PSGPOSettingReport -Reference $previous -Difference $report)
                $node.Summary = if ($nodes.Count) { Get-ChangeSummary $node.Changes } else { 'first backup' }
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
                $node.Title = 'Now'
                $node.Subtitle = "version $($gpo.GetComputerVersion()) / $($gpo.GetUserVersion())"
                $node.Changes = $changes
                $node.Summary = if ($nodes.Count) { "$(Get-ChangeSummary $changes), not backed up" } else { 'not backed up' }
                $node.Previous = $previousDate
                $node.NodeFill = 'Transparent'
                $node.NodeStroke = '#CA5010'
                $node.LineBrush = '#8A8886'
                $nodes.Add($node)
            }
        } catch {
            $problem = "The history cannot be read: $($_.Exception.GetBaseException().Message)"
        }

        $historyTimelineList.ItemsSource = $nodes
        $backed = @($nodes | Where-Object { -not $_.IsCurrent }).Count
        if ($problem) { Set-HistoryStatus $problem -Problem }
        elseif (-not $backed) { Set-HistoryStatus "No backup of this GPO in $root yet: Back up now keeps its settings as they are." }
        elseif ($nodes[-1].IsCurrent) { Set-HistoryStatus "$backed backup$(if ($backed -gt 1) { 's' }) in $root. The GPO changed since the last one (Now)." }
        else { Set-HistoryStatus "$backed backup$(if ($backed -gt 1) { 's' }) in $root. The last one is up to date." }
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
            "No approved version yet: check '$Label' in the notes of a backup to see what changes after it."
        } else {
            $by = if ($drift.ApprovedBy) { ", by $($drift.ApprovedBy)" }
            if ($drift.State -eq 'Drifted') {
                $brush = '#CA5010'
                "Changed since its approved version of $(Format-HistoryDate $drift.Approved)$by ($(Get-ChangeSummary $drift.Changes))."
            } else {
                $brush = '#107C10'
                "The GPO is its approved version of $(Format-HistoryDate $drift.Approved)$by."
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
            elseif ($Node.IsCurrent -and $Node.Previous) { "Changes since the backup of $($Node.Previous), not backed up yet" }
            elseif ($Node.IsCurrent) { 'The settings of the GPO now, never backed up' }
            elseif ($Node.Previous) { "Changes from $($Node.Previous) to $($Node.Title)" }
            else { "First backup, $($Node.Title): the settings of the GPO then" }
        if (-not $Node.Changes.Count) { $historyCompareTextBlock.Text += ': no setting changed (the version or the files did)' }
        $scopes = @{ GPO = 'GPO'; Computer = 'Computer Configuration'; User = 'User Configuration'; Files = 'Files' }
        $brushes = @{ Added = '#107C10'; Removed = '#D13438'; Changed = '#CA5010' }
        $historyChangesList.ItemsSource = @(foreach ($change in $Node.Changes) {
                $row = [AvaloniaChangeRow]::new()
                $row.Change = $change.Change
                $row.ChangeBrush = $brushes[$change.Change]
                $row.Location = "$($scopes[$change.Scope]) > $($change.Path)"
                $row.Name = $change.Name
                $row.Before = $change.Before
                $row.After = $change.After
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
        $info = "Backed up$(if ($backup.BackedUpBy) { " by $($backup.BackedUpBy)" }) on $(Format-HistoryDate $backup.BackedUp)."
        if ($backup.NotesUpdated) { $info += " Notes changed$(if ($backup.NotesUpdatedBy) { " by $($backup.NotesUpdatedBy)" }) on $(Format-HistoryDate $backup.NotesUpdated)." }
        $historyNotesInfoTextBlock.Text = $info
        $historyNotesCommentTextBox.Text = $backup.Comment
        $template = Get-PSGPOTemplateLabel
        $historyNotesLabelsTextBox.Text = @($backup.Labels | Where-Object { $_ -ne $label -and $_ -ne $template }) -join ', '
        $historyNotesApprovedCheckBox.Content = "$label version"
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
            Set-HistoryStatus "The notes are not saved: $($_.Exception.GetBaseException().Message)" -Problem
            return
        }
        Update-HistoryTab -SelectPath $saved.Path
        Set-HistoryStatus "Notes of the backup of $(Format-HistoryDate $(if ($saved.Modified) { $saved.Modified } else { $saved.BackedUp })) saved."
    }

    # Backs up GPOs in the folder of the history, with the comment typed; what was done in the status.
    function Invoke-HistoryBackup {
        param([GPOToolsGpo[]]$Gpos)
        $root = Get-HistoryRoot
        $comment = "$($historyCommentTextBox.Text)".Trim()
        $counts = @{ Created = 0; Unchanged = 0 }
        $errors = [System.Collections.Generic.List[string]]::new()
        try { $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop }
        catch { Set-HistoryStatus "The folder of the backups cannot be created: $($_.Exception.GetBaseException().Message)" -Problem; return }
        Set-PSGPOUserSetting -Values @{ BackupPath = $root }
        foreach ($gpo in $Gpos) {
            try {
                $result = Save-PSGPOBackup -Directory $Directory -Gpo $gpo -Path $root -Comment $comment
                $counts[$result.Result]++
            } catch {
                $errors.Add("$($gpo.DisplayName): $($_.Exception.GetBaseException().Message)")
            }
        }
        $history.Current = @{}
        Update-HistoryTab
        # The comment went with the new backups.
        if ($counts.Created) { $historyCommentTextBox.Text = '' }
        $text = if ($Gpos.Count -eq 1 -and -not $errors.Count) {
            if ($counts.Created) { "Backed up in $root." }
            elseif ($comment) { 'Not backed up again: the GPO did not change since its last backup. Its comment is in the notes of that backup.' }
            else { 'Not backed up again: the GPO did not change since its last backup.' }
        } else {
            "$($counts.Created) GPO(s) backed up, $($counts.Unchanged) unchanged since their last backup, in $root."
        }
        if ($errors.Count) { Set-HistoryStatus "$text Not backed up: $($errors -join '; ')" -Problem } else { Set-HistoryStatus $text }
    }

    # Restore of the selected backup, once confirmed; the GPO as it is now is backed up first.
    $historyRestoreButton.Add_Click({
        $node = $historyTimelineList.SelectedItem
        $gpo = Get-SelectedGpo
        if (-not $node -or $node.IsCurrent -or -not $gpo) { return }
        $historyRestoreTextBlock.Text = "Restore the GPO '$($gpo.DisplayName)' as it was on $($node.Title)? Its files, status and client-side extensions are replaced, " +
            'and its version increases so that the computers apply it again. Its links and security filtering do not change. ' +
            'The GPO as it is now is backed up first.'
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
            Set-HistoryStatus "The GPO is not restored: $($_.Exception.GetBaseException().Message)" -Problem
            return
        }
        # Its settings, details and history as they are now.
        $settingsCache.Remove("$($gpo.Id)")
        $history.Current = @{}
        Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag
        $directoryTabs.SelectedItem = $historyTab
        Update-HistoryTab
        Set-HistoryStatus "GPO restored as it was on $($node.Title) (version $($result.Version)); its state before was backed up."
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
        Show-HistoryChange $node -Title "Changes since the approved version of $(Format-HistoryDate $drift.Approved)"
    })
    $historyBackupButton.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Invoke-HistoryBackup -Gpos @($gpo) } })
    $historyBackupAllButton.Add_Click({ Invoke-HistoryBackup -Gpos @($Directory.Gpos | Where-Object { $Directory.IsGpoVisible($_) }) })
    # Another folder: its backups, remembered for the next time.
    $historyPathTextBox.add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            Set-PSGPOUserSetting -Values @{ BackupPath = (Get-HistoryRoot) }
            Update-HistoryTab
            # Its deleted GPOs in the tree.
            Update-BackupList -Force
            $tag = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
            if ($tag -is [GPOToolsGpo] -or $tag -is [GPOToolsSom]) { Update-DirectoryTree -Select $tag } else { Update-DirectoryTree -Select $Directory.Domain }
        }
    })

    $directoryTabs.add_SelectionChanged({
        param($sender, $e)
        # Only the selection of a tab, not of a control inside one.
        if ([object]::ReferenceEquals($e.Source, $directoryTabs)) { Update-SettingsTab; Update-HistoryTab }
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

        $detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $item -DeletedGpo $backupLists.Deleted
        $directoryTitleTextBlock.Text = $detail.Title
        $directoryPropertiesList.ItemsSource = $detail.Properties
        $linksHeaderTextBlock.Text = $detail.LinksHeader
        $linksHeaderTextBlock.IsVisible = [bool]$detail.LinksHeader
        $linksList.ItemsSource = $detail.Links
        $editGpoButton.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit
        $directoryResultTextBlock.Text = ''
        Hide-DirectoryForm
        $canRestore = $null -ne $detail.Deleted -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo
        $restoreDeletedGpoButton.IsVisible = $canRestore

        # Context menu of the selected node, as in GPMC.
        # A read-only directory (read over LDAP) cannot create GPOs yet.
        # And what the account may do there (its delegations).
        $createLinkedGpoMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo -and $item.CanLink
        $linkGpoMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $item.CanLink -and $Directory.Gpos.Count -gt 0
        $newGpoMenuItem.IsVisible = $item -eq 'GroupPolicyObjects' -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo
        $editGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit
        $deleteLinkMenuItem.IsVisible = $item -is [GPOToolsGpoLink] -and -not $Directory.IsReadOnly -and $selected.Parent.Tag.CanLink
        # Delete a GPO from Group Policy Objects, as GPMC; never a default GPO of the domain.
        $deleteGpoMenuItem.IsVisible = $item -is [GPOToolsGpo] -and -not $Directory.IsReadOnly -and $item.CanEdit -and [GPOToolsDirectory]::DefaultGpoIds -notcontains $item.Id
        $restoreDeletedGpoMenuItem.IsVisible = $canRestore
        Update-SettingsTab
        Update-HistoryTab
    })
    # Nothing to offer on this node: do not open an empty menu.
    (Get-PSGPOAvaloniaControl $window 'domainContextMenu').add_Opening({
        param($sender, $e)
        if (-not ($createLinkedGpoMenuItem.IsVisible -or $linkGpoMenuItem.IsVisible -or $newGpoMenuItem.IsVisible -or $editGpoMenuItem.IsVisible -or $deleteLinkMenuItem.IsVisible -or
                $deleteGpoMenuItem.IsVisible -or $restoreDeletedGpoMenuItem.IsVisible) -or
            -not $domainTreeView.SelectedItem) { $e.Cancel = $true }
    })

    $createLinkedGpoMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsSom]) { Open-NewGpoForm -Som $item } })
    $newGpoMenuItem.Add_Click({ Open-NewGpoForm -Som $null })
    $linkGpoMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsSom]) { Open-LinkGpoForm -Som $item } })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $linkGpoFilterTextBox.add_PropertyChanged({
        param($sender, $e)
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
    $deleteGpoMenuItem.Add_Click({ Open-DeleteGpoForm })
    $deleteGpoConfirmButton.Add_Click({ Submit-DeleteGpo })
    $deleteGpoCancelButton.Add_Click({ $deleteGpoPanel.IsVisible = $false })
    $restoreDeletedGpoMenuItem.Add_Click({ Open-RestoreGpoForm })
    $restoreDeletedGpoButton.Add_Click({ Open-RestoreGpoForm })
    $restoreGpoConfirmButton.Add_Click({ Submit-RestoreGpo })
    $restoreGpoCancelButton.Add_Click({ $restoreGpoPanel.IsVisible = $false })
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
    # The configuration window (New-PSGPOConfigurationWindow), one at a time, owned by the console.
    $configurationWindow = @{ Ui = $null }
    $configurationButton.Add_Click({
        if ($configurationWindow.Ui -and $configurationWindow.Ui.Window.IsVisible) { $configurationWindow.Ui.Window.Activate(); return }
        $configurationWindow.Ui = New-PSGPOConfigurationWindow -Directory $Directory
        $configurationWindow.Ui.Window.RequestedThemeVariant = $window.RequestedThemeVariant
        $configurationWindow.Ui.Window.Show($window)
    })
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
        $controls = @{ Window = $window; Editing = $editing; Clipboard = $clipboard; Directory = $Directory; Configuration = $configurationWindow }
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
            'deleteLinkTextBlock', 'deleteLinkConfirmButton', 'deleteLinkCancelButton', 'linkGpoMenuItem', 'linkGpoPanel',
            'linkGpoTitleTextBlock', 'linkGpoFilterTextBox', 'linkGpoList', 'linkGpoErrorTextBlock', 'linkGpoConfirmButton', 'linkGpoCancelButton',
            'deleteGpoMenuItem', 'deleteGpoPanel', 'deleteGpoTextBlock', 'deleteGpoConfirmButton', 'deleteGpoCancelButton', 'restoreDeletedGpoMenuItem',
            'restoreDeletedGpoButton', 'restoreGpoPanel', 'restoreGpoTextBlock', 'restoreGpoLinkCheckBox', 'restoreGpoConfirmButton', 'restoreGpoCancelButton',
            'newGpoTemplateComboBox', 'historyNotesTemplateCheckBox',
            'historyCommentTextBox', 'historyDriftBorder', 'historyDriftTextBlock', 'historyDriftButton', 'historyNotesPanel', 'historyNotesInfoTextBlock',
            'historyNotesCommentTextBox', 'historyNotesLabelsTextBox', 'historyNotesApprovedCheckBox', 'historyNotesSaveButton', 'historyTab', 'historyPathTextBox', 'historyBackupButton',
            'historyBackupAllButton', 'historyStatusTextBlock', 'historyTimelineList', 'historyCompareTextBlock', 'historyChangesList',
            'historyRestoreButton', 'historyRestorePanel', 'historyRestoreTextBlock', 'historyRestoreConfirmButton', 'historyRestoreCancelButton',
            'detailsTitleTextBlock', 'configurationButton', 'preferencesPanel', 'preferencesTitleTextBlock', 'preferencesInfoTextBlock', 'preferencesNewTypeComboBox',
            'preferencesNewButton', 'preferencesEditButton', 'preferencesDeleteButton', 'preferencesUpButton', 'preferencesDownButton',
            'preferencesStatusTextBlock', 'preferencesEmptyTextBlock', 'preferencesList', 'preferencesDeletePanel', 'preferencesDeleteTextBlock',
            'preferencesDeleteConfirmButton', 'preferencesDeleteCancelButton', 'preferencesFormBorder', 'preferencesFormTitleTextBlock',
            'preferencesFormHost', 'preferencesFormErrorTextBlock', 'preferencesSaveButton', 'preferencesCancelButton') {
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
