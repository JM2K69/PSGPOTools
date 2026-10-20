#Requires -Version 7.4
<#
.SYNOPSIS
    Delegates from Windows, finely, to the technicians of Tier 1 and Tier 2 of the PSGPOTools lab the
    creation of GPOs, and the links of GPOs to the OUs of their tier.
.DESCRIPTION
    After New-PSGPOTierLab.ps1, for each tier, to its group (GPO-Tier1-Admins with tiers1,
    GPO-Tier2-Admins with tiers2):

    - Link GPOs, as the Delegation tab of GPMC gives it on an OU: read and write of gPLink and
      gPOptions on the OU of the tier and the OUs below it.
    - The creation of GPOs, through the approval workflow of PSGPOTools: a fine delegation,
      never Group Policy Creator Owners (which creates GPOs outside the workflow). The
      configuration of the domain must have the workflow enabled with both groups as its
      creators (the console: Settings, Workflow); Initialize-PSGPOWorkflow -Apply then gives
      them the right to create groupPolicyContainer objects in CN=Policies,CN=System and
      their folder in the Policies folder of SYSVOL. The GPOs they create wait for the
      approval of a domain administrator.

    What is there is kept: the script can run again. -WhatIf shows what it would change.

    LDAP with the Kerberos identity of the session (System.DirectoryServices, part of Windows):
    no RSAT needed, Active Directory or Samba AD. Run it in a session of a domain administrator;
    the PSGPOTools module for the workflow.
.PARAMETER Server
    A domain controller of the domain; the domain of the computer by default.
.EXAMPLE
    .\Grant-PSGPOTierDelegation.ps1
.EXAMPLE
    .\Grant-PSGPOTierDelegation.ps1 -Server ADDS.powershell.labo -WhatIf
.LINK
    https://jm2k69.github.io/PSGPOTools/en/getting-started/lab/
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Server
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This script is for Windows: on Linux, take the Linux one (samba-tool).' }

$tiers = @(
    @{ Ou = 'Tier 1'; Group = 'GPO-Tier1-Admins' }
    @{ Ou = 'Tier 2'; Group = 'GPO-Tier2-Admins' }
)
# The attributes of the links of an OU (schema of Active Directory).
$linkAttributes = [ordered]@{ gPLink = [guid]'f30e3bbe-9ff0-11d1-b603-0000f80367c1'; gPOptions = [guid]'f30e3bbf-9ff0-11d1-b603-0000f80367c1' }
$readWrite = [System.DirectoryServices.ActiveDirectoryRights]'ReadProperty, WriteProperty'

# An object of the directory, on the domain controller, with Kerberos, signed and sealed.
# The members of a DirectoryEntry are read through psbase: PowerShell adapts the object to its
# LDAP attributes, and .Children or .Properties would be $null.
$prefix = if ($Server) { "LDAP://$Server/" } else { 'LDAP://' }
function Get-Entry {
    param([string]$DistinguishedName)
    # [NullString]::Value, not $null: PowerShell would pass an empty user name and password, an
    # anonymous bind; a null one is the identity of the session.
    [System.DirectoryServices.DirectoryEntry]::new("$prefix$DistinguishedName", [NullString]::Value, [NullString]::Value, [System.DirectoryServices.AuthenticationTypes]'Secure, Signing, Sealing')
}
function Find-Account {
    param([string]$Name)
    $searcher = [System.DirectoryServices.DirectorySearcher]::new((Get-Entry $domainDN), "(sAMAccountName=$Name)", [string[]]'distinguishedName')
    $found = $searcher.FindOne()
    if ($found) { "$($found.Properties['distinguishedname'][0])" }
}

$rootDse = Get-Entry 'RootDSE'
$domainDN = "$($rootDse.psbase.Properties['defaultNamingContext'].Value)"
if (-not $domainDN) { throw "No distinguished name of the domain read from $(if ($Server) { $Server } else { 'the domain of the computer' })." }
if (-not $Server) { $Server = "$($rootDse.psbase.Properties['dnsHostName'].Value)" }
Write-Host "Domain $domainDN, domain controller $Server"

# The workflow first: without it, nothing is changed.
$groups = @($tiers | ForEach-Object { $_.Group })
if (-not (Get-Module PSGPOTools)) { Import-Module PSGPOTools -ErrorAction Stop }
# Read only: -WhatIf is for the changes.
$workflow = (& { $WhatIfPreference = $false; Get-PSGPOConfiguration -Server $Server }).Configuration.Workflow
$creators = @("$($workflow.Creators)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $workflow.Enabled -or @($groups | Where-Object { $creators -notcontains $_ }).Count) {
    throw "The approval workflow of the domain must be enabled, with $($groups -join ' and ') as its creators: in the console, Settings, Workflow (Enabled, Creators = '$($groups -join ', ')'), then run this script again."
}

foreach ($tier in $tiers) {
    $ouDN = "OU=$($tier.Ou),$domainDN"
    $groupDN = Find-Account $tier.Group
    if (-not $groupDN) { throw "No group $($tier.Group): run New-PSGPOTierLab.ps1 first." }
    $sid = [System.Security.Principal.SecurityIdentifier]::new([byte[]](Get-Entry $groupDN).psbase.Properties['objectSid'].Value, 0)

    # Link GPOs: read and write of gPLink and gPOptions, on the OU and the OUs below it.
    foreach ($attribute in $linkAttributes.GetEnumerator()) {
        $ou = Get-Entry $ouDN
        $present = @($ou.psbase.ObjectSecurity.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) | Where-Object {
                $_.IdentityReference -eq $sid -and $_.AccessControlType -eq 'Allow' -and $_.ObjectType -eq $attribute.Value -and
                $_.InheritanceType -eq 'All' -and ($_.ActiveDirectoryRights -band $readWrite) -eq $readWrite
            }).Count
        if ($present) { Write-Host "  $($tier.Group) writes $($attribute.Key) of $ouDN"; continue }
        if (-not $PSCmdlet.ShouldProcess($ouDN, "Let $($tier.Group) write $($attribute.Key), on this OU and the OUs below it")) { continue }
        $ou.psbase.ObjectSecurity.AddAccessRule([System.DirectoryServices.ActiveDirectoryAccessRule]::new($sid, $readWrite,
                [System.Security.AccessControl.AccessControlType]::Allow, $attribute.Value, [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All))
        # The DACL only: the owner and the audit are left as they are.
        $ou.psbase.Options.SecurityMasks = [System.DirectoryServices.SecurityMasks]::Dacl
        $ou.psbase.CommitChanges()
        Write-Host "  $($tier.Group) now writes $($attribute.Key) of $ouDN"
    }
}

# The creation of GPOs: the right to create GPOs, in the directory and in SYSVOL: what is missing, added.
Initialize-PSGPOWorkflow -Server $Server -Apply -WhatIf:$WhatIfPreference | Format-Table Target, Account, State -AutoSize
Write-Host 'Next: log on as tiers1 (or tiers2), then open the console: Show-GPOManagerAvalonia.'
