# Get-PSGPODrift

Finds the GPOs changed since their approved version.

_The help of the command, as `Get-Help Get-PSGPODrift -Full` gives it._

## Syntax

```powershell
Get-PSGPODrift [-Path] <string> [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [[-Label] <string>] [<CommonParameters>]
```

## Description

The approved version of a GPO is its newest backup with the approved label of the configuration (Backup.ApprovedLabel, 'Approved' by default: Backup-PSGPO -Approve, Set-PSGPOBackup -Approve, or the History tab). Each GPO, as it is now, is compared to it setting by setting, as Compare-PSGPOBackup does: what changed since, in the console or elsewhere (GPMC, samba-tool, a script), is its drift.

State of each GPO: InSync (it is its approved version), Drifted (Changes: what changed since, Added, Removed or Changed with the value before and after), or NotApproved (no approved version yet).

## Parameters

### -Path

Root folder of the backups (Backup-PSGPO).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Name

Display names of the GPOs (wildcards allowed); all the GPOs by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 2 | None | Yes |

### -Directory

Directory of the GPOs (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 3 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -Label

Label of the approved versions, instead of the one of the configuration.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 5 | None | No |

## Examples

### Example 1

```powershell
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
```

### Example 2

```powershell
(Get-PSGPODrift -Path D:\GPO_Backup -Name 'Default Domain Policy').Changes | Format-Table Change, Path, Name, Before, After
```

## Outputs

- `PSGPOTools.Drift`

## Related

- [Backup-PSGPO](backup-psgpo.md)
- [Set-PSGPOBackup](set-psgpobackup.md)
- [All the commands](../commands.md)
