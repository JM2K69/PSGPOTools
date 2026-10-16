# Managing GPOs

Everything is in the context menu of the tree; the menu offers only what your account may do in
the domain (see [delegation](delegation.md)).

## Create a GPO

**Create a GPO in this domain, and Link it here...** on the domain or an OU, or **New GPO...** on
Group Policy Objects:

![The New GPO form](../assets/screenshots/05-new-gpo.png)

| Field | |
|---|---|
| Name | proposed by the configuration (`NewGpo.DefaultName`) |
| GPO status | enabled, computer settings only (user configuration disabled), user settings only |
| Start from | an empty GPO, or a [template](#templates) |
| Create the security filtering groups | `APPLY_<GPO>` (its members alone apply it) and `DENY_<GPO>` (its members never apply it), in the container chosen |

The GPO is created in the domain controller the console reads, with **New-GPO** (RSAT) on
Windows and **samba-tool gpo create** on Linux: both create its container in the directory and
its folder in SYSVOL with its permissions, as GPMC does. Then its status, its template, its
security filtering groups and its link are set, in that order. **It is not linked when its
security filtering failed**: it would apply to every computer and user.

The command line does the same:

```powershell
New-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
```

### The security filtering groups

**Create the security filtering groups** gives the new GPO two security groups of its own, so
that it applies only where you decide:

| Group | Members | Right on the GPO |
|---|---|---|
| `APPLY_<GPO>` | the computers or users that apply it | read and "Apply Group Policy" |
| `DENY_<GPO>` | the computers or users that never apply it | "Apply Group Policy" denied |

- Their names, scope (Global, Domain local, Universal), descriptions and container come from the
  [configuration](configuration.md) (`NewGpo.SecurityFilteringGroups`); the form lists the
  container of the configuration first, then the users container and the OUs.
- **Authenticated Users** no longer applies the GPO but keeps reading it: the computers must read
  every GPO (MS16-072).
- The groups belong to the account that creates them, which manages their members.
- The groups are created **before the link**: if they cannot be created (no right in the
  container, a name already used, a name longer than 64 characters...), the GPO is created but not
  linked, and the console says why.

With the [approval workflow](../workflows/approval.md), a Tier 1 creator is not offered the groups:
a GPO waiting for its approval applies to nobody, and its security filtering is set **at the
approval**, where the approver can create the same groups.

## Link a GPO

**Link an Existing GPO...** on the domain or an OU lists the GPOs not linked there yet, searched
by name; the link gets the lowest precedence (the last link order), as in GPMC.

![Link an existing GPO](../assets/screenshots/06-link-existing-gpo.png)

**Delete link...** on a link removes it, after confirmation; the GPO itself stays in Group Policy
Objects with its other links, and the links after it move up one link order.

The links are written in the `gPLink` attribute over LDAP: the old value is removed and the new
one added in one request, so that a link someone added meanwhile is never lost.

## GPO status and security filtering

The details of a GPO show its **status** and its **security filtering**, as the Scope tab of
GPMC: who applies it ("Apply Group Policy") and who is denied it. The security filtering groups of
a new GPO are created with the prefixes, scope and descriptions of the
[configuration](configuration.md); Authenticated Users keep reading the GPO, as the computers must
(MS16-072).

## Delete a GPO

**Delete GPO...** on a GPO of Group Policy Objects, after confirmation:

![Delete a GPO](../assets/screenshots/08-delete-gpo.png)

1. The GPO is **backed up** first, in the folder of the History tab; its last backup says when and
   by whom it was deleted.
2. Its **links** in the domain are deleted. If your account cannot delete one of them, nothing is
   deleted.
3. The GPO, its container and its SYSVOL folder are deleted (**Remove-GPO** on Windows,
   **samba-tool gpo del** on Linux), and the console checks it is gone.

The Default Domain Policy and the Default Domain Controllers Policy are never deleted.

```powershell
Remove-PSGPO -Name 'U - Lyon - Printers' -BackupPath /srv/gpo-backups
```

!!! note
    The links of the sites (in the configuration partition) are not read by the console: a link
    of a site to a deleted GPO stays there.

## The recycle bin

**Deleted GPOs** lists the GPOs of the domain that are not in it anymore and have a backup (the
newest one). **Restore...** creates the GPO again from it:

![Restore a deleted GPO](../assets/screenshots/07-deleted-gpo.png)

- a **new GPO**, with a new GUID given by the domain (neither New-GPO nor samba-tool choose it),
  the name, settings, status and client-side extensions of the backup;
- **Link it again where it was**: to its containers that still exist, only when its security
  filtering was Authenticated Users and its links were enabled. Its security filtering is not
  restored, so a GPO filtered on a group is not linked again (it would apply to everyone);
- the new GPO is backed up at once, saying where it comes from, and leaves the recycle bin.

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted | Restore-PSGPO -RestoreLink
```

## Templates

A backup labelled **Template** (the check box in its notes, History tab) is proposed in
**Start from** of the New GPO form, whatever domain it comes from: the new GPO starts with its
settings, checked against their SHA-256 first.

```powershell
$Template = Get-PSGPOBackup -Path /srv/gpo-backups -Template -Name 'Template - Servers' | Select-Object -First 1
New-PSGPO -Name 'C - Servers - Lyon' -Template $Template
```
