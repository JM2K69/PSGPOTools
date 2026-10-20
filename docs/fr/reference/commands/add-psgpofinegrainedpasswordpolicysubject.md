# Add-PSGPOFineGrainedPasswordPolicySubject

Applies fine-grained password policies (PSO) to users and groups.

_L'aide de la commande, telle que `Get-Help Add-PSGPOFineGrainedPasswordPolicySubject -Full` la donne (en anglais)._

## Syntaxe

```powershell
Add-PSGPOFineGrainedPasswordPolicySubject [-Name] <string[]> [-Subject] <string[]> [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Adds the users and groups to the "Directly Applies To" list of the PSO (msDS-PSOAppliesTo), as the Active Directory Administrative Center does. A PSO applied to a group reaches its members: on Windows domain controllers through global security groups only, on Samba AD through every security group but the built-in ones. Get-PSGPOResultantPasswordPolicy tells which PSO applies to a user.

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
Add-PSGPOFineGrainedPasswordPolicySubject -Name 'PSO - Tier 1 Admins' -Subject 'GPO-Tier1-Admins', 'tiers1'
```

## Sorties

- `PSGPOTools.FineGrainedPasswordPolicy`

## Voir aussi

- [Remove-PSGPOFineGrainedPasswordPolicySubject](remove-psgpofinegrainedpasswordpolicysubject.md)
- [Toutes les commandes](../commands.md)
