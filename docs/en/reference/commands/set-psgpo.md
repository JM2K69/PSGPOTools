# Set-PSGPO

Renames GPOs, sets their status, their WMI filter and their comment, as GPMC does.

_The help of the command, as `Get-Help Set-PSGPO -Full` gives it._

## Syntax

```powershell
Set-PSGPO [-Name] <string[]> [[-NewName] <string>] [[-Status] <string>] [[-WmiFilter] <string>] [[-Comment] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-NoWmiFilter] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The new name (the Rename item of GPMC) is the display name of the GPO only: its GUID, its folder in SYSVOL, its links and its backups do not change. The status (the GPO Status menu of GPMC) says which part of the GPO the computers apply: all its settings, those of the computers only (User configuration settings disabled), those of the users only, or none. The WMI filter (the WMI Filtering of the Scope tab of GPMC) makes the computers apply the GPO only when each of its queries returns something. The comment (the Comment of the Details tab of GPMC) is in the file GPO.cmt of the folder of the GPO: it is not a setting the computers apply, and the version of the GPO does not change.

## Parameters

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | Yes |

### -NewName

New display name of the GPO: -Name gives one GPO only.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -Status

Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer configuration settings disabled) or Disabled (all settings disabled).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -WmiFilter

Name (or Id) of the WMI filter of the domain the GPOs are linked to (Get-PSGPOWmiFilter).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -NoWmiFilter

The GPOs are linked to no WMI filter anymore.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Comment

Comment of the GPOs (several lines allowed); an empty text removes it.

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
Set-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
```

### Example 2

```powershell
Set-PSGPO -Name 'C - Workstations - *' -WmiFilter 'Workstations'
```

### Example 3

```powershell
Set-PSGPO -Name 'C - Kiosks - Baseline' -NewName 'C - Kiosks - Hardening'
```

### Example 4

```powershell
Set-PSGPO -Name 'C - Kiosks - Baseline' -Comment 'CHG-2041: kiosks of the halls, owner: workplace team'
```

## Outputs

- `GPOToolsGpo`

## Related

- [All the commands](../commands.md)
