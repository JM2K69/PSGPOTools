# Add-ons

An add-on is a module installed beside HGPM that adds to it. HGPM never needs one: an add-on that
is missing, or that cannot be loaded, leaves the consoles as they are.

They are called add-ons, not extensions: a GPO already has client-side extensions.

## What makes a module an add-on

- Its name is `HGPM.<name>` (`HGPM.Contoso`).
- Its manifest tags it `HGPMAddOn` (`PrivateData.PSData.Tags`).
- It requires HGPM (`RequiredModules`): the version that has the hooks it uses, or later. How it
  requires it says how both are updated (see [Versions](#versions)).
- When it is imported, it registers itself with
  [`Register-PSGPOAddOn`](../reference/commands/register-psgpoaddon.md), with the **contract** of
  the add-on points it was built for, and its hooks.

```powershell
# HGPM.Contoso.psd1
@{
    RootModule      = 'HGPM.Contoso.psm1'
    ModuleVersion   = '1.0.0'
    RequiredModules = @(@{ ModuleName = 'HGPM'; ModuleVersion = '0.4.0' })
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
| Refused | built for another contract, or for another version of HGPM than the one loaded (see [Versions](#versions)): never imported | they open without it |
| Failed | it cannot be imported (an error), or did not register | they open without it |

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
| `AuditColumn` (HGPM 0.4.0) | its `Get`: a line of the audit log | its value for that line | a column of the audit log window, and a list of its values that filters the lines |
| `ApprovalNote` (HGPM 0.4.0) | the directory and the pending GPO | lines of text | the approval form of a pending GPO, below what the approver approves |
| `BeforeApproval` (HGPM 0.4.0) | the directory and the pending GPO | nothing; **an error refuses the approval** | before a pending GPO is approved, by the console and `Approve-PSGPO` |

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

### A column of the audit log

`AuditColumn` gives columns of the [audit log window](../features/audit-log.md), after the GPO or
object: what the add-on reads in each line (its `Details`), shown and filtered. Each column is a
hashtable:

| Key | What |
|---|---|
| `Name` | its name, letters and digits |
| `Header` | its title: a text, or a text per language |
| `Width` | its width, 60 to 400 pixels (130) |
| `Get` | `param($Entry)`: its value for a line of the log (`Get-PSGPOAuditLog`) |
| `Filter` | `$true`: a list of its values, the newest first, filters the lines, beside the search |
| `All` | the first item of that list: a text, or a text per language (`<title>: all` when not given) |

```powershell
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -AuditColumn @{
    Name   = 'Ticket'
    Header = 'Ticket'
    Filter = $true
    All    = @{ 'en-US' = 'All the tickets'; 'fr-FR' = 'Tous les tickets' }
    Get    = { param($Entry) $Entry.Details.Ticket }
}
```

The search of the window reads the values of the columns too. The window has three places for the
columns of the add-ons: those beyond are left out, and the technical log says it. A `Get` that
fails leaves its column empty, said once in the technical log.

### The approval of a GPO

With the [approval workflow](../workflows/approval.md), an add-on can tell the approver
what it knows of a pending GPO (`ApprovalNote`: its request, its ticket...) and refuse its
approval (`BeforeApproval`): both are called with the directory and the GPO.

```powershell
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -ApprovalNote {
    param($Directory, $Gpo)
    "Ticket of this session: $env:CONTOSO_TICKET"
} -BeforeApproval {
    param($Directory, $Gpo)
    if (-not $env:CONTOSO_TICKET) { throw "Type the ticket that allows the GPO '$($Gpo.DisplayName)' first." }
}
```

The lines of `ApprovalNote` are shown when the form opens, in a frame below its text; an add-on
that fails tells nothing. `BeforeApproval` is called before anything is written (the groups of
security filtering, the permissions, the owner): its error is the refusal, its message the one the
approver reads in the form, and the GPO stays pending.

### Settings for the domain

An add-on keeps its settings for the domain in the configuration of the domain, `AddOns.<name>`
([configuration](../reference/configuration.md#addons)): every console of the domain reads them,
only an administrator of the domain writes them. In the module of HGPM:
`Get-PSGPOAddOnConfiguration -Name Contoso` gives them, and
`Save-PSGPOAddOnConfiguration -Directory $Directory -Name Contoso -Settings @{ ... }` writes them
(`$null` removes them), the other settings as the domain has them, in the audit log as every
configuration saved.

## Versions

An add-on never stops the updates of HGPM. How its manifest requires HGPM says how both are
updated:

| Its manifest requires | The add-on | The updates |
|---|---|---|
| a minimum version: `@{ ModuleName = 'HGPM'; ModuleVersion = '0.4.0' }` | follows the PowerShell Gallery, as HGPM | HGPM offers those of the Gallery, and its command updates the add-ons installed from the Gallery with it: `Update-PSResource -Name HGPM, HGPM.Contoso` |
| one version only: `@{ ModuleName = 'HGPM'; RequiredVersion = '0.4.0' }` | comes in a package that brings that HGPM, tested with it | HGPM is updated with the package of the add-on: the consoles never offer the Gallery |

An add-on published on the PowerShell Gallery requires a **minimum** version: the first version of
HGPM that has the hooks it uses. A hook added keeps the contract, so the versions of HGPM after it
keep the add-on working. `MaximumVersion` is honoured too, for an add-on that knows the version of
HGPM it no longer takes.

An add-on that comes in a package requires **one** version of HGPM. Its own version is that of
HGPM with a fourth number of its own: `HGPM.Contoso` `0.4.0.1` is made for HGPM `0.4.0`, and a new
version of HGPM brings a new package of the add-on.

An add-on that does not take the HGPM loaded is refused **before** it is imported, with the reason
in the technical log and in the **About** of the launcher:

- one version only, another than the one loaded: install the package of the add-on made for it;
- a minimum version newer than the one loaded: update HGPM;
- a maximum version older than the one loaded: update the add-on.

Imported, such an add-on would make PowerShell load the HGPM it requires beside the one of the
session, as `Update-PSResource` keeps the versions before beside the new one: two HGPM in one
session.

With add-ons loaded, the consoles show their versions beside that of HGPM
(`HGPM 0.4.0 + Contoso 1.0.0`). [`Test-PSGPOUpdate`](../reference/commands/test-psgpoupdate.md)
gives the add-ons that follow the Gallery in `AddOns`, each with its version installed and the
latest one, and the add-on whose package brings HGPM in `Package`.
