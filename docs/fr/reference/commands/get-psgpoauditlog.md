# Get-PSGPOAuditLog

What the consoles and the commands changed in the domain: the audit log.

_L'aide de la commande, telle que `Get-Help Get-PSGPOAuditLog -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOAuditLog [[-Path] <string>] [[-Domain] <string>] [[-Name] <string>] [[-Action] <string[]>] [[-Account] <string>] [[-After] <datetime>] [[-Before] <datetime>] [<CommonParameters>]
```

## Description

Each change the domain accepted, from the console or a command, is a line of the audit log: when, by which account, from which computer, on which domain controller, what and on what (a GPO, a container, the configuration). The log is in Audit.Path of the configuration of the domain (a share the administrators write, the same for every console); by default in the folder Audit of the backups of the account. Newest first.

## Paramètres

### -Path

Folder of the audit log; Audit.Path of the configuration by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

### -Domain

Domain whose changes are listed; all of them by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -Name

Display name of a GPO (* and ? make a pattern): only its changes.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -Action

Only these actions (NewGpo, RenameGpo, SetGpoStatus, RemoveGpo, RemoveDeletedGpoBackup, NewLink, SetLink, RemoveLink, SetBlockInheritance, SetWmiFilter, NewWmiFilter, EditWmiFilter, RemoveWmiFilter, SetWmiFilterPermission, SetGpoPermission, SetGpoSecurityFiltering, ApproveGpo, PendingGpo, SaveGpoFile, RestoreGpo, ImportGpo, ImportPolicyRuleSet, NewFilteringGroups, SaveConfiguration, InstallAdmx, NewPasswordPolicy, SetPasswordPolicy, RemovePasswordPolicy, InitializeAuditShare); * and ? make a pattern.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 4 | Aucune | Non |

### -Account

Only the changes of this account (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

### -After

Only the changes after this date.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `DateTime` | Non | 6 | Aucune | Non |

### -Before

Only the changes before this date.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `DateTime` | Non | 7 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOAuditLog -Path \\files\gpo-audit -After (Get-Date).AddDays(-7) | Format-Table Time, Account, Action, Target
```

### Exemple 2

```powershell
Get-PSGPOAuditLog -Name 'C - Servers - Baseline' -Action SaveGpoFile
```

## Sorties

- `PSGPOTools.AuditEntry`

## Voir aussi

- [Toutes les commandes](../commands.md)
