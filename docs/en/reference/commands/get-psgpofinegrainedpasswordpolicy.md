# Get-PSGPOFineGrainedPasswordPolicy

The fine-grained password policies (password settings objects, PSO) of the domain.

_The help of the command, as `Get-Help Get-PSGPOFineGrainedPasswordPolicy -Full` gives it._

## Syntax

```powershell
Get-PSGPOFineGrainedPasswordPolicy [[-Name] <string[]>] [-Server <string>] [-Credential <pscredential>] [-UseSsl] [<CommonParameters>]
```

## Description

As the Password Settings Container of the Active Directory Administrative Center: the msDS-PasswordSettings objects of CN=Password Settings Container,CN=System of the domain, by order of priority (the lowest precedence first), with their settings and the users and groups each one directly applies to. Windows and Samba AD (4.9 and later) domains, read over LDAP from Windows or Linux.

By default, only the administrators of the domain read the PSOs: another account gets none. A MaxPasswordAge of zero means that the passwords never expire, a LockoutDuration of zero that a locked out account stays locked until an administrator unlocks it.

## Parameters

### -Name

Names of the PSOs (* and ? make a pattern); all of them by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 1 | `*` | No |

### -Server

Domain controller to read the domain from: its DNS name. By default, the domain of the computer (see Get-PSGPODirectory).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Credential

Account to read the domain with, instead of the current identity (Kerberos).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | Named | None | No |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOFineGrainedPasswordPolicy | Format-Table Name, Precedence, MinPasswordLength, MaxPasswordAge, AppliesTo
```

### Example 2

```powershell
# Linux, Samba AD: Kerberos ticket first
kinit administrator@HARDENBOX.LABO
Get-PSGPOFineGrainedPasswordPolicy -Server dc.hardenbox.labo -Name 'PSO - Tier*'
```

## Outputs

- `PSGPOTools.FineGrainedPasswordPolicy`

## Related

- [Get-PSGPOResultantPasswordPolicy](get-psgporesultantpasswordpolicy.md)
- [Show-PSOManagerAvalonia](show-psomanageravalonia.md)
- [All the commands](../commands.md)
