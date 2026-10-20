# New-PSGPOWmiFilter

Creates a WMI filter in the domain, as GPMC "New" in WMI Filters.

_The help of the command, as `Get-Help New-PSGPOWmiFilter -Full` gives it._

## Syntax

```powershell
New-PSGPOWmiFilter [-Name] <string> [-Query] <string[]> [[-Namespace] <string>] [[-Description] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

A msWMI-Som object in CN=SOM,CN=WMIPolicy,CN=System of the domain, with its WQL queries. A computer applies a GPO linked to it (Set-PSGPO -WmiFilter) only when one of its queries returns something. Samba AD keeps the filters for the Windows computers of the domain.

## Parameters

### -Name

Name of the filter, unique in the domain.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Query

WQL queries: SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1 for example.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 2 | None | No |

### -Namespace

WMI namespace of the queries; root\CIMv2 by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | `root\CIMv2` | No |

### -Description

What the filter is for.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 5 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 6 | None | No |

### -WhatIf

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Confirm

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
New-PSGPOWmiFilter -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
```

### Example 2

```powershell
New-PSGPOWmiFilter -Name 'Windows 11' -Query "SELECT * FROM Win32_OperatingSystem WHERE Version LIKE '10.0.2%' AND ProductType = 1" -Description 'Windows 11 workstations'
```

## Outputs

- `PSGPOTools.WmiFilter`

## Related

- [Get-PSGPOWmiFilter](get-psgpowmifilter.md)
- [Set-PSGPO](set-psgpo.md)
- [All the commands](../commands.md)
