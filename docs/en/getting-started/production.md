# Production

The [lab](lab.md) shows HGPM on a domain made for it. This page is the order to follow on a real
domain: each step with what it does, who runs it, and how to check it. The roles are those of the
[security model](../technical/security-model.md): **Tier 0** (the administrators of the domain and
the approvers), **Tier 1** and **Tier 2** (the technicians, who create GPOs that wait for an
approval).

## Before you start

| What | Needed |
|---|---|
| The consoles | PowerShell 7.4 or later, on the admin workstations of each tier (Windows or Linux) |
| Network, to the domain controllers | LDAP 389 (signed and sealed) or LDAPS 636, Kerberos 88, SMB 445 (SYSVOL), DNS 53 |
| Network, to the file server | SMB 445: the share of the audit log, the share of the backups |
| Linux | `smbclient`, `samba-tool`, `python3-samba`, `krb5-user`, a Kerberos ticket (`kinit`) |
| The first start of a console | nuget.org for the Avalonia runtime, or the runtime installed beforehand ([installation](installation.md#the-avalonia-runtime)) |
| The groups | the approvers (Tier 0), the creators of each tier, the auditors, the purgers: groups of the domain, made beforehand |

Keep the consoles of a domain on **the same version** of HGPM: the [configuration](../reference/configuration.md#console)
of a newer one is left out by an older one.

## The steps

| # | Step | Who | Command or place | Check |
|---|---|---|---|---|
| 1 | Install the module on each admin workstation | each account | `Install-PSResource HGPM -Prerelease` | `Get-Module HGPM -ListAvailable` |
| 2 | The ADMX files: the central store of the domain, or a copy next to the module | Tier 0 | the central store (`SYSVOL\<domain>\Policies\PolicyDefinitions`), or `Install-PSGPOAdmx` | the console lists the policies |
| 3 | The configuration of the domain: open the console once | a Domain Admin | `Show-GPOManagerAvalonia` creates `SYSVOL\<domain>\PSGPOTools\Configuration.psd1` | `Get-PSGPOConfiguration` |
| 4 | The roles of the workflow | a Domain Admin | **Settings**: `Workflow.Enabled`, `Workflow.Approvers`, `Workflow.Creators`, `Workflow.ApprovedOwner`, `Workflow.CreatorRights` | `Get-PSGPOConfiguration`: no problem; a role in both lists is refused |
| 5 | The creation of GPOs for the creators | a Domain Admin | `Initialize-PSGPOWorkflow -Apply` | `Initialize-PSGPOWorkflow`: every right `Present` |
| 6 | The links of each tier on its OUs | a Domain Admin | the Delegation tab of the OUs, as GPMC (the lab script `Grant-PSGPOTierDelegation.ps1` is an example) | a technician sees its OUs, the others greyed |
| 7 | The share of the audit log | the administrator of the file server | `New-PSGPOShare.ps1` (Windows) or `New-PSGPOShare.sh` (Samba) ([audit log](../features/audit-log.md#1-the-share)) | the share exists, only the administrators have full control |
| 8 | The audit log: its share and its roles | a Domain Admin | **Settings**: `Audit.Path`, `Audit.Tiers`, `Audit.Readers`, `Audit.Purgers`; then `Initialize-PSGPOAuditShare` | the Audit Log tool of a technician: its tier only, its changes *Verified* |
| 9 | The central backups, for Tier 0 | a Domain Admin | **Settings**: `Backup.Path`; `Initialize-PSGPOBackupShare`; on Linux `New-PSGPOShareMount.sh --fstab` | the History tab of Tier 0; none for the technicians |
| 10 | The log of the system, for a SIEM | an administrator of each Windows workstation | `Register-PSGPOEventSource` (Linux: journald, nothing to do) | the events of source HGPM ([event IDs](../features/audit-log.md#the-log-of-the-system-for-a-siem)) |
| 11 | The retention of the audit log | a Domain Admin | a gMSA in a group of `Audit.Purgers`, a monthly task ([retention](../features/audit-log.md#retention-and-archives)) | `Invoke-PSGPOAuditRetention -WhatIf` as the gMSA |
| 12 | The version of the consoles | a Domain Admin, once every console is updated | **Settings**: `Console.MinimumVersion` | an older console creates no GPO |

## The acceptance test

Before the technicians use it, as in the [lab](lab.md#3-the-console-as-a-technician):

1. A technician of Tier 1 creates a GPO on an OU of its tier: it waits for an approval, applies to
   nobody, and the approver sees it in **Waiting for approval**.
2. The approver approves it with its security filtering groups: Domain Admins owns it, the
   technician reads it only (or edits its settings with `EditSettings`).
3. The technician tries an OU of Tier 2: it is greyed, the link is refused.
4. The Audit Log tool shows the changes, *Verified*; the SIEM receives the events of source HGPM.

## Hardening the deployment

- Only Tier 0 writes `SYSVOL\<domain>\PSGPOTools`: the configuration decides the roles.
- Keep `Workflow.Creators` and `Workflow.Approvers` apart; never a group of every account.
- Give the approvers, Domain Admins and the purgers no other use: they are Tier 0.
- Plan with a gMSA or a dedicated account and its keytab (mode 600), never the password of a
  Domain Admin in a scheduled task.
- Send the log of the system to the SIEM: it keeps a copy of each change out of reach of the
  technicians.

## Rollback

| To remove | How |
|---|---|
| The workflow | **Settings**: `Workflow.Enabled` = `False`; then remove the rights `Initialize-PSGPOWorkflow -Apply` added: the right to create `groupPolicyContainer` objects on `CN=Policies,CN=System` and the right to create folders in `SYSVOL\<domain>\Policies`, for each group of creators (`dsacls` on Windows, `samba-tool dsacl` and `smbcacls` on Samba). While they are there, a console without the configuration creates no GPO ([fails closed](../technical/hardening.md#configuration-fails-closed)) |
| The configuration of the domain | delete `SYSVOL\<domain>\PSGPOTools`, once the delegation is removed |
| The audit log and the backups | keep the shares as long as the company keeps its evidence, then delete them |
| The log of the system | `Remove-EventLog -Source HGPM`, on each Windows workstation |
| The module | `Uninstall-PSResource HGPM`; the data of each account: `%LOCALAPPDATA%\PSGPOTools`, `~/.local/share/PSGPOTools` |

The GPOs, their links and their approvals stay as they are: they are the domain's, as GPMC leaves
them.
