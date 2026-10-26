# Invoke-PSGPOAuditRetention

Archives the months of the audit log older than its retention, then deletes their files.

_L'aide de la commande, telle que `Get-Help Invoke-PSGPOAuditRetention -Full` la donne (en anglais)._

## Syntaxe

```powershell
Invoke-PSGPOAuditRetention [-Path <string>] [-RetentionMonths <int>] [-Server <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
Invoke-PSGPOAuditRetention -Directory <GPOToolsDirectory> [-Path <string>] [-RetentionMonths <int>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The audit log keeps Audit.RetentionMonths months (13 by default; 0 keeps everything): this month and the ones before it. The files of an older month, in every folder of the log (the tiers of the central log), go to a .zip of the folder Archive of the log, Archive\audit-<yyyy-MM>.zip, with their folder in it; once the archive holds them, they are deleted. A month already archived gets the files written since added to its archive. The archives are kept: delete them, or copy them away, as the policy of the company says.

Run it as an account that deletes files of the log (an administrator of the domain: the accounts of the tiers do not delete), by hand or planned (a scheduled task on Windows, a systemd timer or cron on Linux). The folder Archive gets the permissions of the share: Tier 0 and the readers read it. On Linux a share is reached with smbclient (Kerberos). The retention is written to the audit log itself (PurgeAuditLog).

## Paramètres

### -Path

The folder of the log: Audit.Path of the configuration of the domain by default, else the folder Audit of the backups of the account.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -RetentionMonths

Months kept; Audit.RetentionMonths of the configuration by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Non | Nommé | `-1` | Non |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the log and its retention.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Oui | Nommé | Aucune | Non |

### -Server

Domain controller to read the domain from. Without -Directory nor -Server, the domain of the computer when there is one.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -WhatIf

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Confirm

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Invoke-PSGPOAuditRetention -WhatIf
```

### Exemple 2

```powershell
Invoke-PSGPOAuditRetention -Path \\files\gpo-audit -RetentionMonths 24
```

## Sorties

- `PSGPOTools.AuditRetention`

## Voir aussi

- [Get-PSGPOAuditLog](get-psgpoauditlog.md)
- [Toutes les commandes](../commands.md)
