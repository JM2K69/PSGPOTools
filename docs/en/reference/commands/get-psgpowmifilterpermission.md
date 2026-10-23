# Get-PSGPOWmiFilterPermission

The delegation of the WMI filters, as the Delegation tabs of GPMC show it.

_The help of the command, as `Get-Help Get-PSGPOWmiFilterPermission -Full` gives it._

## Syntax

```powershell
Get-PSGPOWmiFilterPermission [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

Without -Name, the Delegation tab of WMI Filters: who creates WMI filters in the domain, WmiCreate (Creator owner: creates filters, changes those it created) or WmiFullControl (creates filters, changes all of them). With -Name, the Delegation tab of each filter: who changes it, WmiEdit or WmiFullControl. WmiCustom: other rights, or a deny. The accounts that only read are not listed, as in GPMC.

## Parameters

### -Name

Names of the WMI filters (* and ? make a pattern); the WMI Filters container without it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 1 | None | No |

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

## Examples

### Example 1

```powershell
Get-PSGPOWmiFilterPermission
```

### Example 2

```powershell
Get-PSGPOWmiFilterPermission -Name 'Workstations' | Format-Table Trustee, Permission, Inherited
```

## Outputs

- `PSGPOTools.WmiFilterPermission`

## Related

- [Set-PSGPOWmiFilterPermission](set-psgpowmifilterpermission.md)
- [All the commands](../commands.md)
