function Get-PSGPOWmiFilter {
    <#
    .SYNOPSIS
        The WMI filters of the domain, and the GPOs linked to each one.
    .DESCRIPTION
        As the WMI Filters container of GPMC: the msWMI-Som objects of CN=SOM,CN=WMIPolicy,
        CN=System of the domain, with their queries. A computer applies a GPO linked to a WMI
        filter only when one of its queries returns something.
    .PARAMETER Name
        Names of the filters (* and ? make a pattern); all of them by default.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOWmiFilter | Format-Table Name, Queries, Gpos
    .OUTPUTS
        PSGPOTools.WmiFilter
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpowmifilter/
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.WmiFilter')]
    param(
        [string[]]$Name = '*',
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    foreach ($filter in $Directory.WmiFilters) {
        if (-not @($Name | Where-Object { Test-PSGPONameMatch -Name $filter.Name -Pattern $_ }).Count) { continue }
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.WmiFilter'
            Name = $filter.Name
            Id = $filter.Id
            Description = $filter.Description
            Queries = $filter.GetQueryText()
            Gpos = [string[]]@($Directory.Gpos | Where-Object { $_.WmiFilterId -eq $filter.Id } | ForEach-Object DisplayName)
            DistinguishedName = $filter.DistinguishedName
        }
    }
}
