# Export-PSGPOPolicyRuleSet

Saves rule sets as a .PolicyRules file of Policy Analyzer.

_L'aide de la commande, telle que `Get-Help Export-PSGPOPolicyRuleSet -Full` la donne (en anglais)._

## Syntaxe

```powershell
Export-PSGPOPolicyRuleSet [-RuleSet] <GPOToolsPolicyRuleSet[]> [-Path] <string> [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Writes the file as GPO2PolicyRules.exe does: PolicyAnalyzer.exe opens it, LGPO.exe /p applies it to the local policy of a computer, and Get-PSGPOPolicyRuleSet reads it again. Several sets are merged in one file, as Merge-PolicyRules.ps1 of Policy Analyzer does: the settings of all their GPOs, and their client-side extensions once.

## Paramètres

### -RuleSet

The sets (Get-PSGPOPolicyRuleSet).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsPolicyRuleSet[]` | Oui | 1 | Aucune | Oui |

### -Path

The .PolicyRules file.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 2 | Aucune | Non |

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
Get-PSGPOPolicyRuleSet -Name 'Tier 1 - *' | Export-PSGPOPolicyRuleSet -Path "$HOME\Documents\PolicyAnalyzer\Tier 1.PolicyRules"
```

### Exemple 2

```powershell
Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows Server 2025 Security Baseline\GPOs' | Export-PSGPOPolicyRuleSet -Path ./WS2025.PolicyRules
```

## Sorties

- `System.IO.FileInfo`

## Voir aussi

- [Get-PSGPOPolicyRuleSet](get-psgpopolicyruleset.md)
- [Toutes les commandes](../commands.md)
