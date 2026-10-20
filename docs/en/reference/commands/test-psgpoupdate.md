# Test-PSGPOUpdate

Tells whether a newer version of HGPM is published on the PowerShell Gallery.

_The help of the command, as `Get-Help Test-PSGPOUpdate -Full` gives it._

## Syntax

```powershell
Test-PSGPOUpdate [[-Repository] <string>] [-Prerelease] [-Quiet] [<CommonParameters>]
```

## Description

Compares the version of HGPM loaded in the session with the latest one of the PowerShell Gallery (Find-PSResource), as semantic versions: a prerelease comes before its release (0.1.4-alpha before 0.1.4), and the prereleases sort by their label (alpha, beta, rc).

The prereleases of the Gallery count when the version loaded is one, or with -Prerelease; a stable version is otherwise only compared with the stable ones. The result gives the command that updates the module: Update-PSResource when it was installed from the Gallery, Install-PSResource otherwise (a copy of the repository, for instance).

Nothing is installed: the command only reads the Gallery.

## Parameters

### -Prerelease

Takes the prereleases of the Gallery into account, even when the version loaded is stable.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Quiet

Returns $true when a newer version is published, $false otherwise, instead of the details.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Repository

Repository of PSResourceGet to look in (Get-PSResourceRepository); PSGallery by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 1 | `PSGallery` | No |

## Examples

### Example 1

```powershell
Test-PSGPOUpdate
```

### Example 2

```powershell
if (Test-PSGPOUpdate -Quiet) { Update-PSResource -Name HGPM -Prerelease }
```

## Outputs

- `PSGPOTools.Update`

## Related

- [All the commands](../commands.md)
