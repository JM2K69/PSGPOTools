function Set-PSGPOBackup {
    <#
    .SYNOPSIS
        Changes the comment and the labels of a backup of a GPO.
    .DESCRIPTION
        The notes of a backup (Get-PSGPOBackup) are kept beside it, in notes.json: its comment and
        its labels, with who changed them and when. The files of the backup and its manifest do
        not change. The approved label of the configuration (Backup.ApprovedLabel, or -Approve)
        makes the backup the approved version of the GPO, to which Get-PSGPODrift compares it.
    .PARAMETER Backup
        The backup (Get-PSGPOBackup).
    .PARAMETER Comment
        The new comment of the backup; an empty string removes it.
    .PARAMETER AddLabel
        Labels to add.
    .PARAMETER RemoveLabel
        Labels to remove (case ignored).
    .PARAMETER Approve
        Adds the approved label of the configuration.
    .PARAMETER Unapprove
        Removes the approved label of the configuration.
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy' | Select-Object -First 1 |
            Set-PSGPOBackup -Approve -Comment 'Reviewed with the security team'
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/set-psgpobackup/
    .LINK
        Get-PSGPOBackup
    .LINK
        Get-PSGPODrift
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.Backup')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('PSGPOTools.Backup')]
        $Backup,

        [AllowEmptyString()]
        [string]$Comment,

        [string[]]$AddLabel,

        [string[]]$RemoveLabel,

        [switch]$Approve,

        [switch]$Unapprove
    )

    begin {
        $add = @($AddLabel)
        $remove = @($RemoveLabel)
        if ($Approve -or $Unapprove) {
            if ($Approve -and $Unapprove) { throw '-Approve and -Unapprove cannot be used together.' }
            $approvedLabel = Get-PSGPOApprovedLabel
            if ($Approve) { $add += $approvedLabel } else { $remove += $approvedLabel }
        }
        $add = ConvertTo-PSGPOBackupLabel -Label $add
    }
    process {
        if (-not (Test-Path -LiteralPath (Join-Path $Backup.Path 'manifest.json') -PathType Leaf)) {
            Write-Error "No backup in $($Backup.Path)."
            return
        }
        $labels = @(@($Backup.Labels) + @($add) | Where-Object { $label = $_; -not @($remove | Where-Object { $_ -eq $label }).Count })
        $text = if ($PSBoundParameters.ContainsKey('Comment')) { $Comment } else { $Backup.Comment }
        $when = if ($Backup.Modified) { $Backup.Modified } else { $Backup.BackedUp }
        if ($PSCmdlet.ShouldProcess("Backup of the GPO '$($Backup.DisplayName)' of $(([datetime]$when).ToLocalTime().ToString('g'))", 'Change its notes')) {
            Save-PSGPOBackupNote -Backup $Backup -Comment $text -Label $labels
        }
    }
}
