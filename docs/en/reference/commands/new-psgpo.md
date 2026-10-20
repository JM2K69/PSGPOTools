# New-PSGPO

Creates a GPO in the domain, empty or from a template.

_The help of the command, as `Get-Help New-PSGPO -Full` gives it._

## Syntax

```powershell
New-PSGPO [-Name] <string> [[-Template] <Backup>] [[-Status] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Like GPMC "New GPO": the GPO is created in the domain (on Windows with New-GPO of RSAT, on Linux with samba-tool and Kerberos), not linked. With -Template, it starts with the settings of a backup (Get-PSGPOBackup -Template: the backups with the template label of the configuration, Backup.TemplateLabel), whatever GPO or domain it comes from: its files, checked against their SHA-256, and their client-side extensions.

## Parameters

### -Name

Display name of the new GPO.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Template

Backup whose settings the GPO starts with.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object` | No | 2 | None | No |

### -Status

GPO status: Enabled (default), ComputerOnly (user settings disabled) or UserOnly (computer settings disabled).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | `Enabled` | No |

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
New-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
```

### Example 2

```powershell
$Template = Get-PSGPOBackup -Path /srv/gpo-backups -Template -Name 'Template - Servers' | Select-Object -First 1
New-PSGPO -Name 'C - Servers - Lyon' -Template $Template
```

## Outputs

- `GPOToolsGpo`

## Related

- [Remove-PSGPO](remove-psgpo.md)
- [Get-PSGPOBackup](get-psgpobackup.md)
- [All the commands](../commands.md)
