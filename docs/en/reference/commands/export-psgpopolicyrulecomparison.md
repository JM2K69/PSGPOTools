# Export-PSGPOPolicyRuleComparison

Saves a comparison of rule sets as an Excel workbook, as Policy Analyzer exports it.

_The help of the command, as `Get-Help Export-PSGPOPolicyRuleComparison -Full` gives it._

## Syntax

```powershell
Export-PSGPOPolicyRuleComparison [-InputObject] <PolicyRuleComparison[]> [-Path] <string> [-All] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Writes a .xlsx file (without Excel nor any module, on any platform) from the rows of Compare-PSGPOPolicyRuleSet: a sheet Comparison with a row per setting and a column per set, with the colours of Policy Analyzer (yellow: the sets, or two GPOs of a set, give the setting different values; grey: the set does not configure it; light grey: it is set several times to the same value), and a sheet GPOs with the GPOs of each set.

By default the table as the Policy Viewer shows it ("Export table to Excel"); with -All, also the value of each GPO, the explanation and the reference of each setting ("Export all data to Excel").

## Parameters

### -InputObject

The rows of Compare-PSGPOPolicyRuleSet.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object[]` | Yes | 1 | None | Yes |

### -Path

The .xlsx file.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 2 | None | No |

### -All

Adds the details of each setting.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

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
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain | Export-PSGPOPolicyRuleComparison -Path ./Comparison.xlsx
```

### Example 2

```powershell
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain -DifferenceOnly | Export-PSGPOPolicyRuleComparison -Path ./Differences.xlsx -All
```

## Outputs

- `System.IO.FileInfo`

## Related

- [Compare-PSGPOPolicyRuleSet](compare-psgpopolicyruleset.md)
- [All the commands](../commands.md)
