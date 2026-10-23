# Set-PSGPOWmiFilterPermission

Changes the delegation of the WMI filters, as the Delegation tabs of GPMC do.

_L'aide de la commande, telle que `Get-Help Set-PSGPOWmiFilterPermission -Full` la donne (en anglais)._

## Syntaxe

```powershell
Set-PSGPOWmiFilterPermission [[-Name] <string[]>] [-Account] <string> [-Permission] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Gives an account one level, in place of what it had (its own ACEs are replaced, the inherited ones stay), with the ACEs GPMC writes:

Without -Name, on WMI Filters: WmiCreate (Creator owner: the account creates filters and changes those it created) or WmiFullControl (it creates filters and changes all of them, those created before included).

With -Name, on each filter: WmiEdit (the account changes its name, description and queries) or WmiFullControl (it also deletes it and changes its permissions).

None removes the permissions of the account there.

## Paramètres

### -Name

Names of the WMI filters (* and ? make a pattern); the WMI Filters container without it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 1 | Aucune | Non |

### -Account

The account: a group or user of the domain (its name, DOMAIN\name or a SID), or a well-known one.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 2 | Aucune | Non |

### -Permission

WmiCreate (WMI Filters only), WmiEdit (a filter only), WmiFullControl or None.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 3 | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 4 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

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
Set-PSGPOWmiFilterPermission -Account 'GPO-Tier1-Admins' -Permission WmiCreate
```

### Exemple 2

```powershell
Set-PSGPOWmiFilterPermission -Name 'Workstations' -Account 'GPO-Tier2-Admins' -Permission WmiEdit
```

## Sorties

- `PSGPOTools.WmiFilterPermission`

## Voir aussi

- [Get-PSGPOWmiFilterPermission](get-psgpowmifilterpermission.md)
- [Toutes les commandes](../commands.md)
