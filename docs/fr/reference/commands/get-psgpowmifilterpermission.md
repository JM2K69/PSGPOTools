# Get-PSGPOWmiFilterPermission

The delegation of the WMI filters, as the Delegation tabs of GPMC show it.

_L'aide de la commande, telle que `Get-Help Get-PSGPOWmiFilterPermission -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOWmiFilterPermission [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

Without -Name, the Delegation tab of WMI Filters: who creates WMI filters in the domain, WmiCreate (Creator owner: creates filters, changes those it created) or WmiFullControl (creates filters, changes all of them). With -Name, the Delegation tab of each filter: who changes it, WmiEdit or WmiFullControl. WmiCustom: other rights, or a deny. The accounts that only read are not listed, as in GPMC.

## Paramètres

### -Name

Names of the WMI filters (* and ? make a pattern); the WMI Filters container without it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 1 | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 2 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOWmiFilterPermission
```

### Exemple 2

```powershell
Get-PSGPOWmiFilterPermission -Name 'Workstations' | Format-Table Trustee, Permission, Inherited
```

## Sorties

- `PSGPOTools.WmiFilterPermission`

## Voir aussi

- [Set-PSGPOWmiFilterPermission](set-psgpowmifilterpermission.md)
- [Toutes les commandes](../commands.md)
