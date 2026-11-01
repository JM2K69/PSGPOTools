# Find-PSGPO

Searches the GPOs of a domain, as the Search of GPMC: by name, link, WMI filter, permission, client-side extension, setting, status, approval or comment.

_L'aide de la commande, telle que `Get-Help Find-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
Find-PSGPO [-Name <string>] [-Id <guid>] [-LinkedTo <string>] [-WmiFilter <string>] [-Account <string>] [-Permission <string>] [-Extension <string>] [-Setting <string>] [-Status <string>] [-ApprovalState <string>] [-Comment <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
Find-PSGPO [-Name <string>] [-Id <guid>] [-LinkedTo <string>] [-Linked] [-WmiFilter <string>] [-Account <string>] [-Permission <string>] [-Extension <string>] [-Setting <string>] [-Status <string>] [-ApprovalState <string>] [-Comment <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
Find-PSGPO [-Name <string>] [-Id <guid>] [-LinkedTo <string>] [-NotLinked] [-WmiFilter <string>] [-Account <string>] [-Permission <string>] [-Extension <string>] [-Setting <string>] [-Status <string>] [-ApprovalState <string>] [-Comment <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
```

## Description

Every criterion given must match. The name, the links, the WMI filter, the status, the approval and the client-side extensions are those of the domain read once; -Account reads the permissions of each GPO left, -Setting and -Comment the folder of each GPO left in SYSVOL: they take longer on a large domain, and come last. The GPOs found are those of the directory, by name: give them to Set-PSGPO, Backup-PSGPO, Get-PSGPOReport...

## Paramètres

### -Name

A part of the display name of the GPOs, or a pattern with * and ?.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Id

The unique ID (GUID) of a GPO.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Guid` | Non | Nommé | Aucune | Non |

### -LinkedTo

The domain, an OU (its distinguished name, or its name when only one OU has it) or a site of the forest (its name or its distinguished name): the GPOs linked there.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Linked

The GPOs linked somewhere in the domain or in a site of the forest.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -NotLinked

The GPOs linked nowhere, in the domain nor in a site of the forest.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -WmiFilter

Name (or Id) of a WMI filter of the domain: the GPOs linked to it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Account

An account or a group, by its name (DOMAIN\name, name) or its SID: the GPOs it has a permission on, -Permission saying which one (any by default). A permission denied is not one it has.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Permission

GpoRead, GpoApply (security filtering), GpoEdit, GpoEditDeleteModifySecurity or GpoCustom, with -Account.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Extension

A client-side extension the GPOs declare: its name (Registry, Security, Scripts, Group Policy Drive Maps...), a part of it or a pattern with * and ?, or its GUID.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Setting

A text found in the settings of the GPOs, as their Settings tab shows them: the names of the policies (with the ADMX files loaded, Initialize-PSGPOAdmx) and of the settings, the registry keys and values, their states and options.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Status

Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer configuration settings disabled) or Disabled.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -ApprovalState

Pending (waiting for approval) or Approved, with the approval workflow.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Comment

A text found in the comment of the GPOs (GPO.cmt).

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
Find-PSGPO -NotLinked
The GPOs linked nowhere: candidates to delete, or forgotten.
```

### Exemple 2

```powershell
Find-PSGPO -Account 'Paris-Workstations' -Permission GpoApply
The GPOs that apply to the group Paris-Workstations through their security filtering.
```

### Exemple 3

```powershell
Find-PSGPO -Setting 'Turn off Windows Defender' | Get-PSGPOReport -ReportType Html -Path ./reports
```

### Exemple 4

```powershell
Find-PSGPO -Extension 'Scripts' -LinkedTo 'OU=Servers,DC=contoso,DC=com'
```

## Sorties

- `GPOToolsGpo`

## Voir aussi

- [Set-PSGPO](set-psgpo.md)
- [Toutes les commandes](../commands.md)
