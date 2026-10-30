# Get-PSGPODrift

Finds the GPOs changed since their approved version.

_The help of the command, as `Get-Help Get-PSGPODrift -Full` gives it._

## Syntax

```powershell
Get-PSGPODrift [-Path] <string> [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [[-Label] <string>] [-IncludePermissions] [<CommonParameters>]
```

## Description

The approved version of a GPO is its newest backup with the approved label of the configuration (Backup.ApprovedLabel, 'Approved' by default: Backup-PSGPO -Approve, Set-PSGPOBackup -Approve, or the History tab). Each GPO, as it is now, is compared to it setting by setting, as Compare-PSGPOBackup does: what changed since, in the console or elsewhere (GPMC, samba-tool, a script), is its drift.

State of each GPO: InSync (it is its approved version), Drifted (Changes: what changed since, Added, Removed or Changed with the value before and after), or NotApproved (no approved version yet).

With -IncludePermissions, its owner and its permissions are compared too, as the Delegation tab lists them (Path Permissions: each account by its SID, its level, denied or inherited): an account added, removed or given another level since the approval, another owner. A backup keeps them since HGPM 0.1.26: when the approved version is older, Permissions says NotRecorded, and the permissions are not compared (approve the GPO again to record them).

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

### -IncludePermissions

Compares the owner and the permissions of each GPO to those of its approved version too.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
```

### Example 2

```powershell
# Who was given rights on a GPO since its approval
(Get-PSGPODrift -Path /srv/gpo-backups -IncludePermissions).Changes | Where-Object Path -EQ 'Permissions' | Format-Table Change, Name, Before, After
```

### Example 3

```powershell
(Get-PSGPODrift -Path D:\GPO_Backup -Name 'Default Domain Policy').Changes | Format-Table Change, Path, Name, Before, After
```

## Outputs

- `PSGPOTools.Drift`

## Related

- [Backup-PSGPO](backup-psgpo.md)
- [Set-PSGPOBackup](set-psgpobackup.md)
- [All the commands](../commands.md)
