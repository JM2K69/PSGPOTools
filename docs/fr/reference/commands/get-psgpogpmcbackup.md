# Get-PSGPOGpmcBackup

Lists the backups of GPMC (Backup-GPO) a folder holds, to import them with Import-PSGPO.

_L'aide de la commande, telle que `Get-Help Get-PSGPOGpmcBackup -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOGpmcBackup [-Path] <string> [[-Name] <string[]>] [<CommonParameters>]
```

## Description

One object per backup, newest first: the GPO backed up (its name, Id and domain), when, its comment, the ID of the backup, its folder, and the accounts of the GPO its Backup.xml lists (SecurityGroups: the names a migration table gives them).

## Paramètres

### -Path

A folder of GPMC backups, or one backup.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Name

Display names of the GPOs backed up (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 2 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOGpmcBackup -Path C:\backupGPO
```

## Sorties

- `PSGPOTools.GpmcBackup`

## Voir aussi

- [Toutes les commandes](../commands.md)
