# Export-PSGPOWmiFilter

Exports WMI filters of the domain to .mof files, as GPMC "Export" does.

_L'aide de la commande, telle que `Get-Help Export-PSGPOWmiFilter -Full` la donne (en anglais)._

## Syntaxe

```powershell
Export-PSGPOWmiFilter -Name <string[]> -Path <string> [-Force] [-Directory <GPOToolsDirectory>] [-Server <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
Export-PSGPOWmiFilter -InputObject <Object[]> -Path <string> [-Force] [-Domain <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

One .mof file for each filter, in the format of GPMC (UTF-16, an instance of MSFT_SomFilter with its rules): GPMC imports it in another domain, and so does Import-PSGPOWmiFilter. The file keeps the name, description, author, dates and WQL queries of the filter.

With -InputObject, filters that are not in a domain are exported: objects with Name, Description and Queries (Namespace and Query), as Show-WmiFilterCreatorAvalonia writes them; no domain is read.

## Paramètres

### -Name

Names of the filters (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | Nommé | Aucune | Non |

### -InputObject

Filters to export without a domain: objects with Name, Description (optional) and Queries (Namespace and Query); Id, Author, CreationDate and ChangeDate are kept when given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object[]` | Oui | Nommé | Aucune | Oui |

### -Path

Folder of the files, each one named after its filter (<name>.mof); or the .mof file of one filter.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | Nommé | Aucune | Non |

### -Force

Replaces a file that exists.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | Nommé | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Domain

DNS name of the domain written in the file with -InputObject; the domain of the computer by default. GPMC creates the filter in the domain it imports it in, whatever this name is.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

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

### Exemple 3

```powershell
$Query = Get-PSGPOWmiQueryTemplate -Id Laptops
[pscustomobject]@{ Name = 'Laptops'; Queries = $Query } | Export-PSGPOWmiFilter -Path C:\Exports
```

## Sorties

- `System.IO.FileInfo`

## Voir aussi

- [Import-PSGPOWmiFilter](import-psgpowmifilter.md)
- [Toutes les commandes](../commands.md)
