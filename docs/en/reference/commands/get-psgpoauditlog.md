# Get-PSGPOAuditLog

What the consoles and the commands changed in the domain: the audit log.

_The help of the command, as `Get-Help Get-PSGPOAuditLog -Full` gives it._

## Syntax

```powershell
Get-PSGPOAuditLog [[-Path] <string>] [[-Domain] <string>] [[-Name] <string>] [[-Action] <string[]>] [[-Account] <string>] [[-After] <datetime>] [[-Before] <datetime>] [<CommonParameters>]
```

## Description

Each change the domain accepted, from the console or a command, is a line of the audit log: when, by which account, from which computer, on which domain controller, what and on what (a GPO, a container, the configuration). The log is in Audit.Path of the configuration of the domain (a share the administrators write, the same for every console); by default in the folder Audit of the backups of the account. Newest first.

## Parameters

### -Path

Folder of the audit log; Audit.Path of the configuration by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 1 | None | No |

### -Domain

Domain whose changes are listed; all of them by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -Name

Display name of a GPO (* and ? make a pattern): only its changes.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -Action

Only these actions (NewGpo, RenameGpo, SetGpoStatus, RemoveGpo, RemoveDeletedGpoBackup, NewLink, SetLink, RemoveLink, SetBlockInheritance, SetWmiFilter, NewWmiFilter, EditWmiFilter, RemoveWmiFilter, SetWmiFilterPermission, SetGpoPermission, SetGpoSecurityFiltering, ApproveGpo, PendingGpo, SaveGpoFile, RestoreGpo, ImportGpo, ImportPolicyRuleSet, NewFilteringGroups, SaveConfiguration, InstallAdmx, NewPasswordPolicy, SetPasswordPolicy, RemovePasswordPolicy, InitializeAuditShare); * and ? make a pattern.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 4 | None | No |

### -Account

Only the changes of this account (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 5 | None | No |

### -After

Only the changes after this date.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `DateTime` | No | 6 | None | No |

### -Before

Only the changes before this date.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `DateTime` | No | 7 | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOAuditLog -Path \\files\gpo-audit -After (Get-Date).AddDays(-7) | Format-Table Time, Account, Action, Target
```

### Example 2

```powershell
Get-PSGPOAuditLog -Name 'C - Servers - Baseline' -Action SaveGpoFile
```

## Outputs

- `PSGPOTools.AuditEntry`

## Related

- [All the commands](../commands.md)
