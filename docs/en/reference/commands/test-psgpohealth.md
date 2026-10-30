# Test-PSGPOHealth

Checks the GPOs of the domain as GPMC and gpotool: their folder and version in SYSVOL, their client-side extensions, the links, and their replication on every domain controller.

_The help of the command, as `Get-Help Test-PSGPOHealth -Full` gives it._

## Syntax

```powershell
Test-PSGPOHealth [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [[-DomainController] <string[]>] [<CommonParameters>]
```

## Description

Returns one row per problem found, nothing when there is none. Severity, Check, Target (a GPO, a folder, an OU or a domain controller), Id of the GPO, DomainController and Detail:

- Error, Redirected: the gPCFileSysPath of the GPO is not its folder in SYSVOL.
- Error, Folder: the GPO has no folder in SYSVOL, or no GPT.INI with a version: the
computers fail to apply it.
- Error, Version: the versions of the GPO in the directory and in SYSVOL differ: a change
stopped halfway, and the computers apply SYSVOL.
- Warning, Extension: a file of the GPO holds settings (Registry.pol, GptTmpl.inf,
audit.csv, scripts.ini, the preferences) whose client-side extension the GPO does not
declare (gPCMachineExtensionNames, gPCUserExtensionNames): they are not applied.
- Warning, Permissions: the folder of the GPO in SYSVOL does not have the permissions of the
GPO in the directory, as GPMC says "the permissions for this GPO in the SYSVOL folder are
inconsistent": an account the folder does not give the rights the GPO gives, or that an
ACE of the folder lets change it. The folders of the default GPOs of Windows, given to
Administrators and read by Authenticated Users, are consistent.
- Warning, OrphanFolder: a folder of SYSVOL without a GPO in the directory.
- Warning, Link: a link to a GPO of the domain that does not exist.
- Warning, Replication: another domain controller does not have the GPO, or not the same
version, in its directory or in its SYSVOL (Get-PSGPOReplicationStatus).
- Warning, DomainController: a domain controller that cannot be read.

The GPOs are checked on the baseline, the domain controller the domain was read from: its PDC emulator, as GPMC (Get-PSGPODirectory). The other domain controllers are compared to it.

## Parameters

### -Name

Display names of the GPOs (wildcards allowed); all the GPOs, the folders without a GPO and the links, by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 1 | None | Yes |

### -Directory

Directory of the GPOs (Get-PSGPODirectory), read over LDAP: its domain controller is the baseline. The domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 2 | None | No |

### -Server

Domain controller to read the domain from, without -Directory: the baseline.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -DomainController

Domain controllers to compare to the baseline (DNS names); every domain controller of the domain by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | 4 | None | No |

## Examples

### Example 1

```powershell
Test-PSGPOHealth | Format-Table Severity, Check, Target, DomainController, Detail -Wrap
```

### Example 2

```powershell
# Nothing returned: no problem
if (-not (Test-PSGPOHealth -Server dc.hardenbox.labo)) { 'The GPOs are healthy.' }
```

## Outputs

- `PSGPOTools.HealthFinding`

## Related

- [Get-PSGPOReplicationStatus](get-psgporeplicationstatus.md)
- [All the commands](../commands.md)
