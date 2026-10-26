# Show-AuditLogAvalonia

Cross-platform (Windows/Linux/macOS) graphical audit log: what the consoles and the commands changed in the domain.

_L'aide de la commande, telle que `Get-Help Show-AuditLogAvalonia -Full` la donne (en anglais)._

## Syntaxe

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

## Paramètres

### -Path

Folder of the audit log, instead of Audit.Path of the configuration of the domain.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the folder of the log.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Oui | Nommé | Aucune | Non |

### -Server

Domain controller to read the configuration of the domain from: its DNS name. By default, the domain of the computer.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Credential

Account to read the domain with, instead of the current identity (Kerberos).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `PSCredential` | Non | Nommé | Aucune | Non |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Language

Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the language of the session, English when the module has no translation for it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | `[cultureinfo]::CurrentUICulture.Name` | Non |

## Exemples

### Exemple 1

```powershell
Show-AuditLogAvalonia
```

### Exemple 2

```powershell
Show-AuditLogAvalonia -Path \\files\gpo-audit
```

### Exemple 3

```powershell
# Linux, Samba AD: Kerberos ticket first
kinit administrator@HARDENBOX.LABO
Show-AuditLogAvalonia -Server dc.hardenbox.labo
```

## Voir aussi

- [Get-PSGPOAuditLog](get-psgpoauditlog.md)
- [Toutes les commandes](../commands.md)
