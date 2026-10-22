# Set-PSGPOWmiFilter

Changes a WMI filter of the domain: its name, description or queries, as GPMC edits a filter.

_L'aide de la commande, telle que `Get-Help Set-PSGPOWmiFilter -Full` la donne (en anglais)._

## Syntaxe

```powershell
Set-PSGPOWmiFilter [-Name] <string> [[-NewName] <string>] [[-Description] <string>] [[-Query] <string[]>] [[-Namespace] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The msWMI-Som object of the filter is changed in place: its Id does not change, so the GPOs linked to it keep it and the computers apply them with its new queries. The change is refused if the filter changed in the domain since it was read.

## Paramètres

### -Name

Name (or Id) of the filter to change.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -NewName

New name of the filter, unique in the domain.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -Description

New description; an empty one removes it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -Query

WQL queries that replace those of the filter.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 4 | Aucune | Non |

### -Namespace

WMI namespace of the queries: of -Query (root\CIMv2 by default), or of the queries the filter has without -Query.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 6 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 7 | Aucune | Non |

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
Set-PSGPOWmiFilter -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1 AND Version LIKE ''10.0.2%'''
```

### Exemple 2

```powershell
Set-PSGPOWmiFilter -Name 'Windows 11' -NewName 'Windows 11 workstations' -Description 'Windows 11, not the servers'
```

## Sorties

- `PSGPOTools.WmiFilter`

## Voir aussi

- [Get-PSGPOWmiFilter](get-psgpowmifilter.md)
- [New-PSGPOWmiFilter](new-psgpowmifilter.md)
- [Toutes les commandes](../commands.md)
