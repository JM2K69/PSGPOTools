# Add-ons

An add-on is a module installed beside HGPM that adds to it. HGPM never needs one: an add-on that
is missing, or that cannot be loaded, leaves the consoles as they are.

They are called add-ons, not extensions: a GPO already has client-side extensions.

## What makes a module an add-on

- Its name is `HGPM.<name>` (`HGPM.Contoso`).
- Its manifest tags it `HGPMAddOn` (`PrivateData.PSData.Tags`).
- It requires the version of HGPM it was tested with (`RequiredModules`).
- When it is imported, it registers itself with
  [`Register-PSGPOAddOn`](../reference/commands/register-psgpoaddon.md), with the **contract** of
  the add-on points it was built for, and its hooks.

```powershell
# HGPM.Contoso.psd1
@{
    RootModule      = 'HGPM.Contoso.psm1'
    ModuleVersion   = '0.3.0.1'
    RequiredModules = @(@{ ModuleName = 'HGPM'; RequiredVersion = '0.3.0' })
    PrivateData     = @{ PSData = @{ Tags = @('HGPMAddOn') } }
}
```

```powershell
# HGPM.Contoso.psm1: its version is read in its manifest
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -Edition 'Contoso' -WindowLogo {
    param($Kind)
    Join-Path $PSScriptRoot "$Kind.png"
}
```

## How HGPM loads them

HGPM looks for the add-ons installed (`Get-Module -ListAvailable HGPM.*`, the newest version of
each one tagged `HGPMAddOn`) the first time something needs them: a window, a report, the
status bar. It does so in each process, as each console of `Start-HGPM` runs in its own, and
imports them in the session.

| State | Why | What the consoles do |
|---|---|---|
| Loaded | it registered itself with the contract of this HGPM | they call its hooks, and show its version |
| Refused | built for another contract | they open without it |
| Failed | it cannot be imported (the version of HGPM it requires, an error), or did not register | they open without it |

An add-on left out is said in the technical log and in the **About** of the launcher, with the
reason why. `PSGPOTOOLS_NO_ADDON=1` loads none (the tests set it).

The first contract, that of HGPM 0.3.0, which brings the add-ons, is **1**. It changes
when a hook changes or goes away, so that an add-on built for it would not work: an add-on built
for another contract is refused with a message that says which package to install, never with an
error inside a console. A hook **added** keeps the contract: the add-ons built before it work as
they did, and one that uses it requires the version of HGPM that has it.

## The hooks of the contract 1

Each hook is a scriptblock, called in a try: an error, or nothing returned, leaves what HGPM does
as it is.

| Hook | Called with | Returns | Where |
|---|---|---|---|
| `WindowLogo` | `Icon` or `Header` | the path of an image | `Icon`: the icon of every window (title bar, task bar); `Header`: the image of the header of the consoles, shown in 44 x 44 |
| `ReportHtml` | the HTML of a report | the HTML changed | the HTML reports (`Get-PSGPOReport -ReportType Html`, **Save report...**) |
| `ReportFormat` (HGPM 0.4.0) | its `Save`: the HTML of a report (`ReportHtml` applied) and a path | the file written | the types of file of **Save report...**, after HTML and XML; `Get-PSGPOReport -ReportType Html -Path` with its extension |
| `BeforeChange` (HGPM 0.4.0) | the directory of the domain | nothing; **an error refuses the change** | before each change of the domain: GPOs, links, WMI filters, permissions, settings, the configuration |
| `AuditEntry` (HGPM 0.4.0) | the line of the audit log, before it is written | nothing: it adds to `$Entry.Details` | each line of the [audit log](../features/audit-log.md), and of the log of the system |
| `ConsoleField` (HGPM 0.4.0) | its `Get` and `Set` | the value, kept by the add-on | a field of the toolbar of the GPO console |

An HTML report holds three markers where an add-on adds what it gives, without reading the rest
of the page: `<!-- hgpm:head -->` before `</head>`, `<!-- hgpm:body-start -->` after `<body>`,
`<!-- hgpm:body-end -->` before `</body>`. A report stays one file: what an add-on adds is in the
page.

