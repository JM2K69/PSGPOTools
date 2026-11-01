<#
    The sites of the forest and their links, as GPMC shows them under Sites: read from CN=Sites of
    the configuration of the forest, not changed (the administrators of the forest link GPOs to
    them, with GPMC). The domain controllers and the computers of a site apply the GPOs linked to
    it before those of their domain and OUs. A link of a site may name a GPO of another domain of
    the forest: it is shown as a GPO not found in this domain.
#>

# The sites of the forest from their entries (name or cn, gPLink), their links resolved in the GPOs
# of the directory; no network, so that it can be tested.
function Add-PSGPOSiteEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [AllowEmptyCollection()] [object[]]$SiteEntry = @()
    )

    # By distinguished name, case-insensitive: a gPLink may write it in another case.
    $gpoByDn = @{}
    foreach ($gpo in $Directory.Gpos) { $gpoByDn[$gpo.DistinguishedName] = $gpo }
    foreach ($entry in $SiteEntry) {
        $name = Get-PSGPOLdapValue $entry 'name'
        if (-not $name) { $name = Get-PSGPOLdapValue $entry 'cn' }
        $site = $Directory.AddSite($name, $entry.DistinguishedName)
        $Directory.SetLinks($site, (Get-PSGPOLdapValue $entry 'gPLink'), $gpoByDn)
    }
}

# Reads the sites of the forest of the directory, from the configuration naming context its
# domain controller gives (rootDSE).
function Read-PSGPODomainSite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [string]$ConfigurationNamingContext
    )

    $entries = @(Invoke-PSGPOLdapSearch -Connection $Connection -SearchBase "CN=Sites,$ConfigurationNamingContext" -Scope OneLevel -Filter '(objectClass=site)' -Attribute 'name', 'cn', 'gPLink')
    Add-PSGPOSiteEntry -Directory $Directory -SiteEntry $entries
}
