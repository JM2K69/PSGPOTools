function Remove-PSGPO {
    <#
    .SYNOPSIS
        Deletes GPOs of the domain, backed up first: they stay in the recycle bin.
    .DESCRIPTION
        Like GPMC "Delete": the links of the GPO in the domain are deleted first (the GPO is not
        deleted when the account cannot delete one of them), then the GPO, its container in the
        directory and its folder in SYSVOL (on Windows with Remove-GPO of RSAT, on Linux with
        samba-tool and Kerberos). The Default Domain Policy and the Default Domain Controllers
        Policy are never deleted.

        Each GPO is backed up first in -BackupPath (unless -NoBackup), and its last backup says
        when and by whom it was deleted: Get-PSGPOBackup -Deleted lists it, Restore-PSGPO creates
        it again.
    .PARAMETER Name
        Display names of the GPOs to delete (wildcards allowed).
    .PARAMETER BackupPath
        Root folder of the backups; by default the one of the History tab of the window.
    .PARAMETER NoBackup
        Does not back up the GPOs before deleting them: they cannot be created again.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Remove-PSGPO -Name 'U - Lyon - Printers' -BackupPath /srv/gpo-backups
    .LINK
        Get-PSGPOBackup
    .LINK
        Restore-PSGPO
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('PSGPOTools.RemovedGpo')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Name,

        [string]$BackupPath,

        [switch]$NoBackup,

        [GPOToolsDirectory]$Directory,

        [string]$Server
    )

    begin {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
        if (-not $BackupPath) { $BackupPath = Get-PSGPODefaultBackupPath }
    }
    process {
        foreach ($pattern in $Name) {
            $found = @($Directory.Gpos | Where-Object { $_.DisplayName -like $pattern })
            if (-not $found) { Write-Error "No GPO named '$pattern' in $($Directory.DomainName)."; continue }
            foreach ($gpo in $found) {
                $links = @($Directory.GetLinksOf($gpo)).Count
                $what = "Delete it and its $links link$(if ($links -ne 1) { 's' })$(if ($NoBackup) { ', without backup' } else { ", backed up in $BackupPath" })"
                if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", $what)) { continue }
                try {
                    Remove-PSGPOWithBackup -Directory $Directory -Gpo $gpo -Path $BackupPath -NoBackup:$NoBackup
                } catch {
                    Write-Error "The GPO '$($gpo.DisplayName)' is not deleted: $($_.Exception.GetBaseException().Message)"
                }
            }
        }
    }
}
