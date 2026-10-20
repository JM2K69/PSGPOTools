# Get-PSGPOWmiFilter

The WMI filters of the domain, and the GPOs linked to each one.

_L'aide de la commande, telle que `Get-Help Get-PSGPOWmiFilter -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOWmiFilter [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

As the WMI Filters container of GPMC: the msWMI-Som objects of CN=SOM,CN=WMIPolicy, CN=System of the domain, with their queries. A computer applies a GPO linked to a WMI filter only when one of its queries returns something.

## Paramètres

### -Name

Names of the filters (* and ? make a pattern); all of them by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 1 | `*` | Non |

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
Get-PSGPOWmiFilter | Format-Table Name, Queries, Gpos
```

## Sorties

- `PSGPOTools.WmiFilter`

## Voir aussi

- [Toutes les commandes](../commands.md)
