# Set-PSGPOInheritance

Blocks the inheritance of the domain or of an OU, or not, as GPMC "Block Inheritance".

_The help of the command, as `Get-Help Set-PSGPOInheritance -Full` gives it._

## Syntax

```powershell
Set-PSGPOInheritance [-Target] <string> [-Blocked] <bool> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Where the inheritance is blocked, the GPOs linked to the parents no longer apply, but for the enforced links. It is bit 0 of the gPOptions of the domain or OU, written only if it did not change meanwhile.

## Parameters

### -Target

The domain or the OU: its distinguished name, the name of the domain, or the name of an OU when only one OU has it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Blocked

$true blocks the inheritance, $false no longer does.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Boolean` | Yes | 2 | None | No |

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
Set-PSGPOInheritance -Target 'OU=Kiosks,DC=contoso,DC=com' -Blocked $true
```

## Related

- [All the commands](../commands.md)
