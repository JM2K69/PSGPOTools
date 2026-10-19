function New-PSGPOMigrationTable {
    <#
    .SYNOPSIS
        Writes a migration table (.migtable) for the backups of a folder, to edit before an import.
    .DESCRIPTION
        As "Populate from Backup" of the Migration Table Editor of GPMC: an entry for each security
        principal and UNC path the backed up GPOs reference (Get-PSGPOMigrationEntry), the same as
        the source, or by relative name for the accounts of a domain with -MapByRelativeName. The
        file is the one GPMC writes (UTF-16, its namespace): the Migration Table Editor opens it,
        and so does Import-PSGPO. Change the destinations, with the editor or in the XML, before
        the import.
    .PARAMETER Path
        The migration table to write (.migtable).
    .PARAMETER BackupPath
        The folder of the backups.
    .PARAMETER Name
        Display names of the GPOs backed up (* and ? make a pattern); all by default.
    .PARAMETER IncludePermission
        The accounts of the permissions of the GPOs too (backups of GPMC).
    .PARAMETER MapByRelativeName
        The accounts of a domain are mapped by relative name (the same name in the domain of the
        import), not kept as they are.
    .PARAMETER Force
        Replaces a table that exists.
    .EXAMPLE
        New-PSGPOMigrationTable -Path C:\backupGPO\prod.migtable -BackupPath C:\backupGPO -MapByRelativeName
    .OUTPUTS
        PSGPOTools.MigrationEntry
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.MigrationEntry')]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$BackupPath,
        [string[]]$Name,
        [switch]$IncludePermission,
        [switch]$MapByRelativeName,
        [switch]$Force
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Force) { throw "The migration table '$Path' exists: give -Force to replace it." }
    $read = @{ Path = $BackupPath; IncludePermission = $IncludePermission }
    if ($Name) { $read.Name = $Name }
    $entries = @(foreach ($reference in @(Get-PSGPOMigrationEntry @read)) {
            $mode = if ($MapByRelativeName -and $reference.Type -notin 'Unknown', 'UNCPath') { 'ByRelativeName' } else { 'SameAsSource' }
            [pscustomobject]@{ PSTypeName = 'PSGPOTools.MigrationEntry'; Type = $reference.Type; Source = $reference.Source; Destination = $null; Mode = $mode }
        })
    if (-not $PSCmdlet.ShouldProcess($Path, "write a migration table of $($entries.Count) entries")) { return }
    $folder = Split-Path -Path $Path -Parent
    if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop }
    Save-PSGPOMigrationTable -Path $Path -Entry $entries
    $entries
}
