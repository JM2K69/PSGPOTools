function Set-PSGPOPermission {
    <#
    .SYNOPSIS
        Changes the permissions of GPOs, as the Delegation and Scope tabs of GPMC do.
    .DESCRIPTION
        -Permission gives an account one level on the GPO, in place of what it had, as the
        Delegation tab of GPMC (Set-GPPermission -Replace): GpoRead, GpoApply (read and apply),
        GpoEdit, GpoEditDeleteModifySecurity, or None to remove the account. An editor that
        applied the GPO keeps applying it.

        -SecurityFiltering Add or Remove changes the security filtering, as the Scope tab of GPMC:
        Add makes the account read and apply the GPO (its other rights kept); Remove makes it stop
        applying the GPO, and stop reading it when that was all it did. Authenticated Users keeps
        reading it: the computers must read every GPO (MS16-072).

        The permissions are written on the GPO in the directory, then on its SYSVOL folder and
        everything in it, as GPMC does. A GPO waiting for its approval is refused: its
        permissions are set when it is approved.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern).
    .PARAMETER Account
        The account: a group, user or computer of the domain (its name, DOMAIN\name, a computer
        as PC01$, or a SID), or a well-known one (Authenticated Users, SYSTEM...).
    .PARAMETER Permission
        GpoRead, GpoApply, GpoEdit, GpoEditDeleteModifySecurity or None.
    .PARAMETER SecurityFiltering
        Add or Remove: the account applies the GPO, or no longer does.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Set-PSGPOPermission -Name 'C - Workstations - BitLocker' -Account 'GPO-Tier2-Admins' -Permission GpoEdit
    .EXAMPLE
        Set-PSGPOPermission -Name 'C - Workstations - BitLocker' -Account 'Paris-Workstations' -SecurityFiltering Add
    .OUTPUTS
        PSGPOTools.Permission
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Permission')]
    [OutputType('PSGPOTools.Permission')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string[]]$Name,
        [Parameter(Mandatory)] [string]$Account,
        [Parameter(Mandatory, ParameterSetName = 'Permission')]
        [ValidateSet('GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity', 'None')] [string]$Permission,
        [Parameter(Mandatory, ParameterSetName = 'Filtering')] [ValidateSet('Add', 'Remove')] [string]$SecurityFiltering,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    begin {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
        $principal = Resolve-PSGPOApplyTo -Directory $Directory -Name $Account
    }
    process {
        foreach ($gpo in @(Find-PSGPOByName -Directory $Directory -Name $Name)) {
            $what = if ($PSCmdlet.ParameterSetName -eq 'Filtering') { "$(if ($SecurityFiltering -eq 'Add') { 'add' } else { 'remove' }) $($principal.Name) $(if ($SecurityFiltering -eq 'Add') { 'to' } else { 'from' }) its security filtering" }
                elseif ($Permission -eq 'None') { "remove the permissions of $($principal.Name)" }
                else { "give $($principal.Name) the permission $Permission" }
            if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", $what)) { continue }
            try {
                if ($PSCmdlet.ParameterSetName -eq 'Filtering') { $Directory.SetGpoSecurityFiltering($gpo, $principal.Sid, $SecurityFiltering -eq 'Add') }
                else { $Directory.SetGpoPermission($gpo, $principal.Sid, $Permission) }
                Get-PSGPOPermissionRow -Directory $Directory -Gpo $gpo | Where-Object Sid -EQ $principal.Sid
            } catch {
                Write-Error "The permissions of the GPO '$($gpo.DisplayName)' are not changed: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
