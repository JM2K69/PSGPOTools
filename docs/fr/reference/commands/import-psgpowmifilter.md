# Import-PSGPOWmiFilter

Creates WMI filters in the domain from .mof files, as GPMC "Import" does.

_L'aide de la commande, telle que `Get-Help Import-PSGPOWmiFilter -Full` la donne (en anglais)._

## Syntaxe

```powershell
Import-PSGPOWmiFilter [-Path] <string[]> [[-Name] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Reads the .mof files GPMC exports (Export in the context menu of a WMI filter), and those of Export-PSGPOWmiFilter: an instance of MSFT_SomFilter with its WQL rules. Each filter is created in the domain with the name, description and queries of the file; it gets a new Id, so that a file exported from this domain is imported again beside its filter. A filter whose name the domain has already is not imported: -Name gives it another one.

## Paramètres

### -Path

The .mof files.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -Name

Name of the imported filter, instead of the one of the file: one filter only.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 3 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

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
Import-PSGPOWmiFilter -Path C:\Exports\Workstations.mof
```

### Exemple 2

```powershell
Get-ChildItem /srv/wmi-filters -Filter *.mof | Import-PSGPOWmiFilter
```

## Sorties

- `PSGPOTools.WmiFilter`

## Voir aussi

- [Export-PSGPOWmiFilter](export-psgpowmifilter.md)
- [Toutes les commandes](../commands.md)
