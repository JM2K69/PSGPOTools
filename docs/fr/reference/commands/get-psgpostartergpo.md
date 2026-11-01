# Get-PSGPOStarterGpo

Gets the Starter GPOs of the domain, as GPMC lists them under Starter GPOs.

_L'aide de la commande, telle que `Get-Help Get-PSGPOStarterGpo -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOStarterGpo [[-Name] <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
```

## Description

A Starter GPO is a set of Administrative Templates a new GPO starts from (New-PSGPO -StarterGpo, New GPO > Source Starter GPO in GPMC). GPMC keeps each in a folder of SYSVOL\<domain>\StarterGPOs: no object in the directory. The System Starter GPOs are those of Microsoft, which GPMC adds with the folder; the Custom ones are those of the domain. A folder whose StarterGPO.tmplx cannot be read is returned with its Problem.

## Paramètres

### -Name

Display name of the Starter GPOs, or a pattern with * and ?; all of them when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | Nommé | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOStarterGpo
```

### Exemple 2

```powershell
Get-PSGPOStarterGpo -Name 'Workstations*' | Select-Object DisplayName, Type, Description
```

## Sorties

- `PSGPOTools.StarterGpo`

## Voir aussi

- [New-PSGPOStarterGpo](new-psgpostartergpo.md)
- [New-PSGPO](new-psgpo.md)
- [Toutes les commandes](../commands.md)
