# Get-PSGPOPolicyRuleSet

Reads rule sets of Policy Analyzer (.PolicyRules), or makes one from GPOs.

_L'aide de la commande, telle que `Get-Help Get-PSGPOPolicyRuleSet -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOPolicyRuleSet [-Path] <string[]> [<CommonParameters>]
Get-PSGPOPolicyRuleSet -GpmcBackupPath <string> [-Name <string[]>] [-SetName <string>] [<CommonParameters>]
Get-PSGPOPolicyRuleSet -Name <string[]> [-SetName <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
Get-PSGPOPolicyRuleSet -Backup <Backup[]> [-SetName <string>] [<CommonParameters>]
```

## Description

A rule set holds the settings of one or more GPOs, as the Policy Analyzer of the Microsoft Security Compliance Toolkit keeps them in a .PolicyRules file: the registry settings of their Registry.pol files (computer and user), their security template (GptTmpl.inf), their advanced audit policy (audit.csv) and their client-side extensions.

It is read from .PolicyRules files (those of the security baselines of Microsoft, or of Policy Analyzer), or made from GPOs: of the domain, of backups of HGPM (Get-PSGPOBackup) or of GPMC (the GPOs folder of a security baseline), as GPO2PolicyRules.exe does. Compare-PSGPOPolicyRuleSet compares sets, Export-PSGPOPolicyRuleSet saves one.

## Paramètres

### -Path

Files of Policy Analyzer (.PolicyRules), or folders: the .PolicyRules files they hold. One set per file, named after it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Non |

### -Name

Display names of the GPOs (* and ? make a pattern): of the domain, or of the GPMC backups of -GpmcBackupPath (all of them by default).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | Nommé | Aucune | Non |

### -Backup

Backups of HGPM (Get-PSGPOBackup).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object[]` | Oui | Nommé | Aucune | Oui |

### -GpmcBackupPath

A folder of GPMC backups (Backup-GPO, the GPOs folder of a security baseline), or one backup.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | Nommé | Aucune | Non |

### -SetName

Name of the set made from GPOs: by default the name of the GPO when there is one, else the name of the domain or of the folder.

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
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy' | Select-Object -First 1 | Get-PSGPOPolicyRuleSet
```

## Sorties

- `GPOToolsPolicyRuleSet`

## Voir aussi

- [Compare-PSGPOPolicyRuleSet](compare-psgpopolicyruleset.md)
- [Export-PSGPOPolicyRuleSet](export-psgpopolicyruleset.md)
- [Toutes les commandes](../commands.md)
