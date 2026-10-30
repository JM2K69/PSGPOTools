<#
    The tree of the editor: the policies of the ADMX files by category, the security settings,
    the preferences, the scripts and the public key policies; what its selection shows, the
    administrative templates loaded the first time they are needed, the search.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerPolicyTreeView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerPolicyTreeView {
    $treeView.add_SelectionChanged({
        $selected = $treeView.SelectedItem

        # Breadcrumb: walk the node's own Parent chain (built while populating the tree).
        $pathParts = [System.Collections.Generic.List[string]]::new()
        $current = $selected
        while ($null -ne $current) {
            $pathParts.Insert(0, $current.Header)
            $current = $current.Parent
        }
        $breadcrumbTextBlock.Text = if ($pathParts.Count -gt 0) { $pathParts -join ' > ' } else { Get-PSGPOText 'Select a policy to see its path' }

        $policy = if ($selected) { $selected.Tag } else { $null }
        $editing.Security = $null
        # A preference type: its items instead of the form of a policy; Restricted Groups: its groups.
        $isPreference = $policy -is [GPOToolsPreferenceNode]
        $isRestricted = $policy -is [string] -and $policy -eq 'RestrictedGroups'
        $isStore = $policy -is [GPOToolsCertificateStoreNode]
        $isScripts = $policy -is [string] -and $policy -match '^Scripts:(Machine|User)\|(\w+)$'
        if ($isScripts) { $scripts.Scope = $Matches[1]; $scripts.Kind = $Matches[2] }
        $preferencesPanel.IsVisible = $isPreference
        $restrictedGroupsPanel.IsVisible = $isRestricted
        $certificatesPanel.IsVisible = $isStore
        $scriptsPanel.IsVisible = $isScripts
        $detailsTabs.IsVisible = -not $isPreference -and -not $isRestricted -and -not $isStore -and -not $isScripts
        $detailsTitleTextBlock.Text = Get-PSGPOText $(if ($isPreference) { 'Preference Items' } elseif ($isRestricted) { 'Restricted Groups' } elseif ($isStore) { 'Public Key Policies' } elseif ($isScripts) { 'Scripts' } else { 'Policy Details' })
        if ($isScripts) {
            $editing.Policy = $null
            $editing.Editor = $null
            Show-ScriptList
            return
        }
        if ($isStore) {
            $editing.Policy = $null
            $editing.Editor = $null
            Show-CertificateStore -Node $policy
            return
        }
        if ($isRestricted) {
            $editing.Policy = $null
            $editing.Editor = $null
            Show-RestrictedGroupList
            return
        }
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
        $notConfiguredRadio.Content = Get-PSGPOText 'Not Configured'
        $enabledRadio.Content = Get-PSGPOText 'Enabled'
        $disabledRadio.IsVisible = $true
        $previewHeaderTextBlock.Text = Get-PSGPOText 'Registry Preview'
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
        $applyStatusTextBlock.Text = if ($pol) { Get-PSGPOText '{0} in {1}\Registry.pol' (Get-PSGPOText $read.State) $policy.Scope } elseif ($editing.Gpo -and $editing.PolError) { $editing.PolError } else { '' }
        if ($policy -is [GPOToolsPolicy]) {
            $editing.Policy = $policy
            $settingTitleTextBlock.Text = $policy.DisplayName
            $editing.Editor = New-PSGPOPolicyEditor -Policy $policy -Value $read.Value -OnChange { Update-RegistryPreview }
            $optionsHost.Content = $editing.Editor.Panel

            $displayNameTextBox.Text = $policy.DisplayName
            $descriptionTextBox.Text = if ($policy.Description) { $policy.Description } else { Get-PSGPOText '(No description available)' }
            $scopeTextBox.Text = Get-PSGPOText $policy.Scope.ToString()

            if ($policy.Registry) {
                $registryPathTextBox.Text = if ($policy.Registry.Path) { $policy.Registry.Path } else { Get-PSGPOText '(No registry path defined)' }
                $registryKeyTextBox.Text = if ($policy.Registry.Key) { $policy.Registry.Key } else { Get-PSGPOText '(No registry value name defined)' }

                $rows = @(Get-PSGPOPolicyRegistryRow -Policy $policy)
                if ($rows.Count -gt 0) {
                    $registryValuesList.ItemsSource = $rows
                } else {
                    $row = [AvaloniaRegistryRow]::new()
                    $row.Key = Get-PSGPOText 'Information'
                    $row.Value = Get-PSGPOText '(No registry value available for this policy)'
                    $registryValuesList.ItemsSource = @($row)
                }
            } else {
                $registryPathTextBox.Text = Get-PSGPOText '(This policy does not use the registry)'
                $registryKeyTextBox.Text = Get-PSGPOText '(No registry value name)'
                $row = [AvaloniaRegistryRow]::new()
                $row.Key = Get-PSGPOText 'Information'
                $row.Value = Get-PSGPOText '(This policy does not store data in the registry)'
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
            $settingTitleTextBlock.Text = Get-PSGPOText 'Select a policy in the tree'
        }
        Update-RegistryPreview
    })

    # The ADMX files chosen last ($AdmxSource), loaded the first time the console needs them: it
    # opens at once, and its views without policies (links, delegation, approval) never wait.
    # Pending: what waits for them, run once they are loaded.
    $admx = @{ Source = $AdmxSource; Loading = $false; Pending = [System.Collections.Generic.List[hashtable]]::new() }
    function Wait-ConsoleAdmx {
        param([Parameter(Mandatory)] [scriptblock]$Then, [object[]]$ArgumentList = @())
        if (-not $admx.Source) { return $false }
        $admx.Pending.Add(@{ Then = $Then; Arguments = $ArgumentList })
        if ($admx.Loading) { return $true }
        $admx.Loading = $true
        $admxLoadingTextBlock.Text = Get-PSGPOText 'Loading the administrative templates (ADMX) of {0}, once for this console...' $admx.Source.Path
        $admxLoadingBanner.IsVisible = $true
        # Posted: the banner shows before the window waits for the files.
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                $load = @{ Path = $admx.Source.Path }
                if ($admx.Source.UICulture) { $load.UICulture = $admx.Source.UICulture }
                $failed = $false
                try {
                    Initialize-PSGPOAdmx @load -WarningAction SilentlyContinue -ErrorAction Stop
                    $admxLoadingBanner.IsVisible = $false
                    # The files that cannot be read are left out: the banner says which.
                    $skipped = @([GPOToolsUtility]::SkippedFiles)
                    if ($skipped.Count) {
                        $admxLoadingTextBlock.Text = Get-PSGPOText 'The administrative templates of {0} are loaded without the files that cannot be read: {1}' $admx.Source.Path ($skipped -join '; ')
                        $admxLoadingBanner.IsVisible = $true
                        Write-PSGPOLogEntry -Level Warning -Source 'GPO console' -Message $admxLoadingTextBlock.Text
                    }
                } catch {
                    $failed = $true
                    # The console goes on without them (the values are Extra Registry Settings), and
                    # the next start asks for them in the ADMX window.
                    [GPOToolsUtility]::RemoveAll()
                    Set-PSGPOUserSetting -Values @{ AdmxFailed = $true }
                    $admxLoadingTextBlock.Text = Get-PSGPOText 'The administrative templates of {0} are not loaded: {1} The next start of the console asks for them.' $admx.Source.Path $_.Exception.GetBaseException().Message
                    Write-PSGPOLogEntry -Level Error -Source 'GPO console' -Message $admxLoadingTextBlock.Text -ErrorRecord $_
                }
                $admx.Source = $null
                $admx.Loading = $false
                $settingsCache.Clear()
                $history.Reports = @{}
                $history.Current = @{}
                Update-PolicyTree
                $pending = @($admx.Pending)
                $admx.Pending.Clear()
                foreach ($item in $pending) { $arguments = $item.Arguments; & $item.Then @arguments }
                # The editor shown meanwhile says it too.
                if ($failed) { $breadcrumbTextBlock.Text = $admxLoadingTextBlock.Text }
            }, [Avalonia.Threading.DispatcherPriority]::Background)
        $true
    }

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
            foreach ($setting in Get-PSGPOSecuritySetting) {
                $store = Get-SecurityStore $setting
                if ($store -and $store.HasValue($setting.Section, $setting.Key)) { [void]$only.Add($setting) }
            }
            if ($editing.Template -and @(Get-PSGPORestrictedGroup -Template $editing.Template).Count) { [void]$only.Add('RestrictedGroups') }
            # The certificate stores with a certificate.
            foreach ($scope in 'Machine', 'User') {
                if (-not $editing.Pol[$scope]) { continue }
                foreach ($store in @(Get-PSGPOCertificateStore -Scope $scope)) {
                    if (@(Get-PSGPOPolicyCertificate -Pol $editing.Pol[$scope] -Store $store.Store).Count) { [void]$only.Add("Certificates:$scope|$($store.Store)") }
                }
            }
            # The preference types and the scripts the GPO declares (its client-side extensions).
            foreach ($scope in 'Machine', 'User') {
                $names = if ($scope -eq 'Machine') { "$($editing.Gpo.MachineExtensionNames)" } else { "$($editing.Gpo.UserExtensionNames)" }
                if ($names.IndexOf([GPOToolsDirectory]::ScriptsExtension, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    foreach ($kind in $script:PSGPOScriptKind[$scope]) { [void]$only.Add("Scripts:$scope|$kind") }
                }
                foreach ($extension in @(Get-PSGPOPreferenceExtension -Scope $scope)) {
                    if ($names.IndexOf($extension.Cse, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { [void]$only.Add("Preference:$scope|$($extension.Id)") }
                }
            }
        }
        $treeView.ItemsSource = New-PSGPOPolicyTree -Filter $searchTextBox.Text -Only $only
        if ($only -and -not @($treeView.ItemsSource).Count) {
            $breadcrumbTextBlock.Text = Get-PSGPOText $(if ($searchTextBox.Text) { 'No configured setting matches the search' } else { 'This GPO configures no setting' })
        }
    }
    $configuredOnlyCheckBox.add_IsCheckedChanged({ Update-PolicyTree })

    # The security settings do not come from the ADMX files: the tree always has them.
    Update-PolicyTree
    if ([GPOToolsUtility]::Policies.Count -eq 0 -and -not $AdmxSource) {
        Write-Warning 'No ADMX policy loaded: run Initialize-PSGPOAdmx before Show-GPOManagerAvalonia for the Administrative Templates.'
        $breadcrumbTextBlock.Text = Get-PSGPOText 'No ADMX policy loaded (Initialize-PSGPOAdmx): only the security settings are shown'
    }

    $searchButton.Add_Click({ Update-PolicyTree })
    $searchTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            Update-PolicyTree
        }
    })
}
