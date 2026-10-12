# LDAP search entries of a small domain, shaped as Samba 4.22 returns them (attribute names in
# lower case, gPLink DNs in lower case as GPMC writes them). Dot-sourced by the tests, in the
# module scope: New-TestLdapDirectory builds the directory without a domain controller.

function New-TestLdapEntry {
    param([string]$DistinguishedName, [hashtable]$Attributes = @{})
    $Values = @{}
    foreach ($Name in $Attributes.Keys) { $Values[$Name.ToLowerInvariant()] = [string[]]@($Attributes[$Name]) }
    [pscustomobject]@{ DistinguishedName = $DistinguishedName; Attributes = $Values }
}

$TestLdapDomainDN = 'DC=hardenbox,DC=labo'
$TestLdapDefaultDomainPolicy = '{31B2F340-016D-11D2-945F-00C04FB984F9}'
$TestLdapDefaultDcPolicy = '{6AC1786C-016F-11D2-945F-00C04FB984F9}'
$TestLdapWorkstationsPolicy = '{8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E30}'
$TestLdapMissingPolicy = '{0BADF00D-0000-4000-8000-000000000000}'

function Get-TestLdapGpoDN { param([string]$Id) "cn=$Id,cn=policies,cn=system,dc=hardenbox,dc=labo" }

function Get-TestLdapEntrySet {
    $Domain = New-TestLdapEntry $TestLdapDomainDN @{ gPLink = "[LDAP://$(Get-TestLdapGpoDN $TestLdapDefaultDomainPolicy);0]" }
    $Gpos = @(
        New-TestLdapEntry "CN=$TestLdapDefaultDomainPolicy,CN=Policies,CN=System,$TestLdapDomainDN" @{
            cn = $TestLdapDefaultDomainPolicy; displayName = 'Default Domain Policy'; versionNumber = '3'; flags = '0'
            gPCFileSysPath = "\\hardenbox.labo\sysvol\hardenbox.labo\Policies\$TestLdapDefaultDomainPolicy" }
        New-TestLdapEntry "CN=$TestLdapDefaultDcPolicy,CN=Policies,CN=System,$TestLdapDomainDN" @{
            cn = $TestLdapDefaultDcPolicy; displayName = 'Default Domain Controllers Policy'; versionNumber = '1'; flags = '0' }
        New-TestLdapEntry "CN=$TestLdapWorkstationsPolicy,CN=Policies,CN=System,$TestLdapDomainDN" @{
            cn = $TestLdapWorkstationsPolicy; displayName = 'Workstations'; versionNumber = '131074'; flags = '1' }
        # Same name as another GPO: Active Directory allows it.
        New-TestLdapEntry "CN={8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E31},CN=Policies,CN=System,$TestLdapDomainDN" @{
            cn = '{8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E31}'; displayName = 'Workstations'; versionNumber = '0'; flags = '0' }
        # No display name
        New-TestLdapEntry "CN={8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E32},CN=Policies,CN=System,$TestLdapDomainDN" @{
            cn = '{8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E32}' }
        # Not a GPO name: ignored with a warning
        New-TestLdapEntry "CN=NotAGuid,CN=Policies,CN=System,$TestLdapDomainDN" @{ cn = 'NotAGuid' }
    )
    # Children before parents, to check the order does not matter.
    $Ous = @(
        New-TestLdapEntry "OU=Laptops,OU=Workstations,OU=Lyon,$TestLdapDomainDN" @{ name = 'Laptops' }
        New-TestLdapEntry "OU=Workstations,OU=Lyon,$TestLdapDomainDN" @{
            name = 'Workstations'; gPOptions = '1'
            # Link order 1 is the last entry: Workstations (enforced), then the missing GPO (disabled link).
            gPLink = "[LDAP://$(Get-TestLdapGpoDN $TestLdapMissingPolicy);1][LDAP://$(Get-TestLdapGpoDN $TestLdapWorkstationsPolicy);2]" }
        New-TestLdapEntry "OU=Lyon,$TestLdapDomainDN" @{ name = 'Lyon' }
        New-TestLdapEntry "OU=Domain Controllers,$TestLdapDomainDN" @{
            name = 'Domain Controllers'; gPLink = "[LDAP://$(Get-TestLdapGpoDN $TestLdapDefaultDcPolicy);0]" }
        New-TestLdapEntry "OU=Sales\, Paris,$TestLdapDomainDN" @{ name = 'Sales, Paris' }
        # Below a container: not a scope of management of GPMC, ignored with a warning
        New-TestLdapEntry "OU=Orphan,CN=Users,$TestLdapDomainDN" @{ name = 'Orphan' }
    )
    @{ Domain = $Domain; Gpos = $Gpos; Ous = $Ous }
}

function New-TestLdapDirectory {
    $Set = Get-TestLdapEntrySet
    ConvertTo-PSGPOLdapDirectory -Server 'dc.hardenbox.labo' -DomainEntry $Set.Domain -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos 3>$null
}
