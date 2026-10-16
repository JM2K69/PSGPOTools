function Import-PSGPODirectory {
    <#
    .SYNOPSIS
        Reads a domain, its OUs, GPOs and GPO links from a JSON description.
    .DESCRIPTION
        Proof of concept of the Group Policy Management view of Show-GPOManagerAvalonia: the
        directory is described in a JSON file instead of being read from Active Directory, and
        the changes made in the window (new GPOs, new links) stay in memory.

        JSON format:
            domain               DNS name of the domain (required)
            gpos                 [ { name (required), id, userVersion, computerVersion,
                                     userEnabled, computerEnabled } ]
            links                links of the domain, by link order (1 first): either the GPO
                                 name or { gpo, enabled, enforced }
            organizationalUnits  [ { name (required), blockInheritance, links, organizationalUnits } ]

        A sample is shipped with the module: Samples/Directory.sample.json.
    .PARAMETER Path
        Path of the JSON file.
    .EXAMPLE
        $Directory = Import-PSGPODirectory -Path (Join-Path (Split-Path (Get-Module PSGPOTools).Path) 'Samples' 'Directory.sample.json')
        Show-GPOManagerAvalonia -Directory $Directory
    #>
    [CmdletBinding()]
    [OutputType([GPOToolsDirectory])]
    Param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Data = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if (-not $Data.domain) { throw "'$Path': the 'domain' property is required." }
    $Directory = [GPOToolsDirectory]::new($Data.domain)
    $Directory.Source = "JSON file $((Resolve-Path -LiteralPath $Path).Path), changes in memory"

    foreach ($Entry in @($Data.gpos)) {
        if ($null -eq $Entry) { continue }
        if (-not $Entry.name) { throw "'$Path': every GPO needs a 'name'." }
        $Gpo = $Directory.AddGpo($Entry.name, $(if ($Entry.id) { [guid]$Entry.id } else { [guid]::Empty }))
        $Gpo.Version = ([int]$Entry.userVersion -shl 16) -bor ([int]$Entry.computerVersion -band 0xFFFF)
        if ($Entry.userEnabled -eq $false) { $Gpo.Flags = $Gpo.Flags -bor 1 }
        if ($Entry.computerEnabled -eq $false) { $Gpo.Flags = $Gpo.Flags -bor 2 }
    }

    function Add-Link {
        param([GPOToolsSom]$Som, $Entries)
        foreach ($Entry in @($Entries)) {
            if ($null -eq $Entry) { continue }
            $Name = if ($Entry -is [string]) { $Entry } else { $Entry.gpo }
            $Gpo = $Directory.FindGpo($Name)
            if (-not $Gpo) { throw "'$Path': $($Som.Name) is linked to '$Name', which is not in 'gpos'." }
            $Link = $Directory.NewLink($Som, $Gpo)
            if ($Entry -isnot [string]) {
                if ($Entry.enabled -eq $false) { $Link.Enabled = $false }
                if ($Entry.enforced) { $Link.Enforced = $true }
            }
        }
    }

    function Add-OrganizationalUnit {
        param([GPOToolsSom]$ParentSom, $Entries)
        foreach ($Entry in @($Entries)) {
            if ($null -eq $Entry) { continue }
            if (-not $Entry.name) { throw "'$Path': every organizational unit needs a 'name'." }
            $Som = $Directory.AddOrganizationalUnit($ParentSom, $Entry.name)
            $Som.BlockInheritance = [bool]$Entry.blockInheritance
            Add-Link $Som $Entry.links
            Add-OrganizationalUnit $Som $Entry.organizationalUnits
        }
    }

    Add-Link $Directory.Domain $Data.links
    Add-OrganizationalUnit $Directory.Domain $Data.organizationalUnits
    # A directory in memory has no configuration of its own: the defaults.
    Use-PSGPODomainConfiguration -Directory $Directory
    $Directory
}
