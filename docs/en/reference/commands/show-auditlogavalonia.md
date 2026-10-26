# Show-AuditLogAvalonia

Cross-platform (Windows/Linux/macOS) graphical audit log: what the consoles and the commands changed in the domain.

_The help of the command, as `Get-Help Show-AuditLogAvalonia -Full` gives it._

## Syntax

```powershell
Show-AuditLogAvalonia [-Path <string>] [-Server <string>] [-Credential <pscredential>] [-UseSsl] [-Language <string>] [<CommonParameters>]
Show-AuditLogAvalonia -Directory <GPOToolsDirectory> [-Path <string>] [-Language <string>] [<CommonParameters>]
```

## Description

The audit log of HGPM (Get-PSGPOAuditLog) in a window: each change the domain accepted, from a console or a command, newest first, with when, which account, from which computer, on which domain controller, what and on what (a GPO, a container, the configuration).

- Filters: the period (the last 24 hours, 7 days, 30 days, everything), the domain, the
action, a search in every text of a change (account, GPO, computer, details).
- The details of the selected change: everything the log keeps of it (the options of a
link changed, the file saved with its SHA-256 and its new version...).
- The changes shown exported to a CSV file.

The log is read from Audit.Path of the configuration of the domain (a share the administrators write, the same for every console): the domain is read once the window is shown (-Server, else the domain of the computer); without a domain, or when its configuration sets no folder, the folder Audit of the backups of the account. -Path reads another folder. The log is on by default: Audit.Enabled = $false in the configuration of the domain stops it.

Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks until the window is closed.

## Parameters

### -Path

Folder of the audit log, instead of Audit.Path of the configuration of the domain.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the folder of the log.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | Yes | Named | None | No |

### -Server

Domain controller to read the configuration of the domain from: its DNS name. By default, the domain of the computer.

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

### -Language

Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the language of the session, English when the module has no translation for it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | `[cultureinfo]::CurrentUICulture.Name` | No |

## Examples

### Example 1

```powershell
Show-AuditLogAvalonia
```

### Example 2

```powershell
Show-AuditLogAvalonia -Path \\files\gpo-audit
```

### Example 3

```powershell
# Linux, Samba AD: Kerberos ticket first
kinit administrator@HARDENBOX.LABO
Show-AuditLogAvalonia -Server dc.hardenbox.labo
```

## Related

- [Get-PSGPOAuditLog](get-psgpoauditlog.md)
- [All the commands](../commands.md)
