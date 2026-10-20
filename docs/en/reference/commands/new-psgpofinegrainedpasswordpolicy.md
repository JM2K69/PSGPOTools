# New-PSGPOFineGrainedPasswordPolicy

Creates a fine-grained password policy (PSO) in the domain.

_The help of the command, as `Get-Help New-PSGPOFineGrainedPasswordPolicy -Full` gives it._

## Syntax

```powershell
New-PSGPOFineGrainedPasswordPolicy [-Name] <string> -Precedence <int> [-MinPasswordLength <int>] [-PasswordHistoryCount <int>] [-ComplexityEnabled <bool>] [-ReversibleEncryptionEnabled <bool>] [-MinPasswordAge <timespan>] [-MaxPasswordAge <timespan>] [-LockoutThreshold <int>] [-LockoutDuration <timespan>] [-LockoutObservationWindow <timespan>] [-Description <string>] [-ProtectedFromAccidentalDeletion <bool>] [-AppliesTo <string[]>] [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As "New > Password Settings" of the Active Directory Administrative Center: a msDS-PasswordSettings object in the Password Settings Container, with its precedence, its password and lockout settings, and the users and groups it directly applies to. The settings not given are those of a new PSO in the Administrative Center: 7 characters, 24 passwords remembered, complexity, 1 day minimum and 42 days maximum age, no lockout (30 minutes when a threshold is given), protected from accidental deletion.

A PSO applies to the users it names, and to the members of the groups it names: on Windows domain controllers through the global security groups only, on Samba AD through every security group but the built-in ones. Of several PSOs, the lowest precedence wins; one applied directly to a user wins over those of its groups (Get-PSGPOResultantPasswordPolicy).

## Parameters

### -Name

Name of the PSO, unique in the domain.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Precedence

Priority of the PSO: of the PSOs that concern a user, the lowest precedence applies (1 or more).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Int32` | Yes | Named | `0` | No |

### -MinPasswordLength

Minimum length of the passwords, in characters (0 to 255).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Int32` | No | Named | `0` | No |

### -PasswordHistoryCount

Number of passwords remembered, that a new password cannot repeat (0 to 1024).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Int32` | No | Named | `0` | No |

### -ComplexityEnabled

The passwords must meet the complexity requirements.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Boolean` | No | Named | None | No |

### -ReversibleEncryptionEnabled

Stores the passwords with a reversible encryption (to be avoided).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Boolean` | No | Named | None | No |

### -MinPasswordAge

Time before a password can be changed again (0 for none).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `TimeSpan` | No | Named | None | No |

### -MaxPasswordAge

Time after which a password must be changed; zero: the passwords never expire.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `TimeSpan` | No | Named | None | No |

### -LockoutThreshold

Number of failed logon attempts that lock the account out; 0: never locked out.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Int32` | No | Named | `0` | No |

### -LockoutDuration

Time an account stays locked out; zero: until an administrator unlocks it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `TimeSpan` | No | Named | None | No |

### -LockoutObservationWindow

Time after which the count of failed logon attempts is reset (no longer than LockoutDuration).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `TimeSpan` | No | Named | None | No |

### -Description

What the PSO is for.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -ProtectedFromAccidentalDeletion

Denies everyone to delete the PSO, as the Administrative Center does ($true by default).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Boolean` | No | Named | `True` | No |

### -AppliesTo

Users and groups the PSO applies to: account names (DOMAIN\name too), names or distinguished names.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | Named | None | No |

### -Server

Domain controller to write to: its DNS name. By default, the domain of the computer.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Credential

Account to write with, instead of the current identity (Kerberos).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | Named | None | No |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -WhatIf

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Confirm

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
New-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 1 Admins' -Precedence 20 -MinPasswordLength 16 -MaxPasswordAge 180.00:00:00 -LockoutThreshold 10 -AppliesTo 'GPO-Tier1-Admins'
```

### Example 2

```powershell
# Service accounts: long passwords that never expire, never locked out
New-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Service Accounts' -Precedence 40 -MinPasswordLength 30 -MinPasswordAge 0 -MaxPasswordAge 0 -AppliesTo 'SVC-Accounts'
```

## Outputs

- `PSGPOTools.FineGrainedPasswordPolicy`

## Related

- [Set-PSGPOFineGrainedPasswordPolicy](set-psgpofinegrainedpasswordpolicy.md)
- [Add-PSGPOFineGrainedPasswordPolicySubject](add-psgpofinegrainedpasswordpolicysubject.md)
- [All the commands](../commands.md)
