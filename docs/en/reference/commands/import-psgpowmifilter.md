# Import-PSGPOWmiFilter

Creates WMI filters in the domain from .mof files, as GPMC "Import" does.

_The help of the command, as `Get-Help Import-PSGPOWmiFilter -Full` gives it._

## Syntax

```powershell
Import-PSGPOWmiFilter [-Path] <string[]> [[-Name] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Reads the .mof files GPMC exports (Export in the context menu of a WMI filter), and those of Export-PSGPOWmiFilter: an instance of MSFT_SomFilter with its WQL rules. Each filter is created in the domain with the name, description and queries of the file; it gets a new Id, so that a file exported from this domain is imported again beside its filter. A filter whose name the domain has already is not imported: -Name gives it another one.

## Parameters

### -Path

The .mof files.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | Yes |

### -Name

Name of the imported filter, instead of the one of the file: one filter only.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 3 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

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
Import-PSGPOWmiFilter -Path C:\Exports\Workstations.mof
```

### Example 2

```powershell
Get-ChildItem /srv/wmi-filters -Filter *.mof | Import-PSGPOWmiFilter
```

## Outputs

- `PSGPOTools.WmiFilter`

## Related

- [Export-PSGPOWmiFilter](export-psgpowmifilter.md)
- [All the commands](../commands.md)
