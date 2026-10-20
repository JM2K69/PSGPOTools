# Set-PSGPO

Sets the status and the WMI filter of GPOs, as GPMC does.

_L'aide de la commande, telle que `Get-Help Set-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
Set-PSGPO [-Name] <string[]> [[-Status] <string>] [[-WmiFilter] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-NoWmiFilter] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The status (the GPO Status menu of GPMC) says which part of the GPO the computers apply: all its settings, those of the computers only (User configuration settings disabled), those of the users only, or none. The WMI filter (the WMI Filtering of the Scope tab of GPMC) makes the computers apply the GPO only when one of its queries returns something.

## Paramètres

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -Status

Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer configuration settings disabled) or Disabled (all settings disabled).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -WmiFilter

Name (or Id) of the WMI filter of the domain the GPOs are linked to (Get-PSGPOWmiFilter).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -NoWmiFilter

The GPOs are linked to no WMI filter anymore.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

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
Set-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
```

### Exemple 2

```powershell
Set-PSGPO -Name 'C - Workstations - *' -WmiFilter 'Workstations'
```

## Sorties

- `GPOToolsGpo`

## Voir aussi

- [Toutes les commandes](../commands.md)
