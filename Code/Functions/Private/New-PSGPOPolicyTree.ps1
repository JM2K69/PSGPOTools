<#
    Builds the scope > categories > policies node tree displayed by Show-GPOManagerAvalonia.
    Kept free of any Avalonia type so it can be tested and timed without a UI.
#>

function New-PSGPOPolicyTree {
    [CmdletBinding()]
    [OutputType([System.Collections.ObjectModel.ObservableCollection[object]])]
    param(
        # Case-insensitive substring matched against the policy display name.
        [string]$Filter = '',

        # Only these policies and security settings (the settings a GPO configures), their
        # folders expanded; $null: all of them.
        [AllowNull()]
        [System.Collections.Generic.HashSet[object]]$Only
    )
    $expand = $null -ne $Only

    $rootNodes = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

    # Icons read once: thousands of nodes share them.
    $folderData = Get-PSGPOIconData -Name 'folder'
    $policyData = Get-PSGPOIconData -Name 'document'

    foreach ($scope in [Enum]::GetValues([ScopePolicy])) {
        $scopeNode = [AvaloniaTreeNode]::new()
        $scopeNode.Header = $scope.ToString()
        # User and Machine, shown as the User / Computer Configuration of the Group Policy editor.
        Set-PSGPOTreeNodeIcon -Node $scopeNode -Name $(if ($scope -eq [ScopePolicy]::User) { 'person' } else { 'desktop' })
        $scopeNode.Tag = $scope

        # One node per category object within this scope, so lookups do not scan siblings.
        $categoryNodes = [System.Collections.Generic.Dictionary[object, object]]::new()

        foreach ($policy in [GPOToolsUtility]::Policies) {
            if ($policy.Scope -ne $scope) { continue }
            if ($Filter -and $policy.DisplayName.IndexOf($Filter, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($expand -and -not $Only.Contains($policy)) { continue }

            # Category chain from the policy's own category up to the root.
            $chain = [System.Collections.Generic.List[object]]::new()
            $category = $policy.Category
            while ($null -ne $category) {
                $chain.Add($category)
                $category = $category.ParentCategory
            }

            $currentNode = $scopeNode
            for ($i = $chain.Count - 1; $i -ge 0; $i--) {
                $cat = $chain[$i]
                $node = $null
                if (-not $categoryNodes.TryGetValue($cat, [ref]$node)) {
                    $node = [AvaloniaTreeNode]::new()
                    $node.Header = $cat.DisplayName
                    $node.Icon = 'folder'
                    $node.IconData = $folderData
                    $node.IconBrush = $script:PSGPOIconBrush['folder']
                    $node.Tag = $cat
                    $node.IsExpanded = $expand
                    $node.Parent = $currentNode
                    $currentNode.Children.Add($node)
                    $categoryNodes[$cat] = $node
                }
                $currentNode = $node
            }

            $policyNode = [AvaloniaTreeNode]::new()
            $policyNode.Header = $policy.DisplayName
            $policyNode.Icon = 'document'
            $policyNode.IconData = $policyData
            $policyNode.IconBrush = $script:PSGPOIconBrush['document']
            $policyNode.Tag = $policy
            $policyNode.Parent = $currentNode
            $currentNode.Children.Add($policyNode)
        }

        # Security settings (GptTmpl.inf) of the computer, first as in the Group Policy editor:
        # Windows Settings > Security Settings > Account Policies > Password Policy > settings.
        if ($scope -eq [ScopePolicy]::Machine) {
            $security = @(Get-PSGPOSecuritySetting | Where-Object {
                (-not $Filter -or $_.Name.IndexOf($Filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -and (-not $expand -or $Only.Contains($_))
            })
            if ($security.Count) {
                $windowsNode = [AvaloniaTreeNode]::new()
                $windowsNode.Header = 'Windows Settings'
                Set-PSGPOTreeNodeIcon -Node $windowsNode -Name 'folder'
                $windowsNode.Tag = 'WindowsSettings'
                $windowsNode.IsExpanded = $expand
                $windowsNode.Parent = $scopeNode
                $securityNode = [AvaloniaTreeNode]::new()
                $securityNode.Header = 'Security Settings'
                Set-PSGPOTreeNodeIcon -Node $securityNode -Name 'shield'
                $securityNode.Tag = 'SecuritySettings'
                $securityNode.IsExpanded = $expand
                $securityNode.Parent = $windowsNode
                $windowsNode.Children.Add($securityNode)
                $folders = @{}
                foreach ($setting in $security) {
                    $parent = $securityNode
                    $folderPath = ''
                    foreach ($part in $setting.Path) {
                        $folderPath = "$folderPath>$part"
                        if (-not $folders.ContainsKey($folderPath)) {
                            $folder = [AvaloniaTreeNode]::new()
                            $folder.Header = $part
                            $folder.Icon = 'folder'
                            $folder.IconData = $folderData
                            $folder.IconBrush = $script:PSGPOIconBrush['folder']
                            $folder.Tag = "Security:$folderPath"
                            $folder.IsExpanded = $expand
                            $folder.Parent = $parent
                            $parent.Children.Add($folder)
                            $folders[$folderPath] = $folder
                        }
                        $parent = $folders[$folderPath]
                    }
                    $node = [AvaloniaTreeNode]::new()
                    $node.Header = $setting.Name
                    Set-PSGPOTreeNodeIcon -Node $node -Name 'shield'
                    $node.Tag = $setting
                    $node.Parent = $parent
                    $parent.Children.Add($node)
                }
                $scopeNode.Children.Insert(0, $windowsNode)
            }
        }

        # Preferences ([MS-GPPREF]), last as in the Group Policy editor: Windows Settings and
        # Control Panel Settings, one node per preference type of the scope.
        $preferences = @(Get-PSGPOPreferenceExtension -Scope "$scope" | Where-Object {
                (-not $Filter -or $_.Name.IndexOf($Filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -and
                (-not $expand -or $Only.Contains("Preference:$scope|$($_.Id)"))
            })
        if ($preferences.Count) {
            $preferencesNode = [AvaloniaTreeNode]::new()
            $preferencesNode.Header = 'Preferences'
            Set-PSGPOTreeNodeIcon -Node $preferencesNode -Name 'toolbox'
            $preferencesNode.Tag = "Preferences:$scope"
            $preferencesNode.IsExpanded = $expand
            $preferencesNode.Parent = $scopeNode
            $groups = @{}
            foreach ($extension in $preferences) {
                if (-not $groups.ContainsKey($extension.Group)) {
                    $group = [AvaloniaTreeNode]::new()
                    $group.Header = $extension.Group
                    # A folder in the colour of the preferences.
                    Set-PSGPOTreeNodeIcon -Node $group -Name 'folder'
                    $group.IconBrush = $script:PSGPOIconBrush['folder-preference']
                    $group.Tag = "Preferences:$scope|$($extension.Group)"
                    $group.IsExpanded = $expand
                    $group.Parent = $preferencesNode
                    $preferencesNode.Children.Add($group)
                    $groups[$extension.Group] = $group
                }
                $node = [AvaloniaTreeNode]::new()
                $node.Header = $extension.Name
                Set-PSGPOTreeNodeIcon -Node $node -Name 'wrench'
                $node.Tag = [GPOToolsPreferenceNode]::new("$scope", $extension)
                $node.Parent = $groups[$extension.Group]
                $groups[$extension.Group].Children.Add($node)
            }
            $scopeNode.Children.Add($preferencesNode)
        }

        if ($scopeNode.Children.Count -gt 0) {
            $scopeNode.IsExpanded = $expand
            $rootNodes.Add($scopeNode)
        }
    }

    # Comma keeps PowerShell from unrolling the collection into the pipeline.
    , $rootNodes
}
