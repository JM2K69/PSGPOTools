#Requires -Version 7.4
<#
.SYNOPSIS
    Creates the tiering of the HGPM lab from Linux: the OUs of Tier 1 and Tier 2, their
    groups, and a technician account per tier.
.DESCRIPTION
    In the domain of the domain controller -Server, whatever its name (its distinguished name is
    read from the domain controller):

        OU=Tier 1       OU=Servers, OU=Groups (group GPO-Tier1-Admins)
        OU=Tier 2       OU=Workstations, OU=Users, OU=Groups (group GPO-Tier2-Admins)
        CN=Users        tiers1, member of GPO-Tier1-Admins; tiers2, member of GPO-Tier2-Admins

    What is there is kept: the script can run again, and an account that exists keeps its
    password. -WhatIf shows what it would create.

    Needs samba-tool (Samba AD, or Active Directory over LDAP) and a Kerberos ticket of a domain
    administrator (kinit administrator): no password is asked. For a test domain only: the
    accounts get the password of the lab.
.PARAMETER Server
    The domain controller of the domain.
.PARAMETER Password
    The password of tiers1 and tiers2; the one of the lab by default.
.EXAMPLE
    ./New-PSGPOTierLab.ps1 -Server dc.hardenbox.labo
.EXAMPLE
    ./New-PSGPOTierLab.ps1 -Server dc.hardenbox.labo -WhatIf
.LINK
    https://jm2k69.github.io/PSGPOTools/en/getting-started/lab/
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$Server,
    [securestring]$Password = (ConvertTo-SecureString -String 'H@rdenB0x!' -AsPlainText -Force)
)

$ErrorActionPreference = 'Stop'

# The tiering: an OU per tier, the OUs below it, the group of its technicians and their account.
$tiers = @(
    @{ Ou = 'Tier 1'; Children = 'Servers', 'Groups'; Group = 'GPO-Tier1-Admins'; User = 'tiers1'; Name = 'Tiers1' }
    @{ Ou = 'Tier 2'; Children = 'Workstations', 'Users', 'Groups'; Group = 'GPO-Tier2-Admins'; User = 'tiers2'; Name = 'Tiers2' }
)

# The distinguished name of the domain, from the RootDSE of the domain controller (read without
# an account).
function Get-DomainDistinguishedName {
    param([string]$Server)
    Add-Type -AssemblyName System.DirectoryServices.Protocols
    $connection = [System.DirectoryServices.Protocols.LdapConnection]::new([System.DirectoryServices.Protocols.LdapDirectoryIdentifier]::new($Server, 389))
    try {
        $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Anonymous
        $connection.SessionOptions.ProtocolVersion = 3
        $request = [System.DirectoryServices.Protocols.SearchRequest]::new('', '(objectClass=*)', [System.DirectoryServices.Protocols.SearchScope]::Base, 'defaultNamingContext')
        "$($connection.SendRequest($request).Entries[0].Attributes['defaultNamingContext'][0])"
    } finally {
        $connection.Dispose()
    }
}

# samba-tool on the domain controller, with the Kerberos ticket of the session: its output, or
# $null when it fails and -AllowFailure is given.
function Invoke-SambaTool {
    param([string[]]$Argument, [switch]$AllowFailure)
    # Kerberos only, never a password prompt.
    $output = & samba-tool @Argument -H "ldap://$Server" --use-kerberos=required --no-pass 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "samba-tool $($Argument -join ' ') failed: $($output -join ' ')"
    }
    $output | ForEach-Object { "$_" }
}

if (-not (Get-Command samba-tool -ErrorAction SilentlyContinue)) {
    throw 'samba-tool is needed (Debian/Ubuntu: apt install samba-common-bin), with a Kerberos ticket of a domain administrator (kinit administrator).'
}
$domainDN = Get-DomainDistinguishedName -Server $Server
if (-not $domainDN) { throw "No distinguished name of the domain read from $Server." }
Write-Host "Domain $domainDN, domain controller $Server"

foreach ($tier in $tiers) {
    $tierDN = "OU=$($tier.Ou),$domainDN"

    # The OU of the tier, then the OUs below it.
    $existing = @(Invoke-SambaTool 'ou', 'list', '--full-dn')
    foreach ($dn in @($tierDN) + @($tier.Children | ForEach-Object { "OU=$_,$tierDN" })) {
        if ($existing -contains $dn) { Write-Host "  $dn is there"; continue }
        if (-not $PSCmdlet.ShouldProcess($dn, 'Create the OU')) { continue }
        $null = Invoke-SambaTool 'ou', 'add', $dn
        Write-Host "  $dn created"
    }

    # The group of the technicians of the tier, in its Groups OU.
    if ($null -ne (Invoke-SambaTool 'group', 'show', $tier.Group -AllowFailure)) { Write-Host "  group $($tier.Group) is there" }
    elseif ($PSCmdlet.ShouldProcess("CN=$($tier.Group),OU=Groups,$tierDN", 'Create the global security group')) {
        $null = Invoke-SambaTool 'group', 'add', $tier.Group, "--groupou=OU=Groups,OU=$($tier.Ou)", "--description=Technicians of $($tier.Ou)"
        Write-Host "  group $($tier.Group) created"
    }

    # The account of the technician, in the Users container of the domain, as in the lab.
    if ($null -ne (Invoke-SambaTool 'user', 'show', $tier.User -AllowFailure)) { Write-Host "  account $($tier.User) is there, its password kept" }
    elseif ($PSCmdlet.ShouldProcess("CN=$($tier.Name),CN=Users,$domainDN", 'Create the account')) {
        $plain = ConvertFrom-SecureString -SecureString $Password -AsPlainText
        $null = Invoke-SambaTool 'user', 'create', $tier.User, $plain, "--given-name=$($tier.Name)", "--description=Technician of $($tier.Ou)"
        Write-Host "  account $($tier.User) created"
    }

    # The technician in the group of the tier.
    if (@(Invoke-SambaTool 'group', 'listmembers', $tier.Group -AllowFailure) -contains $tier.User) { Write-Host "  $($tier.User) is a member of $($tier.Group)" }
    elseif ($PSCmdlet.ShouldProcess($tier.Group, "Add $($tier.User)")) {
        $null = Invoke-SambaTool 'group', 'addmembers', $tier.Group, $tier.User
        Write-Host "  $($tier.User) added to $($tier.Group)"
    }
}
Write-Host 'Next: Grant-PSGPOTierDelegation.ps1, the rights of the groups on GPOs.'
