# New-PSGPOFineGrainedPasswordPolicy

Creates a fine-grained password policy (PSO) in the domain.

_L'aide de la commande, telle que `Get-Help New-PSGPOFineGrainedPasswordPolicy -Full` la donne (en anglais)._

## Syntaxe

```powershell
New-PSGPOFineGrainedPasswordPolicy [-Name] <string> -Precedence <int> [-MinPasswordLength <int>] [-PasswordHistoryCount <int>] [-ComplexityEnabled <bool>] [-ReversibleEncryptionEnabled <bool>] [-MinPasswordAge <timespan>] [-MaxPasswordAge <timespan>] [-LockoutThreshold <int>] [-LockoutDuration <timespan>] [-LockoutObservationWindow <timespan>] [-Description <string>] [-ProtectedFromAccidentalDeletion <bool>] [-AppliesTo <string[]>] [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As "New > Password Settings" of the Active Directory Administrative Center: a msDS-PasswordSettings object in the Password Settings Container, with its precedence, its password and lockout settings, and the users and groups it directly applies to. The settings not given are those of a new PSO in the Administrative Center: 7 characters, 24 passwords remembered, complexity, 1 day minimum and 42 days maximum age, no lockout (30 minutes when a threshold is given), protected from accidental deletion.

A PSO applies to the users it names, and to the members of the groups it names: on Windows domain controllers through the global security groups only, on Samba AD through every security group but the built-in ones. Of several PSOs, the lowest precedence wins; one applied directly to a user wins over those of its groups (Get-PSGPOResultantPasswordPolicy).

## Paramètres

### -Name

Name of the PSO, unique in the domain.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Precedence

Priority of the PSO: of the PSOs that concern a user, the lowest precedence applies (1 or more).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Oui | Nommé | `0` | Non |

### -MinPasswordLength

Minimum length of the passwords, in characters (0 to 255).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Non | Nommé | `0` | Non |

### -PasswordHistoryCount

Number of passwords remembered, that a new password cannot repeat (0 to 1024).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Non | Nommé | `0` | Non |

### -ComplexityEnabled

The passwords must meet the complexity requirements.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Boolean` | Non | Nommé | Aucune | Non |

### -ReversibleEncryptionEnabled

Stores the passwords with a reversible encryption (to be avoided).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Boolean` | Non | Nommé | Aucune | Non |

### -MinPasswordAge

Time before a password can be changed again (0 for none).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `TimeSpan` | Non | Nommé | Aucune | Non |

### -MaxPasswordAge

Time after which a password must be changed; zero: the passwords never expire.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `TimeSpan` | Non | Nommé | Aucune | Non |

### -LockoutThreshold

Number of failed logon attempts that lock the account out; 0: never locked out.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Non | Nommé | `0` | Non |

### -LockoutDuration

Time an account stays locked out; zero: until an administrator unlocks it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `TimeSpan` | Non | Nommé | Aucune | Non |

### -LockoutObservationWindow

Time after which the count of failed logon attempts is reset (no longer than LockoutDuration).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `TimeSpan` | Non | Nommé | Aucune | Non |

### -Description

What the PSO is for.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -ProtectedFromAccidentalDeletion

Denies everyone to delete the PSO, as the Administrative Center does ($true by default).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Boolean` | Non | Nommé | `True` | Non |

### -AppliesTo

Users and groups the PSO applies to: account names (DOMAIN\name too), names or distinguished names.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | Nommé | Aucune | Non |

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
New-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 1 Admins' -Precedence 20 -MinPasswordLength 16 -MaxPasswordAge 180.00:00:00 -LockoutThreshold 10 -AppliesTo 'GPO-Tier1-Admins'
```

### Exemple 2

```powershell
# Service accounts: long passwords that never expire, never locked out
New-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Service Accounts' -Precedence 40 -MinPasswordLength 30 -MinPasswordAge 0 -MaxPasswordAge 0 -AppliesTo 'SVC-Accounts'
```

## Sorties

- `PSGPOTools.FineGrainedPasswordPolicy`

## Voir aussi

- [Set-PSGPOFineGrainedPasswordPolicy](set-psgpofinegrainedpasswordpolicy.md)
- [Add-PSGPOFineGrainedPasswordPolicySubject](add-psgpofinegrainedpasswordpolicysubject.md)
- [Toutes les commandes](../commands.md)
