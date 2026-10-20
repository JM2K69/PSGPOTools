# Remove-PSGPOWmiFilter

Deletes WMI filters of the domain that no GPO uses.

_L'aide de la commande, telle que `Get-Help Remove-PSGPOWmiFilter -Full` la donne (en anglais)._

## Syntaxe

```powershell
Remove-PSGPOWmiFilter [-Name] <string[]> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As GPMC, a filter a GPO is linked to is not deleted: unlink it first (Set-PSGPO -NoWmiFilter). The GPOs of the domain are checked in the directory, those this account cannot see included.

## Paramètres

### -Name

Names of the filters (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Non |

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
Remove-PSGPOWmiFilter -Name 'Windows 7'
```

## Voir aussi

- [Toutes les commandes](../commands.md)
