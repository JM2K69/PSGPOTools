# Test-PSGPOWmiFilter

Tests a WMI filter on a computer, as Windows evaluates it before it applies a GPO.

_L'aide de la commande, telle que `Get-Help Test-PSGPOWmiFilter -Full` la donne (en anglais)._

## Syntaxe

```powershell
Test-PSGPOWmiFilter [-Query] <string[]> [-Namespace <string>] [-ComputerName <string>] [-Credential <pscredential>] [<CommonParameters>]
Test-PSGPOWmiFilter -InputObject <Object[]> [-ComputerName <string>] [-Credential <pscredential>] [<CommonParameters>]
Test-PSGPOWmiFilter -Path <string> [-ComputerName <string>] [-Credential <pscredential>] [<CommonParameters>]
```

## Description

Runs each WQL query of the filter on this computer, or on another one by CIM (WinRM): a query is True when it returns at least one instance, False when it returns nothing or fails (a namespace or a class the computer does not have); the filter is True, and the computer applies the GPOs linked to it, when each query is True. The syntax of each query is checked first.

The queries come from -Query, from a WMI filter of the domain (Get-PSGPOWmiFilter), from the .mof file of a filter (-Path) or from Get-PSGPOWmiQueryTemplate. WMI is a service of Windows: the test runs on Windows only. The GPOs are evaluated by the system: the queries of the TPM and BitLocker classes need an elevated session.

## Paramètres

### -Query

WQL queries.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Non |

### -Namespace

WMI namespace of -Query; root\CIMv2 by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | `root\CIMv2` | Non |

### -InputObject

A WMI filter (Get-PSGPOWmiFilter), or objects with Namespace and Query (Get-PSGPOWmiQueryTemplate).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object[]` | Oui | Nommé | Aucune | Oui |

### -Path

A .mof file of WMI filters, exported by GPMC or HGPM: each filter is tested.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | Nommé | Aucune | Non |

### -ComputerName

Computer to test the filter on, by CIM (WinRM); this computer by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Credential

Account for -ComputerName.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `PSCredential` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Test-PSGPOWmiFilter -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
```

### Exemple 2

```powershell
Get-PSGPOWmiFilter -Name 'Windows 11' | Test-PSGPOWmiFilter -ComputerName PC042
```

### Exemple 3

```powershell
Get-PSGPOWmiQueryTemplate -Id Laptops, Windows11 | Test-PSGPOWmiFilter
```

### Exemple 4

```powershell
Test-PSGPOWmiFilter -Path C:\Exports\Workstations.mof
```

## Sorties

- `PSGPOTools.WmiFilterTest`

## Voir aussi

- [Show-WmiFilterCreatorAvalonia](show-wmifiltercreatoravalonia.md)
- [Get-PSGPOWmiQueryTemplate](get-psgpowmiquerytemplate.md)
- [Toutes les commandes](../commands.md)
