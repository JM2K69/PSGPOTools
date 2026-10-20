# Get-PSGPOCategory

The categories of the administrative templates loaded by Initialize-PSGPOAdmx.

_The help of the command, as `Get-Help Get-PSGPOCategory -Full` gives it._

## Syntax

```powershell
Get-PSGPOCategory [<CommonParameters>]
```

## Description

Each category of the ADMX files loaded (Initialize-PSGPOAdmx), with its name in the language of the ADML files and its parent category: the tree of Administrative Templates in the policy editor.

## Examples

### Example 1

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions
Get-PSGPOCategory | Where-Object DisplayName -Like '*Windows Update*'
```

## Outputs

- `GPOToolsCategory`

## Related

- [Initialize-PSGPOAdmx](initialize-psgpoadmx.md)
- [All the commands](../commands.md)
