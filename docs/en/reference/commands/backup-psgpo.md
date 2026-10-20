# Backup-PSGPO

Backs up GPOs of the domain in a folder, when they changed since their last backup.

_The help of the command, as `Get-Help Backup-PSGPO -Full` gives it._

## Syntax

```powershell
Backup-PSGPO [-Path] <string> [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [[-Comment] <string>] [[-Label] <string[]>] [-Approve] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Each GPO is backed up in <Path>/<GPO name> {<GUID>}/<last change, UTC>/: the files of its SYSVOL folder as they are, and manifest.json with its versions, status, security filtering, links and the SHA-256 of each file. A GPO that did not change since its last backup is not backed up again (Result: Unchanged), unless -Force; run it on a schedule to keep the history of the GPOs, then compare two backups with Compare-PSGPOBackup or in the History tab of Show-GPOManagerAvalonia.

A backup can have a comment (why the GPO changed) and labels; the approved label of the configuration (Backup.ApprovedLabel, 'Approved' by default, or -Approve) makes it the approved version of the GPO, to which Get-PSGPODrift compares it. When the GPO did not change, its last backup gets the labels, not the comment: Set-PSGPOBackup changes it.

Works from Windows (UNC path) and Linux (smbclient with Kerberos), against Windows and Samba domain controllers. These backups are not GPMC backups: Restore-GPO / Import-GPO do not read them.

## Parameters

### -Path

Root folder of the backups; created when missing.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Name

Display names of the GPOs to back up (wildcards allowed); all the GPOs by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 2 | None | Yes |

### -Directory

Directory to back up the GPOs of (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 3 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -Comment

Comment of the backup: why the GPO changed, the ticket of the change.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 5 | None | No |

### -Label

Labels of the backup.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 6 | None | No |

### -Approve

Adds the approved label of the configuration: the backup is the approved version of the GPO.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Force

Backs up a GPO even when it did not change.

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
Backup-PSGPO -Path /srv/gpo-backups
```

### Example 2

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Name 'C - Servers - Security Baseline' -Comment 'CHG-1024: SMB signing' -Approve
```

### Example 3

```powershell
Backup-PSGPO -Path D:\GPO_Backup -Name 'C - *' -Server dc1.contoso.com
```

## Outputs

- `PSGPOTools.Backup`

## Related

- [Get-PSGPOBackup](get-psgpobackup.md)
- [Compare-PSGPOBackup](compare-psgpobackup.md)
- [Get-PSGPODrift](get-psgpodrift.md)
- [All the commands](../commands.md)
