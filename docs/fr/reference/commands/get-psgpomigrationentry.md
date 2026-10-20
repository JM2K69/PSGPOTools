# Get-PSGPOMigrationEntry

Lists the security principals and UNC paths the settings of backed up GPOs reference, as a migration table names them.

_L'aide de la commande, telle que `Get-Help Get-PSGPOMigrationEntry -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOMigrationEntry [-Path] <string> [[-Name] <string[]>] [-IncludePermission] [<CommonParameters>]
```

## Description

As "Populate from Backup" of the Migration Table Editor of GPMC: for the backups of a folder (of GPMC or of HGPM), each account (by its SID, or its name where the settings give a name) and each UNC path (\\server\share) of their security settings, preferences, scripts and folder redirection: its Type (User, Computer, LocalGroup, GlobalGroup, UniversalGroup, UNCPath, or Unknown for free text and SIDs), its Source as a migration table writes it, its SID, and the files and GPOs it is in.

## Paramètres

### -Path

The folder of the backups.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Name

Display names of the GPOs backed up (* and ? make a pattern); all by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 2 | Aucune | Non |

### -IncludePermission

The accounts of the permissions of the GPOs too, as the option of GPMC "include security principals from the DACL on the GPO" (backups of GPMC only).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOMigrationEntry -Path C:\backupGPO | Format-Table Type, Source, Gpos
```

## Sorties

- `PSGPOTools.MigrationReference`

## Voir aussi

- [Toutes les commandes](../commands.md)
