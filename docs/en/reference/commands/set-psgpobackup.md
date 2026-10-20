# Set-PSGPOBackup

Changes the comment and the labels of a backup of a GPO.

_The help of the command, as `Get-Help Set-PSGPOBackup -Full` gives it._

## Syntax

```powershell
Set-PSGPOBackup [-Backup] <Backup> [[-Comment] <string>] [[-AddLabel] <string[]>] [[-RemoveLabel] <string[]>] [-Approve] [-Unapprove] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The notes of a backup (Get-PSGPOBackup) are kept beside it, in notes.json: its comment and its labels, with who changed them and when. The files of the backup and its manifest do not change. The approved label of the configuration (Backup.ApprovedLabel, or -Approve) makes the backup the approved version of the GPO, to which Get-PSGPODrift compares it.

## Parameters

### -Backup

The backup (Get-PSGPOBackup).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object` | Yes | 1 | None | Yes |

### -Comment

The new comment of the backup; an empty string removes it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -AddLabel

Labels to add.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 3 | None | No |

### -RemoveLabel

Labels to remove (case ignored).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 4 | None | No |

### -Approve

Adds the approved label of the configuration.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Unapprove

Removes the approved label of the configuration.

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
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy' | Select-Object -First 1 |
    Set-PSGPOBackup -Approve -Comment 'Reviewed with the security team'
```

## Outputs

- `PSGPOTools.Backup`

## Related

- [Get-PSGPOBackup](get-psgpobackup.md)
- [Get-PSGPODrift](get-psgpodrift.md)
- [All the commands](../commands.md)
