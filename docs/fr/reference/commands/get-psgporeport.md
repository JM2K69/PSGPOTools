# Get-PSGPOReport

Makes the report of GPOs, as Get-GPOReport of GPMC: an object, an XML document or an HTML page.

_L'aide de la commande, telle que `Get-Help Get-PSGPOReport -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOReport [-Name] <string[]> [-ReportType <string>] [-Path <string>] [-Language <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
Get-PSGPOReport -All [-ReportType <string>] [-Path <string>] [-Language <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
```

## Description

The report of a GPO holds its details (status, owner, versions, approval, WMI filter), its links, its security filtering and delegation, the client-side extensions it declares, and the settings of its computer and user configurations as the Settings tab of Show-GPOManagerAvalonia lists them: scripts, security settings, advanced audit policy, the policies of Registry.pol (by the ADMX files loaded with Initialize-PSGPOAdmx, else as extra registry settings), preferences.

It lists apart what HGPM does not interpret: a client-side extension whose settings it does not read (Folder Redirection, Software Installation, IP Security...), a file of the folder of the GPO no reader of HGPM reads. The computers apply them all the same: review them with GPMC, or in the files of the GPO, before approving it.

-ReportType Object (the default) gives PSGPOTools.GpoReport objects; Xml an XML document of HGPM, in English (namespace https://jm2k69.github.io/PSGPOTools/schemas/gpo-report/1, not the schema of the reports of GPMC); Html a page in one file, in the language of the interface (-Language), readable in any browser. Without -Path, the XML and the HTML are returned as a string; with -Path, written in that file (UTF-8), the file returned.

## Paramètres

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -All

Every GPO of the domain.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Oui | Nommé | Aucune | Non |

### -ReportType

Object, Xml or Html.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | `Object` | Non |

### -Path

The file the XML or HTML report is written to; one file for all the GPOs.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Language

Language of an HTML report: en-US, or a language of Resources/Strings (fr-FR); by default the one of the interface (English in a session that never opened a console).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | Nommé | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOReport -Name 'T1 - Servers - Proxy' -ReportType Html -Path ./proxy.html
```

### Exemple 2

```powershell
Get-PSGPOReport -All -ReportType Xml -Path ./gpos.xml
```

### Exemple 3

```powershell
Get-PSGPOReport -Name * | Where-Object { $_.NotInterpreted } | Select-Object DisplayName, NotInterpreted
```

## Sorties

- `PSGPOTools.GpoReport, System.String, System.IO.FileInfo`

## Voir aussi

- [Approve-PSGPO](approve-psgpo.md)
- [Toutes les commandes](../commands.md)
