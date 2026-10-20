# Set-PSGPO

Sets the status and the WMI filter of GPOs, as GPMC does.

_The help of the command, as `Get-Help Set-PSGPO -Full` gives it._

## Syntax

```powershell
Set-PSGPO [-Name] <string[]> [[-Status] <string>] [[-WmiFilter] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-NoWmiFilter] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The status (the GPO Status menu of GPMC) says which part of the GPO the computers apply: all its settings, those of the computers only (User configuration settings disabled), those of the users only, or none. The WMI filter (the WMI Filtering of the Scope tab of GPMC) makes the computers apply the GPO only when one of its queries returns something.

## Parameters

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | Yes |

### -Status

Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer configuration settings disabled) or Disabled (all settings disabled).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -WmiFilter

Name (or Id) of the WMI filter of the domain the GPOs are linked to (Get-PSGPOWmiFilter).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -NoWmiFilter

The GPOs are linked to no WMI filter anymore.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 4 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 5 | None | No |

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
Set-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
```

### Example 2

```powershell
Set-PSGPO -Name 'C - Workstations - *' -WmiFilter 'Workstations'
```

## Outputs

- `GPOToolsGpo`

## Related

- [All the commands](../commands.md)
