function Import-PSGPO {
    <#
    .SYNOPSIS
        Imports the settings of a backed up GPO into a GPO of the domain, with a migration table.
    .DESCRIPTION
        As "Import Settings" of GPMC: the settings of a backup made by GPMC (Backup-GPO) or by
        Backup-PSGPO, of this domain or of another one, replace those of the GPO -TargetName. The
        GPO is backed up first (unless -NoBackup); its links, permissions, status and WMI filter do
        not change, and its version increases so that the computers apply it again.

        A migration table (.migtable, as the Migration Table Editor of GPMC writes it, or
        New-PSGPOMigrationTable) maps the security principals and the UNC paths of the backup to
        those of this domain: the same as the source, the same name in this domain (by relative
        name), another account or path, or none (the account is removed from the setting). The
        security settings, the preferences, the scripts and the folder redirection are migrated;
        the administrative templates are copied as they are, as GPMC does. A destination that
        cannot be found stops the import, nothing is changed.
    .PARAMETER Path
        The folder of the backups: a folder of GPMC backups, one GPMC backup, or a folder of
        Backup-PSGPO.
    .PARAMETER TargetName
        The GPO of the domain that takes the settings.
    .PARAMETER SourceName
        The GPO backed up to import, when the folder holds backups of several GPOs (its newest).
    .PARAMETER BackupId
        The ID of the backup to import (Get-PSGPOGpmcBackup), or its folder name for Backup-PSGPO.
    .PARAMETER MigrationTable
        The migration table (.migtable). Without it, the references are copied as they are.
    .PARAMETER Exclusive
        Every security principal and UNC path of the settings must be in the migration table, as
        "Use migration table exclusively" of GPMC.
    .PARAMETER CreateIfNeeded
        Creates the GPO -TargetName when the domain has none.
    .PARAMETER BackupPath
        Folder of the backup of the GPO made before the import (by default the folder of the backups).
    .PARAMETER NoBackup
        No backup of the GPO before the import.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Import-PSGPO -Path C:\backupGPO -SourceName 'C - Servers - Baseline' -TargetName 'C - Servers - Baseline' -MigrationTable C:\backupGPO\prod.migtable
    .EXAMPLE
        Import-PSGPO -Path C:\backupGPO -SourceName 'TEST' -TargetName 'C - Test' -CreateIfNeeded -WhatIf
    .OUTPUTS
        PSGPOTools.ImportResult
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/import-psgpo/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.ImportResult')]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$TargetName,
        [string]$SourceName,
        [string]$BackupId,
        [string]$MigrationTable,
        [switch]$Exclusive,
        [switch]$CreateIfNeeded,
        [string]$BackupPath,
        [switch]$NoBackup,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    $source = Select-PSGPOImportSource -Path $Path -Name $SourceName -BackupId $BackupId
    # The table read before anything changes: a wrong one stops the import.
    if ($MigrationTable) { $null = @(Read-PSGPOMigrationTable -Path $MigrationTable) }
    $gpo = $Directory.FindGpo($TargetName)
    if (-not $gpo -and -not $CreateIfNeeded) { throw "No GPO named '$TargetName' in $($Directory.DomainName): give -CreateIfNeeded to create it." }
    $what = "import the settings of '$($source.DisplayName)' ($($source.Kind) backup of $(if ($source.BackedUp) { $source.BackedUp.ToLocalTime().ToString('g') }))$(if ($MigrationTable) { " with the migration table $MigrationTable" })"
    if (-not $PSCmdlet.ShouldProcess("GPO '$TargetName' of $($Directory.DomainName)", $what)) { return }
    if (-not $gpo) { $gpo = $Directory.NewGpo($TargetName) }
    $import = @{ Directory = $Directory; Source = $source; Gpo = $gpo; Exclusive = $Exclusive; NoBackup = $NoBackup }
    if ($MigrationTable) { $import.MigrationTable = $MigrationTable }
    if ($BackupPath) { $import.BackupPath = $BackupPath }
    $result = Invoke-PSGPOImport @import
    foreach ($item in @($result.Migration | Where-Object Mode -EQ 'None')) {
        if (@($item.Files | Where-Object { $_ -notmatch '\.inf$|\\Preferences\\' }).Count) { Write-Warning "'$($item.Source)' is kept where only a list or a member can lose it: $(@($item.Files) -join ', ')." }
    }
    $result
}
