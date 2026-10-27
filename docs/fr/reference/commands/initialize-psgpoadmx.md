# Initialize-PSGPOAdmx

Loads the ADMX/ADML files of a folder (local PolicyDefinitions or a SYSVOL central store).

_L'aide de la commande, telle que `Get-Help Initialize-PSGPOAdmx -Full` la donne (en anglais)._

## Syntaxe

```powershell
Initialize-PSGPOAdmx [[-Path] <string>] [[-UICulture] <string>] [-NoCache] [<CommonParameters>]
```

## Description

The language is detected from the names of the language folders of PolicyDefinitions (en-US, fr-FR...): the language of the session, else the same language in another country, else en-US, else the only one there is. When several languages remain, give -UICulture.

An .admx file without an .adml in the language takes the one of en-US, as the Group Policy editor; a file that cannot be read is left out with a warning, and the others are loaded. A load that fails, or where no file can be read, loads nothing.

The files of a folder are parsed once: what is loaded is kept in a cache of the user (%LOCALAPPDATA%\PSGPOTools\Admx on Windows; $XDG_CACHE_HOME/PSGPOTools/Admx, else ~/.cache/PSGPOTools/Admx elsewhere), read instead of the files while they keep their names, sizes and dates. A load with an error, or with a file left out for a reason that may pass (the network, the rights), is not cached. -NoCache parses the files.

## Paramètres

### -Path

Folder containing the .admx files and one sub-folder per culture for the .adml files. Defaults to the central store of the domain when it holds ADMX files, as GPMC (\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions; on a Samba domain controller, its SYSVOL), else to %windir%\PolicyDefinitions on Windows; required elsewhere on Linux and macOS.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

### -UICulture

Culture of the ADML files to load (sub-folder name, for example en-US or fr-FR); detected when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -NoCache

Parses the files, neither reading nor writing the cache.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Initialize-PSGPOAdmx -Path '\\contoso.com\SYSVOL\contoso.com\Policies\PolicyDefinitions' -UICulture 'fr-FR'
```

### Exemple 2

```powershell
# Linux: a copy of the PolicyDefinitions folder, in the language of the session
Initialize-PSGPOAdmx -Path ~/PolicyDefinitions
```

## Voir aussi

- [Toutes les commandes](../commands.md)
