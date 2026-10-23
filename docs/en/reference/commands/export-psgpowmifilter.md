# Export-PSGPOWmiFilter

Exports WMI filters of the domain to .mof files, as GPMC "Export" does.

_The help of the command, as `Get-Help Export-PSGPOWmiFilter -Full` gives it._

## Syntax

```powershell
Export-PSGPOWmiFilter [-Name] <string[]> [-Path] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

One .mof file for each filter, in the format of GPMC (UTF-16, an instance of MSFT_SomFilter with its rules): GPMC imports it in another domain, and so does Import-PSGPOWmiFilter. The file keeps the name, description, author, dates and WQL queries of the filter.

## Parameters

### -Name

Names of the filters (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | No |

### -Path

Folder of the files, each one named after its filter (<name>.mof); or the .mof file of one filter.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -Force

Replaces a file that exists.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

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
Export-PSGPOWmiFilter -Name 'Workstations' -Path C:\Exports
```

### Example 2

```powershell
Export-PSGPOWmiFilter -Name '*' -Path /srv/wmi-filters
```

## Outputs

- `System.IO.FileInfo`

## Related

- [Import-PSGPOWmiFilter](import-psgpowmifilter.md)
- [All the commands](../commands.md)
