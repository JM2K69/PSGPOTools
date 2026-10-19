function Get-PSGPOGpmcBackup {
    <#
    .SYNOPSIS
        Lists the backups of GPMC (Backup-GPO) a folder holds, to import them with Import-PSGPO.
    .DESCRIPTION
        One object per backup, newest first: the GPO backed up (its name, Id and domain), when,
        its comment, the ID of the backup, its folder, and the accounts of the GPO its Backup.xml
        lists (SecurityGroups: the names a migration table gives them).
    .PARAMETER Path
        A folder of GPMC backups, or one backup.
    .PARAMETER Name
        Display names of the GPOs backed up (* and ? make a pattern).
    .EXAMPLE
        Get-PSGPOGpmcBackup -Path C:\backupGPO
    .OUTPUTS
        PSGPOTools.GpmcBackup
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.GpmcBackup')]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string[]]$Name
    )

    foreach ($backup in @(Get-PSGPOGpmcBackupEntry -Path $Path)) {
        if ($Name -and -not @($Name | Where-Object { Test-PSGPONameMatch -Name $backup.DisplayName -Pattern $_ }).Count) { continue }
        $backup
    }
}
