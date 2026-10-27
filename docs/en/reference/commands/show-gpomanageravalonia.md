# Show-GPOManagerAvalonia

Cross-platform (Windows/Linux/macOS) graphical console for Group Policy.

_The help of the command, as `Get-Help Show-GPOManagerAvalonia -Full` gives it._

## Syntax

```powershell
Show-GPOManagerAvalonia [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-PolicyDefinitions <string>] [-UICulture <string>] [-Language <string>] [<CommonParameters>]
Show-GPOManagerAvalonia -Directory <GPOToolsDirectory> [-PolicyDefinitions <string>] [-UICulture <string>] [-Language <string>] [<CommonParameters>]
Show-GPOManagerAvalonia -NoDirectory [-PolicyDefinitions <string>] [-UICulture <string>] [-Language <string>] [<CommonParameters>]
```

## Description

Opens on the Group Policy Management view, as GPMC: the domain, its OUs and their GPO links, and the Group Policy Objects container. Its context menu edits a GPO in the policy editor and, on a writable directory, creates GPOs.

Without -Directory, the domain is detected and read at launch (Get-PSGPODirectory), whether its domain controllers run Windows (Active Directory) or Samba (Samba AD): on a computer of a domain, on a domain controller, or with -Server. When the domain cannot be read (no Kerberos ticket, server unreachable...), the window still opens and says why. When no domain is discovered, the window shows the sample directory of the module (Samples/Directory.sample.json) under a "demonstration environment" banner.

A status bar shows this computer (name, system, addresses), its domain and the domain controller the directory was read from, with its directory service, then the version of HGPM with a dot: green when it is the latest of the PowerShell Gallery, orange when a newer one is there (its tooltip gives the command that installs it), grey when the Gallery was not read.

The policy editor displays the security settings of the computer (Windows Settings > Security Settings) and the policies loaded by Initialize-PSGPOAdmx (scope > categories > policies) with their setting form and details. When no ADMX file is loaded, a window asks for the PolicyDefinitions folder and the language of its ADML files (detected from the names of its language folders), remembering the choice for the next time; the console does not open without them. The central store of the domain shown (as GPMC), or the folder chosen instead in that window, is not asked for again: the console opens at once and reads them the first time it needs them (the policy editor, the Settings and History tabs, a report). The window asks again at the next start when that load fails. -PolicyDefinitions loads a folder without asking, before the console opens. Editing a GPO, each setting is read from the GPO (Registry.pol, GptTmpl.inf) and Apply saves it there.

Hosted on Avalonia UI under PowerShell 7+; the call blocks until the window is closed. The Avalonia assemblies are not bundled with the module: the first time a window opens, the runtime of the computer is downloaded from nuget.org and checked against its pinned SHA-512. For a computer without internet, run .\Avalonia\Get-AvaloniaBinaries.ps1 on another one (see that script's help for details).

## Parameters

### -Directory

Directory to show instead of reading the domain: from Get-PSGPODirectory, or from Import-PSGPODirectory (offline description, for demonstrations).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | Yes | Named | None | No |

### -Server

Domain controller to read the domain from (see Get-PSGPODirectory).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Credential

Account to read the domain with (see Get-PSGPODirectory).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | Named | None | No |

### -UseSsl

Reads the domain over LDAPS (see Get-PSGPODirectory).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -NoDirectory

Neither reads the domain nor shows the sample directory: the window opens on the policy editor to browse the ADMX policies.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | Yes | Named | None | No |

### -PolicyDefinitions

PolicyDefinitions folder to load the ADMX files from, without asking (see Initialize-PSGPOAdmx).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -UICulture

Language of the ADML files of -PolicyDefinitions (en-US, fr-FR...); detected when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Language

Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the language of the session, English when the module has no translation for it. The commands, their messages and errors stay in English.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | `[cultureinfo]::CurrentUICulture.Name` | No |

## Examples

### Example 1

```powershell
# The console in French
Show-GPOManagerAvalonia -Language fr-FR
```

### Example 2

```powershell
# The domain of the computer (Windows session, or a Kerberos ticket on Linux)
Initialize-PSGPOAdmx -UICulture 'en-US'
Show-GPOManagerAvalonia
```

### Example 3

```powershell
# Linux: the ADMX files of a copy of PolicyDefinitions, in the language of the session
Show-GPOManagerAvalonia -PolicyDefinitions ~/PolicyDefinitions
```

### Example 4

```powershell
kinit administrator@HARDENBOX.LABO
Show-GPOManagerAvalonia -Server dc.hardenbox.labo
```

### Example 5

```powershell
$Sample = Join-Path (Split-Path (Get-Module HGPM).Path) 'Samples' 'Directory.sample.json'
Show-GPOManagerAvalonia -Directory (Import-PSGPODirectory -Path $Sample)
```

## Related

- [Get-PSGPODirectory](get-psgpodirectory.md)
- [All the commands](../commands.md)
