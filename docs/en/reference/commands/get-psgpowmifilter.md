# Get-PSGPOWmiFilter

The WMI filters of the domain, and the GPOs linked to each one.

_The help of the command, as `Get-Help Get-PSGPOWmiFilter -Full` gives it._

## Syntax

```powershell
Get-PSGPOWmiFilter [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

As the WMI Filters container of GPMC: the msWMI-Som objects of CN=SOM,CN=WMIPolicy, CN=System of the domain, with their queries. A computer applies a GPO linked to a WMI filter only when each of its queries returns something.

## Parameters

### -Name

Names of the filters (* and ? make a pattern); all of them by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 1 | `*` | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 2 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOWmiFilter | Format-Table Name, Queries, Gpos
```

## Outputs

- `PSGPOTools.WmiFilter`

## Related

- [All the commands](../commands.md)
