# Backups and history

PSGPOTools keeps the history of each GPO as backups, in a folder you choose (by default
`PSGPOTools Backups` in your documents). The **History** tab of a GPO shows them as a timeline.

![The History tab](../assets/screenshots/04-history.png)

## Backups

```text
<root>/<GPO name> {<GUID>}/<last change of the GPO, UTC: yyyy-MM-dd_HH-mm-ss>/
    manifest.json       the GPO and the SHA-256 of each file
    notes.json          its comment and labels, when it has some
    Files/              the files of its SYSVOL folder, as they are
```

- **The GUID** keeps the history of a GPO that is renamed.
- **A backup is written only when the GPO changed** since the last one (its files or its
  properties: name, status, security filtering, links), as GPMC `Backup-GPO` by date of change.
  `-Force` backs it up anyway.
- They are not GPMC backups: `Restore-GPO` and `Import-GPO` do not read them.

**Back up now** (one GPO) and **Back up all GPOs** (those you can see) take the comment typed
above the timeline. The same from the command line, for a scheduled task:

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Comment 'CHG-1024: SMB signing'
```

## The timeline

Oldest first, as the branch of a git graph. Each node is a backup, with its date, its versions
(computer / user) and what changed since the node before it (`+added ~changed -removed`); **Now**
is the GPO as it is, when it changed since its last backup. Select a node to see its changes
setting by setting, with the value before (struck out) and after.

The changes are those of the Settings tab: the policies by category path, the security settings,
the preference items (by their `uid`), the other files by their hash, and the name, status,
security filtering and links of the GPO.

```powershell
$Backups = Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
Compare-PSGPOBackup -ReferenceBackup $Backups[1] -DifferenceBackup $Backups[0]
```

## Restore

**Restore this version...** puts the GPO back as the backup has it, as GPMC `Restore-GPO`:

1. The files of the backup are checked against their SHA-256: a file missing or changed since
   stops the restore.
2. The GPO as it is now is **backed up first**, its comment saying it.
3. Its files are replaced (those the backup does not have are deleted), its status and
   client-side extensions are those of the backup.
4. Its version increases in both scopes, so that the computers apply it again.

Its links and its permissions do not change; its WMI filter is the one of the backup, when that filter is still in the domain.

A backup is never restored in another domain, even on a GPO with its GUID: the Default Domain
Policy and the Default Domain Controllers Policy have the same GUID in every domain. Use it as a
[template](gpo-management.md#templates) of a new GPO instead.

Each path of the manifest must be a file of the GPO folder (no `..`, no rooted path): a backup
whose manifest names another one is ignored, with a warning, as a damaged manifest is; the other
backups are listed.

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'T1 - Servers - Baseline' |
    Where-Object { $_.Modified.Date -eq [datetime]'2026-10-15' } | Select-Object -First 1 | Restore-PSGPO
```

## Notes: comments and labels

The notes of a backup are kept beside it, in `notes.json`; its manifest and files never change,
so a restore still checks them. Select a node to change them: its comment, its labels, and two
check boxes:

- **Approved version**: the label of the approved versions (`Backup.ApprovedLabel` of the
  configuration, `Approved` by default);
- **Template**: the label of the templates of new GPOs (`Backup.TemplateLabel`, `Template`).

On the timeline, the labels are under each node, the comment is its tool tip, and the approved
version is green.

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy' | Select-Object -First 1 |
    Set-PSGPOBackup -Approve -Comment 'Reviewed with the security team'
```

## Drift from the approved version

The newest backup with the approved label is the **approved version** of the GPO. Over the
timeline, the console says whether the GPO is still it, or what changed since: in the console,
with GPMC, `samba-tool`, a script, whoever made the change.

| State | |
|---|---|
| `InSync` | the GPO is its approved version |
| `Drifted` | it changed since: **Show the changes** lists them |
| `NotApproved` | no backup has the approved label yet |

```powershell
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
```

See [the drift workflow](../workflows/drift.md) and the [approval workflow](../workflows/approval.md).

## Audit log

Each change the domain accepted, from the console or a command, is a line of the audit log:

| Field | |
|---|---|
| `Time` | when (UTC) |
| `Account`, `Computer`, `Server` | who, from which computer, on which domain controller |
| `Action` | `NewGpo`, `NewLink`, `SetLink`, `RemoveLink`, `SetBlockInheritance`, `SetGpoStatus`, `SaveGpoFile`, `RestoreGpo`, `RemoveGpo`, `PendingGpo`, `ApproveGpo`, `NewFilteringGroups`, `SaveConfiguration` |
| `Target`, `GpoName`, `GpoId` | on what: the GPO, the domain or OU, the configuration |
| `Details` | how: the link options changed, the file saved with its SHA-256 and the new version, the rights of the creators and the permissions removed at an approval... |

The lines are only added, never rewritten: one file per domain and month,
`<domain>-<yyyy-MM>.jsonl`, in `Audit.Path` of the [configuration](configuration.md) (a share the
administrators of the GPOs write, the same for every console); by default in the folder `Audit` of
the backups of the account, which only its console sees. A log that cannot be written does not
undo the change, which is made: the console says so.

```powershell
Get-PSGPOAuditLog -After (Get-Date).AddDays(-7) | Format-Table Time, Account, Action, GpoName, Target
Get-PSGPOAuditLog -Name 'C - Servers - Baseline' -Action SaveGpoFile, ApproveGpo
```

!!! note
    The log says what the consoles and the commands of PSGPOTools changed, not what GPMC or
    another tool changed. Whoever can write its folder can change it: give the share to the
    administrators of the GPOs only, and keep a copy where they cannot write (a SIEM).
