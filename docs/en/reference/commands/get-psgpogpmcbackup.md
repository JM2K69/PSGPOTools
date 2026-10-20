# Get-PSGPOGpmcBackup

Lists the backups of GPMC (Backup-GPO) a folder holds, to import them with Import-PSGPO.

_The help of the command, as `Get-Help Get-PSGPOGpmcBackup -Full` gives it._

## Syntax

```powershell
Get-PSGPOGpmcBackup [-Path] <string> [[-Name] <string[]>] [<CommonParameters>]
```

## Description

One object per backup, newest first: the GPO backed up (its name, Id and domain), when, its comment, the ID of the backup, its folder, and the accounts of the GPO its Backup.xml lists (SecurityGroups: the names a migration table gives them).

## Parameters

### -Path

A folder of GPMC backups, or one backup.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Name

Display names of the GPOs backed up (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 2 | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOGpmcBackup -Path C:\backupGPO
```

## Outputs

- `PSGPOTools.GpmcBackup`

## Related

- [All the commands](../commands.md)
