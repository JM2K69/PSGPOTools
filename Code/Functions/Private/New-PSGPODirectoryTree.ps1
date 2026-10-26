<#
    Builds the Group Policy Management tree of Show-GPOManagerAvalonia, as GPMC shows it:
    domain > GPO links (by link order) and OUs, then the "Group Policy Objects" container, and
    "Deleted GPOs": the recycle bin, the newest backup of each GPO deleted from the domain.

    With the approval workflow, the GPOs waiting for their approval are found without expanding
    the tree: a "Waiting for approval" node lists them (expanded when the console opens), and an
    OU says how many are linked below it.
    Kept free of any Avalonia type so it can be tested without a UI.

    Every OU, link and GPO is shown, as GPMC shows them to any account of the domain; what the
    account does not manage (RBAC, from the delegations of the domain) is greyed: it only reads it.
    With View.ShowUnmanaged $false in the configuration, only what the account manages is shown:
    the OUs where it links GPOs, their parents greyed as the path to them, without their links;
    the GPOs it edits or that are linked to its OUs.
#>

# Key of a node kept across rebuilds (expanded nodes): the DN of a SOM, a fixed key for the GPO container.
function Get-PSGPODirectoryNodeKey {
    [CmdletBinding()]
    [OutputType([string])]
    param($Node)

    if ($Node.Tag -is [GPOToolsSom]) { 'SOM:' + $Node.Tag.DistinguishedName }
    elseif ($Node.Tag -eq 'GroupPolicyObjects') { 'GPOS:' + $Node.Parent.Tag.DistinguishedName }
    elseif ($Node.Tag -eq 'DeletedGpos') { 'DELETED:' + $Node.Parent.Tag.DistinguishedName }
    elseif ($Node.Tag -eq 'WmiFilters') { 'WMI:' + $Node.Parent.Tag.DistinguishedName }
    elseif ($Node.Tag -eq 'PendingGpos') { 'PENDING:' + $Node.Parent.Tag.DistinguishedName }
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
        [object[]]$DeletedGpo,

        # What the account does not manage is shown, greyed; View.ShowUnmanaged of the configuration
        # when not given.
        [Nullable[bool]]$ShowUnmanaged
    )

    if ($null -eq $ShowUnmanaged) { $ShowUnmanaged = Test-PSGPOUnmanagedShown }
    $VisibleGpos = @(if ($ShowUnmanaged) { $Directory.Gpos } else { $Directory.GetVisibleGpos() })
    # A creator follows its own GPOs only, an approver every one (IsPendingFollowed).
    $Pending = @($VisibleGpos | Where-Object { $Directory.IsPendingFollowed($_) })

    # The GPOs waiting for approval linked to an OU or below it, each once.
    function Get-PendingBelow {
        param([GPOToolsSom]$Som)
        @($Som.Links | Where-Object { $_.Gpo -and $Directory.IsPendingFollowed($_.Gpo) } | ForEach-Object { $_.Gpo.Id })
        foreach ($Child in $Som.Children) { Get-PendingBelow $Child }
    }

    # A GPO waiting for approval: orange, red when it applies already.
    function Add-PendingGpo {
        param([GPOToolsGpo]$Gpo, [AvaloniaTreeNode]$Parent)
        $Label = $Gpo.DisplayName + $(if ($Gpo.AppliesWhilePending()) { Get-PSGPOText ' (waiting for approval, but it applies)' } else { Get-PSGPOText ' (waiting for approval)' })
        $Node = New-Node ($Label + (Get-RedirectedText $Gpo)) 'document-settings' $Gpo $Parent
        $Node.IconBrush = if ($Gpo.AppliesWhilePending() -or $Directory.IsGpoRedirected($Gpo)) { '#C50F1F' } else { '#CA5010' }
    }

    # A GPO whose gPCFileSysPath is another folder (IsGpoRedirected): said, in red.
    function Get-RedirectedText {
        param([GPOToolsGpo]$Gpo)
        if ($Gpo -and $Directory.IsGpoRedirected($Gpo)) { Get-PSGPOText ' (redirected to another folder)' } else { '' }
    }

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
        $Header = if ($Som.BlockInheritance) { Get-PSGPOText '{0} (blocks inheritance)' $Som.Name } else { $Som.Name }
        # An OU with GPOs waiting for approval below it: said, so that they are found without
        # expanding every OU.
        if ($Pending.Count -and $Som.Kind -ne [GPOToolsSomKind]::Domain) {
            $Count = @(Get-PendingBelow $Som | Select-Object -Unique).Count
            if ($Count) { $Header += Get-PSGPOText ' ({0} waiting for approval)' $Count }
        }
        $Icon = if ($Som.Kind -eq [GPOToolsSomKind]::Domain) { 'globe' } elseif ($Som.BlockInheritance) { 'folder-prohibited' } else { 'folder' }
        $Node = New-Node $Header $Icon $Som $Parent
        # An OU where the account does not link GPOs: greyed, as its links; without what the account
        # does not manage, only the path to its OUs, without its links.
        if (-not $Som.CanLink) { $Node.IconBrush = '#8A8886' }

        foreach ($Link in @($Som.Links | Where-Object { $ShowUnmanaged -or $Som.CanLink } | Sort-Object Order)) {
            $LinkHeader = if ($Link.Gpo) { $Link.Gpo.DisplayName } else { Get-PSGPOText 'GPO not found ({0})' $Link.GpoDistinguishedName }
            if ($Link.Gpo -and $Link.Gpo.AppliesWhilePending()) { $LinkHeader += Get-PSGPOText ' (waiting for approval, but it applies)' }
            elseif ($Link.Gpo -and $Link.Gpo.ApprovalState -eq 'Pending') { $LinkHeader += Get-PSGPOText ' (waiting for approval)' }
            if ($Link.Enforced) { $LinkHeader += Get-PSGPOText ' (enforced)' }
            if (-not $Link.Enabled) { $LinkHeader += Get-PSGPOText ' (link disabled)' }
            $LinkHeader += Get-RedirectedText $Link.Gpo
            $LinkIcon = if (-not $Link.Enabled) { 'link-dismiss' } elseif ($Link.Enforced) { 'lock-closed' } else { 'link' }
            $LinkNode = New-Node $LinkHeader $LinkIcon $Link $Node
            if (-not $Som.CanLink) { $LinkNode.IconBrush = '#8A8886' }
            if ($Link.Gpo -and $Directory.IsGpoRedirected($Link.Gpo)) { $LinkNode.IconBrush = '#C50F1F' }
        }
        foreach ($Child in $Som.Children) { if ($ShowUnmanaged -or $Directory.IsSomVisible($Child)) { [void](Add-Som $Child $Node) } }
        $Node
    }

    $Roots = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $DomainNode = Add-Som $Directory.Domain $null
    $DomainNode.IsExpanded = $true

    $GposNode = New-Node (Get-PSGPOText 'Group Policy Objects') 'library' 'GroupPolicyObjects' $DomainNode
    foreach ($Gpo in $VisibleGpos) {
        if ($Gpo.ApprovalState -eq 'Pending') {
            Add-PendingGpo $Gpo $GposNode
        } else {
            $Node = New-Node ($Gpo.DisplayName + (Get-RedirectedText $Gpo)) 'document-settings' $Gpo $GposNode
            # A GPO the account does not edit: greyed, it reads it only; redirected: red.
            if (-not $Gpo.CanEdit) { $Node.IconBrush = '#8A8886' }
            if ($Directory.IsGpoRedirected($Gpo)) { $Node.IconBrush = '#C50F1F' }
        }
    }
    # The GPOs waiting for approval, when there are: expanded when the console opens (no node
    # expanded yet), then as the account leaves it.
    if ($Pending.Count) {
        $PendingNode = New-Node (Get-PSGPOText 'Waiting for approval ({0})' $Pending.Count) 'shield' 'PendingGpos' $DomainNode
        $PendingNode.IconBrush = '#CA5010'
        if (-not $Expanded -or -not $Expanded.Count) { $PendingNode.IsExpanded = $true }
        foreach ($Gpo in $Pending) { Add-PendingGpo $Gpo $PendingNode }
    }
    # WMI Filters, as GPMC: every filter of the domain.
    $WmiNode = New-Node (Get-PSGPOText 'WMI Filters') 'filter' 'WmiFilters' $DomainNode
    foreach ($Filter in $Directory.WmiFilters) { [void](New-Node $Filter.Name 'filter' $Filter $WmiNode) }
    if ($null -ne $DeletedGpo) {
        $DeletedNode = New-Node (Get-PSGPOText 'Deleted GPOs') 'delete' 'DeletedGpos' $DomainNode
        foreach ($Backup in $DeletedGpo) {
            $Node = New-Node $Backup.DisplayName 'document-settings' $Backup $DeletedNode
            $Node.IconBrush = '#8A8886'
        }
    }

    $Roots.Add($DomainNode)
    # Comma keeps PowerShell from unrolling the collection into the pipeline.
    , $Roots
}
