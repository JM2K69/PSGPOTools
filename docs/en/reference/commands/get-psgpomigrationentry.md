# Get-PSGPOMigrationEntry

Lists the security principals and UNC paths the settings of backed up GPOs reference, as a migration table names them.

_The help of the command, as `Get-Help Get-PSGPOMigrationEntry -Full` gives it._

## Syntax

```powershell
Get-PSGPOMigrationEntry [-Path] <string> [[-Name] <string[]>] [-IncludePermission] [<CommonParameters>]
```

## Description

As "Populate from Backup" of the Migration Table Editor of GPMC: for the backups of a folder (of GPMC or of HGPM), each account (by its SID, or its name where the settings give a name) and each UNC path (\\server\share) of their security settings, preferences, scripts and folder redirection: its Type (User, Computer, LocalGroup, GlobalGroup, UniversalGroup, UNCPath, or Unknown for free text and SIDs), its Source as a migration table writes it, its SID, and the files and GPOs it is in.

## Parameters

### -Path

The folder of the backups.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Name

Display names of the GPOs backed up (* and ? make a pattern); all by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 2 | None | No |

### -IncludePermission

The accounts of the permissions of the GPOs too, as the option of GPMC "include security principals from the DACL on the GPO" (backups of GPMC only).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOMigrationEntry -Path C:\backupGPO | Format-Table Type, Source, Gpos
```

## Outputs

- `PSGPOTools.MigrationReference`

## Related

- [All the commands](../commands.md)
