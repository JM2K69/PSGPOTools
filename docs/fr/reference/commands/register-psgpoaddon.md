# Register-PSGPOAddOn

Registers an add-on of HGPM: called by the add-on itself when it is imported, with the contract of the add-on points it was built for and its hooks.

_L'aide de la commande, telle que `Get-Help Register-PSGPOAddOn -Full` la donne (en anglais)._

## Syntaxe

```powershell
Register-PSGPOAddOn [-Name] <string> [[-Version] <version>] [-Contract] <int> [[-Edition] <string>] [[-WindowLogo] <scriptblock>] [[-ReportHtml] <scriptblock>] [[-ReportFormat] <Object[]>] [<CommonParameters>]
```

## Description

An add-on of HGPM is a module named HGPM.<name>, tagged HGPMAddOn in its manifest (PrivateData.PSData.Tags), that requires the version of HGPM it was tested with (RequiredModules). HGPM loads the add-ons installed the first time a console, a report or the status bar needs them, in each process; the add-on then calls this command from its module, once.

-Contract is the version of the add-on points the add-on was built for. An add-on built for another contract than the one of this version of HGPM is refused: the command throws, its import fails, the technical log says why, and the consoles open without it.

The hooks of the contract 1, each called in a try: an error, or nothing returned, leaves
what HGPM does as it is.
- WindowLogo, param($Kind): the path of the image of the windows, Icon (their icon, in
the title bar and the task bar) or Header (the image of their header, shown in 44 x 44).
- ReportHtml, param($Html): the HTML report changed, returned. Its markers say where to
add: <!-- hgpm:head --> before </head>, <!-- hgpm:body-start --> after <body>,
<!-- hgpm:body-end --> before </body>.
- ReportFormat (HGPM 0.4.0): formats of file the reports are saved in besides HTML and
XML: Save report... of the console offers them, and Get-PSGPOReport -ReportType Html
writes in one when -Path has its extension. Each one a hashtable: Name, Extension,
TypeName (the type of file of the save dialog: a text, or a text per language) and
Save, param($Html, $Path), which writes the HTML report (ReportHtml applied) to $Path
in that format; its error is the one of the save. A format that does not fit stops the
registration: the add-on is not loaded, and the technical log says why.
A hook added to the contract keeps it: an add-on built before it works as it did.
With an add-on loaded, the consoles and the reports show its version beside that of HGPM
(HGPM 0.3.0 + Contoso 0.3.0.1), and the updates of the PowerShell Gallery are not
proposed: HGPM is updated with the package of the add-on.

## Paramètres

### -Name

The name of the module of the add-on (HGPM.Contoso).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Version

Its version; by default, the one of its manifest (the module being imported has none yet).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Version` | Non | 2 | Aucune | Non |

### -Contract

The version of the add-on points it was built for.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Oui | 3 | `0` | Non |

### -Edition

The name the consoles and the reports show after that of HGPM (Contoso): HGPM 0.3.0 + Contoso 0.3.0.1. The name of the module by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

### -WindowLogo

The hook that gives the image of the windows: param($Kind), Icon or Header; a path.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `ScriptBlock` | Non | 5 | Aucune | Non |

### -ReportHtml

The hook that changes the HTML reports: param($Html); the HTML returned.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `ScriptBlock` | Non | 6 | Aucune | Non |

### -ReportFormat

The formats of file of the reports the add-on gives: hashtables Name, Extension, TypeName, Save (param($Html, $Path)).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object[]` | Non | 7 | `@()` | Non |

## Exemples

### Exemple 1

```powershell
# In the module of the add-on (HGPM.Contoso.psm1):
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -Edition 'Contoso' -WindowLogo { param($Kind) Join-Path $PSScriptRoot "$Kind.png" }
```

### Exemple 2

```powershell
# A format of report: Save report... offers it, Get-PSGPOReport -Path ./gpo.txt uses it.
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -ReportFormat @{
    Name = 'Text'; Extension = 'txt'; TypeName = @{ 'en-US' = 'Text file'; 'fr-FR' = 'Fichier texte' }
    Save = { param($Html, $Path) Set-Content -LiteralPath $Path -Value ($Html -replace '<[^>]+>', '') }
}
```

## Sorties

- `PSGPOTools.AddOn`

## Voir aussi

- [Toutes les commandes](../commands.md)
