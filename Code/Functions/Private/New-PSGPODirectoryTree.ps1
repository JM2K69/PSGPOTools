<#
    Builds the Group Policy Management tree of Show-GPOManagerAvalonia, as GPMC shows it:
    domain > GPO links (by link order) and OUs, then the "Group Policy Objects" container.
    Kept free of any Avalonia type so it can be tested without a UI.
#>

# Key of a node kept across rebuilds (expanded nodes): the DN of a SOM, a fixed key for the GPO container.
function Get-PSGPODirectoryNodeKey {
    [CmdletBinding()]
    [OutputType([string])]
    param($Node)

    if ($Node.Tag -is [GPOToolsSom]) { 'SOM:' + $Node.Tag.DistinguishedName }
    elseif ($Node.Tag -eq 'GroupPolicyObjects') { 'GPOS:' + $Node.Parent.Tag.DistinguishedName }
}

function New-PSGPODirectoryTree {
    [CmdletBinding()]
    [OutputType([System.Collections.ObjectModel.ObservableCollection[object]])]
    param(
        [Parameter(Mandatory)]
        [GPOToolsDirectory]$Directory,

        # Keys (Get-PSGPODirectoryNodeKey) of the nodes to expand; the domain is always expanded.
        [System.Collections.Generic.HashSet[string]]$Expanded
    )

    function New-Node {
        param([string]$Header, [string]$Icon, $Tag, [AvaloniaTreeNode]$Parent)
        $Node = [AvaloniaTreeNode]::new()
        $Node.Header = $Header
        Set-PSGPOTreeNodeIcon -Node $Node -Name $Icon
        $Node.Tag = $Tag
        $Node.Parent = $Parent
        if ($Parent) { $Parent.Children.Add($Node) }
        if ($Expanded) { $Node.IsExpanded = $Expanded.Contains("$(Get-PSGPODirectoryNodeKey $Node)") }
        $Node
    }

    function Add-Som {
        param([GPOToolsSom]$Som, [AvaloniaTreeNode]$Parent)
        $Header = if ($Som.BlockInheritance) { "$($Som.Name) (blocks inheritance)" } else { $Som.Name }
        $Icon = if ($Som.Kind -eq [GPOToolsSomKind]::Domain) { 'globe' } elseif ($Som.BlockInheritance) { 'folder-prohibited' } else { 'folder' }
        $Node = New-Node $Header $Icon $Som $Parent

        foreach ($Link in @($Som.Links | Sort-Object Order)) {
            $LinkHeader = $Link.Gpo.DisplayName
            if ($Link.Enforced) { $LinkHeader += ' (enforced)' }
            if (-not $Link.Enabled) { $LinkHeader += ' (link disabled)' }
            $LinkIcon = if (-not $Link.Enabled) { 'link-dismiss' } elseif ($Link.Enforced) { 'lock-closed' } else { 'link' }
            [void](New-Node $LinkHeader $LinkIcon $Link $Node)
        }
        foreach ($Child in $Som.Children) { [void](Add-Som $Child $Node) }
        $Node
    }

    $Roots = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $DomainNode = Add-Som $Directory.Domain $null
    $DomainNode.IsExpanded = $true

    $GposNode = New-Node 'Group Policy Objects' 'library' 'GroupPolicyObjects' $DomainNode
    foreach ($Gpo in $Directory.Gpos) { [void](New-Node $Gpo.DisplayName 'document-settings' $Gpo $GposNode) }

    $Roots.Add($DomainNode)
    # Comma keeps PowerShell from unrolling the collection into the pipeline.
    , $Roots
}
