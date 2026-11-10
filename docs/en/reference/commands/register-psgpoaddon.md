# Register-PSGPOAddOn

Registers an add-on of HGPM: called by the add-on itself when it is imported, with the contract of the add-on points it was built for and its hooks.

_The help of the command, as `Get-Help Register-PSGPOAddOn -Full` gives it._

## Syntax

```powershell
Register-PSGPOAddOn [-Name] <string> [[-Version] <version>] [-Contract] <int> [[-Edition] <string>] [[-WindowLogo] <scriptblock>] [[-ReportHtml] <scriptblock>] [[-ReportFormat] <Object[]>] [[-BeforeChange] <scriptblock>] [[-AuditEntry] <scriptblock>] [[-ConsoleField] <Object[]>] [[-AuditColumn] <Object[]>] [[-ApprovalNote] <scriptblock>] [[-BeforeApproval] <scriptblock>] [<CommonParameters>]
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
- BeforeChange (HGPM 0.4.0), param($Directory): called before each change of the
directory (GPOs, links, WMI filters, permissions, settings, the configuration). Its
error refuses the change, its message said to the account: nothing is written.
- AuditEntry (HGPM 0.4.0), param($Entry): the line of the audit log before it is
written; what the add-on knows of the change goes in $Entry.Details.
- ConsoleField (HGPM 0.4.0): fields of the toolbar of the GPO console, each a hashtable:
Name, Label, ToolTip and Placeholder (a text, or a text per language), Width (80 to 400
pixels), Get (its value) and Set, param($Value) (the value typed: its error is said).
- AuditColumn (HGPM 0.4.0): columns of the audit log window, each a hashtable: Name,
Header (a text, or a text per language), Width (60 to 400 pixels), Get, param($Entry)
(its value for a line of the log), and Filter: a list of its values beside the search
filters the lines, All (a text, or a text per language) its first item. Three columns
of add-ons at most.
- ApprovalNote (HGPM 0.4.0), param($Directory, $Gpo): lines of text the approval form of
a pending GPO shows the approver, below what it approves.
- BeforeApproval (HGPM 0.4.0), param($Directory, $Gpo): called before a pending GPO is
approved, by the console and Approve-PSGPO. Its error refuses the approval, its
message said to the account: nothing is written.
The settings of an add-on for the domain are in AddOns.<name> of the configuration of the
domain (the name of the add-on without HGPM.), kept as they are by HGPM.
A hook added to the contract keeps it: an add-on built before it works as it did.
With an add-on loaded, the consoles and the reports show its version beside that of HGPM
(HGPM 0.3.0 + Contoso 0.3.0.1), and the updates of the PowerShell Gallery are not
proposed: HGPM is updated with the package of the add-on.

## Parameters

### -Name

The name of the module of the add-on (HGPM.Contoso).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | 1 | None | No |

### -Version

Its version; by default, the one of its manifest (the module being imported has none yet).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Version` | No | 2 | None | No |

### -Contract

The version of the add-on points it was built for.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Int32` | Yes | 3 | `0` | No |

### -Edition

The name the consoles and the reports show after that of HGPM (Contoso): HGPM 0.3.0 + Contoso 0.3.0.1. The name of the module by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -WindowLogo

The hook that gives the image of the windows: param($Kind), Icon or Header; a path.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `ScriptBlock` | No | 5 | None | No |

### -ReportHtml

The hook that changes the HTML reports: param($Html); the HTML returned.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `ScriptBlock` | No | 6 | None | No |

### -ReportFormat

The formats of file of the reports the add-on gives: hashtables Name, Extension, TypeName, Save (param($Html, $Path)).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object[]` | No | 7 | `@()` | No |

### -BeforeChange

The hook called before each change of the directory: param($Directory); an error refuses it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `ScriptBlock` | No | 8 | None | No |

### -AuditEntry

The hook that completes a line of the audit log: param($Entry), in $Entry.Details.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `ScriptBlock` | No | 9 | None | No |

### -ConsoleField

The fields of the toolbar of the GPO console the add-on gives: hashtables Name, Label, ToolTip, Placeholder, Width, Get, Set (param($Value)).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object[]` | No | 10 | `@()` | No |

### -AuditColumn

The columns of the audit log window the add-on gives: hashtables Name, Header, Width, Get (param($Entry)), Filter, All.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Object[]` | No | 11 | `@()` | No |

### -ApprovalNote

The hook that tells the approver of a pending GPO: param($Directory, $Gpo); lines of text.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `ScriptBlock` | No | 12 | None | No |

### -BeforeApproval

The hook called before a pending GPO is approved: param($Directory, $Gpo); an error refuses it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `ScriptBlock` | No | 13 | None | No |

## Examples

### Example 1

```powershell
# In the module of the add-on (HGPM.Contoso.psm1):
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -Edition 'Contoso' -WindowLogo { param($Kind) Join-Path $PSScriptRoot "$Kind.png" }
```

### Example 2

```powershell
# A format of report: Save report... offers it, Get-PSGPOReport -Path ./gpo.txt uses it.
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -ReportFormat @{
    Name = 'Text'; Extension = 'txt'; TypeName = @{ 'en-US' = 'Text file'; 'fr-FR' = 'Fichier texte' }
    Save = { param($Html, $Path) Set-Content -LiteralPath $Path -Value ($Html -replace '<[^>]+>', '') }
}
```

### Example 3

```powershell
# A value typed in the console, written in the audit log, needed before each change.
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -ConsoleField @{
    Name = 'Ticket'; Label = @{ 'en-US' = 'Ticket'; 'fr-FR' = 'Ticket' }
    Get = { $env:CONTOSO_TICKET }; Set = { param($Value) $env:CONTOSO_TICKET = $Value }
} -BeforeChange {
    param($Directory)
    if (-not $env:CONTOSO_TICKET) { throw 'Type the ticket of the change first.' }
} -AuditEntry {
    param($Entry)
    $Entry.Details['Ticket'] = $env:CONTOSO_TICKET
}
```

### Example 4

```powershell
# The ticket in a column of the audit log window, its values in a list that filters it,
# and the approval of a GPO refused without a ticket.
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -AuditColumn @{
    Name = 'Ticket'; Header = 'Ticket'; Width = 120; Filter = $true; All = @{ 'en-US' = 'All the tickets'; 'fr-FR' = 'Tous les tickets' }
    Get = { param($Entry) $Entry.Details.Ticket }
} -ApprovalNote {
    param($Directory, $Gpo)
    "Ticket of this session: $env:CONTOSO_TICKET"
} -BeforeApproval {
    param($Directory, $Gpo)
    if (-not $env:CONTOSO_TICKET) { throw "Type the ticket that allows the GPO '$($Gpo.DisplayName)' first." }
}
```

## Outputs

- `PSGPOTools.AddOn`

## Related

- [All the commands](../commands.md)
