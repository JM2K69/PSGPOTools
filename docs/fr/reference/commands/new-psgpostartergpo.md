# New-PSGPOStarterGpo

Creates a Custom Starter GPO in the domain, empty or with the Administrative Templates of a GPO.

_L'aide de la commande, telle que `Get-Help New-PSGPOStarterGpo -Full` la donne (en anglais)._

## Syntaxe

```powershell
New-PSGPOStarterGpo [-Name] <string> [[-Description] <string>] [[-FromGpo] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

As GPMC "New Starter GPO": a folder of SYSVOL\<domain>\StarterGPOs with its StarterGPO.tmplx (its name and description), created with the StarterGPOs folder when the domain has none. -FromGpo gives it the Administrative Templates of a GPO (Machine and User Registry.pol, and their comments): a Starter GPO holds no other settings, its security settings, preferences or scripts are not taken. New GPOs then start from it (New-PSGPO -StarterGpo, or New GPO in GPMC).

## Paramètres

### -Name

Display name of the new Starter GPO.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Description

Its description, as the Comment of GPMC (several lines allowed).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -FromGpo

Display name of a GPO whose Administrative Templates the Starter GPO takes.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

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
New-PSGPOStarterGpo -Name 'Workstations - Baseline' -Description 'What every workstation GPO starts from' -FromGpo 'C - Workstations - Security Baseline Windows 11'
```

## Sorties

- `PSGPOTools.StarterGpo`

## Voir aussi

- [Get-PSGPOStarterGpo](get-psgpostartergpo.md)
- [Remove-PSGPOStarterGpo](remove-psgpostartergpo.md)
- [Toutes les commandes](../commands.md)
