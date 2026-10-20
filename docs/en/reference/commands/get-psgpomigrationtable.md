# Get-PSGPOMigrationTable

Reads a migration table (.migtable) of GPMC.

_The help of the command, as `Get-Help Get-PSGPOMigrationTable -Full` gives it._

## Syntax

```powershell
Get-PSGPOMigrationTable [-Path] <string> [<CommonParameters>]
```

## Description

Its entries, checked as GPMC checks them: Type (User, Computer, LocalGroup, GlobalGroup, UniversalGroup, UNCPath, Unknown), Source, and how it maps: Mode SameAsSource (the reference is kept), ByRelativeName (the same name in the domain of the import), None (the account is removed) or Explicit, with its Destination. A UNC path is kept or mapped to another path; free text or a SID is not mapped by relative name; a destination is a name.

## Parameters

### -Path

The migration table.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

## Examples

### Example 1

```powershell
Get-PSGPOMigrationTable -Path C:\backupGPO\prod.migtable | Where-Object Mode -NE SameAsSource
```

## Outputs

- `PSGPOTools.MigrationEntry`

## Related

- [All the commands](../commands.md)
