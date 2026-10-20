# Import-PSGPODirectory

Reads a domain, its OUs, GPOs and GPO links from a JSON description.

_The help of the command, as `Get-Help Import-PSGPODirectory -Full` gives it._

## Syntax

```powershell
Import-PSGPODirectory [-Path] <string> [<CommonParameters>]
```

## Description

Proof of concept of the Group Policy Management view of Show-GPOManagerAvalonia: the directory is described in a JSON file instead of being read from Active Directory, and the changes made in the window (new GPOs, new links) stay in memory.

JSON format:
domain               DNS name of the domain (required)
gpos                 [ { name (required), id, userVersion, computerVersion,
userEnabled, computerEnabled } ]
links                links of the domain, by link order (1 first): either the GPO
name or { gpo, enabled, enforced }
organizationalUnits  [ { name (required), blockInheritance, links, organizationalUnits } ]

A sample is shipped with the module: Samples/Directory.sample.json.

## Parameters

### -Path

Path of the JSON file.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

## Examples

### Example 1

```powershell
$Directory = Import-PSGPODirectory -Path (Join-Path (Split-Path (Get-Module PSGPOTools).Path) 'Samples' 'Directory.sample.json')
Show-GPOManagerAvalonia -Directory $Directory
```

## Outputs

- `GPOToolsDirectory`

## Related

- [All the commands](../commands.md)
