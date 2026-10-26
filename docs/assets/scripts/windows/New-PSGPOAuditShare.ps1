#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates the share of the central audit log of HGPM on a Windows file server.
.DESCRIPTION
    A folder and its SMB share. The share lets the authenticated users change files and the
    administrators do everything: the NTFS permissions decide, written by
    Initialize-PSGPOAuditShare from the roles of the configuration of the domain (a folder per
    tier). Until then the folder is for the administrators only.

    Run it as an administrator of the file server (not a domain controller: SYSVOL and the domain
    controllers keep out of the log), then from a console of a domain administrator:

        Initialize-PSGPOAuditShare -Path \\<server>\gpo-audit

    and Audit.Path = \\<server>\gpo-audit in the Settings of the console. What is there is kept:
    the script can run again.
.PARAMETER Name
    Name of the share.
.PARAMETER Path
    The folder of the share.
.EXAMPLE
    .\New-PSGPOAuditShare.ps1
.EXAMPLE
    .\New-PSGPOAuditShare.ps1 -Name gpo-audit -Path E:\Shares\GPO-Audit -WhatIf
.LINK
    https://jm2k69.github.io/PSGPOTools/en/features/audit-log/
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name = 'gpo-audit',
    [string]$Path = 'D:\Shares\GPO-Audit'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    if ($PSCmdlet.ShouldProcess($Path, 'Create the folder')) {
        $null = New-Item -ItemType Directory -Path $Path
        # The administrators and SYSTEM only, until Initialize-PSGPOAuditShare writes the roles.
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
        -FolderEnumerationMode AccessBased -Description 'Central audit log of HGPM'
    Write-Output "Share \\$env:COMPUTERNAME\$Name created: $Path"
}
Write-Output "Next: Initialize-PSGPOAuditShare -Path \\$([System.Net.Dns]::GetHostEntry('').HostName)\$Name"
