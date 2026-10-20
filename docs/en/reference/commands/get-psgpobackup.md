# Get-PSGPOBackup

Lists the backups of GPOs written by Backup-PSGPO, newest first.

_The help of the command, as `Get-Help Get-PSGPOBackup -Full` gives it._

## Syntax

```powershell
Get-PSGPOBackup [-Path] <string> [[-Name] <string>] [[-Id] <guid>] [[-Label] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Approved] [-Template] [-Deleted] [<CommonParameters>]
```

## Parameters

### -Path

Root folder of the backups.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Name

Display name of the GPO (wildcards allowed), as it was when backed up.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | `*` | No |

### -Id

GUID of the GPO: its backups even when it was renamed.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Guid` | No | 3 | `[guid]::Empty` | No |

### -Label

Only the backups with this label (wildcards allowed).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -Approved

Only the backups with the approved label of the configuration.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Template

Only the templates of new GPOs: the backups with the template label of the configuration.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Deleted

The recycle bin: the newest backup of each GPO of the domain that is not in it anymore (and was not created again since). Reads the domain, or uses -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Directory

With -Deleted: the directory of the domain (Get-PSGPODirectory).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 5 | None | No |

### -Server

With -Deleted: the domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 6 | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
```

### Example 2

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Approved | Select-Object DisplayName, BackedUp, Comment
```

### Example 3

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted | Restore-PSGPO -RestoreLink
```

## Outputs

- `PSGPOTools.Backup`

## Related

- [Backup-PSGPO](backup-psgpo.md)
- [Compare-PSGPOBackup](compare-psgpobackup.md)
- [All the commands](../commands.md)
