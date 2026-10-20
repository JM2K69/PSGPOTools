# Install-PSGPOAdmx

Downloads the ADMX files of HGPM from GitHub: into a folder, or to create the central store of the domain.

_L'aide de la commande, telle que `Get-Help Install-PSGPOAdmx -Full` la donne (en anglais)._

## Syntaxe

```powershell
Install-PSGPOAdmx [-UICulture <string[]>] [-AllLanguages] [-Path <string>] [-Ref <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
Install-PSGPOAdmx -CentralStore [-UICulture <string[]>] [-AllLanguages] [-Directory <GPOToolsDirectory>] [-Server <string>] [-Ref <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The module does not ship ADMX files: the console reads those of the central store of the domain, of Windows (%windir%\PolicyDefinitions) or of the SYSVOL of a Samba domain controller. This command downloads the copy of the repository (sources/PolicyDefinitions: the .admx files and their .adml files in 22 languages) from GitHub, at the tag of the version of the module, with the languages asked for (-UICulture) or all of them (-AllLanguages).

Each set of files (the .admx files, each language) is checked against the SHA-256 the module pins (Resources/PolicyDefinitions.json) before anything is written: a download that differs is refused, nothing installed.

- Without -CentralStore, the files go into -Path, by default next to the module when it can
be written to, else into the data folder of the user (PSGPOTools/PolicyDefinitions),
where the console and Initialize-PSGPOAdmx find them.
- With -CentralStore, they go into the central store of the domain,
SYSVOL\<domain>\Policies\PolicyDefinitions on the domain controller the directory comes
from (Windows: its share; Linux: smbclient with Kerberos), as an administrator creates it
for GPMC: every console of the domain then reads them. The files already there (the ADMX
files of other products) are kept, those of the same name replaced.

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

### -Ref

The tag, branch or commit of the repository to download; the tag of the version of the module (v0.1.2-alpha) by default. Its files must be those the module pins.

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

## Sorties

- `PSGPOTools.AdmxInstall`

## Voir aussi

- [Initialize-PSGPOAdmx](initialize-psgpoadmx.md)
- [Toutes les commandes](../commands.md)
