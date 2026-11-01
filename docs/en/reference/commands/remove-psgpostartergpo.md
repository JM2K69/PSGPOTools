# Remove-PSGPOStarterGpo

Deletes Custom Starter GPOs of the domain.

_The help of the command, as `Get-Help Remove-PSGPOStarterGpo -Full` gives it._

## Syntax

```powershell
Remove-PSGPOStarterGpo [-Name] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As GPMC "Delete" on a Starter GPO: its folder of SYSVOL\<domain>\StarterGPOs is deleted. The GPOs created from it keep their settings: they are copies. The System Starter GPOs of Microsoft are not deleted.

## Parameters

### -Name

Display name of the Starter GPOs, or a pattern with * and ?.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

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
Remove-PSGPOStarterGpo -Name 'Workstations - Baseline (old)'
```

## Related

- [Get-PSGPOStarterGpo](get-psgpostartergpo.md)
- [All the commands](../commands.md)
