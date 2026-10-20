# Add-PSGPOFineGrainedPasswordPolicySubject

Applies fine-grained password policies (PSO) to users and groups.

_The help of the command, as `Get-Help Add-PSGPOFineGrainedPasswordPolicySubject -Full` gives it._

## Syntax

```powershell
Add-PSGPOFineGrainedPasswordPolicySubject [-Name] <string[]> [-Subject] <string[]> [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Adds the users and groups to the "Directly Applies To" list of the PSO (msDS-PSOAppliesTo), as the Active Directory Administrative Center does. A PSO applied to a group reaches its members: on Windows domain controllers through global security groups only, on Samba AD through every security group but the built-in ones. Get-PSGPOResultantPasswordPolicy tells which PSO applies to a user.

## Parameters

### -Name

Names of the PSOs (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | No |

### -Subject

Users and groups: account names (DOMAIN\name too), names or distinguished names.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 2 | None | No |

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
Add-PSGPOFineGrainedPasswordPolicySubject -Name 'PSO - Tier 1 Admins' -Subject 'GPO-Tier1-Admins', 'tiers1'
```

## Outputs

- `PSGPOTools.FineGrainedPasswordPolicy`

## Related

- [Remove-PSGPOFineGrainedPasswordPolicySubject](remove-psgpofinegrainedpasswordpolicysubject.md)
- [All the commands](../commands.md)
