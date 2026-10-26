function Initialize-PSGPOAuditShare {
    <#
    .SYNOPSIS
        Prepares the share of the central audit log: a folder per tier, the permissions of the roles.
    .DESCRIPTION
        The audit log of a domain is central on a share of a file server (Audit.Path of the
        configuration of the domain), not in SYSVOL, which is copied to every domain controller.
        Initialize-PSGPOAuditShare makes its folders and writes their permissions (protected: nothing
        inherited from the share), from the roles of the configuration of the domain:

        - Tier0: the approvers of the workflow (Workflow.Approvers) and Domain Admins;
        - Tier1, Tier2: the groups of Audit.Tiers.Tier1 and Audit.Tiers.Tier2;
        - Unassigned: a user of the domain in no tier (Domain Users);
        - Archive: the archives of the old months (Invoke-PSGPOAuditRetention);
        - the readers (Audit.Readers, the auditors) and Tier 0 read every folder;
        - the accounts of a tier create their own file in the folder of their tier, append to it,
          and read the files of their tier, not those of the other tiers; the files already there
          are made append-only too;
        - the purgers (Audit.Purgers, the group of a gMSA) read every folder, delete the files of
          the old months and write the archives, without being administrators of the domain;
          nobody else but the administrators deletes a file or changes its permissions;
        - SYSTEM, Administrators and Domain Admins have full control.

        Run it once by an account that can change the permissions of the share (an administrator of
        the file server), and again when the groups of the tiers change: the permissions of the
        folders are written again, the files kept. The share itself is made first (the scripts
        New-PSGPOShare.ps1 on Windows and New-PSGPOShare.sh on Samba of the documentation), with share
        permissions that let the accounts of the domain change files: the NTFS or NT permissions
        written here decide.
        On Linux: smbclient's Python bindings (python3-samba) and a Kerberos ticket.
    .PARAMETER Path
        The share: \\server\share (//server/share on Linux too), or a folder in it. Audit.Path of
        the configuration of the domain by default.
    .PARAMETER Directory
        The domain (Get-PSGPODirectory), already read: its configuration gives the groups.
    .PARAMETER Server
        Domain controller to read the domain from. By default, the domain of the computer.
    .PARAMETER Credential
        Account to read the domain with, instead of the current identity.
    .EXAMPLE
        Initialize-PSGPOAuditShare -Path \\files\gpo-audit -WhatIf
    .EXAMPLE
        # Linux, Samba AD
        kinit administrator@HARDENBOX.LABO
        Initialize-PSGPOAuditShare -Path //dc.hardenbox.labo/gpo-audit -Server dc.hardenbox.labo
    .OUTPUTS
        PSGPOTools.AuditShareFolder
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/initialize-psgpoauditshare/
    .LINK
        Show-AuditLogAvalonia
    .LINK
        Get-PSGPOAuditLog
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Domain')]
    [OutputType('PSGPOTools.AuditShareFolder')]
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
    if (-not $Path) { $Path = "$($configuration.Audit.Path)".Trim() }
    if (-not $Path) { throw 'No share: give -Path, or set Audit.Path in the configuration of the domain.' }

    # The SIDs of the groups of the roles, read in the domain: a name that is not found stops, the
    # permissions would miss a role.
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $domainDN = $Directory.Domain.DistinguishedName
        $domain = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $domainDN -Scope Base -Attribute 'objectSid') | Select-Object -First 1
        if (-not $domain -or -not $domain.Values['objectSid']) { throw "The SID of the domain $domainDN cannot be read." }
        $domainSid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$domain.Values['objectSid'][0])
        $find = {
            param([string]$Names)
            @(Find-PSGPODomainAccount -Connection $connection -DomainDistinguishedName $domainDN -Name @("$Names" -split ',' | ForEach-Object Trim | Where-Object { $_ }))
        }
        $roles = [ordered]@{
            Tier0 = & $find $configuration.Workflow.Approvers
            Tier1 = & $find $configuration.Audit.Tiers.Tier1
            Tier2 = & $find $configuration.Audit.Tiers.Tier2
            Readers = & $find $configuration.Audit.Readers
            Purgers = & $find $configuration.Audit.Purgers
        }
    } finally {
        $connection.Dispose()
    }

    $folders = @(Get-PSGPOAuditShareSddl -DomainAdminsSid "$domainSid-512" -Tier0 @($roles.Tier0.Sid) -Tier1 @($roles.Tier1.Sid) -Tier2 @($roles.Tier2.Sid) -Readers @($roles.Readers.Sid) -Purgers @($roles.Purgers.Sid))
    Set-PSGPOAuditShareAcl -Path $Path -Folder $folders
    if ($WhatIfPreference) { return }
    $names = @{ Tier0 = @(@($roles.Tier0.Name) + 'Domain Admins' | Select-Object -Unique); Tier1 = @($roles.Tier1.Name); Tier2 = @($roles.Tier2.Name); Unassigned = @(@('Domain Users') + @($roles.Purgers.Name) | Where-Object { $_ }); Archive = @($roles.Purgers.Name | Where-Object { $_ }) }
    foreach ($item in $folders) {
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.AuditShareFolder'
            Path = if ($item.Folder) { "$($Path.TrimEnd('\', '/'))\$($item.Folder)" } else { $Path }
            Writers = if ($item.Folder) { [string[]]$names[$item.Folder] } else { [string[]]@() }
            Readers = [string[]]@(@($roles.Tier0.Name) + 'Domain Admins' + @($roles.Readers.Name) + $(if ($item.Folder -in 'Tier1', 'Tier2') { $names[$item.Folder] }) | Select-Object -Unique)
            Sddl = $item.Sddl
        }
    }
    Write-PSGPOAuditEntry -Directory $Directory -Action 'InitializeAuditShare' -Target $Path -Details @{ Tier1 = @($roles.Tier1.Name | Where-Object { $_ }); Tier2 = @($roles.Tier2.Name | Where-Object { $_ }); Readers = @($roles.Readers.Name | Where-Object { $_ }); Purgers = @($roles.Purgers.Name | Where-Object { $_ }) }
}
