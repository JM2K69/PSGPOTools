# Get-PSGPOResultantPasswordPolicy

Which fine-grained password policy (PSO) applies to a user, and why.

_L'aide de la commande, telle que `Get-Help Get-PSGPOResultantPasswordPolicy -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOResultantPasswordPolicy [-Identity] <string[]> [-Server <string>] [-Credential <pscredential>] [-UseSsl] [<CommonParameters>]
```

## Description

As "View resultant password settings" of the Active Directory Administrative Center, with the reasons: every PSO that concerns the user or the group, applied directly or through which groups (nested ones included), by order of priority, and the one that applies.

The PSOs applied directly to a user win over those of its groups; of several, the lowest precedence wins, then the smallest objectGUID; without any, the password policy of the domain applies. A PSO reaches the members of a group through global security groups on Windows domain controllers, through every security group but the built-in ones on Samba AD. For a user, the domain controller tells which PSO it applies (msDS-ResultantPSO): its answer is AppliedPolicy, and Differs says when it is not the one this computation finds. For a group: the PSO its members get through it, when no closer PSO applies to them.

The Status of each PSO: Applied, LowerPriority (another one comes first), DirectWins (a PSO applied directly to the user wins over those of its groups) or GroupIgnored (it is applied through a group that passes no PSO on).

## Paramètres

### -Identity

User or group: account name (DOMAIN\name too), name or distinguished name.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -Server

Domain controller to read the domain from: its DNS name. By default, the domain of the computer (see Get-PSGPODirectory).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Credential

Account to read the domain with, instead of the current identity (Kerberos).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `PSCredential` | Non | Nommé | Aucune | Non |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOResultantPasswordPolicy -Identity tiers1
```

### Exemple 2

```powershell
(Get-PSGPOResultantPasswordPolicy -Identity tiers1).Candidates | Format-Table Order, Name, Precedence, AppliesThrough, Status, Reason
```

## Sorties

- `PSGPOTools.ResultantPasswordPolicy`

## Voir aussi

- [Get-PSGPOFineGrainedPasswordPolicy](get-psgpofinegrainedpasswordpolicy.md)
- [Show-PSOManagerAvalonia](show-psomanageravalonia.md)
- [Toutes les commandes](../commands.md)
