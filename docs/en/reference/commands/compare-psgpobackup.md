# Compare-PSGPOBackup

Shows what changed between two backups of a GPO, setting by setting.

_The help of the command, as `Get-Help Compare-PSGPOBackup -Full` gives it._

## Syntax

```powershell
Compare-PSGPOBackup [-ReferenceBackup] <Backup> [-DifferenceBackup] <Backup> [<CommonParameters>]
```

## Description

Compares the settings of two backups (Get-PSGPOBackup) as the Settings tab shows them: the policies of the Registry.pol files by category path (with the ADMX files loaded by Initialize-PSGPOAdmx; otherwise as extra registry values), the security settings (GptTmpl.inf), the other files of the GPO by their content, and its name, status, security filtering and links. Each change is Added, Removed or Changed, with the value before and after.

## Parameters

### -ReferenceBackup

The older backup.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object` | Yes | 1 | None | No |

### -DifferenceBackup

The newer backup.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object` | Yes | 2 | None | No |

## Examples

### Example 1

```powershell
$Backups = Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
Compare-PSGPOBackup -ReferenceBackup $Backups[1] -DifferenceBackup $Backups[0]
```

## Outputs

- `PSGPOTools.SettingChange`

## Related

- [Backup-PSGPO](backup-psgpo.md)
- [All the commands](../commands.md)
