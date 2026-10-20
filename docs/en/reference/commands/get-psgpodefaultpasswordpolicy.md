# Get-PSGPODefaultPasswordPolicy

The password policy of the domain: what applies to the accounts no PSO applies to.

_The help of the command, as `Get-Help Get-PSGPODefaultPasswordPolicy -Full` gives it._

## Syntax

```powershell
Get-PSGPODefaultPasswordPolicy [[-Server] <string>] [[-Credential] <pscredential>] [-UseSsl] [<CommonParameters>]
```

## Description

The password and lockout settings of the domain object (minPwdLength, pwdHistoryLength, pwdProperties, minPwdAge, maxPwdAge, lockoutThreshold, lockoutDuration, lockOutObservationWindow), which the Default Domain Policy GPO sets. A fine-grained password policy (Get-PSGPOFineGrainedPasswordPolicy) replaces them for the users it applies to.

A MaxPasswordAge of zero means that the passwords never expire, a LockoutDuration of zero that a locked out account stays locked until an administrator unlocks it.

## Parameters

### -Server

Domain controller to read the domain from: its DNS name. By default, the domain of the computer (see Get-PSGPODirectory).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 1 | None | No |

### -Credential

Account to read the domain with, instead of the current identity (Kerberos).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | 2 | None | No |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
Get-PSGPODefaultPasswordPolicy
```

## Outputs

- `PSGPOTools.DefaultPasswordPolicy`

## Related

- [Get-PSGPOFineGrainedPasswordPolicy](get-psgpofinegrainedpasswordpolicy.md)
- [All the commands](../commands.md)
