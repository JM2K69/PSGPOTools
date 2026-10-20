# Get-PSGPOPolicy

The policies of the administrative templates loaded by Initialize-PSGPOAdmx.

_The help of the command, as `Get-Help Get-PSGPOPolicy -Full` gives it._

## Syntax

```powershell
Get-PSGPOPolicy [[-Scope] <string>] [<CommonParameters>]
```

## Description

Each policy of the ADMX files loaded (Initialize-PSGPOAdmx): its name and explanation in the language of the ADML files, its category, its supported platforms, the registry values it writes when enabled or disabled, and its options (elements). A policy of both scopes in the ADMX is listed once for each.

## Parameters

### -Scope

Machine (Computer Configuration) or User (User Configuration); both by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 1 | None | No |

## Examples

### Example 1

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions -UICulture fr-FR
Get-PSGPOPolicy -Scope Machine | Where-Object DisplayName -Like '*biom*' | Select-Object DisplayName, Registry
```

## Outputs

- `GPOToolsPolicy`

## Related

- [Initialize-PSGPOAdmx](initialize-psgpoadmx.md)
- [All the commands](../commands.md)
