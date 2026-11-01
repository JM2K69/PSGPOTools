# Copy-PSGPO

Copies a GPO into a new GPO of its domain, as Copy and Paste of GPMC: its settings, status, client-side extensions, WMI filter and comment; not its links.

_The help of the command, as `Get-Help Copy-PSGPO -Full` gives it._

## Syntax

```powershell
Copy-PSGPO [-Name] <string> [-TargetName] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-CopyAcl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The new GPO gets the files of the folder of the GPO in SYSVOL (its settings and its comment), its status, the client-side extensions it declares and its WMI filter. Its links are not copied: link the copy where it applies (New-PSGPOLink). Its permissions are those of a new GPO, as GPMC gives by default; -CopyAcl gives it those of the GPO instead (Preserve the existing permissions, in GPMC), but the ones a level of permission cannot give (denied, custom), which are said. With the approval workflow, the copy of a creator waits for its approval as any new GPO, and the approval gives its security filtering: -CopyAcl is refused to a creator.

## Parameters

### -Name

Display name of the GPO to copy (one GPO).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -TargetName

Display name of the new GPO.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -CopyAcl

The permissions of the GPO copied, not those of a new GPO.

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
Copy-PSGPO -Name 'C - Workstations - BitLocker' -TargetName 'C - Laptops - BitLocker'
```

### Example 2

```powershell
Copy-PSGPO -Name 'C - Servers - Baseline' -TargetName 'C - Servers - Baseline (test)' -CopyAcl
```

## Outputs

- `GPOToolsGpo`

## Related

- [New-PSGPOLink](new-psgpolink.md)
- [All the commands](../commands.md)
