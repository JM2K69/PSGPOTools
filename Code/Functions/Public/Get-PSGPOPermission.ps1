function Get-PSGPOPermission {
    <#
    .SYNOPSIS
        Lists the permissions of GPOs, as the Delegation tab of GPMC shows them.
    .DESCRIPTION
        One row per account of the permissions of the GPO, with its level as GPMC names it:
        GpoRead (Read), GpoApply (Read, from the security filtering: it applies the GPO), GpoEdit
        (Edit settings), GpoEditDeleteModifySecurity (Edit settings, delete, modify security) or
        GpoCustom (other rights, or a denial). The inherited permissions come from the Policies
        container of the domain: they are listed, Set-PSGPOPermission does not change them.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern).
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOPermission -Name 'C - Workstations - BitLocker'
    .EXAMPLE
        Get-PSGPOPermission -Name * | Where-Object Permission -EQ GpoEdit
    .OUTPUTS
        PSGPOTools.Permission
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.Permission')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string[]]$Name,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    begin {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
    }
    process {
        foreach ($gpo in @(Find-PSGPOByName -Directory $Directory -Name $Name)) {
            try {
                Get-PSGPOPermissionRow -Directory $Directory -Gpo $gpo
            } catch {
                Write-Error "The permissions of the GPO '$($gpo.DisplayName)' cannot be read: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
