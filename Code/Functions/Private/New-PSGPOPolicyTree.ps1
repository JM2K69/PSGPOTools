<#
    Builds the scope > categories > policies node tree displayed by Show-GPOManagerAvalonia.
    Kept free of any Avalonia type so it can be tested and timed without a UI.
#>

function New-PSGPOPolicyTree {
    [CmdletBinding()]
    [OutputType([System.Collections.ObjectModel.ObservableCollection[object]])]
    param(
        # Case-insensitive substring matched against the policy display name.
        [string]$Filter = ''
    )

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

        if ($scopeNode.Children.Count -gt 0) {
            $rootNodes.Add($scopeNode)
        }
    }

    # Comma keeps PowerShell from unrolling the collection into the pipeline.
    , $rootNodes
}
