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

        # GPOToolsSom, GPOToolsGpoLink, GPOToolsGpo, 'GroupPolicyObjects', 'DeletedGpos' or the
        # backup of a deleted GPO
        [AllowNull()]
        $Item,

        # The backups of the deleted GPOs, for 'DeletedGpos'
        [AllowEmptyCollection()]
        [object[]]$DeletedGpo = @()
    )

    $Date = { param($Value) if ($Value) { ([datetime]$Value).ToLocalTime().ToString('g') } else { 'unknown date' } }

    function New-Row {
        param([string]$Key, [string]$Value)
        $Row = [AvaloniaRegistryRow]::new()
        $Row.Key = $Key
        $Row.Value = $Value
        $Row
    }

    function New-LinkRow {
        param([GPOToolsGpoLink]$Link, [string]$Name, [string]$Location)
        $Row = [AvaloniaLinkRow]::new()
        $Row.Order = $Link.Order
        $Row.Name = $Name
        $Row.Location = $Location
        $Row.Enforced = 'Enforced: ' + $(if ($Link.Enforced) { 'Yes' } else { 'No' })
        $Row.LinkEnabled = 'Link enabled: ' + $(if ($Link.Enabled) { 'Yes' } else { 'No' })
        $Row.Status = $Link.GetStatus()
        $Row
    }

    $Detail = @{ Title = 'Select an item in the tree'; Properties = @(); LinksHeader = ''; Links = @(); Gpo = $null; Som = $null; Deleted = $null }

    if ($Item -is [GPOToolsSom]) {
        $Detail.Som = $Item
        $Detail.Title = $Item.Name
        $Detail.Properties = @(
            New-Row 'Type' $(if ($Item.Kind -eq [GPOToolsSomKind]::Domain) { 'Domain' } else { 'Organizational unit' })
            New-Row 'Distinguished name' $Item.DistinguishedName
            New-Row 'Block inheritance' $(if ($Item.BlockInheritance) { 'Yes' } else { 'No' })
        )
        if ($Directory.Account) {
            $Detail.Properties += New-Row 'Your rights' $(if ($Item.CanLink) { 'Link GPOs' } else { 'None: shown as the path to the OUs you manage' })
        }
        if ($Item.Kind -eq [GPOToolsSomKind]::Domain -and $Directory -is [GPOToolsLdapDirectory]) {
            $Detail.Properties += New-Row 'Domain controller' $Directory.Server
            $Detail.Properties += New-Row 'Directory service' $Directory.ServerType
        }
        if ($Item.Kind -eq [GPOToolsSomKind]::Domain -and $Directory.Workflow -and $Directory.Workflow.Enabled) {
            $Detail.Properties += New-Row 'Approval workflow' $(
                if ($Directory.Workflow.Problem) { "Cannot be read: $($Directory.Workflow.Problem)" }
                elseif ($Directory.Workflow.IsApprover) { "You approve the GPOs (approvers: $($Directory.Workflow.Approvers -join ', '))" }
                elseif ($Directory.Workflow.IsCreator) { "Your GPOs wait for an approval (approvers: $($Directory.Workflow.Approvers -join ', '))" }
                else { "Approvers: $($Directory.Workflow.Approvers -join ', '); creators: $($Directory.Workflow.Creators -join ', ')" })
        }
        if ($Item.Kind -eq [GPOToolsSomKind]::Domain -and $Directory.Account) {
            $Detail.Properties += New-Row 'Connected as' $Directory.Account
            $Detail.Properties += New-Row 'Delegation' $(if ($Directory.IsLimited()) { 'Limited: only the OUs and GPOs this account manages are shown' } else { 'Full: this account manages every OU and GPO' })
        }
        $Detail.LinksHeader = "Linked Group Policy Objects ($($Item.Links.Count))"
        $Detail.Links = @(foreach ($Link in @($Item.Links | Where-Object { $Item.CanLink } | Sort-Object Order)) { New-LinkRow $Link $Link.GetDisplayName() '' })
        if (-not $Item.CanLink) { $Detail.LinksHeader = 'Linked Group Policy Objects: not shown, no delegation here' }
    } elseif ($Item -is [GPOToolsGpoLink] -and -not $Item.Gpo) {
        $Detail.Title = $Item.GetDisplayName()
        $Detail.Properties = @(
            New-Row 'GPO status' $Item.GetStatus()
            New-Row 'Distinguished name' $Item.GpoDistinguishedName
            New-Row 'Link order' $Item.Order
        )
    } elseif ($Item -is [GPOToolsGpoLink] -or $Item -is [GPOToolsGpo]) {
        $Gpo = if ($Item -is [GPOToolsGpoLink]) { $Item.Gpo } else { $Item }
        $Detail.Gpo = $Gpo
        $Detail.Title = $Gpo.DisplayName
        $Detail.Properties = @(
            New-Row 'Unique ID' ('{' + $Gpo.Id.ToString().ToUpperInvariant() + '}')
            New-Row 'GPO status' $Gpo.GetStatus()
            if ($Gpo.ApprovalState -eq 'Pending') { New-Row 'Approval' "Waiting for approval: it applies to nobody until an approver approves it$(if ($Gpo.Owner) { " (created by $($Gpo.Owner))" })." }
            elseif ($Gpo.ApprovalState -eq 'Approved') { New-Row 'Approval' 'Approved' }
            if ($Gpo.Owner) { New-Row 'Owner' $Gpo.Owner }
            # Security filtering, as the Scope tab of GPMC: who applies the GPO, who is denied it.
            New-Row 'Security filtering' $(
                if ($null -eq $Gpo.SecurityFiltering) { 'Not read (no access to the permissions of the GPO)' }
                elseif ($Gpo.SecurityFiltering.Count -eq 0) { 'Nobody: the GPO applies to no computer or user' }
                else { $Gpo.SecurityFiltering -join ', ' })
            if ($Gpo.DeniedTo.Count) { New-Row 'Denied to' ($Gpo.DeniedTo -join ', ') }
            New-Row 'User version' $Gpo.GetUserVersion()
            New-Row 'Computer version' $Gpo.GetComputerVersion()
            New-Row 'Distinguished name' $Gpo.DistinguishedName
            New-Row 'File system path' $Gpo.FileSysPath
        )
        if ($Directory.Account) {
            $Detail.Properties = @($Detail.Properties[0..1]) + @(New-Row 'Your rights' $(if ($Gpo.CanEdit) { 'Edit settings' } else { 'Read only' })) + @($Detail.Properties | Select-Object -Skip 2)
        }
        $Found = @($Directory.GetLinksOf($Gpo) | Sort-Object { $_.Som.DistinguishedName.Length }, { $_.Som.DistinguishedName })
        $Detail.LinksHeader = "Links ($($Found.Count))"
        $Detail.Links = @(foreach ($Pair in $Found) { New-LinkRow $Pair.Link $Pair.Som.Name $Pair.Som.DistinguishedName })
    } elseif ($Item -and $Item.PSObject.TypeNames -contains 'PSGPOTools.Backup') {
        # A deleted GPO, as its newest backup has it.
        $Detail.Deleted = $Item
        $Detail.Title = "$($Item.DisplayName) (deleted)"
        $Detail.Properties = @(
            New-Row 'Unique ID' ('{' + $Item.Id.ToString().ToUpperInvariant() + '}')
            New-Row 'Last backup' "$(& $Date $Item.BackedUp)$(if ($Item.BackedUpBy) { ", by $($Item.BackedUpBy)" })"
            if ($Item.Comment) { New-Row 'Comment' $Item.Comment }
            New-Row 'GPO status' $Item.Status
            New-Row 'Security filtering' $(if ($null -eq $Item.SecurityFiltering) { 'Not read' } else { @($Item.SecurityFiltering) -join ', ' })
            if (@($Item.DeniedTo | Where-Object { $_ }).Count) { New-Row 'Denied to' (@($Item.DeniedTo) -join ', ') }
            New-Row 'Was linked to' $(if (@($Item.Links).Count) { @($Item.Links | ForEach-Object { $_.Container }) -join [Environment]::NewLine } else { 'Nothing' })
            New-Row 'Backup' $Item.Path
        )
    } elseif ($Item -eq 'DeletedGpos') {
        $Detail.Title = "Deleted GPOs of $($Directory.DomainName)"
        # Not "= if (...) { @(...) }": the output of if unrolls a list of one row.
        $Detail.Properties = @(foreach ($Backup in $DeletedGpo) { New-Row $Backup.DisplayName "Last backup: $(& $Date $Backup.BackedUp)" })
        if (-not $DeletedGpo.Count) { $Detail.Properties = @(New-Row 'None' 'No GPO deleted from the domain has a backup in the folder of the History tab.') }
    } elseif ($Item -eq 'GroupPolicyObjects') {
        $Detail.Title = "Group Policy Objects in $($Directory.DomainName)"
        $Detail.Properties = @(foreach ($Gpo in $Directory.Gpos) { if ($Directory.IsGpoVisible($Gpo)) { New-Row $Gpo.DisplayName $Gpo.GetStatus() } })
    }
    $Detail
}
