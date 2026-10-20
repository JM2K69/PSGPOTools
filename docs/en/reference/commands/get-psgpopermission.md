# Get-PSGPOPermission

Lists the permissions of GPOs, as the Delegation tab of GPMC shows them.

_The help of the command, as `Get-Help Get-PSGPOPermission -Full` gives it._

## Syntax

```powershell
Get-PSGPOPermission [-Name] <string[]> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

One row per account of the permissions of the GPO, with its level as GPMC names it: GpoRead (Read), GpoApply (Read, from the security filtering: it applies the GPO), GpoEdit (Edit settings), GpoEditDeleteModifySecurity (Edit settings, delete, modify security) or GpoCustom (other rights, or a denial). The inherited permissions come from the Policies container of the domain: they are listed, Set-PSGPOPermission does not change them.

## Parameters

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | Yes |

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
Get-PSGPOPermission -Name 'C - Workstations - BitLocker'
```

### Example 2

```powershell
Get-PSGPOPermission -Name * | Where-Object Permission -EQ GpoEdit
```

## Outputs

- `PSGPOTools.Permission`

## Related

- [All the commands](../commands.md)
