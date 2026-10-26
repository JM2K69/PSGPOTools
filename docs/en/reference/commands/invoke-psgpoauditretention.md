# Invoke-PSGPOAuditRetention

Archives the months of the audit log older than its retention, then deletes their files.

_The help of the command, as `Get-Help Invoke-PSGPOAuditRetention -Full` gives it._

## Syntax

```powershell
Invoke-PSGPOAuditRetention [-Path <string>] [-RetentionMonths <int>] [-Server <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
Invoke-PSGPOAuditRetention -Directory <GPOToolsDirectory> [-Path <string>] [-RetentionMonths <int>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The audit log keeps Audit.RetentionMonths months (13 by default; 0 keeps everything): this month and the ones before it. The files of an older month, in every folder of the log (the tiers of the central log), go to a .zip of the folder Archive of the log, Archive\audit-<yyyy-MM>.zip, with their folder in it; once the archive holds them, they are deleted. A month already archived gets the files written since added to its archive. The archives are kept: delete them, or copy them away, as the policy of the company says.

Run it as an account that deletes files of the log: a member of Audit.Purgers (the group of a gMSA, which Initialize-PSGPOAuditShare gives the deletion of the files and the archives), or an administrator of the domain; the accounts of the tiers do not delete. By hand or planned: a scheduled task of the gMSA on Windows (no password stored), a systemd timer or cron with the keytab of a dedicated account on Linux. The folder Archive is read by Tier 0 and the readers. On Linux a share is reached with smbclient (Kerberos). The retention is written to the audit log itself (PurgeAuditLog).

## Parameters

### -Path

The folder of the log: Audit.Path of the configuration of the domain by default, else the folder Audit of the backups of the account.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -RetentionMonths

Months kept; Audit.RetentionMonths of the configuration by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Int32` | No | Named | `-1` | No |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the log and its retention.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | Yes | Named | None | No |

### -Server

Domain controller to read the domain from. Without -Directory nor -Server, the domain of the computer when there is one.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

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
Invoke-PSGPOAuditRetention -WhatIf
```

### Example 2

```powershell
Invoke-PSGPOAuditRetention -Path \\files\gpo-audit -RetentionMonths 24
```

## Outputs

- `PSGPOTools.AuditRetention`

## Related

- [Get-PSGPOAuditLog](get-psgpoauditlog.md)
- [All the commands](../commands.md)
