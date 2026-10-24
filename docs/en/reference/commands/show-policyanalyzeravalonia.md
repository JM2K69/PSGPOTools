# Show-PolicyAnalyzerAvalonia

Cross-platform (Windows/Linux/macOS) graphical Policy Analyzer: GPOs and the security baselines of Microsoft compared setting by setting.

_The help of the command, as `Get-Help Show-PolicyAnalyzerAvalonia -Full` gives it._

## Syntax

```powershell
Show-PolicyAnalyzerAvalonia [-Path <string>] [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-PolicyDefinitions <string>] [-UICulture <string>] [-Language <string>] [<CommonParameters>]
Show-PolicyAnalyzerAvalonia -Directory <GPOToolsDirectory> [-Path <string>] [-PolicyDefinitions <string>] [-UICulture <string>] [-Language <string>] [<CommonParameters>]
```

## Description

The Policy Analyzer of HGPM, as the one of the Microsoft Security Compliance Toolkit, with the same .PolicyRules files:

- Rule sets: the .PolicyRules files of a folder (Documents\PolicyAnalyzer by default, as
Policy Analyzer: the files of the security baselines of Microsoft), GPOs of the domain as
they are now, GPMC backups (the GPOs folder of a baseline). The domain is read the first
time its GPOs are asked for (-Server, else the domain of the computer).
- Comparison: the sets checked, a row per setting and a column per set, with the colours of
Policy Analyzer (yellow: different values; grey: not configured; light grey: set more than
once); only the differences, only the conflicts, a search; the details of a setting:
where GPMC shows it, the value each GPO gives it, its explanation.
- A set saved as a .PolicyRules file (Policy Analyzer, LGPO.exe /p), the comparison
exported to an Excel workbook.

The settings are named as GPMC names them with the ADMX files loaded (Initialize-PSGPOAdmx, -PolicyDefinitions; the central store or %windir%\PolicyDefinitions by default on Windows); without them, a registry value is shown by its key.

Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks until the window is closed. Get-PSGPOPolicyRuleSet and Compare-PSGPOPolicyRuleSet do the same in a script.

## Parameters

### -Path

The folder of the .PolicyRules files shown at start, instead of the one of the last time.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Directory

The domain of the GPOs (Get-PSGPODirectory), already read.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | Yes | Named | None | No |

### -Server

Domain controller to read the GPOs from: its DNS name. By default, the domain of the computer.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Credential

Account to read the domain with, instead of the current identity (Kerberos).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | Named | None | No |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -PolicyDefinitions

Folder of the ADMX files that name the registry values, when none is loaded.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -UICulture

Language of the ADML files (en-US, fr-FR...).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Language

Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the language of the session, English when the module has no translation for it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | `[cultureinfo]::CurrentUICulture.Name` | No |

## Examples

### Example 1

```powershell
Show-PolicyAnalyzerAvalonia
```

### Example 2

```powershell
Show-PolicyAnalyzerAvalonia -Path '.\Windows 11 v25H2 Security Baseline\Documentation'
```

### Example 3

```powershell
# Linux, Samba AD: Kerberos ticket first
kinit administrator@HARDENBOX.LABO
Show-PolicyAnalyzerAvalonia -Server dc.hardenbox.labo -PolicyDefinitions ~/PolicyDefinitions
```

## Related

- [Get-PSGPOPolicyRuleSet](get-psgpopolicyruleset.md)
- [Compare-PSGPOPolicyRuleSet](compare-psgpopolicyruleset.md)
- [All the commands](../commands.md)
