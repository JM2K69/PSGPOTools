# Install-PSGPOProductAdmx

Installs the ADMX files of other products than Windows (Office, Firefox, Adobe, Edge, Chrome...) from their publishers, or from a folder: into a folder, or into the central store of the domain.

_The help of the command, as `Get-Help Install-PSGPOProductAdmx -Full` gives it._

## Syntax

```powershell
Install-PSGPOProductAdmx [-Name] <string[]> [-UICulture <string[]>] [-AllLanguages] [-Path <string>] [-PackagePath <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
Install-PSGPOProductAdmx [-Name] <string[]> -CentralStore [-UICulture <string[]>] [-AllLanguages] [-Directory <GPOToolsDirectory>] [-Server <string>] [-PackagePath <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
Install-PSGPOProductAdmx -SourcePath <string> -CentralStore [-UICulture <string[]>] [-AllLanguages] [-Directory <GPOToolsDirectory>] [-Server <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
Install-PSGPOProductAdmx -SourcePath <string> [-UICulture <string[]>] [-AllLanguages] [-Path <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Install-PSGPOAdmx installs the ADMX files of Windows; this command those of the products
HGPM pins (Get-PSGPOProductAdmx lists them), downloaded from their publishers:
- Office: Microsoft 365 Apps, Office LTSC and Office 2016 to 2024 (Microsoft);
- Firefox (Mozilla);
- AdobeAcrobat and AdobeReader: Adobe Acrobat and Acrobat Reader (Adobe);
- Edge (Microsoft);
- Chrome and GoogleUpdate (Google).
Their files are those of their publishers, under their terms.

The module pins each package (Resources/AdmxProducts.json): its address, size and SHA-256, and the SHA-256 of each of its .admx and .adml files. A download that differs is refused, and so is a package without one of the files pinned, before anything is written. The package is read without running anything: a zip archive, a cabinet (expand on Windows, cabextract or 7-Zip on Linux and macOS), or the cabinet the program of Office holds. A newer version than the one pinned: extract it, and install its folder with -SourcePath.

-SourcePath installs the ADMX files of any product from a PolicyDefinitions folder: its ADMX files, and one folder per language (en-US, fr-FR...) with their ADML files. The folder is checked as GPMC reads it: every .admx file has its .adml file in each language installed, with the strings and presentations it names. The folders of the languages are named after their culture (fr-FR, not fr-fr: the SYSVOL of Samba tells them apart).

- Without -CentralStore, the files go into -Path, by default the folder of
Install-PSGPOAdmx that holds the ADMX files of Windows (next to the module, else in the
data folder of the user), as the console reads one folder.
- With -CentralStore, they go into the central store of the domain,
SYSVOL\<domain>\Policies\PolicyDefinitions on the domain controller the directory comes
from (Windows: its share; Linux: smbclient with Kerberos), with the ADMX files of
Windows: every console of the domain, GPMC and HGPM, then reads them. The other files
are kept; the install is written to the audit log.

The .admx files of the product already there are replaced with -Force only. A file that declares the namespace of a file of another name already there is refused: GPMC refuses a store where two files declare one namespace. A product whose files use those of Windows (windows.admx) is installed with a warning when they are not there.

## Parameters

### -Name

The products pinned to install (Get-PSGPOProductAdmx): Office, Firefox, AdobeAcrobat, AdobeReader, Edge, Chrome, GoogleUpdate.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | No |

### -SourcePath

A PolicyDefinitions folder to install, instead of a product pinned: its .admx files, and one folder per language with the .adml files.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | Named | None | No |

### -UICulture

The languages of the .adml files to install (en-US, fr-FR...); by default en-US and the language of the session. A language a product does not have is left with a warning (GPMC and HGPM show its policies in en-US).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | No | Named | None | No |

### -AllLanguages

Every language of the product.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Path

The PolicyDefinitions folder to write; by default the one that holds the ADMX files of Windows installed by Install-PSGPOAdmx.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -CentralStore

Writes the central store of the domain (SYSVOL\<domain>\Policies\PolicyDefinitions).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | Yes | Named | None | No |

### -Directory

With -CentralStore: the domain (from Get-PSGPODirectory); the domain of the computer by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | Named | None | No |

### -Server

With -CentralStore: the domain controller to read the domain from and write to.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -PackagePath

The package of the product downloaded beforehand (one product, -Name): nothing is downloaded. It must be the package the module pins.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Force

Replaces the .admx files of the product already there.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -WhatIf

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Confirm

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
Install-PSGPOProductAdmx -Name Office, Firefox -CentralStore -Server dc.hardenbox.labo -UICulture en-US, fr-FR
Adds the ADMX files of Office and Firefox to the central store of the domain, in English and French.
```

### Example 2

```powershell
Install-PSGPOProductAdmx -Name Edge, Chrome, GoogleUpdate
Next to those of Windows installed by Install-PSGPOAdmx, in en-US and the language of the session.
```

### Example 3

```powershell
Install-PSGPOProductAdmx -SourcePath ~/Downloads/Zoom/PolicyDefinitions -CentralStore -Server dc.hardenbox.labo
The ADMX files of another product, checked, then added to the central store.
```

### Example 4

```powershell
Install-PSGPOProductAdmx -Name Office -PackagePath D:\admintemplates_x64_5568_1000_en-us.exe -AllLanguages
From the package copied to a computer without internet.
```

## Outputs

- `PSGPOTools.AdmxInstall`

## Related

- [Get-PSGPOProductAdmx](get-psgpoproductadmx.md)
- [Install-PSGPOAdmx](install-psgpoadmx.md)
- [All the commands](../commands.md)
