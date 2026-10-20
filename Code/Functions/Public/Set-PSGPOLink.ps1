function Set-PSGPOLink {
    <#
    .SYNOPSIS
        Enables, disables, enforces or moves the links of GPOs, as GPMC does on a link.
    .DESCRIPTION
        Like the Link Enabled and Enforced items of a link in GPMC, and the arrows of its Linked
        Group Policy Objects tab. The change is written to the gPLink of the domain or OU, refused
        when the links changed in the domain meanwhile.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern).
    .PARAMETER Target
        The domain or the OU: its distinguished name, the name of the domain, or the name of an OU
        when only one OU has it.
    .PARAMETER Enabled
        $true enables the link, $false disables it: the GPO no longer applies there.
    .PARAMETER Enforced
        $true enforces the link (the GPO applies even where the inheritance is blocked, and wins
        over the GPOs linked below), $false no longer does.
    .PARAMETER Order
        The link order to move the link to: 1 is the highest precedence.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Set-PSGPOLink -Name 'C - Servers - Baseline' -Target Servers -Enforced $true -Order 1
    .EXAMPLE
        # Disable a link for a while, without deleting it
        Set-PSGPOLink -Name 'U - Lyon - Printers' -Target Lyon -Enabled $false
    .OUTPUTS
        PSGPOTools.Link
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/set-psgpolink/
    .LINK
        New-PSGPOLink
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.Link')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string[]]$Name,
        [Parameter(Mandatory)] [string]$Target,
        [Nullable[bool]]$Enabled,
        [Nullable[bool]]$Enforced,
        [ValidateRange(1, 2147483647)] [int]$Order,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    begin {
        if ($null -eq $Enabled -and $null -eq $Enforced -and -not $Order) { throw 'Give -Enabled, -Enforced or -Order: what changes.' }
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
                $what = @(
                    if ($null -ne $Enabled) { if ($Enabled) { 'enable it' } else { 'disable it' } }
                    if ($null -ne $Enforced) { if ($Enforced) { 'enforce it' } else { 'no longer enforce it' } }
                    if ($Order) { "move it to the link order $Order" }
                ) -join ', '
                if (-not $PSCmdlet.ShouldProcess("Link of the GPO '$($gpo.DisplayName)' to $($som.DistinguishedName)", $what)) { continue }
                if ($null -ne $Enabled -or $null -ne $Enforced) {
                    $newEnabled = if ($null -ne $Enabled) { [bool]$Enabled } else { $link.Enabled }
                    $newEnforced = if ($null -ne $Enforced) { [bool]$Enforced } else { $link.Enforced }
                    $Directory.SetLink($som, $link, $newEnabled, $newEnforced)
                }
                if ($Order) { $Directory.MoveLink($som, $link, $Order) }
                ConvertTo-PSGPOLinkOutput -Som $som -Link $link
            } catch {
                Write-Error "The link of the GPO '$($gpo.DisplayName)' to $($som.Name) is not changed: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
