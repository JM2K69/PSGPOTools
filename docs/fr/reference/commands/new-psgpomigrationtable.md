# New-PSGPOMigrationTable

Writes a migration table (.migtable) for the backups of a folder, to edit before an import.

_L'aide de la commande, telle que `Get-Help New-PSGPOMigrationTable -Full` la donne (en anglais)._

## Syntaxe

```powershell
New-PSGPOMigrationTable [-Path] <string> [-BackupPath] <string> [[-Name] <string[]>] [-IncludePermission] [-MapByRelativeName] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As "Populate from Backup" of the Migration Table Editor of GPMC: an entry for each security principal and UNC path the backed up GPOs reference (Get-PSGPOMigrationEntry), the same as the source, or by relative name for the accounts of a domain with -MapByRelativeName. The file is the one GPMC writes (UTF-16, its namespace): the Migration Table Editor opens it, and so does Import-PSGPO. Change the destinations, with the editor or in the XML, before the import.

## Paramètres

### -Path

The migration table to write (.migtable).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -BackupPath

The folder of the backups.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 2 | Aucune | Non |

### -Name

Display names of the GPOs backed up (* and ? make a pattern); all by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 3 | Aucune | Non |

### -IncludePermission

The accounts of the permissions of the GPOs too (backups of GPMC).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -MapByRelativeName

The accounts of a domain are mapped by relative name (the same name in the domain of the import), not kept as they are.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Force

Replaces a table that exists.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

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
New-PSGPOMigrationTable -Path C:\backupGPO\prod.migtable -BackupPath C:\backupGPO -MapByRelativeName
```

## Sorties

- `PSGPOTools.MigrationEntry`

## Voir aussi

- [Toutes les commandes](../commands.md)
