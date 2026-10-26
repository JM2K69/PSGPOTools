# Initialize-PSGPOBackupShare

Prepares the share of the central backups of the GPOs: for Tier 0 only.

_The help of the command, as `Get-Help Initialize-PSGPOBackupShare -Full` gives it._

## Syntax

```powershell
Initialize-PSGPOBackupShare [-Path <string>] [-Server <string>] [-Credential <pscredential>] [-WhatIf] [-Confirm] [<CommonParameters>]
Initialize-PSGPOBackupShare -Directory <GPOToolsLdapDirectory> [-Path <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The backups of the GPOs of a domain are central on a share of a file server (Backup.Path of the configuration of the domain): the History tab, the approved versions (Get-PSGPODrift), the deleted GPOs and their restore. They are for Tier 0 only: Initialize-PSGPOBackupShare writes the permissions of the share (protected: nothing inherited from it):

- SYSTEM, Administrators and Domain Admins: full control;
- the approvers of the workflow (Workflow.Approvers): change (read, write, delete);
- nobody else: the accounts of Tier 1 and Tier 2 neither read nor write it. The console does
not show them the History tab nor the deleted GPOs, and does not back up a GPO before
they change it (the approval backs up the approved version).

Run it once by an account that can change the permissions of the share, and again when the approvers change: the backups are kept. The share is made first (New-PSGPOShare.ps1 on Windows, New-PSGPOShare.sh on Samba). On Linux, the consoles of Tier 0 mount the share (New-PSGPOShareMount.sh): HGPM finds where in /proc/mounts.

## Parameters

### -Path

The share: \\server\share (//server/share on Linux too), or a folder in it. Backup.Path of the configuration of the domain by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the approvers.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsLdapDirectory` | Yes | Named | None | No |

### -Server

Domain controller to read the domain from. By default, the domain of the computer.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Credential

Account to read the domain with, instead of the current identity.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | Named | None | No |

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
Initialize-PSGPOBackupShare -Path \\files\gpo-backups -WhatIf
```

### Example 2

```powershell
# Linux, Samba AD
kinit administrator@HARDENBOX.LABO
Initialize-PSGPOBackupShare -Path //dc.hardenbox.labo/gpo-backups -Server dc.hardenbox.labo
```

## Outputs

- `PSGPOTools.BackupShare`

## Related

- [Initialize-PSGPOAuditShare](initialize-psgpoauditshare.md)
- [Backup-PSGPO](backup-psgpo.md)
- [All the commands](../commands.md)
