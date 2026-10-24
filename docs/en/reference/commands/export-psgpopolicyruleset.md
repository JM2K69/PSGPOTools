# Export-PSGPOPolicyRuleSet

Saves rule sets as a .PolicyRules file of Policy Analyzer.

_The help of the command, as `Get-Help Export-PSGPOPolicyRuleSet -Full` gives it._

## Syntax

```powershell
Export-PSGPOPolicyRuleSet [-RuleSet] <GPOToolsPolicyRuleSet[]> [-Path] <string> [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Writes the file as GPO2PolicyRules.exe does: PolicyAnalyzer.exe opens it, LGPO.exe /p applies it to the local policy of a computer, and Get-PSGPOPolicyRuleSet reads it again. Several sets are merged in one file, as Merge-PolicyRules.ps1 of Policy Analyzer does: the settings of all their GPOs, and their client-side extensions once.

## Parameters

### -RuleSet

The sets (Get-PSGPOPolicyRuleSet).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsPolicyRuleSet[]` | Yes | 1 | None | Yes |

### -Path

The .PolicyRules file.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -Force

Replaces a file that exists.

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
Get-PSGPOPolicyRuleSet -Name 'Tier 1 - *' | Export-PSGPOPolicyRuleSet -Path "$HOME\Documents\PolicyAnalyzer\Tier 1.PolicyRules"
```

### Example 2

```powershell
Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows Server 2025 Security Baseline\GPOs' | Export-PSGPOPolicyRuleSet -Path ./WS2025.PolicyRules
```

## Outputs

- `System.IO.FileInfo`

## Related

- [Get-PSGPOPolicyRuleSet](get-psgpopolicyruleset.md)
- [All the commands](../commands.md)
