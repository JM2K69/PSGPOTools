# Export-PSGPOWmiFilter

Exports WMI filters of the domain to .mof files, as GPMC "Export" does.

_L'aide de la commande, telle que `Get-Help Export-PSGPOWmiFilter -Full` la donne (en anglais)._

## Syntaxe

```powershell
Export-PSGPOWmiFilter [-Name] <string[]> [-Path] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

One .mof file for each filter, in the format of GPMC (UTF-16, an instance of MSFT_SomFilter with its rules): GPMC imports it in another domain, and so does Import-PSGPOWmiFilter. The file keeps the name, description, author, dates and WQL queries of the filter.

## Paramètres

### -Name

Names of the filters (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Non |

### -Path

Folder of the files, each one named after its filter (<name>.mof); or the .mof file of one filter.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 2 | Aucune | Non |

### -Force

Replaces a file that exists.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

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
Export-PSGPOWmiFilter -Name 'Workstations' -Path C:\Exports
```

### Exemple 2

```powershell
Export-PSGPOWmiFilter -Name '*' -Path /srv/wmi-filters
```

## Sorties

- `System.IO.FileInfo`

## Voir aussi

- [Import-PSGPOWmiFilter](import-psgpowmifilter.md)
- [Toutes les commandes](../commands.md)
