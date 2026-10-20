# Import-PSGPO

Imports the settings of a backed up GPO into a GPO of the domain, with a migration table.

_L'aide de la commande, telle que `Get-Help Import-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
Import-PSGPO [-Path] <string> [-TargetName] <string> [[-SourceName] <string>] [[-BackupId] <string>] [[-MigrationTable] <string>] [[-BackupPath] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Exclusive] [-CreateIfNeeded] [-NoBackup] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As "Import Settings" of GPMC: the settings of a backup made by GPMC (Backup-GPO) or by Backup-PSGPO, of this domain or of another one, replace those of the GPO -TargetName. The GPO is backed up first (unless -NoBackup); its links, permissions, status and WMI filter do not change, and its version increases so that the computers apply it again.

A migration table (.migtable, as the Migration Table Editor of GPMC writes it, or New-PSGPOMigrationTable) maps the security principals and the UNC paths of the backup to those of this domain: the same as the source, the same name in this domain (by relative name), another account or path, or none (the account is removed from the setting). The security settings, the preferences, the scripts and the folder redirection are migrated; the administrative templates are copied as they are, as GPMC does. A destination that cannot be found stops the import, nothing is changed.

## Paramètres

### -Path

The folder of the backups: a folder of GPMC backups, one GPMC backup, or a folder of Backup-PSGPO.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -TargetName

The GPO of the domain that takes the settings.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 2 | Aucune | Non |

### -SourceName

The GPO backed up to import, when the folder holds backups of several GPOs (its newest).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -BackupId

The ID of the backup to import (Get-PSGPOGpmcBackup), or its folder name for Backup-PSGPO.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

### -MigrationTable

The migration table (.migtable). Without it, the references are copied as they are.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

### -Exclusive

Every security principal and UNC path of the settings must be in the migration table, as "Use migration table exclusively" of GPMC.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -CreateIfNeeded

Creates the GPO -TargetName when the domain has none.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -BackupPath

Folder of the backup of the GPO made before the import (by default the folder of the backups).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 6 | Aucune | Non |

### -NoBackup

No backup of the GPO before the import.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 7 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 8 | Aucune | Non |

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
Import-PSGPO -Path C:\backupGPO -SourceName 'C - Servers - Baseline' -TargetName 'C - Servers - Baseline' -MigrationTable C:\backupGPO\prod.migtable
```

### Exemple 2

```powershell
Import-PSGPO -Path C:\backupGPO -SourceName 'TEST' -TargetName 'C - Test' -CreateIfNeeded -WhatIf
```

## Sorties

- `PSGPOTools.ImportResult`

## Voir aussi

- [Toutes les commandes](../commands.md)
