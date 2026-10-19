function Get-PSGPOMigrationEntry {
    <#
    .SYNOPSIS
        Lists the security principals and UNC paths the settings of backed up GPOs reference, as a
        migration table names them.
    .DESCRIPTION
        As "Populate from Backup" of the Migration Table Editor of GPMC: for the backups of a folder
        (of GPMC or of PSGPOTools), each account (by its SID, or its name where the settings give
        a name) and each UNC path (\\server\share) of their security settings, preferences, scripts
        and folder redirection: its Type (User, Computer, LocalGroup, GlobalGroup,
        UniversalGroup, UNCPath, or Unknown for free text and SIDs), its Source as a migration
        table writes it, its SID, and the files and GPOs it is in.
    .PARAMETER Path
        The folder of the backups.
    .PARAMETER Name
        Display names of the GPOs backed up (* and ? make a pattern); all by default.
    .PARAMETER IncludePermission
        The accounts of the permissions of the GPOs too, as the option of GPMC "include security
        principals from the DACL on the GPO" (backups of GPMC only).
    .EXAMPLE
        Get-PSGPOMigrationEntry -Path C:\backupGPO | Format-Table Type, Source, Gpos
    .OUTPUTS
        PSGPOTools.MigrationReference
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.MigrationReference')]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string[]]$Name,
        [switch]$IncludePermission
    )

    $found = [ordered]@{}
    foreach ($source in @(Get-PSGPOImportSource -Path $Path)) {
        if ($Name -and -not @($Name | Where-Object { Test-PSGPONameMatch -Name $source.DisplayName -Pattern $_ }).Count) { continue }
        $files = Read-PSGPOImportFile -Source $source
        foreach ($reference in @(Get-PSGPOMigrationReference -Files $files -SecurityGroups $source.SecurityGroups -IncludePermission:$IncludePermission)) {
            $key = "$($reference.Type)|$($reference.Source)".ToLowerInvariant()
            if (-not $found.Contains($key)) {
                $found[$key] = [pscustomobject]@{
                    PSTypeName = 'PSGPOTools.MigrationReference'
                    Type = $reference.Type
                    Source = $reference.Source
                    Sid = $reference.Sid
                    Files = [System.Collections.Generic.List[string]]::new()
                    Gpos = [System.Collections.Generic.List[string]]::new()
                }
            }
            $item = $found[$key]
            foreach ($file in $reference.Files) { if (-not $item.Files.Contains($file)) { $item.Files.Add($file) } }
            if (-not $item.Gpos.Contains($source.DisplayName)) { $item.Gpos.Add($source.DisplayName) }
        }
    }
    @($found.Values)
}
