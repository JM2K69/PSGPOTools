# Invoke-PSGPOUpdate

Has computers apply their GPOs now, as Group Policy Update of GPMC and gpupdate.

_The help of the command, as `Get-Help Invoke-PSGPOUpdate -Full` gives it._

## Syntax

```powershell
Invoke-PSGPOUpdate [[-ComputerName] <string[]>] [[-Target] <string>] [[-User] <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Windows: gpupdate on this computer; on other computers (-ComputerName), Invoke-GPUpdate of RSAT when it is there, as GPMC does (a scheduled task on the computer, for it and for each user logged on), else gpupdate through PowerShell remoting (the computer part, and the user of the remote session). Linux, a member of a domain: samba-gpupdate, which applies the policy with the machine account: root only (sudo pwsh); the user part for the user given. -Force applies every setting again, not only those of the GPOs that changed.

## Parameters

### -ComputerName

The computers, on Windows; this computer when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 1 | None | No |

### -Target

Computer, User or All (default): the parts to apply.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | `All` | No |

### -User

On Linux, the user whose part is applied (samba-gpupdate -U).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -Force

Every setting applied again (gpupdate /force, samba-gpupdate --force).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

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
Invoke-PSGPOUpdate -Target Computer -Force
```

### Example 2

```powershell
Invoke-PSGPOUpdate -ComputerName PC-LYON-041, PC-LYON-042
```

## Outputs

- `PSGPOTools.UpdateResult`

## Related

- [Get-PSGPOResult](get-psgporesult.md)
- [All the commands](../commands.md)
