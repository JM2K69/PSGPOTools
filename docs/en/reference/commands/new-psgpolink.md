# New-PSGPOLink

Links GPOs to the domain or to an OU, as GPMC "Link an Existing GPO".

_The help of the command, as `Get-Help New-PSGPOLink -Full` gives it._

## Syntax

```powershell
New-PSGPOLink [-Name] <string[]> [-Target] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Enforced] [-Disabled] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The link has the lowest precedence (the last link order), like in GPMC. It is written to the gPLink of the domain or OU in one LDAP request that also removes the value read, so that a link someone else added meanwhile is never lost: the change is refused instead.

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

### -Enforced

Enforces the link: the GPO applies even where the inheritance is blocked.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Disabled

Creates the link disabled.

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
New-PSGPOLink -Name 'C - Servers - Baseline' -Target 'OU=Servers,DC=contoso,DC=com'
```

## Outputs

- `PSGPOTools.Link`

## Related

- [Set-PSGPOLink](set-psgpolink.md)
- [Remove-PSGPOLink](remove-psgpolink.md)
- [All the commands](../commands.md)
