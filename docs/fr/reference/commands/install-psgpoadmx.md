# Install-PSGPOAdmx

Installs the ADMX files of Windows from the package of Microsoft: into a folder, or to create the central store of the domain.

_L'aide de la commande, telle que `Get-Help Install-PSGPOAdmx -Full` la donne (en anglais)._

## Syntaxe

```powershell
Install-PSGPOAdmx [-UICulture <string[]>] [-AllLanguages] [-Path <string>] [-MsiPath <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
Install-PSGPOAdmx -CentralStore [-UICulture <string[]>] [-AllLanguages] [-Directory <GPOToolsDirectory>] [-Server <string>] [-MsiPath <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The module does not ship ADMX files: the console reads those of the central store of the domain, of Windows (%windir%\PolicyDefinitions) or of the SYSVOL of a Samba domain controller. This command downloads the package of Microsoft, Administrative Templates (.admx) for Windows 11 (an .msi, from download.microsoft.com), extracts it without installing it (msiexec /a on Windows, msiextract of msitools on Linux and macOS) and installs its .admx files with their .adml files in the languages asked for (-UICulture) or all of them (-AllLanguages, 22 languages). The files are those of Microsoft, under its terms.

The module pins the package (Resources/PolicyDefinitions.json): a download whose size or SHA-256 differs is refused, and so are extracted files that are not those pinned, set by set (the .admx files, each language), before anything is written.

- Without -CentralStore, the files go into -Path, by default next to the module when it can
be written to, else into the data folder of the user (PSGPOTools/PolicyDefinitions),
where the console and Initialize-PSGPOAdmx find them.
- With -CentralStore, they go into the central store of the domain,
SYSVOL\<domain>\Policies\PolicyDefinitions on the domain controller the directory comes
from (Windows: its share; Linux: smbclient with Kerberos), as an administrator creates it
for GPMC: every console of the domain then reads them. The files already there (the ADMX
files of other products) are kept, those of the same name replaced.

A computer without internet: download the package on another computer (the page of Microsoft is in the error of a failed download) and give it with -MsiPath; it is checked as a download is.

## Paramètres

### -UICulture

The languages of the .adml files to install (en-US, fr-FR...); by default en-US and the language of the session.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | Nommé | Aucune | Non |

### -AllLanguages

The 22 languages.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Path

The PolicyDefinitions folder to write; next to the module, else the data folder of the user, by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -CentralStore

Writes the central store of the domain (SYSVOL\<domain>\Policies\PolicyDefinitions).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Oui | Nommé | Aucune | Non |

### -Directory

With -CentralStore: the domain (from Get-PSGPODirectory); the domain of the computer by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | Nommé | Aucune | Non |

### -Server

With -CentralStore: the domain controller to read the domain from and write to.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -MsiPath

The package of Microsoft downloaded beforehand (the .msi file): nothing is downloaded. It must be the package the module pins.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Force

Writes even when ADMX files are already there.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -WhatIf

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Confirm

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Install-PSGPOAdmx
The .admx files, with their en-US .adml files and those of the language of the session,
next to the module.
```

### Exemple 2

```powershell
Install-PSGPOAdmx -CentralStore -Server dc.hardenbox.labo -UICulture en-US, fr-FR
Creates the central store of the domain, in English and French.
```

### Exemple 3

```powershell
Install-PSGPOAdmx -AllLanguages -Path ~/PolicyDefinitions; Initialize-PSGPOAdmx -Path ~/PolicyDefinitions
```

### Exemple 4

```powershell
Install-PSGPOAdmx -MsiPath 'D:\Administrative Templates (.admx) for Windows 11 Sep 2026 Update.msi'
From the package copied to a computer without internet.
```

## Sorties

- `PSGPOTools.AdmxInstall`

## Voir aussi

- [Initialize-PSGPOAdmx](initialize-psgpoadmx.md)
- [Toutes les commandes](../commands.md)
