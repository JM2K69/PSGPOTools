# Set-PSGPOWmiFilterPermission

Changes the delegation of the WMI filters, as the Delegation tabs of GPMC do.

_The help of the command, as `Get-Help Set-PSGPOWmiFilterPermission -Full` gives it._

## Syntax

```powershell
Set-PSGPOWmiFilterPermission [[-Name] <string[]>] [-Account] <string> [-Permission] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Gives an account one level, in place of what it had (its own ACEs are replaced, the inherited ones stay), with the ACEs GPMC writes:

Without -Name, on WMI Filters: WmiCreate (Creator owner: the account creates filters and changes those it created) or WmiFullControl (it creates filters and changes all of them, those created before included).

With -Name, on each filter: WmiEdit (the account changes its name, description and queries) or WmiFullControl (it also deletes it and changes its permissions).

None removes the permissions of the account there.

## Parameters

### -Name

Names of the WMI filters (* and ? make a pattern); the WMI Filters container without it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 1 | None | No |

### -Account

The account: a group or user of the domain (its name, DOMAIN\name or a SID), or a well-known one.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -Permission

WmiCreate (WMI Filters only), WmiEdit (a filter only), WmiFullControl or None.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 3 | None | No |

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
Set-PSGPOWmiFilterPermission -Account 'GPO-Tier1-Admins' -Permission WmiCreate
```

### Example 2

```powershell
Set-PSGPOWmiFilterPermission -Name 'Workstations' -Account 'GPO-Tier2-Admins' -Permission WmiEdit
```

## Outputs

- `PSGPOTools.WmiFilterPermission`

## Related

- [Get-PSGPOWmiFilterPermission](get-psgpowmifilterpermission.md)
- [All the commands](../commands.md)
