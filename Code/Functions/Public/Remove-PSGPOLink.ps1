function Remove-PSGPOLink {
    <#
    .SYNOPSIS
        Deletes the links of GPOs to the domain or to an OU, as GPMC "Delete" on a link.
    .DESCRIPTION
        The GPO itself is kept, with its other links; the links after it move up one link order.
        The change is refused when the links changed in the domain meanwhile.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern).
    .PARAMETER Target
        The domain or the OU: its distinguished name, the name of the domain, or the name of an OU
        when only one OU has it.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Remove-PSGPOLink -Name 'U - Lyon - Printers' -Target Lyon
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/remove-psgpolink/
    .LINK
        New-PSGPOLink
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string[]]$Name,
        [Parameter(Mandatory)] [string]$Target,
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
        $som = Resolve-PSGPOSom -Directory $Directory -Target $Target
    }
    process {
        foreach ($gpo in @(Find-PSGPOByName -Directory $Directory -Name $Name)) {
            try {
                $link = Get-PSGPOSomLink -Som $som -Gpo $gpo
                if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", "Delete its link to $($som.DistinguishedName)")) { continue }
                $Directory.RemoveLink($som, $link)
            } catch {
                Write-Error "The link of the GPO '$($gpo.DisplayName)' to $($som.Name) is not deleted: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
