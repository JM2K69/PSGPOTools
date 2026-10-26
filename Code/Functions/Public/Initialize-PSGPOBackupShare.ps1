function Initialize-PSGPOBackupShare {
    <#
    .SYNOPSIS
        Prepares the share of the central backups of the GPOs: for Tier 0 only.
    .DESCRIPTION
        The backups of the GPOs of a domain are central on a share of a file server (Backup.Path of
        the configuration of the domain): the History tab, the approved versions (Get-PSGPODrift),
        the deleted GPOs and their restore. They are for Tier 0 only: Initialize-PSGPOBackupShare
        writes the permissions of the share (protected: nothing inherited from it):

        - SYSTEM, Administrators and Domain Admins: full control;
        - the approvers of the workflow (Workflow.Approvers): change (read, write, delete);
        - nobody else: the accounts of Tier 1 and Tier 2 neither read nor write it. The console does
          not show them the History tab nor the deleted GPOs, and does not back up a GPO before
          they change it (the approval backs up the approved version).

        Run it once by an account that can change the permissions of the share, and again when the
        approvers change: the backups are kept. The share is made first (New-PSGPOShare.ps1 on
        Windows, New-PSGPOShare.sh on Samba). On Linux, the consoles of Tier 0 mount the share
        (New-PSGPOShareMount.sh): HGPM finds where in /proc/mounts.
    .PARAMETER Path
        The share: \\server\share (//server/share on Linux too), or a folder in it. Backup.Path of the
        configuration of the domain by default.
    .PARAMETER Directory
        The domain (Get-PSGPODirectory), already read: its configuration gives the approvers.
    .PARAMETER Server
        Domain controller to read the domain from. By default, the domain of the computer.
    .PARAMETER Credential
        Account to read the domain with, instead of the current identity.
    .EXAMPLE
        Initialize-PSGPOBackupShare -Path \\files\gpo-backups -WhatIf
    .EXAMPLE
        # Linux, Samba AD
        kinit administrator@HARDENBOX.LABO
        Initialize-PSGPOBackupShare -Path //dc.hardenbox.labo/gpo-backups -Server dc.hardenbox.labo
    .OUTPUTS
        PSGPOTools.BackupShare
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/initialize-psgpobackupshare/
    .LINK
        Initialize-PSGPOAuditShare
    .LINK
        Backup-PSGPO
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Domain')]
    [OutputType('PSGPOTools.BackupShare')]
    param(
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Directory')]
        [GPOToolsLdapDirectory]$Directory,

        [Parameter(ParameterSetName = 'Domain')]
        [string]$Server,

        [Parameter(ParameterSetName = 'Domain')]
        [pscredential]$Credential
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        if ($Credential) { $read.Credential = $Credential }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    $configuration = Get-PSGPOConfigurationData
    if (-not $Path) { $Path = "$($configuration.Backup.Path)".Trim() }
    if (-not $Path) { throw 'No share: give -Path, or set Backup.Path in the configuration of the domain.' }

    # The approvers, read in the domain: a name that is not found stops, Tier 0 would miss a group.
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $domainDN = $Directory.Domain.DistinguishedName
        $domain = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $domainDN -Scope Base -Attribute 'objectSid') | Select-Object -First 1
        if (-not $domain -or -not $domain.Values['objectSid']) { throw "The SID of the domain $domainDN cannot be read." }
        $domainSid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$domain.Values['objectSid'][0])
        $approvers = @(Find-PSGPODomainAccount -Connection $connection -DomainDistinguishedName $domainDN -Name @("$($configuration.Workflow.Approvers)" -split ',' | ForEach-Object Trim | Where-Object { $_ }))
    } finally {
        $connection.Dispose()
    }

    $sddl = Get-PSGPOBackupShareSddl -DomainAdminsSid "$domainSid-512" -Tier0 @($approvers.Sid)
    Set-PSGPOAuditShareAcl -Path $Path -Folder @([pscustomobject]@{ Folder = ''; Sddl = $sddl })
    if ($WhatIfPreference) { return }
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.BackupShare'
        Path = $Path
        Tier0 = [string[]]@(@($approvers.Name) + 'Domain Admins' | Select-Object -Unique)
        Sddl = $sddl
    }
    Write-PSGPOAuditEntry -Directory $Directory -Action 'InitializeBackupShare' -Target $Path -Details @{ Tier0 = @($approvers.Name) }
}
