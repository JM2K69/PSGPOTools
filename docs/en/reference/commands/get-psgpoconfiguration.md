# Get-PSGPOConfiguration

Shows the configuration of PSGPOTools for the domain, and where it comes from.

_The help of the command, as `Get-Help Get-PSGPOConfiguration -Full` gives it._

## Syntax

```powershell
Get-PSGPOConfiguration [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

The configuration is the Resources/Configuration.psd1 of the module (every setting with its default, commented), with over it the configuration of the domain: Configuration.psd1 in SYSVOL\<domain>\PSGPOTools on the domain controller, which holds only the settings it changes. It is the same for every console of the domain, and only the administrators of the domain can write it (SYSVOL: Authenticated Users read it); there is no configuration of the user. It is read as data, never run; one that cannot be read or holds a wrong value is reported and left out.

The configuration in use is the one of the last domain read (Get-PSGPODirectory, the window, or a command given -Directory); -Directory or -Server reads another one. The Settings window of the console changes it.

It sets what the window proposes for a new GPO (name, status, security filtering groups), and the labels of the approved versions and of the templates.

## Parameters

### -Directory

Directory of the domain (Get-PSGPODirectory).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 1 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOConfiguration -Server dc1.contoso.com
```

### Example 2

```powershell
# An administrator of the domain: the groups of the new GPOs in OU=GPO,OU=Groups
$Path = (Get-PSGPOConfiguration).DomainPath
Set-Content -Path $Path -Value "@{ NewGpo = @{ SecurityFilteringGroups = @{ Create = `$true; Container = 'OU=GPO,OU=Groups' } } }"
```

## Outputs

- `System.Management.Automation.PSObject`

## Related

- [All the commands](../commands.md)
