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

        # GPOToolsSom, GPOToolsGpoLink, GPOToolsGpo or 'GroupPolicyObjects'
        [AllowNull()]
        $Item
    )

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

    $Detail = @{ Title = 'Select an item in the tree'; Properties = @(); LinksHeader = ''; Links = @(); Gpo = $null; Som = $null }

    if ($Item -is [GPOToolsSom]) {
        $Detail.Som = $Item
        $Detail.Title = $Item.Name
        $Detail.Properties = @(
            New-Row 'Type' $(if ($Item.Kind -eq [GPOToolsSomKind]::Domain) { 'Domain' } else { 'Organizational unit' })
            New-Row 'Distinguished name' $Item.DistinguishedName
            New-Row 'Block inheritance' $(if ($Item.BlockInheritance) { 'Yes' } else { 'No' })
        )
        if ($Item.Kind -eq [GPOToolsSomKind]::Domain -and $Directory -is [GPOToolsLdapDirectory]) {
            $Detail.Properties += New-Row 'Domain controller' $Directory.Server
            $Detail.Properties += New-Row 'Directory service' $Directory.ServerType
        }
        $Detail.LinksHeader = "Linked Group Policy Objects ($($Item.Links.Count))"
        $Detail.Links = @(foreach ($Link in @($Item.Links | Sort-Object Order)) { New-LinkRow $Link $Link.GetDisplayName() '' })
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
        $Found = @($Directory.GetLinksOf($Gpo) | Sort-Object { $_.Som.DistinguishedName.Length }, { $_.Som.DistinguishedName })
        $Detail.LinksHeader = "Links ($($Found.Count))"
        $Detail.Links = @(foreach ($Pair in $Found) { New-LinkRow $Pair.Link $Pair.Som.Name $Pair.Som.DistinguishedName })
    } elseif ($Item -eq 'GroupPolicyObjects') {
        $Detail.Title = "Group Policy Objects in $($Directory.DomainName)"
        $Detail.Properties = @(foreach ($Gpo in $Directory.Gpos) { New-Row $Gpo.DisplayName $Gpo.GetStatus() })
    }
    $Detail
}
