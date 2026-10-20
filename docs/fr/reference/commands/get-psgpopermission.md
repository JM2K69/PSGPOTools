# Get-PSGPOPermission

Lists the permissions of GPOs, as the Delegation tab of GPMC shows them.

_L'aide de la commande, telle que `Get-Help Get-PSGPOPermission -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOPermission [-Name] <string[]> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

One row per account of the permissions of the GPO, with its level as GPMC names it: GpoRead (Read), GpoApply (Read, from the security filtering: it applies the GPO), GpoEdit (Edit settings), GpoEditDeleteModifySecurity (Edit settings, delete, modify security) or GpoCustom (other rights, or a denial). The inherited permissions come from the Policies container of the domain: they are listed, Set-PSGPOPermission does not change them.

## Paramètres

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

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
Get-PSGPOPermission -Name 'C - Workstations - BitLocker'
```

### Exemple 2

```powershell
Get-PSGPOPermission -Name * | Where-Object Permission -EQ GpoEdit
```

## Sorties

- `PSGPOTools.Permission`

## Voir aussi

- [Toutes les commandes](../commands.md)
