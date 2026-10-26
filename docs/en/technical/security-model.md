# Security model

HGPM is a console of Tier 0 that technicians of Tier 1 and Tier 2 use too. It adds no service and
no account of its own: what an account may do is what the domain lets it do. This page says what
HGPM protects, what it relies on, and what the administrators of the domain must protect;
[hardening](hardening.md) says what was tested, and [SECURITY.md](https://github.com/JM2K69/PSGPOTools/blob/master/SECURITY.md)
how to report a flaw.

## The tiers

| Tier | Who | Does with HGPM |
|---|---|---|
| **Tier 0** | the administrators of the domain, the approvers (`Workflow.Approvers`), the owner of the approved GPOs, the purgers of the audit log (`Audit.Purgers`) | configures HGPM for the domain, approves the GPOs, owns them once approved, keeps the backups and the archives |
| **Tier 1, Tier 2** | the creators (`Workflow.Creators`), the groups of `Audit.Tiers` | create GPOs that wait for an approval, link them to the OUs of their tier, read the audit log of their tier |
| **Readers** | the auditors (`Audit.Readers`) | read the whole audit log |
| **Unassigned** | any other user of the domain | reads what the domain lets it read; writes its changes, if any, in `Unassigned` |

The boundary is the approval: a GPO of a technician applies to nobody until Tier 0 approves it,
and is Tier 0's from then on.

## The assets

| Asset | Who writes it | The threat | What HGPM does | What the administrators protect |
|---|---|---|---|---|
| A GPO waiting for approval | its creator (it owns it) | it applies before its approval; it points at another folder; it changes after its review | removes "Apply Group Policy"; refuses a GPO redirected to another folder; approves what was reviewed, or nothing ([hardening](hardening.md#approval)) | give the creators the right to link only where their GPOs may apply |
| An approved GPO | Tier 0; the creators with `EditSettings` | the creator takes it back | gives it and its SYSVOL folder to Tier 0, rebuilds its permissions, denies the creators `gPCFileSysPath` | choose `ReadOnly` unless the creators must keep editing; watch the drift |
| The security filtering groups (`APPLY_`, `DENY_`) | whoever manages their members | a technician makes them before the approval, or adds its servers | proposes only groups Tier 0 owns | manage their members in Tier 0, or delegate them knowingly |
| The configuration (`SYSVOL\<domain>\PSGPOTools`) | the administrators of the domain | another console, another version, a missing copy (Samba does not replicate SYSVOL) | reads it as data; fails closed when it cannot use it ([hardening](hardening.md#configuration-fails-closed)); checks the roles | only Tier 0 writes the folder; every domain controller has it; `Console.MinimumVersion` once the consoles are updated |
| The delegation of the creation of GPOs | `Initialize-PSGPOWorkflow -Apply` | Group Policy Creator Owners, whose GPOs skip the workflow | never uses Group Policy Creator Owners | keep Group Policy Creator Owners empty |
| The audit log (`Audit.Path`) | each account, its own file | a technician rewrites its lines, writes in the name of another, a share down loses them | append only, chained lines checked when read, the log of the system first, a local queue ([hardening](hardening.md#audit-log)) | send the log of the system to a SIEM; the purgers in Tier 0 |
| The backups (`Backup.Path`) | Tier 0 | a backup changed, then restored | checks their SHA-256 and their paths; Tier 0 only | only Tier 0 writes the share |
| The admin workstation | its user | a malicious module, a stolen ticket | a signed LDAP, signed SMB on Linux, no password on plain LDAP; the Avalonia runtime checked against its SHA-512 | an admin workstation per tier, the module from the Gallery |

## What HGPM relies on

- **The domain computes the rights.** The console shows what the domain says the account may do
  (`allowedAttributesEffective`, `tokenGroups`) and the domain controller refuses the rest. HGPM is
  no barrier of its own: an account that can write a GPO with another tool can do it without
  HGPM. HGPM makes the workflow safe for those who follow it, and visible for those who do not
  (the approval rebuilds, the drift and the audit log show).
- **SYSVOL, the shares and their permissions** are the file servers'. HGPM writes the permissions
  it needs (`Initialize-PSGPOWorkflow`, `Initialize-PSGPOAuditShare`, `Initialize-PSGPOBackupShare`)
  and checks them where it can.
- **Kerberos**: the tickets of the accounts, on Linux too (`kinit`). HGPM keeps no password.

## Not covered

- **The owner of a waiting GPO** can still give "Apply Group Policy" back with another tool: HGPM
  says it in red and the approval removes it, but does not prevent it.
- **The creators with `EditSettings`** change an approved GPO without a new approval: the drift
  shows it.
- **On Samba**, the owner of a file of the audit log can still write in it with a tool that opens
  it to append: the chain shows a line changed, the log of the system keeps a copy.
- **A Domain Admin** can do everything, HGPM included: protect Tier 0 as the domain requires.
- **The module itself** is not signed yet; install it from the PowerShell Gallery, on admin
  workstations only.
