# New-PSGPOMigrationTable

Writes a migration table (.migtable) for the backups of a folder, to edit before an import.

_The help of the command, as `Get-Help New-PSGPOMigrationTable -Full` gives it._

## Syntax

```powershell
New-PSGPOMigrationTable [-Path] <string> [-BackupPath] <string> [[-Name] <string[]>] [-IncludePermission] [-MapByRelativeName] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As "Populate from Backup" of the Migration Table Editor of GPMC: an entry for each security principal and UNC path the backed up GPOs reference (Get-PSGPOMigrationEntry), the same as the source, or by relative name for the accounts of a domain with -MapByRelativeName. The file is the one GPMC writes (UTF-16, its namespace): the Migration Table Editor opens it, and so does Import-PSGPO. Change the destinations, with the editor or in the XML, before the import.

## Parameters

### -Path

The migration table to write (.migtable).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -BackupPath

The folder of the backups.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -Name

Display names of the GPOs backed up (* and ? make a pattern); all by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 3 | None | No |

### -IncludePermission

The accounts of the permissions of the GPOs too (backups of GPMC).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -MapByRelativeName

The accounts of a domain are mapped by relative name (the same name in the domain of the import), not kept as they are.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Force

Replaces a table that exists.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

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
New-PSGPOMigrationTable -Path C:\backupGPO\prod.migtable -BackupPath C:\backupGPO -MapByRelativeName
```

## Outputs

- `PSGPOTools.MigrationEntry`

## Related

- [All the commands](../commands.md)
