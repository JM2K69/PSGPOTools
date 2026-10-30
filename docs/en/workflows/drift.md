# Drift from the approved version

Goal: know when a GPO is no longer what was approved, whoever changed it and with whatever tool.

## 1. Approve a version

Once a GPO is reviewed, label its backup as approved: **History** tab > select the backup >
check **Approved version** > **Save notes**; or at the backup:

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Name 'C - Servers - Security Baseline' -Comment 'Reviewed with the security team' -Approve
```

The approved node is green on the timeline.

## 2. See the drift

Over the timeline of the GPO, the console compares it to its approved version:

- green: **the GPO is its approved version**;
- orange: **changed since its approved version** (`+added ~changed -removed`), and
  **Show the changes** lists them, setting by setting.

## 3. Check every GPO on a schedule

```powershell
$Drift = Get-PSGPODrift -Server dc.hardenbox.labo -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
foreach ($Gpo in $Drift) {
    "$($Gpo.DisplayName): changed since its approval of $($Gpo.Approved) by $($Gpo.ApprovedBy)"
    $Gpo.Changes | Format-Table Change, Path, Name, Before, After | Out-String
}
```

Send it by mail or to your monitoring: a GPO changed outside the change process (GPMC by
someone else, `samba-tool`, a script) shows up here.

### Its permissions too { #its-permissions-too }

A backup keeps the owner and the permissions of the GPO, as the Delegation tab lists them (since
HGPM 0.1.26). `-IncludePermissions` compares them too: an account added, removed or given another
level since the approval, another owner.

```powershell
(Get-PSGPODrift -Path /srv/gpo-backups -IncludePermissions).Changes | Where-Object Path -EQ 'Permissions' |
    Format-Table Change, Name, Before, After
```

An approved version backed up before has no permissions: `Permissions` says `NotRecorded`, and a
warning asks to approve the GPO again. Who changed them: the [domain
controllers](../technical/dc-audit.md).

## 4. Then

- the change is right: approve the new version (back it up with `-Approve`);
- it is not: restore the approved version ([Back up and restore](backup-and-restore.md)).
