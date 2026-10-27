# Approve-PSGPO

Approves GPOs that wait for their approval (approval workflow).

_The help of the command, as `Get-Help Approve-PSGPO -Full` gives it._

## Syntax

```powershell
Approve-PSGPO [-Name] <string[]> [[-CreatorRights] <string>] [[-ApplyTo] <string>] [[-DenyTo] <string>] [[-GroupContainer] <string>] [[-BackupPath] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-CreateFilteringGroups] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

A GPO a creator (Tier 1) creates waits for its approval: its creator owns it, and it applies to nobody. An approver (Tier 0) approves it:

- its owner becomes the owner of the approved GPOs (Workflow.ApprovedOwner), in the
directory and in SYSVOL, its folder and every file in it: the creator cannot give itself
its rights back;
- the creator and the groups of creators lose their rights; the groups of creators of the
creator keep editing its settings (-CreatorRights EditSettings: each change makes it
differ from its approved version, Get-PSGPODrift) or only read it (ReadOnly);
- it applies to -ApplyTo and is denied to -DenyTo; with -CreateFilteringGroups, to its new
groups APPLY_<GPO> and DENY_<GPO> (the prefixes, scope and container of the
configuration: NewGpo.SecurityFilteringGroups), created first by the approver: a GPO
whose groups cannot be created is not approved. Without them, the GPO applies to its
groups APPLY_<GPO> and DENY_<GPO> when they exist, else to Authenticated Users;
- it is backed up with the approved label (Backup.ApprovedLabel), in -BackupPath.

Whoever manages the members of the group that applies the GPO decides where it applies: the groups the approver creates are its own.

The settings of the GPO that HGPM does not interpret (a client-side extension whose settings it does not read, a file of its folder no reader of HGPM reads) are said in a warning and in the confirmation: the computers apply them all the same. Review them with GPMC, or in the files of the GPO, before confirming (Get-PSGPOReport lists them).

## Parameters

### -Name

Display names of the GPOs (wildcards allowed).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String[]` | Yes | 1 | None | Yes |

### -CreatorRights

What the creators may still do with the GPO: ReadOnly or EditSettings; by default the one of the configuration (Workflow.CreatorRights).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

### -ApplyTo

The group of the domain that applies the GPO; by default its group APPLY_<GPO> when it exists, else Authenticated Users.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 3 | None | No |

### -DenyTo

A group of the domain the GPO is denied to; by default its group DENY_<GPO> when it exists.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 4 | None | No |

### -CreateFilteringGroups

Creates the groups APPLY_<GPO> and DENY_<GPO>, and the GPO applies to the first and is denied to the second.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -GroupContainer

Where -CreateFilteringGroups creates the groups; by default the container of the configuration (NewGpo.SecurityFilteringGroups.Container), else the users container.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 5 | None | No |

### -BackupPath

Root folder of the backups; by default the one of the History tab of the window.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 6 | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 7 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 8 | None | No |

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
Approve-PSGPO -Name 'T1 - Servers - Proxy' -ApplyTo 'APPLY_T1 - Servers - Proxy'
```

### Example 2

```powershell
Approve-PSGPO -Name 'T1 - Servers - Proxy' -CreateFilteringGroups -GroupContainer 'OU=Groups,OU=Tier 1'
```

### Example 3

```powershell
Approve-PSGPO -Name 'T1 - *' -CreatorRights EditSettings
```

## Outputs

- `System.Management.Automation.PSObject`

## Related

- [Initialize-PSGPOWorkflow](initialize-psgpoworkflow.md)
- [All the commands](../commands.md)
