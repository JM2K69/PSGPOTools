# Get-PSGPOWmiQueryTemplate

Gets the ready-made WQL queries of the WMI filter creator, their parameters given.

_The help of the command, as `Get-Help Get-PSGPOWmiQueryTemplate -Full` gives it._

## Syntax

```powershell
Get-PSGPOWmiQueryTemplate [[-Id] <string[]>] [-Category <string[]>] [-Value <hashtable>] [<CommonParameters>]
```

## Description

The library of Show-WmiFilterCreatorAvalonia: more than sixty queries for WMI filters, by category (operating system, edition and language, domain and name, hardware, virtual machines, security, network and location, software and services, files, time and state), each with its namespace, its note (the pitfalls of the query) and its source.

A query with parameters ({Build}, {Memory}...) is given with their default values, or those of -Value; Parameters lists them (Name, Label, Kind Text, Number or Choice, Default, Choices). The query goes to New-PSGPOWmiFilter, Set-PSGPOWmiFilter or Test-PSGPOWmiFilter.

## Parameters

### -Id

Identifiers of the queries (* and ? make a pattern): Windows11, Laptops, Subnet...

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 1 | None | No |

### -Category

Categories of the queries (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | Named | None | No |

### -Value

Values of the parameters, by name: @{ Memory = 16 } for the query Memory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Hashtable` | No | Named | `@{}` | No |

## Examples

### Example 1

```powershell
Get-PSGPOWmiQueryTemplate | Format-Table Category, Id, Query
```

### Example 2

```powershell
$Query = Get-PSGPOWmiQueryTemplate -Id Memory -Value @{ Memory = 16 }
New-PSGPOWmiFilter -Name '16 GB' -Query $Query.Query -Namespace $Query.Namespace
```

### Example 3

```powershell
Get-PSGPOWmiQueryTemplate -Category 'Virtual machines'
```

## Outputs

- `PSGPOTools.WmiQueryTemplate`

## Related

- [Show-WmiFilterCreatorAvalonia](show-wmifiltercreatoravalonia.md)
- [Test-PSGPOWmiFilter](test-psgpowmifilter.md)
- [All the commands](../commands.md)
