function New-PSGPOWmiFilter {
    <#
    .SYNOPSIS
        Creates a WMI filter in the domain, as GPMC "New" in WMI Filters.
    .DESCRIPTION
        A msWMI-Som object in CN=SOM,CN=WMIPolicy,CN=System of the domain, with its WQL queries. A
        computer applies a GPO linked to it (Set-PSGPO -WmiFilter) only when one of its queries
        returns something. Samba AD keeps the filters for the Windows computers of the domain.
    .PARAMETER Name
        Name of the filter, unique in the domain.
    .PARAMETER Query
        WQL queries: SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1 for example.
    .PARAMETER Namespace
        WMI namespace of the queries; root\CIMv2 by default.
    .PARAMETER Description
        What the filter is for.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        New-PSGPOWmiFilter -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
    .EXAMPLE
        New-PSGPOWmiFilter -Name 'Windows 11' -Query "SELECT * FROM Win32_OperatingSystem WHERE Version LIKE '10.0.2%' AND ProductType = 1" -Description 'Windows 11 workstations'
    .OUTPUTS
        PSGPOTools.WmiFilter
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/new-psgpowmifilter/
    .LINK
        Get-PSGPOWmiFilter
    .LINK
        Set-PSGPO
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.WmiFilter')]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string[]]$Query,
        [string]$Namespace = 'root\CIMv2',
        [string]$Description,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    if (-not $PSCmdlet.ShouldProcess("WMI filter '$Name' of $($Directory.DomainName)", 'Create it')) { return }
    $filter = $Directory.NewWmiFilter($Name, $Description, @($Query | ForEach-Object { [pscustomobject]@{ Namespace = $Namespace; Query = $_ } }))
    Get-PSGPOWmiFilter -Directory $Directory -Name $filter.Name
}
