# Restore-PSGPO

Puts a GPO back as one of its backups has it (Backup-PSGPO).

_The help of the command, as `Get-Help Restore-PSGPO -Full` gives it._

## Syntax

```powershell
Restore-PSGPO [-Backup] <Backup> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-NoBackup] [-RestoreLink] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Like GPMC Restore-GPO: the files of the SYSVOL folder of the GPO are replaced by those of the backup (the files the backup does not have are deleted), and its status and client-side extensions are those of the backup. Its version increases in both scopes, so that the computers apply it again. Its links and permissions (security filtering) do not change.

The GPO as it is now is backed up first, in the same folder, so that the restore can be undone (unless -NoBackup). The files of the backup are checked against their SHA-256 first.

A backup of another domain is never restored, even when a GPO of this domain has its GUID (the Default Domain Policy and the Default Domain Controllers Policy have the same GUID in every domain): use it as a template of a new GPO (New-PSGPO -Template).

A backup of a deleted GPO (Get-PSGPOBackup -Deleted) creates it again: a new GPO, with a new GUID given by the domain, the name, settings, status and client-side extensions of the backup. Its security filtering is not restored (it applies to Authenticated Users); with -RestoreLink it is linked again to its containers that still exist, only when its security filtering was Authenticated Users and its links were enabled. The new GPO is backed up at once, and the deleted one leaves the recycle bin.

## Parameters

### -Backup

The backup to restore (Get-PSGPOBackup).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object` | Yes | 1 | None | Yes |

### -Directory

Directory of the GPO (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 2 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -NoBackup

Does not back up the GPO as it is now before restoring it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -RestoreLink

For a deleted GPO: links it again where it was (see the description).

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
# A deleted GPO, created again and linked where it was
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted | Where-Object DisplayName -EQ 'U - Lyon - Printers' | Restore-PSGPO -RestoreLink
```

### Example 2

```powershell
# The GPO as it was on 15 October
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'T1 - Servers - Baseline' |
    Where-Object { $_.Modified.Date -eq [datetime]'2026-10-15' } | Select-Object -First 1 | Restore-PSGPO
```

## Outputs

- `System.Management.Automation.PSObject`

## Related

- [Backup-PSGPO](backup-psgpo.md)
- [All the commands](../commands.md)
