function Remove-PSGPOWmiFilter {
    <#
    .SYNOPSIS
        Deletes WMI filters of the domain that no GPO uses.
    .DESCRIPTION
        As GPMC, a filter a GPO is linked to is not deleted: unlink it first (Set-PSGPO
        -NoWmiFilter). The GPOs of the domain are checked in the directory, those this account
        cannot see included.
    .PARAMETER Name
        Names of the filters (* and ? make a pattern).
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Remove-PSGPOWmiFilter -Name 'Windows 7'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string[]]$Name,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    foreach ($pattern in $Name) {
        $found = @($Directory.WmiFilters | Where-Object { Test-PSGPONameMatch -Name $_.Name -Pattern $pattern })
        if (-not $found) { Write-Error "No WMI filter named '$pattern' in $($Directory.DomainName)."; continue }
        foreach ($filter in $found) {
            if (-not $PSCmdlet.ShouldProcess("WMI filter '$($filter.Name)'", 'Delete it')) { continue }
            try {
                $Directory.RemoveWmiFilter($filter)
            } catch {
                Write-Error "The WMI filter '$($filter.Name)' is not deleted: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
