<#
.SYNOPSIS
    Builds a tiered delegation lab in a test domain, to see the console as a Tier 1 or Tier 2
    technician sees it.
.DESCRIPTION
    Creates, when missing (it can run again):
    - OU=Tier 1 (Servers, Groups) and OU=Tier 2 (Workstations, Users, Groups);
    - the global security groups GPO-Tier1-Admins and GPO-Tier2-Admins, in the Groups OU of
      their tier;
    - for each group, the GPMC delegation "Link GPOs" on its tier OU and the OUs below it (read
      and write of gPLink and gPOptions);
    - a GPO per tier, linked to its Servers / Workstations OU, that the group of the tier can
      edit (GPMC "Edit settings", in the directory and in SYSVOL).
    The accounts of the technicians are not created: they need a password. Create them, add them
    to the groups, then kinit as one of them:

        samba-tool user create tier1 --userou='OU=Groups,OU=Tier 1'
        samba-tool group addmembers GPO-Tier1-Admins tier1
        kinit tier1@HARDENBOX.LABO

    Needs Linux, samba-tool, a Kerberos ticket of a domain administrator (kinit) and the module
    built (CI/03_Build.ps1).
.PARAMETER Server
    Domain controller of the test domain.
.EXAMPLE
    pwsh CI/New-TierDelegationLab.ps1 -Server dc.hardenbox.labo
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'PSGPOTools' 'PSGPOTools.psd1') -Force

& (Get-Module PSGPOTools) {
    param($Server)
    $ErrorActionPreference = 'Stop'

    $gPLink = [guid]'f30e3bbe-9ff0-11d1-b603-0000f80367c1'
    $gPOptions = [guid]'f30e3bbf-9ff0-11d1-b603-0000f80367c1'
    # GPMC "Edit settings": create and delete children, list, self write, read and write
    # properties, list object, read permissions.
    $editSettings = [uint32]0x000200BF
    $readWriteProperty = [uint32]0x30

    $directory = Get-PSGPODirectory -Server $Server
    $domainDN = $directory.Domain.DistinguishedName
    $tiers = @(
        @{ Name = 'Tier 1'; Children = 'Servers', 'Groups'; Group = 'GPO-Tier1-Admins'; Gpo = 'T1 - Servers - Baseline'; LinkTo = 'Servers' }
        @{ Name = 'Tier 2'; Children = 'Workstations', 'Users', 'Groups'; Group = 'GPO-Tier2-Admins'; Gpo = 'T2 - Workstations - Baseline'; LinkTo = 'Workstations' }
    )

    function Test-Entry {
        param([string]$Base, [string]$Filter = '(objectClass=*)', [string]$Scope = 'Base')
        $connection = New-PSGPODirectoryConnection -Directory $directory
        try {
            $request = [System.DirectoryServices.Protocols.SearchRequest]::new($Base, $Filter, $Scope, 'objectSid')
            $entries = $connection.SendRequest($request).Entries
            if ($entries.Count -and $entries[0].Attributes['objectSid']) { return ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entries[0].Attributes['objectSid'].GetValues([byte[]])[0]) }
            return $entries.Count -gt 0
        } catch [System.DirectoryServices.Protocols.DirectoryOperationException] {
            return $false
        } finally {
            $connection.Dispose()
        }
    }

    # Adds the ACEs missing from the DACL of an object; returns the descriptor as written.
    function Add-Ace {
        param([string]$DistinguishedName, [GPOToolsAce[]]$Ace, [string]$Name)
        $connection = New-PSGPODirectoryConnection -Directory $directory
        try {
            $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $DistinguishedName
            $missing = @($Ace | Where-Object { $wanted = $_.ToSddl(); -not ($descriptor.Dacl | Where-Object { $_.IsKnown() -and $_.ToSddl() -eq $wanted }) })
            foreach ($entry in $missing) { $descriptor.AddAce($entry) }
            if ($missing.Count) {
                Set-PSGPODomainDacl -Connection $connection -DistinguishedName $DistinguishedName -Descriptor $descriptor -Name $Name
                Write-Host "  $Name`: $($missing.Count) permission(s) added"
            }
            Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $DistinguishedName
        } finally {
            $connection.Dispose()
        }
    }

    foreach ($tier in $tiers) {
        Write-Host $tier.Name
        $tierDN = "OU=$($tier.Name),$domainDN"
        foreach ($dn in @($tierDN) + @($tier.Children | ForEach-Object { "OU=$_,$tierDN" })) {
            if (-not (Test-Entry $dn)) {
                $null = Invoke-PSGPOSambaTool -ArgumentList 'ou', 'add', $dn, '-H', "ldap://$Server", '--use-kerberos=required'
                Write-Host "  $dn created"
            }
        }

        $sid = Test-Entry $domainDN "(sAMAccountName=$($tier.Group))" 'Subtree'
        if (-not $sid) {
            $sid = (New-PSGPODomainGroup -Directory $directory -Name $tier.Group -Container "OU=Groups,$tierDN" `
                    -Description "Technicians of $($tier.Name): link GPOs to its OUs and edit its GPOs").Sid
            Write-Host "  group $($tier.Group) created"
        }

        # Link GPOs on the tier OU and the OUs below it.
        $null = Add-Ace -DistinguishedName $tierDN -Name $tierDN -Ace @(
            [GPOToolsAce]::new([GPOToolsAce]::AccessAllowedObject, [GPOToolsAce]::ContainerInherit, $readWriteProperty, $sid, $gPLink)
            [GPOToolsAce]::new([GPOToolsAce]::AccessAllowedObject, [GPOToolsAce]::ContainerInherit, $readWriteProperty, $sid, $gPOptions))

        # The GPO of the tier, linked, edited by the group: in the directory, then in SYSVOL.
        $directory = Get-PSGPODirectory -Server $Server 3>$null
        $gpo = $directory.FindGpo($tier.Gpo)
        if (-not $gpo) {
            $gpo = $directory.NewGpo($tier.Gpo)
            Write-Host "  GPO $($tier.Gpo) created"
        }
        $som = $directory.FindSom("OU=$($tier.LinkTo),$tierDN")
        if (-not @($som.Links | Where-Object { [object]::ReferenceEquals($_.Gpo, $gpo) })) {
            $null = $directory.NewLink($som, $gpo)
            Write-Host "  linked to $($som.DistinguishedName)"
        }
        $descriptor = Add-Ace -DistinguishedName $gpo.DistinguishedName -Name "GPO $($tier.Gpo)" -Ace @(
            [GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, [GPOToolsAce]::ContainerInherit, $editSettings, $sid, [guid]::Empty))
        Set-PSGPOSysvolAcl -Directory $directory -Gpo $gpo -Descriptor $descriptor.ConvertToFileSystem()
    }
    Write-Host 'Done. Create the technicians (samba-tool user create), add them to GPO-Tier1-Admins / GPO-Tier2-Admins, then kinit as one of them.'
} $Server
