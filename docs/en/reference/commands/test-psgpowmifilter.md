# Test-PSGPOWmiFilter

Tests a WMI filter on a computer, as Windows evaluates it before it applies a GPO.

_The help of the command, as `Get-Help Test-PSGPOWmiFilter -Full` gives it._

## Syntax

```powershell
Test-PSGPOWmiFilter [-Query] <string[]> [-Namespace <string>] [-ComputerName <string>] [-Credential <pscredential>] [<CommonParameters>]
Test-PSGPOWmiFilter -InputObject <Object[]> [-ComputerName <string>] [-Credential <pscredential>] [<CommonParameters>]
Test-PSGPOWmiFilter -Path <string> [-ComputerName <string>] [-Credential <pscredential>] [<CommonParameters>]
```

## Description

Runs each WQL query of the filter on this computer, or on another one by CIM (WinRM): a query is True when it returns at least one instance, False when it returns nothing or fails (a namespace or a class the computer does not have); the filter is True, and the computer applies the GPOs linked to it, when each query is True. The syntax of each query is checked first.

The queries come from -Query, from a WMI filter of the domain (Get-PSGPOWmiFilter), from the .mof file of a filter (-Path) or from Get-PSGPOWmiQueryTemplate. WMI is a service of Windows: the test runs on Windows only. The GPOs are evaluated by the system: the queries of the TPM and BitLocker classes need an elevated session.

## Parameters

### -Query

WQL queries.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | No |

### -Namespace

WMI namespace of -Query; root\CIMv2 by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | `root\CIMv2` | No |

### -InputObject

A WMI filter (Get-PSGPOWmiFilter), or objects with Namespace and Query (Get-PSGPOWmiQueryTemplate).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object[]` | Yes | Named | None | Yes |

### -Path

A .mof file of WMI filters, exported by GPMC or HGPM: each filter is tested.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | Named | None | No |

### -ComputerName

Computer to test the filter on, by CIM (WinRM); this computer by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Credential

Account for -ComputerName.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | Named | None | No |

## Examples

### Example 1

```powershell
Test-PSGPOWmiFilter -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
```

### Example 2

```powershell
Get-PSGPOWmiFilter -Name 'Windows 11' | Test-PSGPOWmiFilter -ComputerName PC042
```

### Example 3

```powershell
Get-PSGPOWmiQueryTemplate -Id Laptops, Windows11 | Test-PSGPOWmiFilter
```

### Example 4

```powershell
Test-PSGPOWmiFilter -Path C:\Exports\Workstations.mof
```

## Outputs

- `PSGPOTools.WmiFilterTest`

## Related

- [Show-WmiFilterCreatorAvalonia](show-wmifiltercreatoravalonia.md)
- [Get-PSGPOWmiQueryTemplate](get-psgpowmiquerytemplate.md)
- [All the commands](../commands.md)
