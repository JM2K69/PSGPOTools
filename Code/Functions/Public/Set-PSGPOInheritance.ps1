function Set-PSGPOInheritance {
    <#
    .SYNOPSIS
        Blocks the inheritance of the domain or of an OU, or not, as GPMC "Block Inheritance".
    .DESCRIPTION
        Where the inheritance is blocked, the GPOs linked to the parents no longer apply, but for
        the enforced links. It is bit 0 of the gPOptions of the domain or OU, written only if it
        did not change meanwhile.
    .PARAMETER Target
        The domain or the OU: its distinguished name, the name of the domain, or the name of an OU
        when only one OU has it.
    .PARAMETER Blocked
        $true blocks the inheritance, $false no longer does.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Set-PSGPOInheritance -Target 'OU=Kiosks,DC=contoso,DC=com' -Blocked $true
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string]$Target,
        [Parameter(Mandatory)] [bool]$Blocked,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    $som = Resolve-PSGPOSom -Directory $Directory -Target $Target
    $what = if ($Blocked) { 'Block the inheritance' } else { 'No longer block the inheritance' }
    if (-not $PSCmdlet.ShouldProcess($som.DistinguishedName, $what)) { return }
    $Directory.SetBlockInheritance($som, $Blocked)
}
