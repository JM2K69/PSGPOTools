# Remove-PSGPOFineGrainedPasswordPolicySubject

Stops applying fine-grained password policies (PSO) to users and groups.

_L'aide de la commande, telle que `Get-Help Remove-PSGPOFineGrainedPasswordPolicySubject -Full` la donne (en anglais)._

## Syntaxe

```powershell
Remove-PSGPOFineGrainedPasswordPolicySubject [-Name] <string[]> [-Subject] <string[]> [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Removes the users and groups from the "Directly Applies To" list of the PSO (msDS-PSOAppliesTo). They then get the next PSO that concerns them, or the password policy of the domain.

## Paramètres

### -Name

Names of the PSOs (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Non |

### -Subject

Users and groups: account names (DOMAIN\name too), names or distinguished names.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 2 | Aucune | Non |

### -Server

Domain controller to write to: its DNS name. By default, the domain of the computer.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Credential

Account to write with, instead of the current identity (Kerberos).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `PSCredential` | Non | Nommé | Aucune | Non |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

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
Remove-PSGPOFineGrainedPasswordPolicySubject -Name 'PSO - Tier 1 Admins' -Subject 'tiers1'
```

## Sorties

- `PSGPOTools.FineGrainedPasswordPolicy`

## Voir aussi

- [Add-PSGPOFineGrainedPasswordPolicySubject](add-psgpofinegrainedpasswordpolicysubject.md)
- [Toutes les commandes](../commands.md)
