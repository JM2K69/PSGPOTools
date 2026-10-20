# Get-PSGPOResultantPasswordPolicy

Which fine-grained password policy (PSO) applies to a user, and why.

_The help of the command, as `Get-Help Get-PSGPOResultantPasswordPolicy -Full` gives it._

## Syntax

```powershell
Get-PSGPOResultantPasswordPolicy [-Identity] <string[]> [-Server <string>] [-Credential <pscredential>] [-UseSsl] [<CommonParameters>]
```

## Description

As "View resultant password settings" of the Active Directory Administrative Center, with the reasons: every PSO that concerns the user or the group, applied directly or through which groups (nested ones included), by order of priority, and the one that applies.

The PSOs applied directly to a user win over those of its groups; of several, the lowest precedence wins, then the smallest objectGUID; without any, the password policy of the domain applies. A PSO reaches the members of a group through global security groups on Windows domain controllers, through every security group but the built-in ones on Samba AD. For a user, the domain controller tells which PSO it applies (msDS-ResultantPSO): its answer is AppliedPolicy, and Differs says when it is not the one this computation finds. For a group: the PSO its members get through it, when no closer PSO applies to them.

The Status of each PSO: Applied, LowerPriority (another one comes first), DirectWins (a PSO applied directly to the user wins over those of its groups) or GroupIgnored (it is applied through a group that passes no PSO on).

## Parameters

### -Identity

User or group: account name (DOMAIN\name too), name or distinguished name.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | Yes |

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
Get-PSGPOResultantPasswordPolicy -Identity tiers1
```

### Example 2

```powershell
(Get-PSGPOResultantPasswordPolicy -Identity tiers1).Candidates | Format-Table Order, Name, Precedence, AppliesThrough, Status, Reason
```

## Outputs

- `PSGPOTools.ResultantPasswordPolicy`

## Related

- [Get-PSGPOFineGrainedPasswordPolicy](get-psgpofinegrainedpasswordpolicy.md)
- [Show-PSOManagerAvalonia](show-psomanageravalonia.md)
- [All the commands](../commands.md)
