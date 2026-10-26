# Import-PSGPOAuditLog

Moves the changes of an audit log of a console into the central audit log of the domain.

_L'aide de la commande, telle que `Get-Help Import-PSGPOAuditLog -Full` la donne (en anglais)._

## Syntaxe

```powershell
Import-PSGPOAuditLog -Path <string> [-Destination <string>] [-Remove] [-Server <string>] [-Credential <pscredential>] [-WhatIf] [-Confirm] [<CommonParameters>]
Import-PSGPOAuditLog -Path <string> -Directory <GPOToolsLdapDirectory> [-Destination <string>] [-Remove] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Before the central log (Audit.Path), each console wrote its changes in the folder Audit of the backups of its account. Import-PSGPOAuditLog adds them to the central log as the consoles write it now: each change in a file of its account, of its computer and of its month, in the folder of the tier of the account (read in its groups, as for a change made now; an account the domain does not know goes to Unassigned). The file is named ...-imported.jsonl: the account that runs the import owns it, and each account writes only the files it made.

It can run again: a change already in the central log (same time, account, action and target) is not written twice. With -Remove, the files read are deleted once their changes are written. Run it with an account that writes every tier (an administrator of the domain), as the files go in the folders of the accounts that made the changes.

## Paramètres

### -Path

The folder of the log to import (the folder Audit of the backups of an account).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | Nommé | Aucune | Non |

### -Destination

The central log: Audit.Path of the configuration of the domain by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Remove

Deletes the files read, once their changes are in the central log.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the central log and the tiers.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsLdapDirectory` | Oui | Nommé | Aucune | Non |

### -Server

Domain controller to read the domain from. By default, the domain of the computer.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Credential

Account to read the domain with, instead of the current identity.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `PSCredential` | Non | Nommé | Aucune | Non |

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
Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -WhatIf
```

### Exemple 2

```powershell
Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -Server dc.hardenbox.labo -Remove
```

## Sorties

- `PSGPOTools.AuditImport`

## Voir aussi

- [Initialize-PSGPOAuditShare](initialize-psgpoauditshare.md)
- [Get-PSGPOAuditLog](get-psgpoauditlog.md)
- [Toutes les commandes](../commands.md)
