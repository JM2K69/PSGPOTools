# Find-PSGPO

Searches the GPOs of a domain, as the Search of GPMC: by name, link, WMI filter, permission, client-side extension, setting, status, approval or comment.

_The help of the command, as `Get-Help Find-PSGPO -Full` gives it._

## Syntax

```powershell
Find-PSGPO [-Name <string>] [-Id <guid>] [-LinkedTo <string>] [-WmiFilter <string>] [-Account <string>] [-Permission <string>] [-Extension <string>] [-Setting <string>] [-Status <string>] [-ApprovalState <string>] [-Comment <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
Find-PSGPO [-Name <string>] [-Id <guid>] [-LinkedTo <string>] [-Linked] [-WmiFilter <string>] [-Account <string>] [-Permission <string>] [-Extension <string>] [-Setting <string>] [-Status <string>] [-ApprovalState <string>] [-Comment <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
Find-PSGPO [-Name <string>] [-Id <guid>] [-LinkedTo <string>] [-NotLinked] [-WmiFilter <string>] [-Account <string>] [-Permission <string>] [-Extension <string>] [-Setting <string>] [-Status <string>] [-ApprovalState <string>] [-Comment <string>] [-Directory <GPOToolsDirectory>] [-Server <string>] [<CommonParameters>]
```

## Description

Every criterion given must match. The name, the links, the WMI filter, the status, the approval and the client-side extensions are those of the domain read once; -Account reads the permissions of each GPO left, -Setting and -Comment the folder of each GPO left in SYSVOL: they take longer on a large domain, and come last. The GPOs found are those of the directory, by name: give them to Set-PSGPO, Backup-PSGPO, Get-PSGPOReport...

## Parameters

### -Name

A part of the display name of the GPOs, or a pattern with * and ?.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Id

The unique ID (GUID) of a GPO.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `Guid` | No | Named | None | No |

### -LinkedTo

The domain or an OU (its distinguished name, or its name when only one OU has it): the GPOs linked there.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Linked

The GPOs linked somewhere in the domain.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -NotLinked

The GPOs linked nowhere in the domain.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -WmiFilter

Name (or Id) of a WMI filter of the domain: the GPOs linked to it.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Account

An account or a group, by its name (DOMAIN\name, name) or its SID: the GPOs it has a permission on, -Permission saying which one (any by default). A permission denied is not one it has.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Permission

GpoRead, GpoApply (security filtering), GpoEdit, GpoEditDeleteModifySecurity or GpoCustom, with -Account.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Extension

A client-side extension the GPOs declare: its name (Registry, Security, Scripts, Group Policy Drive Maps...), a part of it or a pattern with * and ?, or its GUID.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Setting

A text found in the settings of the GPOs, as their Settings tab shows them: the names of the policies (with the ADMX files loaded, Initialize-PSGPOAdmx) and of the settings, the registry keys and values, their states and options.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Status

Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer configuration settings disabled) or Disabled.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -ApprovalState

Pending (waiting for approval) or Approved, with the approval workflow.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Comment

A text found in the comment of the GPOs (GPO.cmt).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | Named | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

## Examples

### Example 1

```powershell
Find-PSGPO -NotLinked
The GPOs linked nowhere: candidates to delete, or forgotten.
```

### Example 2

```powershell
Find-PSGPO -Account 'Paris-Workstations' -Permission GpoApply
The GPOs that apply to the group Paris-Workstations through their security filtering.
```

### Example 3

```powershell
Find-PSGPO -Setting 'Turn off Windows Defender' | Get-PSGPOReport -ReportType Html -Path ./reports
```

### Example 4

```powershell
Find-PSGPO -Extension 'Scripts' -LinkedTo 'OU=Servers,DC=contoso,DC=com'
```

## Outputs

- `GPOToolsGpo`

## Related

- [Set-PSGPO](set-psgpo.md)
- [All the commands](../commands.md)
