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

        A backup of another domain is never restored, even when a GPO of this domain has its GUID
        (the Default Domain Policy and the Default Domain Controllers Policy have the same GUID in
        every domain): use it as a template of a new GPO (New-PSGPO -Template).

        A backup of a deleted GPO (Get-PSGPOBackup -Deleted) creates it again: a new GPO, with a
        new GUID given by the domain, the name, settings, status and client-side extensions of the
        backup. Its security filtering is not restored (it applies to Authenticated Users); with
        -RestoreLink it is linked again to its containers that still exist, only when its
        security filtering was Authenticated Users and its links were enabled. The new GPO is
        backed up at once, and the deleted one leaves the recycle bin.
    .PARAMETER Backup
        The backup to restore (Get-PSGPOBackup).
    .PARAMETER Directory
        Directory of the GPO (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .PARAMETER NoBackup
        Does not back up the GPO as it is now before restoring it.
    .PARAMETER RestoreLink
        For a deleted GPO: links it again where it was (see the description).
    .EXAMPLE
        # A deleted GPO, created again and linked where it was
        Get-PSGPOBackup -Path /srv/gpo-backups -Deleted | Where-Object DisplayName -EQ 'U - Lyon - Printers' | Restore-PSGPO -RestoreLink
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

        [switch]$NoBackup,

        [switch]$RestoreLink
    )

    begin {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
    }
    process {
        # Before anything: the GUIDs of the default GPOs are the same in every domain.
        if (-not [string]::Equals($Backup.Domain, $Directory.DomainName, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The backup of '$($Backup.DisplayName)' is of a GPO of $($Backup.Domain), not of $($Directory.DomainName): it is not restored here. Use it as a template of a new GPO (New-PSGPO -Template)."
        }
        $gpo = $Directory.Gpos | Where-Object Id -EQ $Backup.Id | Select-Object -First 1
        $date = if ($Backup.Modified) { $Backup.Modified } else { $Backup.BackedUp }
        $files = Get-PSGPOVerifiedBackupFile -Backup $Backup
        if (-not $gpo) {
            if ($Backup.RestoredAs) { throw "The deleted GPO '$($Backup.DisplayName)' was created again already, as {$($Backup.RestoredAs)}." }
            if (-not $PSCmdlet.ShouldProcess("Deleted GPO '$($Backup.DisplayName)'", "Create it again from its backup of $(([datetime]$date).ToLocalTime().ToString('g'))")) { return }
            Restore-PSGPODeletedGpo -Directory $Directory -Backup $Backup -Files $files -RestoreLink:$RestoreLink
            return
        }
        if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)' of $($Directory.DomainName)", "Restore its backup of $(([datetime]$date).ToLocalTime().ToString('g'))")) { return }

        $safety = $null
        if (-not $NoBackup) {
            $safety = Save-PSGPOBackup -Directory $Directory -Gpo $gpo -Path (Split-Path -Parent (Split-Path -Parent $Backup.Path))
            # Why this backup was made, in its history; not on a backup that was there already.
            if ($safety.Result -eq 'Created') {
                $safety = Save-PSGPOBackupNote -Backup $safety -Comment "Before the restore of the version of $(([datetime]$date).ToLocalTime().ToString('g'))." -Label $safety.Labels -Account $Directory.Account
            }
        }
        $extensions = Get-PSGPOBackupExtensionName -Backup $Backup -Files $files
        $Directory.RestoreGpo($gpo, $files, $Backup.Flags, $extensions.Machine, $extensions.User)
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.Restore'
            DisplayName = $gpo.DisplayName
            Id = $gpo.Id
            RestoredFrom = $Backup.Path
            Version = $gpo.Version
            Status = $gpo.GetStatus()
            BackupBefore = if ($safety) { $safety.Path }
            CreatedAgain = $false
            Backup = $null
            Linked = [string[]]@()
            Problems = [string[]]@()
        }
    }
}
