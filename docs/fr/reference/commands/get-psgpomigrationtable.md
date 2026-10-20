# Get-PSGPOMigrationTable

Reads a migration table (.migtable) of GPMC.

_L'aide de la commande, telle que `Get-Help Get-PSGPOMigrationTable -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOMigrationTable [-Path] <string> [<CommonParameters>]
```

## Description

Its entries, checked as GPMC checks them: Type (User, Computer, LocalGroup, GlobalGroup, UniversalGroup, UNCPath, Unknown), Source, and how it maps: Mode SameAsSource (the reference is kept), ByRelativeName (the same name in the domain of the import), None (the account is removed) or Explicit, with its Destination. A UNC path is kept or mapped to another path; free text or a SID is not mapped by relative name; a destination is a name.

## Paramètres

### -Path

The migration table.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOMigrationTable -Path C:\backupGPO\prod.migtable | Where-Object Mode -NE SameAsSource
```

## Sorties

- `PSGPOTools.MigrationEntry`

## Voir aussi

- [Toutes les commandes](../commands.md)
