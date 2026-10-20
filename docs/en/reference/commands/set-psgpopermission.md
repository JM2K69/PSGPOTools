# Set-PSGPOPermission

Changes the permissions of GPOs, as the Delegation and Scope tabs of GPMC do.

_The help of the command, as `Get-Help Set-PSGPOPermission -Full` gives it._

## Syntax

```powershell
Set-PSGPOPermission -Name <string[]> -Account <string> -Permission <string> [-Directory <GPOToolsDirectory>] [-Server <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
Set-PSGPOPermission -Name <string[]> -Account <string> -SecurityFiltering <string> [-Directory <GPOToolsDirectory>] [-Server <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

-Permission gives an account one level on the GPO, in place of what it had, as the Delegation tab of GPMC (Set-GPPermission -Replace): GpoRead, GpoApply (read and apply), GpoEdit, GpoEditDeleteModifySecurity, or None to remove the account. An editor that applied the GPO keeps applying it.

-SecurityFiltering Add or Remove changes the security filtering, as the Scope tab of GPMC: Add makes the account read and apply the GPO (its other rights kept); Remove makes it stop applying the GPO, and stop reading it when that was all it did. Authenticated Users keeps reading it: the computers must read every GPO (MS16-072).

The permissions are written on the GPO in the directory, then on its SYSVOL folder and everything in it, as GPMC does. A GPO waiting for its approval is refused: its permissions are set when it is approved.

## Parameters

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | Named | None | Yes |

### -Account

The account: a group, user or computer of the domain (its name, DOMAIN\name, a computer as PC01$, or a SID), or a well-known one (Authenticated Users, SYSTEM...).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | Named | None | No |

### -Permission

GpoRead, GpoApply, GpoEdit, GpoEditDeleteModifySecurity or None.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | Named | None | No |

### -SecurityFiltering

Add or Remove: the account applies the GPO, or no longer does.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | Named | None | No |

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
Set-PSGPOPermission -Name 'C - Workstations - BitLocker' -Account 'GPO-Tier2-Admins' -Permission GpoEdit
```

### Example 2

```powershell
Set-PSGPOPermission -Name 'C - Workstations - BitLocker' -Account 'Paris-Workstations' -SecurityFiltering Add
```

## Outputs

- `PSGPOTools.Permission`

## Related

- [All the commands](../commands.md)
