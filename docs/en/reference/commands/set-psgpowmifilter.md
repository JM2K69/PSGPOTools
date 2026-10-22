# Set-PSGPOWmiFilter

Changes a WMI filter of the domain: its name, description or queries, as GPMC edits a filter.

_The help of the command, as `Get-Help Set-PSGPOWmiFilter -Full` gives it._

## Syntax

```powershell
Set-PSGPOWmiFilter [-Name] <string> [[-NewName] <string>] [[-Description] <string>] [[-Query] <string[]>] [[-Namespace] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The msWMI-Som object of the filter is changed in place: its Id does not change, so the GPOs linked to it keep it and the computers apply them with its new queries. The change is refused if the filter changed in the domain since it was read.

## Parameters

### -Name

Name (or Id) of the filter to change.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -NewName

New name of the filter, unique in the domain.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -Description

New description; an empty one removes it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -Query

WQL queries that replace those of the filter.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 4 | None | No |

### -Namespace

WMI namespace of the queries: of -Query (root\CIMv2 by default), or of the queries the filter has without -Query.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 5 | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 6 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 7 | None | No |

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
Set-PSGPOWmiFilter -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1 AND Version LIKE ''10.0.2%'''
```

### Example 2

```powershell
Set-PSGPOWmiFilter -Name 'Windows 11' -NewName 'Windows 11 workstations' -Description 'Windows 11, not the servers'
```

## Outputs

- `PSGPOTools.WmiFilter`

## Related

- [Get-PSGPOWmiFilter](get-psgpowmifilter.md)
- [New-PSGPOWmiFilter](new-psgpowmifilter.md)
- [All the commands](../commands.md)
