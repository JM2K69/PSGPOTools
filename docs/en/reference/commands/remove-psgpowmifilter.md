# Remove-PSGPOWmiFilter

Deletes WMI filters of the domain that no GPO uses.

_The help of the command, as `Get-Help Remove-PSGPOWmiFilter -Full` gives it._

## Syntax

```powershell
Remove-PSGPOWmiFilter [-Name] <string[]> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As GPMC, a filter a GPO is linked to is not deleted: unlink it first (Set-PSGPO -NoWmiFilter). The GPOs of the domain are checked in the directory, those this account cannot see included.

## Parameters

### -Name

Names of the filters (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | No |

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
Remove-PSGPOWmiFilter -Name 'Windows 7'
```

## Related

- [All the commands](../commands.md)
