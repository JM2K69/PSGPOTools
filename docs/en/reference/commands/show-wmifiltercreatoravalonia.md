# Show-WmiFilterCreatorAvalonia

Cross-platform (Windows/Linux/macOS) graphical tool to write the WMI filters of the GPOs.

_The help of the command, as `Get-Help Show-WmiFilterCreatorAvalonia -Full` gives it._

## Syntax

```powershell
Show-WmiFilterCreatorAvalonia [[-Path] <string>] [[-Server] <string>] [[-Credential] <pscredential>] [[-Language] <string>] [-UseSsl] [<CommonParameters>]
```

## Description

The WMI filter creator of HGPM: a WMI filter is written from a library of queries, checked, tested, then exported to a .mof file or created in the domain.

- Ready-made queries: more than sixty queries an administrator needs (Get-PSGPOWmiQueryTemplate),
by category: operating system and its versions (Windows 10, 11 and their releases, Windows
Server 2016 to 2025), edition, architecture, language, domain and name of the computer,
hardware (laptops, desktops, manufacturer, model, memory, disk, processor), virtual machines
(Hyper-V, Azure, VMware, VirtualBox, KVM, Nutanix, Xen, EC2), security (TPM, BitLocker, VBS,
antivirus), network (IP subnet, gateway, DNS suffix, time zone), programs, services,
updates, roles, files and time. Each one says its pitfalls and its source (Microsoft Learn
first); its parameters are given in the window.
- Query builder: a class of the catalog, its properties with their known values, an operator
and a value; the conditions are joined by AND or OR.
- Each query of the filter is checked as it is typed (WQL syntax, namespace of the class),
and can be written by hand.
- Test on this computer (Windows): each query runs as Windows evaluates the filter before it
applies a GPO; the filter is True when each query returns something.
- Export .mof: the format of GPMC, which Import... on WMI Filters reads in GPMC and HGPM
(Import-PSGPOWmiFilter). A .mof file exported by GPMC opens in the window too.
- Create in the domain: as New... on WMI Filters, with the rights of the account; the domain
is read on the first creation (-Server, else the domain of the computer).

Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks until the window is closed.

## Parameters

### -Path

A .mof file to open at start: a WMI filter exported by GPMC or HGPM.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 1 | None | No |

### -Server

Domain controller to create the filters in: its DNS name. By default, the domain of the computer.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -Credential

Account to create the filters with, instead of the current identity (Kerberos).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | 3 | None | No |

### -UseSsl

LDAPS (port 636): the certificate of the server must be trusted by the system.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Language

Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the language of the session, English when the module has no translation for it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | `[cultureinfo]::CurrentUICulture.Name` | No |

## Examples

### Example 1

```powershell
Show-WmiFilterCreatorAvalonia
```

### Example 2

```powershell
Show-WmiFilterCreatorAvalonia -Path C:\Exports\Workstations.mof
```

### Example 3

```powershell
# Linux, Samba AD: Kerberos ticket first
kinit administrator@HARDENBOX.LABO
Show-WmiFilterCreatorAvalonia -Server dc.hardenbox.labo -Language fr-FR
```

## Related

- [Get-PSGPOWmiQueryTemplate](get-psgpowmiquerytemplate.md)
- [Test-PSGPOWmiFilter](test-psgpowmifilter.md)
- [Export-PSGPOWmiFilter](export-psgpowmifilter.md)
- [All the commands](../commands.md)
