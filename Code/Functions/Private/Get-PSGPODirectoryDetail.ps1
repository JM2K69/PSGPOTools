<#
    Details panel of the Group Policy Management view for the selected tree item (Tag of the
    New-PSGPODirectoryTree node). Kept free of any Avalonia type so it can be tested without a UI.
#>

function Get-PSGPODirectoryDetail {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [GPOToolsDirectory]$Directory,

        # GPOToolsSom, GPOToolsGpoLink, GPOToolsGpo, GPOToolsWmiFilter, 'GroupPolicyObjects',
        # 'WmiFilters', 'DeletedGpos' or the backup of a deleted GPO
        [AllowNull()]
        $Item,

        # The backups of the deleted GPOs, for 'DeletedGpos'
        [AllowEmptyCollection()]
        [object[]]$DeletedGpo = @()
    )

    $Date = { param($Value) if ($Value) { ([datetime]$Value).ToLocalTime().ToString('g') } else { Get-PSGPOText 'unknown date' } }
    $YesNo = { param($Value) if ($Value) { Get-PSGPOText 'Yes' } else { Get-PSGPOText 'No' } }

    # A row of the details: its label in the language of the interface, but a name (-Name).
    function New-Row {
        param([string]$Key, [string]$Value, [switch]$Name)
        $Row = [AvaloniaRegistryRow]::new()
        $Row.Key = if ($Name) { $Key } else { Get-PSGPOText $Key }
        $Row.Value = $Value
        $Row
    }

    function New-LinkRow {
        param([GPOToolsGpoLink]$Link, [string]$Name, [string]$Location)
        $Row = [AvaloniaLinkRow]::new()
        $Row.Order = $Link.Order
        $Row.Name = $Name
        $Row.Location = $Location
        $Row.Enforced = Get-PSGPOText 'Enforced: {0}' (& $YesNo $Link.Enforced)
        $Row.LinkEnabled = Get-PSGPOText 'Link enabled: {0}' (& $YesNo $Link.Enabled)
        $Row.Status = Get-PSGPOText $Link.GetStatus()
        $Row
    }

    $Detail = @{ Title = (Get-PSGPOText 'Select an item in the tree'); Properties = @(); LinksHeader = ''; Links = @(); Gpo = $null; Som = $null; Deleted = $null }

    if ($Item -is [GPOToolsSom]) {
        $Detail.Som = $Item
        $Detail.Title = $Item.Name
        $Detail.Properties = @(
            New-Row 'Type' (Get-PSGPOText $(if ($Item.Kind -eq [GPOToolsSomKind]::Domain) { 'Domain' } else { 'Organizational unit' }))
            New-Row 'Distinguished name' $Item.DistinguishedName
            New-Row 'Block inheritance' (& $YesNo $Item.BlockInheritance)
        )
        if ($Directory.Account) {
            $Detail.Properties += New-Row 'Your rights' (Get-PSGPOText $(if ($Item.CanLink) { 'Link GPOs' } else { 'None: shown as the path to the OUs you manage' }))
        }
        if ($Item.Kind -eq [GPOToolsSomKind]::Domain -and $Directory -is [GPOToolsLdapDirectory]) {
            $Detail.Properties += New-Row 'Domain controller' $Directory.Server
            $Detail.Properties += New-Row 'Directory service' $Directory.ServerType
        }
        if ($Item.Kind -eq [GPOToolsSomKind]::Domain -and $Directory.Workflow -and $Directory.Workflow.Enabled) {
            $Approvers = $Directory.Workflow.Approvers -join ', '
            $Detail.Properties += New-Row 'Approval workflow' $(
                if ($Directory.Workflow.Problem) { Get-PSGPOText 'Cannot be read: {0}' $Directory.Workflow.Problem }
                elseif ($Directory.Workflow.IsApprover) { Get-PSGPOText 'You approve the GPOs (approvers: {0})' $Approvers }
                elseif ($Directory.Workflow.IsCreator) { Get-PSGPOText 'Your GPOs wait for an approval (approvers: {0})' $Approvers }
                else { Get-PSGPOText 'Approvers: {0}; creators: {1}' $Approvers ($Directory.Workflow.Creators -join ', ') })
        }
        if ($Item.Kind -eq [GPOToolsSomKind]::Domain -and $Directory.Account) {
            $Detail.Properties += New-Row 'Connected as' $Directory.Account
            $Detail.Properties += New-Row 'Delegation' (Get-PSGPOText $(if ($Directory.IsLimited()) { 'Limited: only the OUs and GPOs this account manages are shown' } else { 'Full: this account manages every OU and GPO' }))
        }
        $Detail.LinksHeader = Get-PSGPOText 'Linked Group Policy Objects ({0})' $Item.Links.Count
        $Detail.Links = @(foreach ($Link in @($Item.Links | Where-Object { $Item.CanLink } | Sort-Object Order)) { New-LinkRow $Link $Link.GetDisplayName() '' })
        if (-not $Item.CanLink) { $Detail.LinksHeader = Get-PSGPOText 'Linked Group Policy Objects: not shown, no delegation here' }
    } elseif ($Item -is [GPOToolsGpoLink] -and -not $Item.Gpo) {
        $Detail.Title = $Item.GetDisplayName()
        $Detail.Properties = @(
            New-Row 'GPO status' (Get-PSGPOText $Item.GetStatus())
            New-Row 'Distinguished name' $Item.GpoDistinguishedName
            New-Row 'Link order' $Item.Order
        )
    } elseif ($Item -is [GPOToolsGpoLink] -or $Item -is [GPOToolsGpo]) {
        $Gpo = if ($Item -is [GPOToolsGpoLink]) { $Item.Gpo } else { $Item }
        $Detail.Gpo = $Gpo
        $Detail.Title = $Gpo.DisplayName
        $CreatedBy = if ($Gpo.Owner) { Get-PSGPOText ' (created by {0})' $Gpo.Owner } else { '' }
        $Detail.Properties = @(
            New-Row 'Unique ID' ('{' + $Gpo.Id.ToString().ToUpperInvariant() + '}')
            New-Row 'GPO status' (Get-PSGPOText $Gpo.GetStatus())
            if ($Gpo.AppliesWhilePending()) { New-Row 'Approval' (Get-PSGPOText "Waiting for approval, but it APPLIES to {0}: its creator owns it until it is approved, and gave 'Apply Group Policy' back{1}. Approve it (its permissions are rebuilt) or delete it." ($Gpo.SecurityFiltering -join ', ') $CreatedBy) }
            elseif ($Gpo.ApprovalState -eq 'Pending') { New-Row 'Approval' (Get-PSGPOText 'Waiting for approval: it applies to nobody until an approver approves it{0}.' $CreatedBy) }
            elseif ($Gpo.ApprovalState -eq 'Approved') { New-Row 'Approval' (Get-PSGPOText 'Approved') }
            if ($Gpo.RemovedAtApproval.Count) { New-Row 'Removed at approval' (Get-PSGPOText 'Permissions added while it was pending: {0}' ($Gpo.RemovedAtApproval -join ' ')) }
            if ($Gpo.Owner) { New-Row 'Owner' $Gpo.Owner }
            # Security filtering, as the Scope tab of GPMC: who applies the GPO, who is denied it.
            New-Row 'Security filtering' $(
                if ($null -eq $Gpo.SecurityFiltering) { Get-PSGPOText 'Not read (no access to the permissions of the GPO)' }
                elseif ($Gpo.SecurityFiltering.Count -eq 0) { Get-PSGPOText 'Nobody: the GPO applies to no computer or user' }
                else { $Gpo.SecurityFiltering -join ', ' })
            if ($Gpo.DeniedTo.Count) { New-Row 'Denied to' ($Gpo.DeniedTo -join ', ') }
            # WMI filtering, as the Scope tab of GPMC.
            $WmiFilter = $Directory.GetWmiFilter($Gpo)
            New-Row 'WMI filter' $(
                if ($null -eq $Gpo.WmiFilterId) { Get-PSGPOText 'None' }
                elseif ($WmiFilter) { "$($WmiFilter.Name) ($($WmiFilter.GetQueryText()))" }
                else { Get-PSGPOText '{0}: not in the domain anymore, the computers ignore the GPO' ('{' + $Gpo.WmiFilterId.ToString().ToUpperInvariant() + '}') })
            New-Row 'User version' $Gpo.GetUserVersion()
            New-Row 'Computer version' $Gpo.GetComputerVersion()
            New-Row 'Distinguished name' $Gpo.DistinguishedName
            New-Row 'File system path' $Gpo.FileSysPath
        )
        if ($Directory.Account) {
            # A slice, not Select-Object: the pipeline wraps the rows in PSObject, which Avalonia cannot bind.
            $Detail.Properties = @($Detail.Properties[0..1]) + @(New-Row 'Your rights' (Get-PSGPOText $(if ($Gpo.CanEdit) { 'Edit settings' } else { 'Read only' }))) + @($Detail.Properties[2..($Detail.Properties.Count - 1)])
        }
        $Found = @($Directory.GetLinksOf($Gpo) | Sort-Object { $_.Som.DistinguishedName.Length }, { $_.Som.DistinguishedName })
        $Detail.LinksHeader = Get-PSGPOText 'Links ({0})' $Found.Count
        $Detail.Links = @(foreach ($Pair in $Found) { New-LinkRow $Pair.Link $Pair.Som.Name $Pair.Som.DistinguishedName })
    } elseif ($Item -and $Item.PSObject.TypeNames -contains 'PSGPOTools.Backup') {
        # A deleted GPO, as its newest backup has it.
        $Detail.Deleted = $Item
        $Detail.Title = Get-PSGPOText '{0} (deleted)' $Item.DisplayName
        $Detail.Properties = @(
            New-Row 'Unique ID' ('{' + $Item.Id.ToString().ToUpperInvariant() + '}')
            New-Row 'Last backup' $(if ($Item.BackedUpBy) { Get-PSGPOText '{0}, by {1}' (& $Date $Item.BackedUp) $Item.BackedUpBy } else { & $Date $Item.BackedUp })
            if ($Item.Comment) { New-Row 'Comment' $Item.Comment }
            New-Row 'GPO status' (Get-PSGPOText $Item.Status)
            New-Row 'Security filtering' $(if ($null -eq $Item.SecurityFiltering) { Get-PSGPOText 'Not read' } else { @($Item.SecurityFiltering) -join ', ' })
            if (@($Item.DeniedTo | Where-Object { $_ }).Count) { New-Row 'Denied to' (@($Item.DeniedTo) -join ', ') }
            New-Row 'Was linked to' $(if (@($Item.Links).Count) { @($Item.Links | ForEach-Object { $_.Container }) -join [Environment]::NewLine } else { Get-PSGPOText 'Nothing' })
            New-Row 'Backup' $Item.Path
        )
    } elseif ($Item -eq 'DeletedGpos') {
        $Detail.Title = Get-PSGPOText 'Deleted GPOs of {0}' $Directory.DomainName
        # Not "= if (...) { @(...) }": the output of if unrolls a list of one row.
        $Detail.Properties = @(foreach ($Backup in $DeletedGpo) { New-Row $Backup.DisplayName (Get-PSGPOText 'Last backup: {0}' (& $Date $Backup.BackedUp)) -Name })
        if (-not $DeletedGpo.Count) { $Detail.Properties = @(New-Row 'None' (Get-PSGPOText 'No GPO deleted from the domain has a backup in the folder of the History tab.')) }
    } elseif ($Item -eq 'WmiFilters') {
        $Detail.Title = Get-PSGPOText 'WMI Filters in {0}' $Directory.DomainName
        $Detail.Properties = @(foreach ($Filter in $Directory.WmiFilters) { New-Row $Filter.Name $Filter.GetQueryText() -Name })
        if (-not $Directory.WmiFilters.Count) { $Detail.Properties = @(New-Row 'None' (Get-PSGPOText 'No WMI filter in the domain: New WMI Filter... in the context menu creates one.')) }
    } elseif ($Item -is [GPOToolsWmiFilter]) {
        $Detail.Title = $Item.Name
        $Users = @($Directory.Gpos | Where-Object { $_.WmiFilterId -eq $Item.Id } | ForEach-Object DisplayName)
        $Detail.Properties = @(
            New-Row 'Type' (Get-PSGPOText 'WMI filter')
            New-Row 'Description' $(if ($Item.Description) { $Item.Description } else { Get-PSGPOText '(none)' })
            foreach ($Query in @($Item.Queries)) { New-Row 'Query' "$($Query.Namespace): $($Query.Query)" }
            New-Row 'GPOs using it' $(if ($Users.Count) { $Users -join [Environment]::NewLine } else { Get-PSGPOText 'None' })
            New-Row 'Unique ID' ('{' + $Item.Id.ToString().ToUpperInvariant() + '}')
            New-Row 'Distinguished name' $Item.DistinguishedName
        )
    } elseif ($Item -eq 'GroupPolicyObjects') {
        $Detail.Title = Get-PSGPOText 'Group Policy Objects in {0}' $Directory.DomainName
        $Detail.Properties = @(foreach ($Gpo in $Directory.GetVisibleGpos()) { New-Row $Gpo.DisplayName (Get-PSGPOText $Gpo.GetStatus()) -Name })
    }
    $Detail
}
