<#
    Builds the Group Policy Management tree of Show-GPOManagerAvalonia, as GPMC shows it:
    domain > GPO links (by link order) and OUs, then the "Group Policy Objects" container, and
    "Deleted GPOs": the recycle bin, the newest backup of each GPO deleted from the domain.
    Kept free of any Avalonia type so it can be tested without a UI.

    Only what the account manages is shown (RBAC, from the delegations of the domain): the OUs
    where it links GPOs, their parents greyed as the path to them, without their links; the GPOs
    it edits or that are linked to its OUs.
#>

# Key of a node kept across rebuilds (expanded nodes): the DN of a SOM, a fixed key for the GPO container.
function Get-PSGPODirectoryNodeKey {
    [CmdletBinding()]
    [OutputType([string])]
    param($Node)

    if ($Node.Tag -is [GPOToolsSom]) { 'SOM:' + $Node.Tag.DistinguishedName }
    elseif ($Node.Tag -eq 'GroupPolicyObjects') { 'GPOS:' + $Node.Parent.Tag.DistinguishedName }
    elseif ($Node.Tag -eq 'DeletedGpos') { 'DELETED:' + $Node.Parent.Tag.DistinguishedName }
}

function New-PSGPODirectoryTree {
    [CmdletBinding()]
    [OutputType([System.Collections.ObjectModel.ObservableCollection[object]])]
    param(
        [Parameter(Mandatory)]
        [GPOToolsDirectory]$Directory,

        # Keys (Get-PSGPODirectoryNodeKey) of the nodes to expand; the domain is always expanded.
        [System.Collections.Generic.HashSet[string]]$Expanded,

        # The backups of the deleted GPOs (Get-PSGPODeletedGpoBackup): the "Deleted GPOs" node.
        [AllowEmptyCollection()]
        [object[]]$DeletedGpo
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
        # Only the path to the OUs the account manages: greyed, without its links.
        if (-not $Som.CanLink) { $Node.IconBrush = '#8A8886' }

        foreach ($Link in @($Som.Links | Where-Object { $Som.CanLink } | Sort-Object Order)) {
            $LinkHeader = $Link.GetDisplayName()
            if ($Link.Enforced) { $LinkHeader += ' (enforced)' }
            if (-not $Link.Enabled) { $LinkHeader += ' (link disabled)' }
            $LinkIcon = if (-not $Link.Enabled) { 'link-dismiss' } elseif ($Link.Enforced) { 'lock-closed' } else { 'link' }
            [void](New-Node $LinkHeader $LinkIcon $Link $Node)
        }
        foreach ($Child in $Som.Children) { if ($Directory.IsSomVisible($Child)) { [void](Add-Som $Child $Node) } }
        $Node
    }

    $Roots = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $DomainNode = Add-Som $Directory.Domain $null
    $DomainNode.IsExpanded = $true

    $GposNode = New-Node 'Group Policy Objects' 'library' 'GroupPolicyObjects' $DomainNode
    foreach ($Gpo in $Directory.Gpos) {
        if ($Directory.IsGpoVisible($Gpo)) { [void](New-Node $Gpo.DisplayName 'document-settings' $Gpo $GposNode) }
    }
    if ($null -ne $DeletedGpo) {
        $DeletedNode = New-Node 'Deleted GPOs' 'delete' 'DeletedGpos' $DomainNode
        foreach ($Backup in $DeletedGpo) {
            $Node = New-Node $Backup.DisplayName 'document-settings' $Backup $DeletedNode
            $Node.IconBrush = '#8A8886'
        }
    }

    $Roots.Add($DomainNode)
    # Comma keeps PowerShell from unrolling the collection into the pipeline.
    , $Roots
}
