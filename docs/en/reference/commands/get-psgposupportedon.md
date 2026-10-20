# Get-PSGPOSupportedOn

The platforms the policies of the loaded administrative templates support.

_The help of the command, as `Get-Help Get-PSGPOSupportedOn -Full` gives it._

## Syntax

```powershell
Get-PSGPOSupportedOn [<CommonParameters>]
```

## Description

Each supportedOn definition of the ADMX files loaded (Initialize-PSGPOAdmx), with its text in the language of the ADML files ("At least Windows 10"...): what the Details tab of a policy shows, and what the policy editor filters on.

## Examples

### Example 1

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions
Get-PSGPOSupportedOn | Where-Object DisplayName -Like '*Windows 11*'
```

## Outputs

- `GPOToolsSupportedOn`

## Related

- [Initialize-PSGPOAdmx](initialize-psgpoadmx.md)
- [All the commands](../commands.md)
