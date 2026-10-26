#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a share of HGPM on a Windows file server: the central audit log or the central backups.
.DESCRIPTION
    A folder and its SMB share. The share lets the authenticated users change files and the
    administrators do everything: the NTFS permissions decide, written by
    Initialize-PSGPOAuditShare (the audit log, a folder per tier) or Initialize-PSGPOBackupShare
    (the backups, Tier 0 only) from the roles of the configuration of the domain. Until then the
    folder is for the administrators only.

    Run it as an administrator of the file server (not a domain controller: SYSVOL is copied to
    every domain controller), once per share, then from a console of a domain administrator:

        Initialize-PSGPOAuditShare -Path \\<server>\gpo-audit
        Initialize-PSGPOBackupShare -Path \\<server>\gpo-backups

    and Audit.Path or Backup.Path in the Settings of the console. What is there is kept: the script
    can run again.
.PARAMETER Name
    Name of the share: gpo-audit, gpo-backups.
.PARAMETER Path
    The folder of the share; D:\Shares\<Name> by default.
.EXAMPLE
    .\New-PSGPOShare.ps1 -Name gpo-audit
.EXAMPLE
    .\New-PSGPOShare.ps1 -Name gpo-backups -Path E:\Shares\GPO-Backups -WhatIf
.LINK
    https://jm2k69.github.io/PSGPOTools/en/features/audit-log/
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name = 'gpo-audit',
    [string]$Path
)

$ErrorActionPreference = 'Stop'
if (-not $Path) { $Path = "D:\Shares\$Name" }

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    if ($PSCmdlet.ShouldProcess($Path, 'Create the folder')) {
        $null = New-Item -ItemType Directory -Path $Path
        # The administrators and SYSTEM only, until Initialize-PSGPO...Share writes the roles.
        $acl = [System.Security.AccessControl.DirectorySecurity]::new()
        $acl.SetSecurityDescriptorSddlForm('D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
        Set-Acl -LiteralPath $Path -AclObject $acl
    }
}

if (Get-SmbShare -Name $Name -ErrorAction SilentlyContinue) {
    Write-Output "The share $Name exists: kept."
} elseif ($PSCmdlet.ShouldProcess("\\$env:COMPUTERNAME\$Name", 'Create the share')) {
    # Share permissions: change for the accounts of the domain, the NTFS permissions decide.
    $null = New-SmbShare -Name $Name -Path $Path -FullAccess 'BUILTIN\Administrators' -ChangeAccess 'NT AUTHORITY\Authenticated Users' `
        -FolderEnumerationMode AccessBased -Description "HGPM: $Name"
    Write-Output "Share \\$env:COMPUTERNAME\$Name created: $Path"
}
