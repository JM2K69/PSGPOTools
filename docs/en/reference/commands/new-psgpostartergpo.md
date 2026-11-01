# New-PSGPOStarterGpo

Creates a Custom Starter GPO in the domain, empty or with the Administrative Templates of a GPO.

_The help of the command, as `Get-Help New-PSGPOStarterGpo -Full` gives it._

## Syntax

```powershell
New-PSGPOStarterGpo [-Name] <string> [[-Description] <string>] [[-FromGpo] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As GPMC "New Starter GPO": a folder of SYSVOL\<domain>\StarterGPOs with its StarterGPO.tmplx (its name and description), created with the StarterGPOs folder when the domain has none. -FromGpo gives it the Administrative Templates of a GPO (Machine and User Registry.pol, and their comments): a Starter GPO holds no other settings, its security settings, preferences or scripts are not taken. New GPOs then start from it (New-PSGPO -StarterGpo, or New GPO in GPMC).

## Parameters

### -Name

Display name of the new Starter GPO.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Description

Its description, as the Comment of GPMC (several lines allowed).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -FromGpo

Display name of a GPO whose Administrative Templates the Starter GPO takes.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

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
New-PSGPOStarterGpo -Name 'Workstations - Baseline' -Description 'What every workstation GPO starts from' -FromGpo 'C - Workstations - Security Baseline Windows 11'
```

## Outputs

- `PSGPOTools.StarterGpo`

## Related

- [Get-PSGPOStarterGpo](get-psgpostartergpo.md)
- [Remove-PSGPOStarterGpo](remove-psgpostartergpo.md)
- [All the commands](../commands.md)
