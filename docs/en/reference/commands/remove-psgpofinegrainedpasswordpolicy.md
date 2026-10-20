# Remove-PSGPOFineGrainedPasswordPolicy

Deletes fine-grained password policies (PSO) of the domain.

_The help of the command, as `Get-Help Remove-PSGPOFineGrainedPasswordPolicy -Full` gives it._

## Syntax

```powershell
Remove-PSGPOFineGrainedPasswordPolicy [-Name] <string[]> [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The users the PSO applied to get the next PSO that concerns them, or the password policy of the domain. As in the Active Directory Administrative Center, a PSO protected from accidental deletion is kept: clear its protection first (Set-PSGPOFineGrainedPasswordPolicy -ProtectedFromAccidentalDeletion $false).

## Parameters

### -Name

Names of the PSOs (* and ? make a pattern).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | No |

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
Remove-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old'
```

## Related

- [Set-PSGPOFineGrainedPasswordPolicy](set-psgpofinegrainedpasswordpolicy.md)
- [All the commands](../commands.md)
