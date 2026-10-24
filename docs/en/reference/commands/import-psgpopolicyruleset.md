# Import-PSGPOPolicyRuleSet

Writes the settings of a rule set (a .PolicyRules file, a security baseline of Microsoft) in a GPO of the domain, as LGPO.exe /p applies one to the local policy of a computer.

_The help of the command, as `Get-Help Import-PSGPOPolicyRuleSet -Full` gives it._

## Syntax

```powershell
Import-PSGPOPolicyRuleSet [-RuleSet] <GPOToolsPolicyRuleSet> [-TargetName] <string> [[-PolicyName] <string[]>] [[-BackupPath] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Replace] [-CreateIfNeeded] [-NoBackup] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The registry settings of the set go to the Registry.pol files of the GPO (computer and user), its security template to GptTmpl.inf, its advanced audit policy to audit.csv, and the GPO declares the client-side extensions they need (those the set lists included: the exploit protection, LAPS...). The version of the GPO increases: the computers apply it again. On Windows and on Linux, for Active Directory and Samba AD.

By default the settings are merged: a setting of the set replaces the same setting of the GPO, its other settings stay. With -Replace, the registry settings, the security template and the audit policy of the GPO are those of the set alone. The other files of the GPO (preferences, scripts) never change, nor its links, status and permissions.

The GPO is backed up first (Backup-PSGPO), unless -NoBackup. A setting the GPOs of the set give different values is written with the value of the last one, after a warning.

## Parameters

### -RuleSet

The set (Get-PSGPOPolicyRuleSet).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsPolicyRuleSet` | Yes | 1 | None | Yes |

### -TargetName

Display name of the GPO.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -PolicyName

Only the settings of these GPOs of the set (* and ? make a pattern); all of them by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 3 | None | No |

### -Replace

The registry settings, security template and audit policy of the GPO replaced by those of the set, instead of merged.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -CreateIfNeeded

Creates the GPO when the domain does not have it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -BackupPath

Folder of the backup of the GPO before the change; the folder of the backups of the console by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -NoBackup

Changes the GPO without backing it up first.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 5 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 6 | None | No |

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
Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules |
    Import-PSGPOPolicyRuleSet -TargetName 'Workstations - Baseline' -PolicyName '*- Computer' -CreateIfNeeded
```

### Example 2

```powershell
$baseline = Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows Server 2025 Security Baseline\GPOs'
Import-PSGPOPolicyRuleSet -RuleSet $baseline -TargetName 'Servers - Baseline' -Replace -WhatIf
```

## Outputs

- `PSGPOTools.PolicyRuleImport`

## Related

- [Get-PSGPOPolicyRuleSet](get-psgpopolicyruleset.md)
- [Import-PSGPO](import-psgpo.md)
- [All the commands](../commands.md)
