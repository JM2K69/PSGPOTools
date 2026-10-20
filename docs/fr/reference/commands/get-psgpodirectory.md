# Get-PSGPODirectory

Reads the domain, its OUs, GPOs and GPO links from Active Directory over LDAP.

_L'aide de la commande, telle que `Get-Help Get-PSGPODirectory -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPODirectory [[-Server] <string>] [[-Credential] <pscredential>] [[-Port] <int>] [-UseSsl] [<CommonParameters>]
```

## Description

Reads the domain as GPMC shows it: the domain and its organizational units with their GPO links (gPLink, by link order, enforced and disabled links) and blocked inheritance (gPOptions), and the group policy containers (GPOs). Works with Windows and Samba domain controllers, from Windows and Linux, through System.DirectoryServices.Protocols.

The configuration of HGPM for the domain (Get-PSGPOConfiguration: SYSVOL\<domain>\ PSGPOTools\Configuration.psd1) is read with it, and used from then on.

Its changes are written to the domain: NewGpo creates a GPO with New-GPO of RSAT on Windows (the GroupPolicy module), with samba-tool on Linux (Kerberos), NewLink links a GPO to the domain or an OU over LDAP. Pass it to Show-GPOManagerAvalonia -Directory to manage it in the window.

Authentication:
- Windows: the identity of the session (Kerberos), or -Credential.
- Linux: a Kerberos ticket (kinit user@REALM), which needs the SASL GSSAPI module
(Debian/Ubuntu: libsasl2-modules-gssapi-mit); or -Credential with -UseSsl.
A password is never sent over plain LDAP.

## Paramètres

### -Server

Domain controller to read from: its DNS name (Kerberos needs the name, not the IP address). By default, the computer itself when it is a domain controller, else the domain of the computer (Windows locates a domain controller).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

### -Credential

Account to read the directory with, instead of the current identity.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `PSCredential` | Non | 2 | Aucune | Non |

### -UseSsl

LDAPS (port 636). The certificate of the server must be trusted by the system.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Port

LDAP port, when not 389 (636 with -UseSsl).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Non | 3 | `0` | Non |

## Exemples

### Exemple 1

```powershell
Show-GPOManagerAvalonia -Directory (Get-PSGPODirectory)
```

### Exemple 2

```powershell
# Linux, Samba AD: Kerberos ticket first
kinit administrator@HARDENBOX.LABO
Get-PSGPODirectory -Server dc.hardenbox.labo
```

### Exemple 3

```powershell
Get-PSGPODirectory -Server dc.contoso.com -Credential (Get-Credential) -UseSsl
```

## Sorties

- `GPOToolsDirectory`

## Voir aussi

- [Toutes les commandes](../commands.md)
