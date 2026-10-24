# Compare-PSGPOPolicyRuleSet

Compares rule sets setting by setting, as the Policy Viewer of Policy Analyzer does.

_L'aide de la commande, telle que `Get-Help Compare-PSGPOPolicyRuleSet -Full` la donne (en anglais)._

## Syntaxe

```powershell
Compare-PSGPOPolicyRuleSet [-RuleSet] <GPOToolsPolicyRuleSet[]> [-DifferenceOnly] [-ConflictOnly] [<CommonParameters>]
```

## Description

One row per setting configured by one of the sets, with a property per set (named after it) holding its value: empty when the set does not configure the setting, ***CONFLICT*** when two GPOs of the set give it different values. As Policy Analyzer, [[[delete]]] is a registry value deleted, [[[Delete all values]]] the values of a key deleted, lists whose order does not matter (accounts of a user right, REG_MULTI_SZ) are compared in any order, and a REG_DWORD 5 is not a REG_SZ 5.

Each row also has Conflict (two sets, or two GPOs of a set, give the setting different values), Difference (a conflict, or a set does not configure it), the setting as Policy Analyzer lists it (PolicyType, Group, Setting) and as GPMC shows it (Path, Name, Option: the policies of the ADMX loaded by Initialize-PSGPOAdmx, the security settings), its explanation, and Cells: for each set its state (Absent, Set, Duplicate, Conflict, Overridden) and the value of each GPO. Export-PSGPOPolicyRuleComparison saves the rows as an Excel workbook.

One set alone shows its own conflicts and duplicates. The precedence of the GPOs of a set is not taken into account, but for the GPOs of a domain or an OU (Get-PSGPOPolicyRuleSet -Container): the value of the GPO of precedence 1 is the one of the set (Overridden when others give another one), a **delvals. of higher precedence clearing the values of its key.

## Paramètres

### -RuleSet

The sets (Get-PSGPOPolicyRuleSet), in the order of their columns.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsPolicyRuleSet[]` | Oui | 1 | Aucune | Oui |

### -DifferenceOnly

Only the rows with a difference, as "Show only Differences" of Policy Analyzer.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -ConflictOnly

Only the rows with a conflict, as "Show only Conflicts".

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
$baseline = Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules
$domain = Get-PSGPOPolicyRuleSet -Name 'Workstations - *' -SetName 'Domain'
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain -DifferenceOnly | Format-Table Scope, Name, MSFT-Win11-v25H2, Domain
```

### Exemple 2

```powershell
Get-PSGPOPolicyRuleSet -Path .\MyGpos.PolicyRules | Compare-PSGPOPolicyRuleSet -ConflictOnly
```

## Sorties

- `PSGPOTools.PolicyRuleComparison`

## Voir aussi

- [Get-PSGPOPolicyRuleSet](get-psgpopolicyruleset.md)
- [Export-PSGPOPolicyRuleComparison](export-psgpopolicyrulecomparison.md)
- [Toutes les commandes](../commands.md)
