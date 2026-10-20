# Show-PSOManagerAvalonia

Cross-platform (Windows/Linux/macOS) graphical console for the fine-grained password policies (PSO).

_The help of the command, as `Get-Help Show-PSOManagerAvalonia -Full` gives it._

## Syntax

```powershell
Show-PSOManagerAvalonia [[-Server] <string>] [[-Credential] <pscredential>] [[-View] <string>] [[-Language] <string>] [-UseSsl] [<CommonParameters>]
```

## Description

The password settings of the Active Directory Administrative Center, for Windows and Samba AD domains, from Windows or Linux. Two views:

- Password Settings: the PSOs of the Password Settings Container by order of priority, with
their settings and the users and groups each one directly applies to; New, Properties and
Delete as in the Administrative Center (precedence, minimum length, history, complexity,
reversible encryption, minimum and maximum age, lockout, protection from accidental
deletion, description, "Directly Applies To"). The password policy of the domain is shown
under the list: it applies to the accounts no PSO applies to.
- Resultant Password Settings: search a user or a group, select it, and see every PSO that
concerns it (directly, or through which groups, nested ones included) by order of
priority, the one that applies and why the others do not. For a user, the domain
controller gives the PSO it applies (msDS-ResultantPSO).

Without -Server, the domain of the computer is read; when no domain is discovered, the window shows sample policies (Samples/PasswordPolicy.sample.json) under a "demonstration environment" banner, and their changes stay in memory. The changes of a domain are written over LDAP, and to the audit log of HGPM (Get-PSGPOAuditLog).

Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks until the window is closed.

## Parameters

### -Server

Domain controller to read the domain from: its DNS name. By default, the domain of the computer (see Get-PSGPODirectory).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 1 | None | No |

### -Credential

Account to read and change the domain with, instead of the current identity (Kerberos).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | 2 | None | No |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -View

View shown at launch: Policies (Password Settings), or Resultant (Resultant Password Settings).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | `Policies` | No |

### -Language

Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the language of the session, English when the module has no translation for it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | `[cultureinfo]::CurrentUICulture.Name` | No |

## Examples

### Example 1

```powershell
Show-PSOManagerAvalonia
```

### Example 2

```powershell
# Linux, Samba AD: Kerberos ticket first
kinit administrator@HARDENBOX.LABO
Show-PSOManagerAvalonia -Server dc.hardenbox.labo -Language fr-FR
```

### Example 3

```powershell
Show-PSOManagerAvalonia -View Resultant
```

## Related

- [Get-PSGPOFineGrainedPasswordPolicy](get-psgpofinegrainedpasswordpolicy.md)
- [Get-PSGPOResultantPasswordPolicy](get-psgporesultantpasswordpolicy.md)
- [All the commands](../commands.md)
