function Set-PSGPO {
    <#
    .SYNOPSIS
        Sets the status and the WMI filter of GPOs, as GPMC does.
    .DESCRIPTION
        The status (the GPO Status menu of GPMC) says which part of the GPO the computers apply:
        all its settings, those of the computers only (User configuration settings disabled), those
        of the users only, or none. The WMI filter (the WMI Filtering of the Scope tab of GPMC)
        makes the computers apply the GPO only when one of its queries returns something.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern).
    .PARAMETER Status
        Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer
        configuration settings disabled) or Disabled (all settings disabled).
    .PARAMETER WmiFilter
        Name (or Id) of the WMI filter of the domain the GPOs are linked to (Get-PSGPOWmiFilter).
    .PARAMETER NoWmiFilter
        The GPOs are linked to no WMI filter anymore.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Set-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
    .EXAMPLE
        Set-PSGPO -Name 'C - Workstations - *' -WmiFilter 'Workstations'
    .OUTPUTS
        GPOToolsGpo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/set-psgpo/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([GPOToolsGpo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string[]]$Name,
        [ValidateSet('Enabled', 'ComputerOnly', 'UserOnly', 'Disabled')] [string]$Status,
        [string]$WmiFilter,
        [switch]$NoWmiFilter,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    begin {
        if (-not $Status -and -not $WmiFilter -and -not $NoWmiFilter) { throw 'Give -Status, -WmiFilter or -NoWmiFilter: what changes.' }
        if ($WmiFilter -and $NoWmiFilter) { throw 'Give -WmiFilter or -NoWmiFilter, not both.' }
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
        $flags = if ($Status) { @{ Enabled = 0; ComputerOnly = 1; UserOnly = 2; Disabled = 3 }[$Status] }
        $filter = $null
        if ($WmiFilter) {
            $filter = $Directory.FindWmiFilter($WmiFilter)
            if (-not $filter) { throw "No WMI filter named '$WmiFilter' in $($Directory.DomainName): $(@($Directory.WmiFilters.Name) -join ', ')." }
        }
    }
    process {
        foreach ($gpo in @(Find-PSGPOByName -Directory $Directory -Name $Name)) {
            $what = @(
                if ($Status) { "set its status to $Status" }
                if ($filter) { "link it to the WMI filter '$($filter.Name)'" }
                if ($NoWmiFilter) { 'unlink it from its WMI filter' }
            ) -join ', '
            if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", $what)) { continue }
            try {
                if ($Status) { $Directory.SetGpoStatus($gpo, $flags) }
                if ($filter -or $NoWmiFilter) { $Directory.SetWmiFilter($gpo, $filter) }
                $gpo
            } catch {
                Write-Error "The GPO '$($gpo.DisplayName)' is not changed: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
