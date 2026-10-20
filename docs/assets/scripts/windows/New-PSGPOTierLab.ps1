#Requires -Version 7.4
<#
.SYNOPSIS
    Creates the tiering of the PSGPOTools lab from Windows: the OUs of Tier 1 and Tier 2, their
    groups, and a technician account per tier.
.DESCRIPTION
    In the domain of the computer, or of the domain controller -Server, whatever its name (its
    distinguished name is read from the RootDSE of the domain controller):

        OU=Tier 1       OU=Servers, OU=Groups (group GPO-Tier1-Admins)
        OU=Tier 2       OU=Workstations, OU=Users, OU=Groups (group GPO-Tier2-Admins)
        CN=Users        tiers1, member of GPO-Tier1-Admins; tiers2, member of GPO-Tier2-Admins

    What is there is kept: the script can run again, and an account that exists keeps its
    password. -WhatIf shows what it would create.

    LDAP with the Kerberos identity of the session (System.DirectoryServices, part of Windows):
    no RSAT needed, Active Directory or Samba AD. Run it in a session of a domain administrator.
    For a test domain only: the accounts get the password of the lab.
.PARAMETER Server
    A domain controller of the domain; the domain of the computer by default.
.PARAMETER Password
    The password of tiers1 and tiers2; the one of the lab by default.
.EXAMPLE
    .\New-PSGPOTierLab.ps1
.EXAMPLE
    .\New-PSGPOTierLab.ps1 -Server ADDS.powershell.labo -WhatIf
.LINK
    https://jm2k69.github.io/PSGPOTools/en/getting-started/lab/
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Server,
    [securestring]$Password = (ConvertTo-SecureString -String 'H@rdenB0x!' -AsPlainText -Force)
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This script is for Windows: on Linux, take the Linux one (samba-tool).' }

# The tiering: an OU per tier, the OUs below it, the group of its technicians and their account.
$tiers = @(
    @{ Ou = 'Tier 1'; Children = 'Servers', 'Groups'; Group = 'GPO-Tier1-Admins'; User = 'tiers1'; Name = 'Tiers1' }
    @{ Ou = 'Tier 2'; Children = 'Workstations', 'Users', 'Groups'; Group = 'GPO-Tier2-Admins'; User = 'tiers2'; Name = 'Tiers2' }
)

# An object of the directory, on the domain controller, with Kerberos, signed and sealed (the
# password of an account is only set over a sealed connection).
$prefix = if ($Server) { "LDAP://$Server/" } else { 'LDAP://' }
function Get-Entry {
    param([string]$DistinguishedName)
    [System.DirectoryServices.DirectoryEntry]::new("$prefix$DistinguishedName", $null, $null, [System.DirectoryServices.AuthenticationTypes]'Secure, Signing, Sealing')
}
function Test-Entry {
    param([string]$DistinguishedName)
    try { $null = (Get-Entry $DistinguishedName).NativeGuid; $true } catch { $false }
}
# The distinguished name of the account or group of a sAMAccountName, $null when there is none.
function Find-Account {
    param([string]$Name)
    $searcher = [System.DirectoryServices.DirectorySearcher]::new((Get-Entry $domainDN), "(sAMAccountName=$Name)", [string[]]'distinguishedName')
    $found = $searcher.FindOne()
    if ($found) { "$($found.Properties['distinguishedname'][0])" }
}

$rootDse = Get-Entry 'RootDSE'
$domainDN = "$($rootDse.Properties['defaultNamingContext'].Value)"
if (-not $domainDN) { throw "No distinguished name of the domain read from $(if ($Server) { $Server } else { 'the domain of the computer' })." }
$domainName = ($domainDN -split ',' | ForEach-Object { $_ -replace '^DC=' }) -join '.'
$usersDN = "CN=Users,$domainDN"
Write-Host "Domain $domainName ($domainDN), domain controller $($rootDse.Properties['dnsHostName'].Value)"

foreach ($tier in $tiers) {
    $tierDN = "OU=$($tier.Ou),$domainDN"

    # The OU of the tier, then the OUs below it.
    foreach ($ou in @(@{ Name = $tier.Ou; Parent = $domainDN }) + @($tier.Children | ForEach-Object { @{ Name = $_; Parent = $tierDN } })) {
        $dn = "OU=$($ou.Name),$($ou.Parent)"
        if (Test-Entry $dn) { Write-Host "  $dn is there"; continue }
        if (-not $PSCmdlet.ShouldProcess($dn, 'Create the OU')) { continue }
        $entry = (Get-Entry $ou.Parent).Children.Add("OU=$($ou.Name)", 'organizationalUnit')
        $entry.CommitChanges()
        Write-Host "  $dn created"
    }

    # The group of the technicians of the tier, in its Groups OU: global security group.
    $groupDN = Find-Account $tier.Group
    if ($groupDN) { Write-Host "  group $($tier.Group) is there" }
    elseif ($PSCmdlet.ShouldProcess("CN=$($tier.Group),OU=Groups,$tierDN", 'Create the global security group')) {
        $entry = (Get-Entry "OU=Groups,$tierDN").Children.Add("CN=$($tier.Group)", 'group')
        $entry.Properties['sAMAccountName'].Value = $tier.Group
        $entry.Properties['groupType'].Value = [int](0x2 -bor 0x80000000)
        $entry.Properties['description'].Value = "Technicians of $($tier.Ou)"
        $entry.CommitChanges()
        $groupDN = "CN=$($tier.Group),OU=Groups,$tierDN"
        Write-Host "  group $($tier.Group) created"
    }

    # The account of the technician, in the Users container of the domain, as in the lab:
    # created disabled, given its password, then enabled.
    $userDN = Find-Account $tier.User
    if ($userDN) { Write-Host "  account $($tier.User) is there, its password kept" }
    elseif ($PSCmdlet.ShouldProcess("CN=$($tier.Name),$usersDN", 'Create the account')) {
        $entry = (Get-Entry $usersDN).Children.Add("CN=$($tier.Name)", 'user')
        $entry.Properties['sAMAccountName'].Value = $tier.User
        $entry.Properties['userPrincipalName'].Value = "$($tier.User)@$domainName"
        $entry.Properties['givenName'].Value = $tier.Name
        $entry.Properties['displayName'].Value = $tier.Name
        $entry.Properties['description'].Value = "Technician of $($tier.Ou)"
        $entry.CommitChanges()
        $entry.Invoke('SetPassword', (ConvertFrom-SecureString -SecureString $Password -AsPlainText))
        # NORMAL_ACCOUNT, enabled.
        $entry.Properties['userAccountControl'].Value = 0x200
        $entry.CommitChanges()
        $userDN = "CN=$($tier.Name),$usersDN"
        Write-Host "  account $($tier.User) created"
    }

    # The technician in the group of the tier.
    $member = $groupDN -and $userDN -and @((Get-Entry $groupDN).Properties['member'] | ForEach-Object { "$_" }) -contains $userDN
    if ($member) { Write-Host "  $($tier.User) is a member of $($tier.Group)" }
    elseif ($PSCmdlet.ShouldProcess($tier.Group, "Add $($tier.User)")) {
        $group = Get-Entry $groupDN
        $null = $group.Properties['member'].Add($userDN)
        $group.CommitChanges()
        Write-Host "  $($tier.User) added to $($tier.Group)"
    }
}
Write-Host 'Next: Grant-PSGPOTierDelegation.ps1, the rights of the groups on GPOs.'
