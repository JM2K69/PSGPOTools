# Test-PSGPOHealth

Checks the GPOs of the domain as GPMC and gpotool: their folder and version in SYSVOL, their client-side extensions, the links, and their replication on every domain controller.

_L'aide de la commande, telle que `Get-Help Test-PSGPOHealth -Full` la donne (en anglais)._

## Syntaxe

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
- Warning, OrphanFolder: a folder of SYSVOL without a GPO in the directory.
- Warning, Link: a link to a GPO of the domain that does not exist.
- Warning, Replication: another domain controller does not have the GPO, or not the same
version, in its directory or in its SYSVOL (Get-PSGPOReplicationStatus).
- Warning, DomainController: a domain controller that cannot be read.

The GPOs are checked on the baseline, the domain controller the domain was read from: its PDC emulator, as GPMC (Get-PSGPODirectory). The other domain controllers are compared to it.

## Paramètres

### -Name

Display names of the GPOs (wildcards allowed); all the GPOs, the folders without a GPO and the links, by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 1 | Aucune | Oui |

### -Directory

Directory of the GPOs (Get-PSGPODirectory), read over LDAP: its domain controller is the baseline. The domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 2 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory: the baseline.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -DomainController

Domain controllers to compare to the baseline (DNS names); every domain controller of the domain by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 4 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Test-PSGPOHealth | Format-Table Severity, Check, Target, DomainController, Detail -Wrap
```

### Exemple 2

```powershell
# Nothing returned: no problem
if (-not (Test-PSGPOHealth -Server dc.hardenbox.labo)) { 'The GPOs are healthy.' }
```

## Sorties

- `PSGPOTools.HealthFinding`

## Voir aussi

- [Get-PSGPOReplicationStatus](get-psgporeplicationstatus.md)
- [Toutes les commandes](../commands.md)
