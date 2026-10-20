# Get-PSGPODefaultPasswordPolicy

The password policy of the domain: what applies to the accounts no PSO applies to.

_L'aide de la commande, telle que `Get-Help Get-PSGPODefaultPasswordPolicy -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPODefaultPasswordPolicy [[-Server] <string>] [[-Credential] <pscredential>] [-UseSsl] [<CommonParameters>]
```

## Description

The password and lockout settings of the domain object (minPwdLength, pwdHistoryLength, pwdProperties, minPwdAge, maxPwdAge, lockoutThreshold, lockoutDuration, lockOutObservationWindow), which the Default Domain Policy GPO sets. A fine-grained password policy (Get-PSGPOFineGrainedPasswordPolicy) replaces them for the users it applies to.

A MaxPasswordAge of zero means that the passwords never expire, a LockoutDuration of zero that a locked out account stays locked until an administrator unlocks it.

## Paramètres

### -Server

Domain controller to read the domain from: its DNS name. By default, the domain of the computer (see Get-PSGPODirectory).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

### -Credential

Account to read the domain with, instead of the current identity (Kerberos).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `PSCredential` | Non | 2 | Aucune | Non |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPODefaultPasswordPolicy
```

## Sorties

- `PSGPOTools.DefaultPasswordPolicy`

## Voir aussi

- [Get-PSGPOFineGrainedPasswordPolicy](get-psgpofinegrainedpasswordpolicy.md)
- [Toutes les commandes](../commands.md)
