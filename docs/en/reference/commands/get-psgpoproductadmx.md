# Get-PSGPOProductAdmx

Lists the products whose ADMX files Install-PSGPOProductAdmx installs: their publisher, the version pinned, their languages.

_The help of the command, as `Get-Help Get-PSGPOProductAdmx -Full` gives it._

## Syntax

```powershell
Get-PSGPOProductAdmx [[-Name] <string[]>] [<CommonParameters>]
```

## Description

The module pins one package of each product (Resources/AdmxProducts.json): its address on the site of its publisher, its size and SHA-256, and the SHA-256 of each of its .admx and of its .adml files. Install-PSGPOProductAdmx installs only that package, those files. A newer version of a product than the one pinned is installed from its folder with -SourcePath.

## Parameters

### -Name

The products to show (Office, Firefox...); all of them by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 1 | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOProductAdmx | Format-Table Name, Publisher, Version, Languages
```

### Example 2

```powershell
(Get-PSGPOProductAdmx -Name Firefox).Languages
```

## Outputs

- `PSGPOTools.AdmxProduct`

## Related

- [Install-PSGPOProductAdmx](install-psgpoproductadmx.md)
- [All the commands](../commands.md)
