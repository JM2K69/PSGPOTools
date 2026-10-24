# Export-PSGPOWmiFilter

Exports WMI filters of the domain to .mof files, as GPMC "Export" does.

_The help of the command, as `Get-Help Export-PSGPOWmiFilter -Full` gives it._

## Syntax

```powershell
Export-PSGPOWmiFilter -Name <string[]> -Path <string> [-Force] [-Directory <GPOToolsDirectory>] [-Server <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
Export-PSGPOWmiFilter -InputObject <Object[]> -Path <string> [-Force] [-Domain <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

One .mof file for each filter, in the format of GPMC (UTF-16, an instance of MSFT_SomFilter with its rules): GPMC imports it in another domain, and so does Import-PSGPOWmiFilter. The file keeps the name, description, author, dates and WQL queries of the filter.

With -InputObject, filters that are not in a domain are exported: objects with Name, Description and Queries (Namespace and Query), as Show-WmiFilterCreatorAvalonia writes them; no domain is read.

## Parameters

### -Name

Names of the filters (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | Named | None | No |

### -InputObject

Filters to export without a domain: objects with Name, Description (optional) and Queries (Namespace and Query); Id, Author, CreationDate and ChangeDate are kept when given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object[]` | Yes | Named | None | Yes |

### -Path

Folder of the files, each one named after its filter (<name>.mof); or the .mof file of one filter.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | Named | None | No |

### -Force

Replaces a file that exists.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | Named | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Domain

DNS name of the domain written in the file with -InputObject; the domain of the computer by default. GPMC creates the filter in the domain it imports it in, whatever this name is.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

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

### Example 3

```powershell
$Query = Get-PSGPOWmiQueryTemplate -Id Laptops
[pscustomobject]@{ Name = 'Laptops'; Queries = $Query } | Export-PSGPOWmiFilter -Path C:\Exports
```

## Outputs

- `System.IO.FileInfo`

## Related

- [Import-PSGPOWmiFilter](import-psgpowmifilter.md)
- [All the commands](../commands.md)
