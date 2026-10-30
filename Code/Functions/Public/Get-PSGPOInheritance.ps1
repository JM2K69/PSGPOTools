function Get-PSGPOInheritance {
    <#
    .SYNOPSIS
        The GPOs linked to the domain or to an OU, and those that apply there by inheritance, as the
        Linked Group Policy Objects and Group Policy Inheritance tabs of GPMC (Get-GPInheritance).
    .DESCRIPTION
        One object per domain or OU: Name, ContainerType (Domain, OrganizationalUnit), Path (its
        distinguished name), GpoInheritanceBlocked, and:

        - GpoLinks: the links of the domain or OU, by link order (1 wins): Order, DisplayName,
          GpoId, Enabled, Enforced, Target;
        - InheritedGpoLinks: the GPOs that apply there, by precedence (1 wins), as the Group Policy
          Inheritance tab lists them: first the enforced links, from the domain down (the one
          nearest the domain wins), then the other links, from the domain or OU up to the domain,
          until an OU that blocks the inheritance (its own links included). Precedence,
          DisplayName, GpoId, Enforced, Status (a GPO whose settings are all disabled is listed
          with it), Target (where it is linked). The disabled links are left out.

        The security filtering and the WMI filters, which depend on each computer or user, are not
        taken into account; neither are the links of the sites.
    .PARAMETER Target
        The domain or the OU: its distinguished name, the name of the domain, or the name of an OU
        when only one OU has it.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        (Get-PSGPOInheritance -Target 'OU=Workstations,OU=Tier 2,DC=contoso,DC=com').InheritedGpoLinks | Format-Table Precedence, DisplayName, Enforced, Target
    .EXAMPLE
        Get-PSGPOInheritance -Target contoso.com | Select-Object -ExpandProperty GpoLinks
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpoinheritance/
    .LINK
        Set-PSGPOLink
    .LINK
        Set-PSGPOInheritance
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.GpoInheritance')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Target,

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
        foreach ($item in $Target) {
            $som = Resolve-PSGPOSom -Directory $Directory -Target $item
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.GpoInheritance'
                Name = $som.Name
                ContainerType = "$($som.Kind)"
                Path = $som.DistinguishedName
                GpoInheritanceBlocked = $som.BlockInheritance
                GpoLinks = @(foreach ($link in @($som.Links | Sort-Object Order)) {
                        [pscustomobject]@{
                            PSTypeName = 'PSGPOTools.GpoLinkOrder'
                            Order = $link.Order
                            DisplayName = $link.GetDisplayName()
                            GpoId = if ($link.Gpo) { $link.Gpo.Id }
                            Enabled = $link.Enabled
                            Enforced = $link.Enforced
                            Target = $som.DistinguishedName
                        }
                    })
                InheritedGpoLinks = @(foreach ($row in @(Get-PSGPOSomPrecedence -Som $som -IncludeDisabledGpo)) {
                        [pscustomobject]@{
                            PSTypeName = 'PSGPOTools.InheritedGpoLink'
                            Precedence = $row.Precedence
                            DisplayName = $row.Gpo.DisplayName
                            GpoId = $row.Gpo.Id
                            Enforced = $row.Enforced
                            Status = $row.Gpo.GetStatus()
                            Target = $row.Som.DistinguishedName
                        }
                    })
            }
        }
    }
}