### Formats of report

`ReportFormat` gives the formats of file an add-on writes the reports in, besides the HTML page
and the XML document of HGPM. Each one is a hashtable:

| Key | What |
|---|---|
| `Name` | its name (`Text`), in the technical log |
| `Extension` | its extension, letters and digits (`txt`); not `html`, `htm` nor `xml`, those of HGPM |
| `TypeName` | the type of file of the save dialog: a text, or a text per language (`@{ 'en-US' = 'Text file'; 'fr-FR' = 'Fichier texte' }`, English when the language of the interface has none) |
| `Save` | `param($Html, $Path)`: writes the HTML report to `$Path` in that format |

```powershell
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -ReportFormat @{
    Name      = 'Text'
    Extension = 'txt'
    TypeName  = @{ 'en-US' = 'Text file'; 'fr-FR' = 'Fichier texte' }
    Save      = { param($Html, $Path) Set-Content -LiteralPath $Path -Value ($Html -replace '<[^>]+>', '') }
}
```

**Save report...** offers each type, and the report is written by the extension of the file
chosen; `Get-PSGPOReport -ReportType Html -Path ./gpo.txt` does the same. Unlike the other hooks,
the error of `Save` is the one of the save: the console says the report is not saved, with it, and
a `Save` that writes no file is an error too. A format that does not fit (an extension of HGPM,
no `Save`...) stops the registration: the add-on is not loaded, and the technical log says why.

### A value of the console, before each change

An add-on can ask for a value in the GPO console (`ConsoleField`), write it in each line of the
audit log (`AuditEntry`) and refuse a change without it (`BeforeChange`): a ticket of change, for
instance. A field is a hashtable:

| Key | What |
|---|---|
| `Name` | its name, letters and digits |
| `Label`, `ToolTip`, `Placeholder` | its texts: a text, or a text per language |
| `Width` | its width, 80 to 400 pixels (160) |
| `Get` | its value, as the add-on keeps it |
| `Set` | `param($Value)`: the value typed (Enter, or the field left); its error is said in the console, in red, and the field shows the value the add-on keeps |

```powershell
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -ConsoleField @{
    Name  = 'Ticket'
    Label = @{ 'en-US' = 'Ticket'; 'fr-FR' = 'Ticket' }
    Get   = { $env:CONTOSO_TICKET }
    Set   = { param($Value) $env:CONTOSO_TICKET = $Value }
} -BeforeChange {
    param($Directory)
    if (-not $env:CONTOSO_TICKET) { throw 'Type the ticket of the change first.' }
} -AuditEntry {
    param($Entry)
    $Entry.Details['Ticket'] = $env:CONTOSO_TICKET
}
```

`BeforeChange` is called for the domain only, not for a directory in memory (a sample, a file
read). Unlike the other hooks, its error is the refusal: the change is not made, and its message is
the one the account reads. A console runs its long operations in a runspace of its own: a value
the add-on keeps for the process (an environment variable of the process) is seen by both.

### Settings for the domain

An add-on keeps its settings for the domain in the configuration of the domain, `AddOns.<name>`
([configuration](../reference/configuration.md#addons)): every console of the domain reads them,
only an administrator of the domain writes them. In the module of HGPM:
`Get-PSGPOAddOnConfiguration -Name Contoso` gives them, and
`Save-PSGPOAddOnConfiguration -Directory $Directory -Name Contoso -Settings @{ ... }` writes them
(`$null` removes them), the other settings as the domain has them, in the audit log as every
configuration saved.

## Versions

An add-on is tested with one version of HGPM, and requires it: its package holds both, in the
versions tested together, and a new version of HGPM brings a new package of the add-on. Its
version is that of HGPM with a fourth number of its own: `HGPM.Contoso` `0.3.0.1` is made for
HGPM `0.3.0`. With an add-on loaded, the consoles show both versions
(`HGPM 0.3.0 + Contoso 0.3.0.1`) and do not propose the updates of the PowerShell Gallery: HGPM
is updated with the package of the add-on.
