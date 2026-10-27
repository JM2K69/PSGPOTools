# Reads the domain of a directory again, from the same domain controller or from -Server (Change
# Domain Controller... of GPMC), with the same account and transport (-Credential, LDAPS, port),
# and puts it in place in the directory object: what holds it keeps it. The configuration of the
# domain is read again too.
function Update-PSGPODirectoryFromDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [string]$Server
    )

    $read = @{ Server = $(if ($Server) { $Server } else { $Directory.Server }); ErrorAction = 'Stop'; WarningAction = 'SilentlyContinue' }
    if ($Directory.Credential) { $read.Credential = $Directory.Credential }
    if ($Directory.UseSsl) { $read.UseSsl = $true }
    if ($Directory.Port) { $read.Port = $Directory.Port }
    $again = Get-PSGPODirectory @read
    $Directory.ReplaceWith($again)
    Use-PSGPODomainConfiguration -Directory $Directory -Force
}

# The object of $Directory that stands for $Item of the directory before it was read again: the
# same SOM (by distinguished name), GPO (by Id) or link (by its SOM and GPO); $Item itself for the
# fixed nodes (Group Policy Objects, Deleted GPOs), $null when it is not there anymore.
function Find-PSGPODirectoryItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [AllowNull()] $Item,
        # The distinguished name of the SOM of a link
        [string]$LinkSom
    )

    if ($null -eq $Item) { return $null }
    if ($Item -is [string]) { return $Item }
    if ($Item -is [GPOToolsSom]) { return $Directory.FindSom($Item.DistinguishedName) }
    if ($Item -is [GPOToolsGpo]) { return $Directory.Gpos | Where-Object Id -EQ $Item.Id | Select-Object -First 1 }
    if ($Item -is [GPOToolsGpoLink] -and $LinkSom) {
        $som = $Directory.FindSom($LinkSom)
        if ($som) { return $som.Links | Where-Object { [string]::Equals($_.GpoDistinguishedName, $Item.GpoDistinguishedName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1 }
    }
    $null
}
