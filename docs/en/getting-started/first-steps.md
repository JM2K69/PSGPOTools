# First steps

## Open the console on your domain

```powershell
Import-Module HGPM
Show-GPOManagerAvalonia
```

Without parameters, the console finds the domain itself: the domain of the computer (Windows,
or `smb.conf` / `krb5.conf` on Linux), or the computer itself when it is a domain controller.
Give the domain controller when it cannot:

```powershell
# Linux: a Kerberos ticket first
kinit administrator@HARDENBOX.LABO
Show-GPOManagerAvalonia -Server dc.hardenbox.labo
```

When the domain cannot be read (no ticket, server unreachable...), the window still opens and
says why. When no domain is found at all, it shows a sample directory under a
**demonstration environment** banner, to discover the console offline.

## The administrative templates

The policy editor needs the ADMX and ADML files. The first time, a window asks for the
`PolicyDefinitions` folder (the local one on Windows, a copy or the central store of SYSVOL on
Linux) and the language of its ADML files, detected from the names of its language folders; the
choice is remembered. You can also load them beforehand:

```powershell
Initialize-PSGPOAdmx -Path \\hardenbox.labo\SYSVOL\hardenbox.labo\Policies\PolicyDefinitions -UICulture en-US
Show-GPOManagerAvalonia
```

## Find your way in the window

![The details of a GPO](../assets/screenshots/02-gpo-details.png)

- **Left**: the domain, its OUs with their GPO links (by link order), **Group Policy Objects**,
  and **Deleted GPOs** (the recycle bin, from the backups).
- **Right**: the details of what is selected, and for a GPO its **Settings** and **History** tabs.
- **Right click**: what you can do there, as GPMC (create and link, link an existing GPO, edit,
  delete a link, delete, restore, approve...). Only what your account may do is offered.
- **Top**: the ADMX browser, the **Settings** window (configuration of the domain), light and dark
  themes.
- **Bottom**: this computer, its domain, and the domain controller with its directory service.

## From the command line

Everything the window does is also a command, for scripts and scheduled tasks:

```powershell
$Directory = Get-PSGPODirectory -Server dc.hardenbox.labo
Backup-PSGPO -Directory $Directory -Path /srv/gpo-backups
Get-PSGPODrift -Directory $Directory -Path /srv/gpo-backups | Where-Object State -EQ Drifted
```

See [the commands](../reference/commands.md).
