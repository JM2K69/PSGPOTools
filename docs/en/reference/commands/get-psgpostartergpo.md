# Get-PSGPOStarterGpo

Gets the Starter GPOs of the domain, as GPMC lists them under Starter GPOs.

_The help of the command, as `Get-Help Get-PSGPOStarterGpo -Full` gives it._

## Syntax

```powershell
Get-PSGPOStarterGpo [[-Name] <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
```

## Description

A Starter GPO is a set of Administrative Templates a new GPO starts from (New-PSGPO -StarterGpo, New GPO > Source Starter GPO in GPMC). GPMC keeps each in a folder of SYSVOL\<domain>\StarterGPOs: no object in the directory. The System Starter GPOs are those of Microsoft, which GPMC adds with the folder; the Custom ones are those of the domain. A folder whose StarterGPO.tmplx cannot be read is returned with its Problem.

## Parameters

### -Name

Display name of the Starter GPOs, or a pattern with * and ?; all of them when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 1 | None | No |

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

## Examples

### Example 1

```powershell
Get-PSGPOStarterGpo
```

### Example 2

```powershell
Get-PSGPOStarterGpo -Name 'Workstations*' | Select-Object DisplayName, Type, Description
```

## Outputs

- `PSGPOTools.StarterGpo`

## Related

- [New-PSGPOStarterGpo](new-psgpostartergpo.md)
- [New-PSGPO](new-psgpo.md)
- [All the commands](../commands.md)
