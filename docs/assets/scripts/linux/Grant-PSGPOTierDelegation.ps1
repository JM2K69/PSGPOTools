#Requires -Version 7.4
<#
.SYNOPSIS
    Delegates from Linux to the technicians of Tier 1 and Tier 2 of the PSGPOTools lab the
    creation of GPOs, and the links of GPOs to the OUs of their tier.
.DESCRIPTION
    After New-PSGPOTierLab.ps1, for each tier, to its group (GPO-Tier1-Admins with tiers1,
    GPO-Tier2-Admins with tiers2):

    - Link GPOs, as the Delegation tab of GPMC gives it on an OU: read and write of gPLink and
      gPOptions on the OU of the tier and the OUs below it.
    - The creation of GPOs, by -CreationRight:
      - Workflow (by default, as in the lab): the approval workflow of PSGPOTools. The GPOs the
        technicians create wait for the approval of a domain administrator. The configuration of
        the domain must have the workflow enabled with both groups as its creators (the console:
        Settings, Workflow); Initialize-PSGPOWorkflow -Apply then gives them the right to create
        GPOs, in the directory and in SYSVOL.
      - GroupPolicyCreatorOwners: both groups in Group Policy Creator Owners, as GPMC delegates
        the creation of GPOs, without approval.

    What is there is kept: the script can run again. -WhatIf shows what it would change.

    Needs samba-tool and a Kerberos ticket of a domain administrator (kinit administrator); the
    PSGPOTools module for the workflow.
.PARAMETER Server
    The domain controller of the domain.
.PARAMETER CreationRight
    Workflow (approval of PSGPOTools) or GroupPolicyCreatorOwners (GPMC, no approval).
.EXAMPLE
    ./Grant-PSGPOTierDelegation.ps1 -Server dc.hardenbox.labo
.EXAMPLE
    ./Grant-PSGPOTierDelegation.ps1 -Server dc.hardenbox.labo -CreationRight GroupPolicyCreatorOwners -WhatIf
.LINK
    https://jm2k69.github.io/PSGPOTools/en/getting-started/lab/
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$Server,
    [ValidateSet('Workflow', 'GroupPolicyCreatorOwners')] [string]$CreationRight = 'Workflow'
)

$ErrorActionPreference = 'Stop'

$tiers = @(
    @{ Ou = 'Tier 1'; Group = 'GPO-Tier1-Admins' }
    @{ Ou = 'Tier 2'; Group = 'GPO-Tier2-Admins' }
)
# The attributes of the links of an OU (schema of Active Directory).
$linkAttributes = [ordered]@{ gPLink = 'f30e3bbe-9ff0-11d1-b603-0000f80367c1'; gPOptions = 'f30e3bbf-9ff0-11d1-b603-0000f80367c1' }

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
    $ouDN = "OU=$($tier.Ou),$domainDN"
    $sid = "$(@(Invoke-SambaTool 'group', 'show', $tier.Group, '--attributes=objectSid' -AllowFailure) -match '^objectSid: ' | Select-Object -First 1)" -replace '^objectSid: '
    if (-not $sid) { throw "No group $($tier.Group): run New-PSGPOTierLab.ps1 first." }

    # Link GPOs: read and write of gPLink and gPOptions, on the OU and the OUs below it (CI).
    foreach ($attribute in $linkAttributes.GetEnumerator()) {
        $ace = "(OA;CI;RPWP;$($attribute.Value);;$sid)"
        $acl = (@(Invoke-SambaTool 'dsacl', 'get', "--objectdn=$ouDN") -join '').ToLowerInvariant()
        if ($acl.Contains($ace.ToLowerInvariant())) { Write-Host "  $($tier.Group) writes $($attribute.Key) of $ouDN"; continue }
        if (-not $PSCmdlet.ShouldProcess($ouDN, "Let $($tier.Group) write $($attribute.Key), on this OU and the OUs below it")) { continue }
        $null = Invoke-SambaTool 'dsacl', 'set', "--objectdn=$ouDN", "--sddl=$ace"
        Write-Host "  $($tier.Group) now writes $($attribute.Key) of $ouDN"
    }
}

# The creation of GPOs.
$groups = @($tiers | ForEach-Object { $_.Group })
if ($CreationRight -eq 'GroupPolicyCreatorOwners') {
    $members = @(Invoke-SambaTool 'group', 'listmembers', 'Group Policy Creator Owners')
    foreach ($group in $groups) {
        if ($members -contains $group) { Write-Host "  $group is in Group Policy Creator Owners"; continue }
        if (-not $PSCmdlet.ShouldProcess('Group Policy Creator Owners', "Add $group")) { continue }
        $null = Invoke-SambaTool 'group', 'addmembers', 'Group Policy Creator Owners', $group
        Write-Host "  $group added to Group Policy Creator Owners"
    }
} else {
    if (-not (Get-Module PSGPOTools)) { Import-Module PSGPOTools -ErrorAction Stop }
    # Read only: -WhatIf is for the changes.
    $workflow = (& { $WhatIfPreference = $false; Get-PSGPOConfiguration -Server $Server }).Configuration.Workflow
    $creators = @("$($workflow.Creators)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $workflow.Enabled -or @($groups | Where-Object { $creators -notcontains $_ }).Count) {
        throw "The approval workflow of the domain must be enabled, with $($groups -join ' and ') as its creators: in the console, Settings, Workflow (Enabled, Creators = '$($groups -join ', ')'), then run this script again. Or give -CreationRight GroupPolicyCreatorOwners."
    }
    # The right to create GPOs, in the directory and in SYSVOL: what is missing, added.
    Initialize-PSGPOWorkflow -Server $Server -Apply -WhatIf:$WhatIfPreference | Format-Table Target, Account, State -AutoSize
}
Write-Host 'Next: kinit tiers1 (or tiers2), then open the console: Show-GPOManagerAvalonia.'
