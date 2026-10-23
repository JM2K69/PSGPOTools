function Get-PSGPOWmiFilterPermission {
    <#
    .SYNOPSIS
        The delegation of the WMI filters, as the Delegation tabs of GPMC show it.
    .DESCRIPTION
        Without -Name, the Delegation tab of WMI Filters: who creates WMI filters in the domain,
        WmiCreate (Creator owner: creates filters, changes those it created) or WmiFullControl
        (creates filters, changes all of them). With -Name, the Delegation tab of each filter: who
        changes it, WmiEdit or WmiFullControl. WmiCustom: other rights, or a deny. The accounts
        that only read are not listed, as in GPMC.
    .PARAMETER Name
        Names of the WMI filters (* and ? make a pattern); the WMI Filters container without it.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOWmiFilterPermission
    .EXAMPLE
        Get-PSGPOWmiFilterPermission -Name 'Workstations' | Format-Table Trustee, Permission, Inherited
    .OUTPUTS
        PSGPOTools.WmiFilterPermission
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpowmifilterpermission/
    .LINK
        Set-PSGPOWmiFilterPermission
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.WmiFilterPermission')]
    param(
        [string[]]$Name,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    # Not "= if (...) { @(...) }": the output of if unrolls @($null) into nothing.
    $targets = @($null)
    if ($Name) { $targets = @(Find-PSGPOWmiFilterByName -Directory $Directory -Name $Name) }
    foreach ($filter in $targets) {
        foreach ($row in @($Directory.GetWmiFilterPermissions($filter))) {
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.WmiFilterPermission'
                WmiFilter = if ($filter) { $filter.Name } else { $null }
                Trustee = $row.Name
                Sid = $row.Sid
                Permission = $row.Permission
                Inherited = $row.Inherited
            }
        }
    }
}
