# Export-PSGPOPolicyRuleComparison

Saves a comparison of rule sets as an Excel workbook, as Policy Analyzer exports it.

_L'aide de la commande, telle que `Get-Help Export-PSGPOPolicyRuleComparison -Full` la donne (en anglais)._

## Syntaxe

```powershell
Export-PSGPOPolicyRuleComparison [-InputObject] <PolicyRuleComparison[]> [-Path] <string> [-All] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Writes a .xlsx file (without Excel nor any module, on any platform) from the rows of Compare-PSGPOPolicyRuleSet: a sheet Comparison with a row per setting and a column per set, with the colours of Policy Analyzer (yellow: the sets, or two GPOs of a set, give the setting different values; grey: the set does not configure it; light grey: it is set several times to the same value), and a sheet GPOs with the GPOs of each set.

By default the table as the Policy Viewer shows it ("Export table to Excel"); with -All, also the value of each GPO, the explanation and the reference of each setting ("Export all data to Excel").

## Paramètres

### -InputObject

The rows of Compare-PSGPOPolicyRuleSet.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object[]` | Oui | 1 | Aucune | Oui |

### -Path

The .xlsx file.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 2 | Aucune | Non |

### -All

Adds the details of each setting.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Force

Replaces a file that exists.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -WhatIf

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Confirm

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain | Export-PSGPOPolicyRuleComparison -Path ./Comparison.xlsx
```

### Exemple 2

```powershell
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain -DifferenceOnly | Export-PSGPOPolicyRuleComparison -Path ./Differences.xlsx -All
```

## Sorties

- `System.IO.FileInfo`

## Voir aussi

- [Compare-PSGPOPolicyRuleSet](compare-psgpopolicyruleset.md)
- [Toutes les commandes](../commands.md)
