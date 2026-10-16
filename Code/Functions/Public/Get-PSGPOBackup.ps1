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
    .PARAMETER Label
        Only the backups with this label (wildcards allowed).
    .PARAMETER Approved
        Only the backups with the approved label of the configuration.
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Approved | Select-Object DisplayName, BackedUp, Comment
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

        [guid]$Id = [guid]::Empty,

        [string]$Label,

        [switch]$Approved
    )

    $approvedLabel = if ($Approved) { Get-PSGPOApprovedLabel }
    Get-PSGPOBackupEntry -Path $Path -Id $Id | Where-Object {
        $_.DisplayName -like $Name -and
        (-not $Label -or @($_.Labels | Where-Object { $_ -like $Label }).Count) -and
        (-not $approvedLabel -or $_.Labels -contains $approvedLabel)
    }
}
