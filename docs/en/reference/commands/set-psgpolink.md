# Set-PSGPOLink

Enables, disables, enforces or moves the links of GPOs, as GPMC does on a link.

_The help of the command, as `Get-Help Set-PSGPOLink -Full` gives it._

## Syntax

```powershell
Set-PSGPOLink [-Name] <string[]> [-Target] <string> [[-Enabled] <bool>] [[-Enforced] <bool>] [[-Order] <int>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Like the Link Enabled and Enforced items of a link in GPMC, and the arrows of its Linked Group Policy Objects tab. The change is written to the gPLink of the domain or OU, refused when the links changed in the domain meanwhile.

## Parameters

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | Yes |

### -Target

The domain or the OU: its distinguished name, the name of the domain, or the name of an OU when only one OU has it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -Enabled

$true enables the link, $false disables it: the GPO no longer applies there.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Nullable`1` | No | 3 | None | No |

### -Enforced

$true enforces the link (the GPO applies even where the inheritance is blocked, and wins over the GPOs linked below), $false no longer does.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Nullable`1` | No | 4 | None | No |

### -Order

The link order to move the link to: 1 is the highest precedence.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Int32` | No | 5 | `0` | No |

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
Set-PSGPOLink -Name 'C - Servers - Baseline' -Target Servers -Enforced $true -Order 1
```

### Example 2

```powershell
# Disable a link for a while, without deleting it
Set-PSGPOLink -Name 'U - Lyon - Printers' -Target Lyon -Enabled $false
```

## Outputs

- `PSGPOTools.Link`

## Related

- [New-PSGPOLink](new-psgpolink.md)
- [All the commands](../commands.md)
