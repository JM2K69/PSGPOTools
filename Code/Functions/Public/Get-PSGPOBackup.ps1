function Get-PSGPOBackup {
    <#
    .SYNOPSIS
        Lists the backups of GPOs written by Backup-PSGPO, newest first.
    .PARAMETER Path
        Root folder of the backups.
    .PARAMETER Name
        Display name of the GPO (wildcards allowed), as it was when backed up.
    .PARAMETER Id
        GUID of the GPO: its backups even when it was renamed.
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
    .LINK
        Backup-PSGPO
    .LINK
        Compare-PSGPOBackup
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.Backup')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Name = '*',

        [guid]$Id = [guid]::Empty
    )

    Get-PSGPOBackupEntry -Path $Path -Id $Id | Where-Object { $_.DisplayName -like $Name }
}
