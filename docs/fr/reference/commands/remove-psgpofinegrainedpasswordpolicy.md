# Remove-PSGPOFineGrainedPasswordPolicy

Deletes fine-grained password policies (PSO) of the domain.

_L'aide de la commande, telle que `Get-Help Remove-PSGPOFineGrainedPasswordPolicy -Full` la donne (en anglais)._

## Syntaxe

```powershell
Remove-PSGPOFineGrainedPasswordPolicy [-Name] <string[]> [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The users the PSO applied to get the next PSO that concerns them, or the password policy of the domain. As in the Active Directory Administrative Center, a PSO protected from accidental deletion is kept: clear its protection first (Set-PSGPOFineGrainedPasswordPolicy -ProtectedFromAccidentalDeletion $false).

## Paramètres

### -Name

Names of the PSOs (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Non |

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
Remove-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old'
```

## Voir aussi

- [Set-PSGPOFineGrainedPasswordPolicy](set-psgpofinegrainedpasswordpolicy.md)
- [Toutes les commandes](../commands.md)
