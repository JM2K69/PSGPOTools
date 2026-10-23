function Set-PSGPOWmiFilterPermission {
    <#
    .SYNOPSIS
        Changes the delegation of the WMI filters, as the Delegation tabs of GPMC do.
    .DESCRIPTION
        Gives an account one level, in place of what it had (its own ACEs are replaced, the
        inherited ones stay), with the ACEs GPMC writes:

        Without -Name, on WMI Filters: WmiCreate (Creator owner: the account creates filters and
        changes those it created) or WmiFullControl (it creates filters and changes all of them,
        those created before included).

        With -Name, on each filter: WmiEdit (the account changes its name, description and
        queries) or WmiFullControl (it also deletes it and changes its permissions).

        None removes the permissions of the account there.
    .PARAMETER Name
        Names of the WMI filters (* and ? make a pattern); the WMI Filters container without it.
    .PARAMETER Account
        The account: a group or user of the domain (its name, DOMAIN\name or a SID), or a
        well-known one.
    .PARAMETER Permission
        WmiCreate (WMI Filters only), WmiEdit (a filter only), WmiFullControl or None.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Set-PSGPOWmiFilterPermission -Account 'GPO-Tier1-Admins' -Permission WmiCreate
    .EXAMPLE
        Set-PSGPOWmiFilterPermission -Name 'Workstations' -Account 'GPO-Tier2-Admins' -Permission WmiEdit
    .OUTPUTS
        PSGPOTools.WmiFilterPermission
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/set-psgpowmifilterpermission/
    .LINK
        Get-PSGPOWmiFilterPermission
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.WmiFilterPermission')]
    param(
        [string[]]$Name,
        [Parameter(Mandatory)] [string]$Account,
        [Parameter(Mandatory)] [ValidateSet('WmiCreate', 'WmiEdit', 'WmiFullControl', 'None')] [string]$Permission,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if ($Name -and $Permission -eq 'WmiCreate') { throw 'WmiCreate is a permission of WMI Filters, who creates filters: give it without -Name (WmiEdit or WmiFullControl on a filter).' }
    if (-not $Name -and $Permission -eq 'WmiEdit') { throw 'WmiEdit is a permission of a filter: give -Name (WmiCreate or WmiFullControl on WMI Filters).' }
    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    $principal = Resolve-PSGPOApplyTo -Directory $Directory -Name $Account
    # Not "= if (...) { @(...) }": the output of if unrolls @($null) into nothing.
    $targets = @($null)
    if ($Name) { $targets = @(Find-PSGPOWmiFilterByName -Directory $Directory -Name $Name) }
    foreach ($filter in $targets) {
        $where = if ($filter) { "WMI filter '$($filter.Name)'" } else { "WMI Filters of $($Directory.DomainName)" }
        $what = if ($Permission -eq 'None') { "remove the permissions of $($principal.Name)" } else { "give $($principal.Name) the permission $Permission" }
        if (-not $PSCmdlet.ShouldProcess($where, $what)) { continue }
        try {
            $Directory.SetWmiFilterPermission($filter, $principal.Sid, $Permission)
            Get-PSGPOWmiFilterPermission -Directory $Directory -Name $(if ($filter) { $filter.Name }) | Where-Object Sid -EQ $principal.Sid
        } catch {
            Write-Error "The permissions of the $where are not changed: $($_.Exception.GetBaseException().Message)"
        }
    }
}
