function Compare-PSGPOBackup {
    <#
    .SYNOPSIS
        Shows what changed between two backups of a GPO, setting by setting.
    .DESCRIPTION
        Compares the settings of two backups (Get-PSGPOBackup) as the Settings tab shows them:
        the policies of the Registry.pol files by category path (with the ADMX files loaded by
        Initialize-PSGPOAdmx; otherwise as extra registry values), the security settings
        (GptTmpl.inf), the other files of the GPO by their content, and its name, status, security
        filtering and links. Each change is Added, Removed or Changed, with the value before and after.
    .PARAMETER ReferenceBackup
        The older backup.
    .PARAMETER DifferenceBackup
        The newer backup.
    .EXAMPLE
        $Backups = Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
        Compare-PSGPOBackup -ReferenceBackup $Backups[1] -DifferenceBackup $Backups[0]
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/compare-psgpobackup/
    .LINK
        Backup-PSGPO
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.SettingChange')]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('PSGPOTools.Backup')]
        $ReferenceBackup,

        [Parameter(Mandatory)]
        [PSTypeName('PSGPOTools.Backup')]
        $DifferenceBackup
    )

    if ($ReferenceBackup.Id -ne $DifferenceBackup.Id) {
        Write-Warning "The backups are of two GPOs: '$($ReferenceBackup.DisplayName)' and '$($DifferenceBackup.DisplayName)'."
    }
    Compare-PSGPOSettingReport -Reference @(Get-PSGPOBackupSetting -Backup $ReferenceBackup) -Difference @(Get-PSGPOBackupSetting -Backup $DifferenceBackup)
}
