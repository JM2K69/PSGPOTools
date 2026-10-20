# Import-PSGPO

Imports the settings of a backed up GPO into a GPO of the domain, with a migration table.

_The help of the command, as `Get-Help Import-PSGPO -Full` gives it._

## Syntax

```powershell
Import-PSGPO [-Path] <string> [-TargetName] <string> [[-SourceName] <string>] [[-BackupId] <string>] [[-MigrationTable] <string>] [[-BackupPath] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Exclusive] [-CreateIfNeeded] [-NoBackup] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As "Import Settings" of GPMC: the settings of a backup made by GPMC (Backup-GPO) or by Backup-PSGPO, of this domain or of another one, replace those of the GPO -TargetName. The GPO is backed up first (unless -NoBackup); its links, permissions, status and WMI filter do not change, and its version increases so that the computers apply it again.

A migration table (.migtable, as the Migration Table Editor of GPMC writes it, or New-PSGPOMigrationTable) maps the security principals and the UNC paths of the backup to those of this domain: the same as the source, the same name in this domain (by relative name), another account or path, or none (the account is removed from the setting). The security settings, the preferences, the scripts and the folder redirection are migrated; the administrative templates are copied as they are, as GPMC does. A destination that cannot be found stops the import, nothing is changed.

## Parameters

### -Path

The folder of the backups: a folder of GPMC backups, one GPMC backup, or a folder of Backup-PSGPO.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -TargetName

The GPO of the domain that takes the settings.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -SourceName

The GPO backed up to import, when the folder holds backups of several GPOs (its newest).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -BackupId

The ID of the backup to import (Get-PSGPOGpmcBackup), or its folder name for Backup-PSGPO.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -MigrationTable

The migration table (.migtable). Without it, the references are copied as they are.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 5 | None | No |

### -Exclusive

Every security principal and UNC path of the settings must be in the migration table, as "Use migration table exclusively" of GPMC.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -CreateIfNeeded

Creates the GPO -TargetName when the domain has none.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -BackupPath

Folder of the backup of the GPO made before the import (by default the folder of the backups).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 6 | None | No |

### -NoBackup

No backup of the GPO before the import.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 7 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 8 | None | No |

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
Import-PSGPO -Path C:\backupGPO -SourceName 'C - Servers - Baseline' -TargetName 'C - Servers - Baseline' -MigrationTable C:\backupGPO\prod.migtable
```

### Example 2

```powershell
Import-PSGPO -Path C:\backupGPO -SourceName 'TEST' -TargetName 'C - Test' -CreateIfNeeded -WhatIf
```

## Outputs

- `PSGPOTools.ImportResult`

## Related

- [All the commands](../commands.md)
