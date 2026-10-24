# Get-PSGPOPolicyRuleSet

Reads rule sets of Policy Analyzer (.PolicyRules), or makes one from GPOs.

_L'aide de la commande, telle que `Get-Help Get-PSGPOPolicyRuleSet -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOPolicyRuleSet [-Path] <string[]> [<CommonParameters>]
Get-PSGPOPolicyRuleSet -GpmcBackupPath <string> [-Name <string[]>] [-SetName <string>] [<CommonParameters>]
Get-PSGPOPolicyRuleSet -Name <string[]> [-SetName <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
Get-PSGPOPolicyRuleSet -Backup <Backup[]> [-SetName <string>] [<CommonParameters>]
Get-PSGPOPolicyRuleSet -Container <string> [-SetName <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
Get-PSGPOPolicyRuleSet -EffectiveState -RuleSet <GPOToolsPolicyRuleSet[]> [-SetName <string>] [<CommonParameters>]
```

## Description

A rule set holds the settings of one or more GPOs, as the Policy Analyzer of the Microsoft Security Compliance Toolkit keeps them in a .PolicyRules file: the registry settings of their Registry.pol files (computer and user), their security template (GptTmpl.inf), their advanced audit policy (audit.csv) and their client-side extensions.

It is read from .PolicyRules files (those of the security baselines of Microsoft, or of Policy Analyzer), or made from GPOs: of the domain, of backups of HGPM (Get-PSGPOBackup) or of GPMC (the GPOs folder of a security baseline), as GPO2PolicyRules.exe does. Compare-PSGPOPolicyRuleSet compares sets, Export-PSGPOPolicyRuleSet saves one.

With -Container, the set is made of the GPOs that apply to a domain or an OU, in their order of precedence as the Group Policy Inheritance tab of GPMC lists them (the enforced links first, from the domain down, then the others from the OU up until an OU that blocks the inheritance; the links disabled and the parts a GPO status disables left out): each setting then has the precedence of its GPO, and Compare-PSGPOPolicyRuleSet shows the value that wins. The security filtering, the WMI filters and the loopback processing are those of each computer or user, not taken into account.

With -EffectiveState, the set is the state of this computer for the settings of -RuleSet, as "Compare to Effective State" of Policy Analyzer reads it (Windows): the registry of the computer and of the user of the session (the security options and the startup of the services included), the other security settings (secedit /export) and the advanced audit policy (auditpol /backup). A setting the computer does not have is not in the set. secedit and auditpol need PowerShell run as an administrator: without, their settings are left out, with a warning. The set is named as Policy Analyzer names it, EffectiveState_<computer>_<date>.

## Paramètres

### -Path

Files of Policy Analyzer (.PolicyRules), or folders: the .PolicyRules files they hold. One set per file, named after it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Non |

### -Name

Display names of the GPOs (* and ? make a pattern): of the domain, or of the backups of -GpmcBackupPath (all of them by default).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | Nommé | Aucune | Non |

### -Backup

Backups of HGPM (Get-PSGPOBackup).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object[]` | Oui | Nommé | Aucune | Oui |

### -GpmcBackupPath

A folder of backups (alias -BackupPath): of GPMC (Backup-GPO, the GPOs folder of a security baseline, or one backup), or of HGPM (the folder of Backup-PSGPO, the newest backup of each GPO; the folder of a GPO; one backup, or its Files folder).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | Nommé | Aucune | Non |

### -Container

A domain or an OU: its distinguished name, the name of the domain, or the name of an OU when only one OU has it. The set holds the GPOs that apply to it, by precedence.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | Nommé | Aucune | Non |

### -EffectiveState

The effective state of this computer for the settings of -RuleSet.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Oui | Nommé | Aucune | Non |

### -RuleSet

With -EffectiveState: the sets whose settings are read on the computer (the baselines).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsPolicyRuleSet[]` | Oui | Nommé | Aucune | Non |

### -SetName

Name of the set made from GPOs: by default the name of the GPO when there is one, else the name of the domain or of the folder; "<OU> (precedence)" with -Container; EffectiveState_<computer>_<yyyyMMdd-HHmmss> with -EffectiveState.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | Nommé | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOPolicyRuleSet -Path "$HOME\Documents\PolicyAnalyzer"
```

### Exemple 2

```powershell
Get-PSGPOPolicyRuleSet -Name 'Tier 1 - Servers*' -SetName 'Production'
```

### Exemple 3

```powershell
Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows 11 v25H2 Security Baseline\GPOs'
```

### Exemple 4

```powershell
# What the computers of an OU get, against the baseline of Microsoft
$ou = Get-PSGPOPolicyRuleSet -Container 'OU=Workstations,DC=contoso,DC=com'
Compare-PSGPOPolicyRuleSet -RuleSet (Get-PSGPOPolicyRuleSet .\MSFT-Win11-v25H2.PolicyRules), $ou -DifferenceOnly
```

### Exemple 5

```powershell
# This computer against the baseline of Microsoft (PowerShell run as an administrator)
$baseline = Get-PSGPOPolicyRuleSet .\MSFT-Win11-v25H2.PolicyRules
$state = Get-PSGPOPolicyRuleSet -EffectiveState -RuleSet $baseline
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $state -DifferenceOnly
Export-PSGPOPolicyRuleSet -RuleSet $state -Path ".\$($state.Name).PolicyRules"
```

### Exemple 6

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy' | Select-Object -First 1 | Get-PSGPOPolicyRuleSet
```

## Sorties

- `GPOToolsPolicyRuleSet`

## Voir aussi

- [Compare-PSGPOPolicyRuleSet](compare-psgpopolicyruleset.md)
- [Export-PSGPOPolicyRuleSet](export-psgpopolicyruleset.md)
- [Toutes les commandes](../commands.md)
