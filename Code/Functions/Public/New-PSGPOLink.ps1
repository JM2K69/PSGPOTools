function New-PSGPOLink {
    <#
    .SYNOPSIS
        Links GPOs to the domain or to an OU, as GPMC "Link an Existing GPO".
    .DESCRIPTION
        The link has the lowest precedence (the last link order), like in GPMC. It is written to
        the gPLink of the domain or OU in one LDAP request that also removes the value read, so
        that a link someone else added meanwhile is never lost: the change is refused instead.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern).
    .PARAMETER Target
        The domain or the OU: its distinguished name, the name of the domain, or the name of an OU
        when only one OU has it.
    .PARAMETER Enforced
        Enforces the link: the GPO applies even where the inheritance is blocked.
    .PARAMETER Disabled
        Creates the link disabled.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        New-PSGPOLink -Name 'C - Servers - Baseline' -Target 'OU=Servers,DC=contoso,DC=com'
    .OUTPUTS
        PSGPOTools.Link
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/new-psgpolink/
    .LINK
        Set-PSGPOLink
    .LINK
        Remove-PSGPOLink
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.Link')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string[]]$Name,
        [Parameter(Mandatory)] [string]$Target,
        [switch]$Enforced,
        [switch]$Disabled,
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
            if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", "Link it to $($som.DistinguishedName)")) { continue }
            try {
                $link = $Directory.NewLink($som, $gpo)
                if ($Enforced -or $Disabled) { $Directory.SetLink($som, $link, -not $Disabled, [bool]$Enforced) }
                ConvertTo-PSGPOLinkOutput -Som $som -Link $link
            } catch {
                Write-Error "The GPO '$($gpo.DisplayName)' is not linked to $($som.Name): $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
