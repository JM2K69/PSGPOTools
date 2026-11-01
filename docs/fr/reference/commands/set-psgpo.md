# Set-PSGPO

Renames GPOs, sets their status, their WMI filter and their comment, as GPMC does.

_L'aide de la commande, telle que `Get-Help Set-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
Set-PSGPO [-Name] <string[]> [[-NewName] <string>] [[-Status] <string>] [[-WmiFilter] <string>] [[-Comment] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-NoWmiFilter] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The new name (the Rename item of GPMC) is the display name of the GPO only: its GUID, its folder in SYSVOL, its links and its backups do not change. The status (the GPO Status menu of GPMC) says which part of the GPO the computers apply: all its settings, those of the computers only (User configuration settings disabled), those of the users only, or none. The WMI filter (the WMI Filtering of the Scope tab of GPMC) makes the computers apply the GPO only when each of its queries returns something. The comment (the Comment of the Details tab of GPMC) is in the file GPO.cmt of the folder of the GPO: it is not a setting the computers apply, and the version of the GPO does not change.

## Paramètres

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -NewName

New display name of the GPO: -Name gives one GPO only.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -Status

Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer configuration settings disabled) or Disabled (all settings disabled).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -WmiFilter

Name (or Id) of the WMI filter of the domain the GPOs are linked to (Get-PSGPOWmiFilter).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

### -NoWmiFilter

The GPOs are linked to no WMI filter anymore.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Comment

Comment of the GPOs (several lines allowed); an empty text removes it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 6 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 7 | Aucune | Non |

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

### Exemple 3

```powershell
Set-PSGPO -Name 'C - Kiosks - Baseline' -NewName 'C - Kiosks - Hardening'
```

### Exemple 4

```powershell
Set-PSGPO -Name 'C - Kiosks - Baseline' -Comment 'CHG-2041: kiosks of the halls, owner: workplace team'
```

## Sorties

- `GPOToolsGpo`

## Voir aussi

- [Toutes les commandes](../commands.md)
