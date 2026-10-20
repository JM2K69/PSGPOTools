# Set-PSGPOFineGrainedPasswordPolicy

Changes the settings, the name or the protection of fine-grained password policies (PSO).

_L'aide de la commande, telle que `Get-Help Set-PSGPOFineGrainedPasswordPolicy -Full` la donne (en anglais)._

## Syntaxe

```powershell
Set-PSGPOFineGrainedPasswordPolicy [-Name] <string[]> [-NewName <string>] [-Precedence <int>] [-MinPasswordLength <int>] [-PasswordHistoryCount <int>] [-ComplexityEnabled <bool>] [-ReversibleEncryptionEnabled <bool>] [-MinPasswordAge <timespan>] [-MaxPasswordAge <timespan>] [-LockoutThreshold <int>] [-LockoutDuration <timespan>] [-LockoutObservationWindow <timespan>] [-Description <string>] [-ProtectedFromAccidentalDeletion <bool>] [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As the properties of a PSO in the Active Directory Administrative Center: only the settings given change. A value is changed only if the domain still has the one read: a PSO another console changed meanwhile is refused (run the command again). The users and groups it applies to change with Add- and Remove-PSGPOFineGrainedPasswordPolicySubject.

## Paramètres

### -Name

Names of the PSOs (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Non |

### -NewName

New name of the PSO (one PSO only).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Precedence

Priority of the PSO: of the PSOs that concern a user, the lowest precedence applies (1 or more).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Non | Nommé | `0` | Non |

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

Denies everyone to delete the PSO; $false lets it be deleted.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Boolean` | Non | Nommé | Aucune | Non |

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
Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 1 Admins' -MinPasswordLength 18 -LockoutDuration 0
```

### Exemple 2

```powershell
Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old' -ProtectedFromAccidentalDeletion $false
Remove-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old'
```

## Sorties

- `PSGPOTools.FineGrainedPasswordPolicy`

## Voir aussi

- [Get-PSGPOFineGrainedPasswordPolicy](get-psgpofinegrainedpasswordpolicy.md)
- [Toutes les commandes](../commands.md)
