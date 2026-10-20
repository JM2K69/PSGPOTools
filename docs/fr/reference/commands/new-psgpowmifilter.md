# New-PSGPOWmiFilter

Creates a WMI filter in the domain, as GPMC "New" in WMI Filters.

_L'aide de la commande, telle que `Get-Help New-PSGPOWmiFilter -Full` la donne (en anglais)._

## Syntaxe

```powershell
New-PSGPOWmiFilter [-Name] <string> [-Query] <string[]> [[-Namespace] <string>] [[-Description] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

A msWMI-Som object in CN=SOM,CN=WMIPolicy,CN=System of the domain, with its WQL queries. A computer applies a GPO linked to it (Set-PSGPO -WmiFilter) only when one of its queries returns something. Samba AD keeps the filters for the Windows computers of the domain.

## Paramètres

### -Name

Name of the filter, unique in the domain.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Query

WQL queries: SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1 for example.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 2 | Aucune | Non |

### -Namespace

WMI namespace of the queries; root\CIMv2 by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | `root\CIMv2` | Non |

### -Description

What the filter is for.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 5 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 6 | Aucune | Non |

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
New-PSGPOWmiFilter -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
```

### Exemple 2

```powershell
New-PSGPOWmiFilter -Name 'Windows 11' -Query "SELECT * FROM Win32_OperatingSystem WHERE Version LIKE '10.0.2%' AND ProductType = 1" -Description 'Windows 11 workstations'
```

## Sorties

- `PSGPOTools.WmiFilter`

## Voir aussi

- [Get-PSGPOWmiFilter](get-psgpowmifilter.md)
- [Set-PSGPO](set-psgpo.md)
- [Toutes les commandes](../commands.md)
