# Initialize-PSGPOAdmx

Loads the ADMX/ADML files of a folder (local PolicyDefinitions or a SYSVOL central store).

_The help of the command, as `Get-Help Initialize-PSGPOAdmx -Full` gives it._

## Syntax

```powershell
Initialize-PSGPOAdmx [[-Path] <string>] [[-UICulture] <string>] [<CommonParameters>]
```

## Description

The language is detected from the names of the language folders of PolicyDefinitions (en-US, fr-FR...): the language of the session, else the same language in another country, else en-US, else the only one there is. When several languages remain, give -UICulture.

## Parameters

### -Path

Folder containing the .admx files and one sub-folder per culture for the .adml files. Defaults to %windir%\PolicyDefinitions on Windows; required on Linux and macOS.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 1 | None | No |

### -UICulture

Culture of the ADML files to load (sub-folder name, for example en-US or fr-FR); detected when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

## Examples

### Example 1

```powershell
Initialize-PSGPOAdmx -Path '\\contoso.com\SYSVOL\contoso.com\Policies\PolicyDefinitions' -UICulture 'fr-FR'
```

### Example 2

```powershell
# Linux: a copy of the PolicyDefinitions folder, in the language of the session
Initialize-PSGPOAdmx -Path ~/PolicyDefinitions
```

## Related

- [All the commands](../commands.md)
