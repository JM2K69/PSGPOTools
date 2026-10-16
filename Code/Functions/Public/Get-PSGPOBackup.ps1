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
    .PARAMETER Template
        Only the templates of new GPOs: the backups with the template label of the configuration.
    .PARAMETER Deleted
        The recycle bin: the newest backup of each GPO of the domain that is not in it anymore
        (and was not created again since). Reads the domain, or uses -Directory.
    .PARAMETER Directory
        With -Deleted: the directory of the domain (Get-PSGPODirectory).
    .PARAMETER Server
        With -Deleted: the domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Approved | Select-Object DisplayName, BackedUp, Comment
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Deleted | Restore-PSGPO -RestoreLink
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

        [switch]$Approved,

        [switch]$Template,

        [switch]$Deleted,

        [GPOToolsDirectory]$Directory,

        [string]$Server
    )

    $approvedLabel = if ($Approved) { Get-PSGPOApprovedLabel }
    $templateLabel = if ($Template) { Get-PSGPOTemplateLabel }
    $entries = if ($Deleted) {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Get-PSGPODeletedGpoBackup -Directory $Directory -Path $Path | Where-Object { $Id -eq [guid]::Empty -or $_.Id -eq $Id }
    } else {
        Get-PSGPOBackupEntry -Path $Path -Id $Id
    }
    $entries | Where-Object {
        (-not $templateLabel -or $_.Labels -contains $templateLabel) -and
        $_.DisplayName -like $Name -and
        (-not $Label -or @($_.Labels | Where-Object { $_ -like $Label }).Count) -and
        (-not $approvedLabel -or $_.Labels -contains $approvedLabel)
    }
}
