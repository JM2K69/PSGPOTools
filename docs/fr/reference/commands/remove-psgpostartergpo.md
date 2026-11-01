# Remove-PSGPOStarterGpo

Deletes Custom Starter GPOs of the domain.

_L'aide de la commande, telle que `Get-Help Remove-PSGPOStarterGpo -Full` la donne (en anglais)._

## Syntaxe

```powershell
Remove-PSGPOStarterGpo [-Name] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As GPMC "Delete" on a Starter GPO: its folder of SYSVOL\<domain>\StarterGPOs is deleted. The GPOs created from it keep their settings: they are copies. The System Starter GPOs of Microsoft are not deleted.

## Paramètres

### -Name

Display name of the Starter GPOs, or a pattern with * and ?.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

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
Remove-PSGPOStarterGpo -Name 'Workstations - Baseline (old)'
```

## Voir aussi

- [Get-PSGPOStarterGpo](get-psgpostartergpo.md)
- [Toutes les commandes](../commands.md)
