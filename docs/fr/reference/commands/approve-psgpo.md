# Approve-PSGPO

Approves GPOs that wait for their approval (approval workflow).

_L'aide de la commande, telle que `Get-Help Approve-PSGPO -Full` la donne (en anglais)._

## Syntaxe

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

## Paramètres

### -Name

Display names of the GPOs (wildcards allowed).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -CreatorRights

What the creators may still do with the GPO: ReadOnly or EditSettings; by default the one of the configuration (Workflow.CreatorRights).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -ApplyTo

The group of the domain that applies the GPO; by default its group APPLY_<GPO> when it exists, else Authenticated Users.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -DenyTo

A group of the domain the GPO is denied to; by default its group DENY_<GPO> when it exists.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

### -CreateFilteringGroups

Creates the groups APPLY_<GPO> and DENY_<GPO>, and the GPO applies to the first and is denied to the second.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -GroupContainer

Where -CreateFilteringGroups creates the groups; by default the container of the configuration (NewGpo.SecurityFilteringGroups.Container), else the users container.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

### -BackupPath

Root folder of the backups; by default the one of the History tab of the window.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 6 | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 7 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 8 | Aucune | Non |

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
Approve-PSGPO -Name 'T1 - Servers - Proxy' -ApplyTo 'APPLY_T1 - Servers - Proxy'
```

### Exemple 2

```powershell
Approve-PSGPO -Name 'T1 - Servers - Proxy' -CreateFilteringGroups -GroupContainer 'OU=Groups,OU=Tier 1'
```

### Exemple 3

```powershell
Approve-PSGPO -Name 'T1 - *' -CreatorRights EditSettings
```

## Sorties

- `System.Management.Automation.PSObject`

## Voir aussi

- [Initialize-PSGPOWorkflow](initialize-psgpoworkflow.md)
- [Toutes les commandes](../commands.md)
