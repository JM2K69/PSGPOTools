# Remove-PSGPOBackup

Deletes for good a GPO of the recycle bin: all its backups.

_The help of the command, as `Get-Help Remove-PSGPOBackup -Full` gives it._

## Syntax

```powershell
Remove-PSGPOBackup [-Backup] <Backup> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

A GPO deleted from the domain stays in the recycle bin (Get-PSGPOBackup -Deleted) as long as its backups are in the folder: Remove-PSGPOBackup deletes every backup of its GUID in the folder of the backup given, made before or after a rename, the templates made from it too. It cannot be restored afterwards.

The backups of a GPO that is still in the domain are its history: they are not deleted, nor those of another domain.

## Parameters

### -Backup

A backup of the deleted GPO (Get-PSGPOBackup -Deleted).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object` | Yes | 1 | None | Yes |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 2 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -WhatIf

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Confirm

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted -Name 'U - Lyon - Printers' | Remove-PSGPOBackup
```

## Outputs

- `PSGPOTools.RemovedBackup`

## Related

- [Get-PSGPOBackup](get-psgpobackup.md)
- [Restore-PSGPO](restore-psgpo.md)
- [All the commands](../commands.md)
