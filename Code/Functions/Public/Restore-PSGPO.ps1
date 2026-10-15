function Restore-PSGPO {
    <#
    .SYNOPSIS
        Puts a GPO back as one of its backups has it (Backup-PSGPO).
    .DESCRIPTION
        Like GPMC Restore-GPO: the files of the SYSVOL folder of the GPO are replaced by those of
        the backup (the files the backup does not have are deleted), and its status and client-side
        extensions are those of the backup. Its version increases in both scopes, so that the
        computers apply it again. Its links and permissions (security filtering) do not change.

        The GPO as it is now is backed up first, in the same folder, so that the restore can be
        undone (unless -NoBackup). The files of the backup are checked against their SHA-256 first.
    .PARAMETER Backup
        The backup to restore (Get-PSGPOBackup).
    .PARAMETER Directory
        Directory of the GPO (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .PARAMETER NoBackup
        Does not back up the GPO as it is now before restoring it.
    .EXAMPLE
        # The GPO as it was on 15 October
        Get-PSGPOBackup -Path /srv/gpo-backups -Name 'T1 - Servers - Baseline' |
            Where-Object { $_.Modified.Date -eq [datetime]'2026-10-15' } | Select-Object -First 1 | Restore-PSGPO
    .LINK
        Backup-PSGPO
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('PSGPOTools.Backup')]
        $Backup,

        [GPOToolsDirectory]$Directory,

        [string]$Server,

        [switch]$NoBackup
    )

    begin {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
    }
    process {
        $gpo = $Directory.Gpos | Where-Object Id -EQ $Backup.Id | Select-Object -First 1
        if (-not $gpo) { throw "The GPO '$($Backup.DisplayName)' {$($Backup.Id)} is not in $($Directory.DomainName): restoring a deleted GPO is not available." }
        $date = if ($Backup.Modified) { $Backup.Modified } else { $Backup.BackedUp }
        $files = Get-PSGPOVerifiedBackupFile -Backup $Backup
        if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", "Restore its backup of $(([datetime]$date).ToLocalTime().ToString('g'))")) { return }

        $safety = $null
        if (-not $NoBackup) {
            $safety = Save-PSGPOBackup -Directory $Directory -Gpo $gpo -Path (Split-Path -Parent (Split-Path -Parent $Backup.Path))
        }
        $machine = $Backup.MachineExtensionNames
        $user = $Backup.UserExtensionNames
        if ($null -eq $machine -and $null -eq $user) {
            # A backup without them: the extensions of its files.
            $machine = Get-PSGPOFileExtensionName -Files $files -Scope Machine
            $user = Get-PSGPOFileExtensionName -Files $files -Scope User
        }
        $Directory.RestoreGpo($gpo, $files, $Backup.Flags, $machine, $user)
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.Restore'
            DisplayName = $gpo.DisplayName
            RestoredFrom = $Backup.Path
            Version = $gpo.Version
            Status = $gpo.GetStatus()
            BackupBefore = if ($safety) { $safety.Path }
        }
    }
}
