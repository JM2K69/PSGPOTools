function Remove-PSGPOBackup {
    <#
    .SYNOPSIS
        Deletes for good a GPO of the recycle bin: all its backups.
    .DESCRIPTION
        A GPO deleted from the domain stays in the recycle bin (Get-PSGPOBackup -Deleted) as long
        as its backups are in the folder: Remove-PSGPOBackup deletes every backup of its GUID in
        the folder of the backup given, made before or after a rename, the templates made from it
        too. It cannot be restored afterwards.

        The backups of a GPO that is still in the domain are its history: they are not deleted,
        nor those of another domain.
    .PARAMETER Backup
        A backup of the deleted GPO (Get-PSGPOBackup -Deleted).
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Deleted -Name 'U - Lyon - Printers' | Remove-PSGPOBackup
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/remove-psgpobackup/
    .LINK
        Get-PSGPOBackup
    .LINK
        Restore-PSGPO
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('PSGPOTools.RemovedBackup')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('PSGPOTools.Backup')]
        $Backup,

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
        # The GPOs deleted already, when several of their backups come in.
        $done = [System.Collections.Generic.HashSet[guid]]::new()
    }
    process {
        if ($done.Contains($Backup.Id)) { return }
        # The root folder of the backups: <root>/<GPO name> {GUID}/<date>.
        $root = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetDirectoryName($Backup.Path))
        if (-not $PSCmdlet.ShouldProcess("Deleted GPO '$($Backup.DisplayName)' ($root)", 'Delete all its backups: it cannot be restored afterwards')) { return }
        try {
            Remove-PSGPODeletedGpoBackup -Directory $Directory -Path $root -Id $Backup.Id
            [void]$done.Add($Backup.Id)
        } catch {
            Write-Error "The deleted GPO '$($Backup.DisplayName)' is not deleted for good: $($_.Exception.GetBaseException().Message)"
        }
    }
}
