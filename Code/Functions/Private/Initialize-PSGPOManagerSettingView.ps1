<#
    The form of the setting selected in the editor: the options of a policy of the ADMX files and
    the registry values it writes, or a security setting (GptTmpl.inf, audit.csv); Apply writes it
    to the GPO edited. Its state ($editing: the policy, the GPO, its Registry.pol and security
    files) is the one every view of the editor reads.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerSettingView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerSettingView {
    # Options form of the selected policy (New-PSGPOPolicyEditor), the policy it edits and the
    # GPO opened from the Group Policy Management view ($null: browsing the ADMX policies).
    # Pol: the Registry.pol of the GPO by scope; Saved: the registry values of the setting of the
    # selected policy in it, compared with the form to know whether there is something to apply.
    # Security: the selected security setting, Template: the GptTmpl.inf of the GPO (security
    # settings), Audit: its audit.csv (advanced audit policy); Saved is then the raw value of the
    # setting in it.
    $editing = @{ Policy = $null; Security = $null; Editor = $null; Gpo = $null; Pol = @{}; PolError = $null; Template = $null; Audit = $null; Saved = $null; Preferences = @{} }
    $notDefinedMark = '(not defined)'

    # The file of a security setting in the GPO: audit.csv for the advanced audit policy, else
    # GptTmpl.inf; $null when the GPO is not read.
    function Get-SecurityStore {
        param([GPOToolsSecuritySetting]$Setting)
        if ($Setting.Section -eq [GPOToolsAuditPolicyFile]::Section) { $editing.Audit } else { $editing.Template }
    }
    function Get-SecurityFileName {
        param([GPOToolsSecuritySetting]$Setting)
        if ($Setting.Section -eq [GPOToolsAuditPolicyFile]::Section) { 'audit.csv' } else { 'GptTmpl.inf' }
    }

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
                elseif ($editing.Security -and (Get-SecurityStore $editing.Security)) { $changed = (Get-SecuritySignature) -ne $editing.Saved }
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
                    $audit = $editing.Security.Section -eq [GPOToolsAuditPolicyFile]::Section
                    $row.Title = Get-PSGPOText $(if ($audit) { 'Set in audit.csv' } else { 'Set in GptTmpl.inf' })
                    $row.Key = if ($audit) { $editing.Security.Name } else { "[$($editing.Security.Section)]" }
                    $row.ValueName = $editing.Security.Key
                    $row.Data = $editing.Security.ConvertToRaw((& $editing.Editor.GetValue))
                    $rows = @($row)
                } catch {
                    $settingErrorTextBlock.Text = $_.Exception.Message
                }
            }
            $registryPreviewList.ItemsSource = $rows
            $previewEmptyTextBlock.IsVisible = $rows.Count -eq 0
            $previewEmptyTextBlock.Text = Get-PSGPOText $(if ($settingErrorTextBlock.Text) { 'Fix the value above to see the line of {0}.' } else { 'Not defined: nothing is written to {0}.' }) (Get-SecurityFileName $editing.Security)
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
        $previewEmptyTextBlock.Text = Get-PSGPOText $(if (-not $policy) { 'Select a policy in the tree.' }
            elseif ($settingErrorTextBlock.Text) { 'Fix the options above to see the registry values.' }
            else { 'Not configured: nothing is written to the registry.' })
        Update-ApplyButton
    }

    # Saves the setting of the selected policy in the Registry.pol of the GPO. The file is
    # changed on a copy: if the domain refuses it, the setting read before stays.
    $applySettingButton.Add_Click({
        if ($editing.Security) {
            # A security setting: written to a copy of GptTmpl.inf (audit.csv for the advanced
            # audit policy), saved, then kept.
            $setting = $editing.Security
            $store = Get-SecurityStore $setting
            if (-not $editing.Gpo -or -not $store) { return }
            $value = if ($enabledRadio.IsChecked) { & $editing.Editor.GetValue } else { $null }
            $copy = if ($store -is [GPOToolsAuditPolicyFile]) { [GPOToolsAuditPolicyFile]::Parse($store.ToBytes()) } else { [GPOToolsSecurityTemplate]::Parse($store.ToBytes()) }
            try {
                Set-PSGPOSecurityValue -Template $copy -Setting $setting -Value $value
                if ($copy -is [GPOToolsAuditPolicyFile]) {
                    $Directory.WriteAuditPolicyFile($editing.Gpo, $copy.ToBytes())
                    $editing.Audit = $copy
                } else {
                    $Directory.WriteSecurityTemplate($editing.Gpo, $copy.ToBytes())
                    $editing.Template = $copy
                }
                $editing.Saved = Get-SecuritySignature
                $applyStatusTextBlock.Text = Get-PSGPOText 'Saved: {0} in {1} (version {2}).' (ConvertTo-PSGPODisplayText $setting.FormatValue($value)) (Get-SecurityFileName $setting) $editing.Gpo.GetComputerVersion()
            } catch {
                $applyStatusTextBlock.Text = Get-PSGPOText 'Not saved: {0}' $_.Exception.GetBaseException().Message
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
            $applyStatusTextBlock.Text = Get-PSGPOText 'Saved: {0} in {1}\Registry.pol (version {2}).' (Get-PSGPOText $state) $scope $version
        } catch {
            $applyStatusTextBlock.Text = Get-PSGPOText 'Not saved: {0}' $_.Exception.GetBaseException().Message
        }
        Update-ApplyButton
    })
    foreach ($radio in $notConfiguredRadio, $enabledRadio, $disabledRadio) {
        $radio.add_IsCheckedChanged({ Update-RegistryPreview })
    }

    # Theme: the one of the session, the same in every window (PSGPOTheme.ps1); FluentTheme and
    # our ThemeDictionaries swap when RequestedThemeVariant changes.
    Register-PSGPOThemeWindow -Window $window -ToggleText $themeToggleText -ToggleIcon $themeToggleIcon
    $themeToggleButton.Add_Click({ Switch-PSGPOTheme })

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
        $store = Get-SecurityStore $Setting
        $fileName = Get-SecurityFileName $Setting
        if ($store) { $read = Get-PSGPOSecurityValue -Template $store -Setting $Setting }
        $editing.Policy = $null
        $editing.Saved = if ($read.Defined) { $read.Raw } else { $notDefinedMark }
        $notConfiguredRadio.Content = Get-PSGPOText 'Not Defined'
        $enabledRadio.Content = Get-PSGPOText 'Define this policy setting'
        $disabledRadio.IsVisible = $false
        $previewHeaderTextBlock.Text = Get-PSGPOText '{0} Preview' $fileName
        if ($read.Defined -and -not $read.Problem) { $enabledRadio.IsChecked = $true } else { $notConfiguredRadio.IsChecked = $true }
        $applyStatusTextBlock.Text = if ($read.Problem) { $read.Problem }
            elseif ($store) { Get-PSGPOText $(if ($read.Defined) { 'Defined in {0}' } else { 'Not defined in {0}' }) $fileName }
            elseif ($editing.Gpo -and $editing.PolError) { $editing.PolError } else { '' }

        $editing.Security = $Setting
        $settingTitleTextBlock.Text = Get-PSGPOText $Setting.Name
        $editing.Editor = New-PSGPOSecurityEditor -Setting $Setting -Value $read.Value -OnChange { Update-RegistryPreview } -Directory $Directory
        $optionsHost.Content = $editing.Editor.Panel

        $displayNameTextBox.Text = Get-PSGPOText $Setting.Name
        $descriptionTextBox.Text = (Get-PSGPOText $(if ($fileName -eq 'audit.csv') { 'Advanced audit policy of the computer, in audit.csv (Machine\Microsoft\Windows NT\Audit): the events of this subcategory the computers audit.' } else { 'Security setting of the computer, in GptTmpl.inf (Machine\Microsoft\Windows NT\SecEdit).' })) + $(if ($Setting.Reference) { "`n`n" + (Get-PSGPOText 'Reference: {0}' $Setting.Reference) })
        $scopeTextBox.Text = Get-PSGPOText 'Machine'
        $registryPathTextBox.Text = if ($fileName -eq 'audit.csv') { [GPOToolsDirectory]::AuditPolicyPath } else { "GptTmpl.inf [$($Setting.Section)]" }
        $registryKeyTextBox.Text = $Setting.Key
        $registryValuesList.ItemsSource = @(
            foreach ($pair in @(
                    @('Category', (@($Setting.Path | ForEach-Object { Get-PSGPOText $_ }) -join ' > '))
                    @('Value', $(if ($Setting.Kind -eq 'RegistryValue') { Get-PSGPOText '{0}, registry type {1}' (Get-PSGPOText "$($Setting.Display)") $Setting.RegistryType } else { Get-PSGPOText "$($Setting.Kind)" }))
                    @('Range', $(if ($null -ne $Setting.Min -or $null -ne $Setting.Max) { (Get-PSGPOText '{0} to {1} {2}' $Setting.Min $Setting.Max (Get-PSGPOText "$($Setting.Unit)")).Trim() }))
                    @('Values', (@($Setting.Choices | ForEach-Object { "$($_.Value): $(Get-PSGPOText "$($_.Text)")" }) -join '; ')))) {
                if (-not $pair[1]) { continue }
                $row = [AvaloniaRegistryRow]::new()
                $row.Key = Get-PSGPOText $pair[0]
                $row.Value = $pair[1]
                $row
            })
        Update-RegistryPreview
    }
}
