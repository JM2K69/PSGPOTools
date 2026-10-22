function Set-PSGPOWmiFilter {
    <#
    .SYNOPSIS
        Changes a WMI filter of the domain: its name, description or queries, as GPMC edits a filter.
    .DESCRIPTION
        The msWMI-Som object of the filter is changed in place: its Id does not change, so the GPOs
        linked to it keep it and the computers apply them with its new queries. The change is
        refused if the filter changed in the domain since it was read.
    .PARAMETER Name
        Name (or Id) of the filter to change.
    .PARAMETER NewName
        New name of the filter, unique in the domain.
    .PARAMETER Description
        New description; an empty one removes it.
    .PARAMETER Query
        WQL queries that replace those of the filter.
    .PARAMETER Namespace
        WMI namespace of the queries: of -Query (root\CIMv2 by default), or of the queries the
        filter has without -Query.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Set-PSGPOWmiFilter -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1 AND Version LIKE ''10.0.2%'''
    .EXAMPLE
        Set-PSGPOWmiFilter -Name 'Windows 11' -NewName 'Windows 11 workstations' -Description 'Windows 11, not the servers'
    .OUTPUTS
        PSGPOTools.WmiFilter
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/set-psgpowmifilter/
    .LINK
        Get-PSGPOWmiFilter
    .LINK
        New-PSGPOWmiFilter
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.WmiFilter')]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$NewName,
        [AllowEmptyString()] [string]$Description,
        [string[]]$Query,
        [string]$Namespace,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    $changes = 'NewName', 'Description', 'Query', 'Namespace' | Where-Object { $PSBoundParameters.ContainsKey($_) }
    if (-not $changes) { throw 'Give -NewName, -Description, -Query or -Namespace: what changes.' }
    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    $filter = $Directory.FindWmiFilter($Name)
    if (-not $filter) { throw "No WMI filter named '$Name' in $($Directory.DomainName)." }
    $queries = if ($Query) {
        @($Query | ForEach-Object { [pscustomobject]@{ Namespace = $(if ($Namespace) { $Namespace } else { 'root\CIMv2' }); Query = $_ } })
    } else {
        @($filter.Queries | ForEach-Object { [pscustomobject]@{ Namespace = $(if ($Namespace) { $Namespace } else { $_.Namespace }); Query = $_.Query } })
    }
    $newName = if ($NewName) { $NewName } else { $filter.Name }
    $newDescription = if ($PSBoundParameters.ContainsKey('Description')) { $Description } else { $filter.Description }
    if (-not $PSCmdlet.ShouldProcess("WMI filter '$($filter.Name)' of $($Directory.DomainName)", "Change it ($($changes -join ', '))")) { return }
    $Directory.EditWmiFilter($filter, $newName, $newDescription, $queries)
    Get-PSGPOWmiFilter -Directory $Directory -Name $filter.Name
}
