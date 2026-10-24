# Get-PSGPOWmiQueryTemplate

Gets the ready-made WQL queries of the WMI filter creator, their parameters given.

_L'aide de la commande, telle que `Get-Help Get-PSGPOWmiQueryTemplate -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOWmiQueryTemplate [[-Id] <string[]>] [-Category <string[]>] [-Value <hashtable>] [<CommonParameters>]
```

## Description

The library of Show-WmiFilterCreatorAvalonia: more than sixty queries for WMI filters, by category (operating system, edition and language, domain and name, hardware, virtual machines, security, network and location, software and services, files, time and state), each with its namespace, its note (the pitfalls of the query) and its source.

A query with parameters ({Build}, {Memory}...) is given with their default values, or those of -Value; Parameters lists them (Name, Label, Kind Text, Number or Choice, Default, Choices). The query goes to New-PSGPOWmiFilter, Set-PSGPOWmiFilter or Test-PSGPOWmiFilter.

## Paramètres

### -Id

Identifiers of the queries (* and ? make a pattern): Windows11, Laptops, Subnet...

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 1 | Aucune | Non |

### -Category

Categories of the queries (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | Nommé | Aucune | Non |

### -Value

Values of the parameters, by name: @{ Memory = 16 } for the query Memory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Hashtable` | Non | Nommé | `@{}` | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOWmiQueryTemplate | Format-Table Category, Id, Query
```

### Exemple 2

```powershell
$Query = Get-PSGPOWmiQueryTemplate -Id Memory -Value @{ Memory = 16 }
New-PSGPOWmiFilter -Name '16 GB' -Query $Query.Query -Namespace $Query.Namespace
```

### Exemple 3

```powershell
Get-PSGPOWmiQueryTemplate -Category 'Virtual machines'
```

## Sorties

- `PSGPOTools.WmiQueryTemplate`

## Voir aussi

- [Show-WmiFilterCreatorAvalonia](show-wmifiltercreatoravalonia.md)
- [Test-PSGPOWmiFilter](test-psgpowmifilter.md)
- [Toutes les commandes](../commands.md)
