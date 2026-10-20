# Set-PSGPOFineGrainedPasswordPolicy

Changes the settings, the name or the protection of fine-grained password policies (PSO).

_The help of the command, as `Get-Help Set-PSGPOFineGrainedPasswordPolicy -Full` gives it._

## Syntax

```powershell
Set-PSGPOFineGrainedPasswordPolicy [-Name] <string[]> [-NewName <string>] [-Precedence <int>] [-MinPasswordLength <int>] [-PasswordHistoryCount <int>] [-ComplexityEnabled <bool>] [-ReversibleEncryptionEnabled <bool>] [-MinPasswordAge <timespan>] [-MaxPasswordAge <timespan>] [-LockoutThreshold <int>] [-LockoutDuration <timespan>] [-LockoutObservationWindow <timespan>] [-Description <string>] [-ProtectedFromAccidentalDeletion <bool>] [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As the properties of a PSO in the Active Directory Administrative Center: only the settings given change. A value is changed only if the domain still has the one read: a PSO another console changed meanwhile is refused (run the command again). The users and groups it applies to change with Add- and Remove-PSGPOFineGrainedPasswordPolicySubject.

## Parameters

### -Name

Names of the PSOs (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | No |

### -NewName

New name of the PSO (one PSO only).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Precedence

Priority of the PSO: of the PSOs that concern a user, the lowest precedence applies (1 or more).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Int32` | No | Named | `0` | No |

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

Denies everyone to delete the PSO; $false lets it be deleted.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Boolean` | No | Named | None | No |

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
Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 1 Admins' -MinPasswordLength 18 -LockoutDuration 0
```

### Example 2

```powershell
Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old' -ProtectedFromAccidentalDeletion $false
Remove-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old'
```

## Outputs

- `PSGPOTools.FineGrainedPasswordPolicy`

## Related

- [Get-PSGPOFineGrainedPasswordPolicy](get-psgpofinegrainedpasswordpolicy.md)
- [All the commands](../commands.md)
