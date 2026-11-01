function Remove-PSGPOStarterGpo {
    <#
    .SYNOPSIS
        Deletes Custom Starter GPOs of the domain.
    .DESCRIPTION
        As GPMC "Delete" on a Starter GPO: its folder of SYSVOL\<domain>\StarterGPOs is deleted.
        The GPOs created from it keep their settings: they are copies. The System Starter GPOs of
        Microsoft are not deleted.
    .PARAMETER Name
        Display name of the Starter GPOs, or a pattern with * and ?.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Remove-PSGPOStarterGpo -Name 'Workstations - Baseline (old)'
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/remove-psgpostartergpo/
    .LINK
        Get-PSGPOStarterGpo
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    foreach ($starter in @(Find-PSGPOStarterGpoByName -Directory $Directory -Name $Name)) {
        if ($starter.Type -eq 'System') { Write-Error "The Starter GPO '$($starter.DisplayName)' is a System Starter GPO of Microsoft: it is not deleted."; continue }
        if (-not $PSCmdlet.ShouldProcess("Starter GPO '$($starter.DisplayName)' in $($Directory.DomainName)", 'Delete it')) { continue }
        try {
            $Directory.RemoveStarterGpo($starter.Id, $starter.DisplayName)
        } catch {
            Write-Error "The Starter GPO '$($starter.DisplayName)' is not deleted: $($_.Exception.GetBaseException().Message)"
        }
    }
}
