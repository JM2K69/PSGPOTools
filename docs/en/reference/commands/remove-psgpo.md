# Remove-PSGPO

Deletes GPOs of the domain, backed up first: they stay in the recycle bin.

_The help of the command, as `Get-Help Remove-PSGPO -Full` gives it._

## Syntax

```powershell
Remove-PSGPO [-Name] <string[]> [[-BackupPath] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-NoBackup] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Like GPMC "Delete": the links of the GPO in the domain are deleted first (the GPO is not deleted when the account cannot delete one of them), then the GPO, its container in the directory and its folder in SYSVOL (on Windows with Remove-GPO of RSAT, on Linux with samba-tool and Kerberos). The Default Domain Policy and the Default Domain Controllers Policy are never deleted.

Each GPO is backed up first in -BackupPath (unless -NoBackup), and its last backup says when and by whom it was deleted: Get-PSGPOBackup -Deleted lists it, Restore-PSGPO creates it again.

## Parameters

### -Name

Display names of the GPOs to delete (wildcards allowed).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | Yes |

### -BackupPath

Root folder of the backups; by default the one of the History tab of the window.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -NoBackup

Does not back up the GPOs before deleting them: they cannot be created again.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 3 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

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
Remove-PSGPO -Name 'U - Lyon - Printers' -BackupPath /srv/gpo-backups
```

## Outputs

- `PSGPOTools.RemovedGpo`

## Related

- [Get-PSGPOBackup](get-psgpobackup.md)
- [Restore-PSGPO](restore-psgpo.md)
- [All the commands](../commands.md)
