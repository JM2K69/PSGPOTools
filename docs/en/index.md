# HGPM

**HGPM** is a Group Policy management console, in the spirit of GPMC, written in
PowerShell 7 with an [Avalonia](https://avaloniaui.net/) interface. It runs on **Windows and
Linux**, and manages the GPOs of **Samba AD** and **Windows Active Directory** domains alike.

![The Group Policy Management view on a Samba AD domain](assets/screenshots/01-console-domain.png)

## What it does

<div class="grid cards" markdown>

- **Group Policy Management view**

    The domain, its OUs and their GPO links, the Group Policy Objects, as GPMC shows them; create,
    link, delete and restore GPOs, enforce, disable and order their links, block the inheritance, set their status and security filtering.
    [The console](features/console.md)

- **Policy editor**

    The administrative templates (ADMX/ADML), the security settings (GptTmpl.inf) and the Group
    Policy Preferences of a GPO, read from SYSVOL and saved there.
    [The policy editor](features/policy-editor.md)

- **History and approval**

    Backups with comments and labels, a timeline of each GPO, the differences between two
    versions, restore, drift from the approved version, and an approval workflow Tier 0 / Tier 1.
    [Backups and history](features/backup-history.md)

- **Rights of the domain**

    The console shows what the account manages (its delegations), the configuration is the one of
    the domain (SYSVOL), and the workflow relies on the ACLs of the directory and of SYSVOL only.
    [Delegation](features/delegation.md)

</div>

## At a glance

| | |
|---|---|
| **Runs on** | Windows 10/11 and Server, Linux (Debian, Ubuntu, RHEL...), with PowerShell 7.4 or later |
| **Domains** | Samba AD (4.x) and Active Directory (Windows Server domain controllers) |
| **Directory** | LDAP (System.DirectoryServices.Protocols), Kerberos; LDAPS with a password |
| **SYSVOL** | The UNC path on Windows; `smbclient` and the Samba Python bindings on Linux |
| **GPO creation and deletion** | RSAT (`New-GPO`, `Remove-GPO`) on Windows; `samba-tool` on Linux |
| **Interface** | Avalonia 11, installed on the first opening of the window |

## Where to start

1. [Install the module](getting-started/installation.md) and what it needs on your platform.
2. [Open the console](getting-started/first-steps.md) on your domain.
3. Follow a [workflow](workflows/index.md): create and link a GPO, back it up and restore it,
   approve the GPOs of the Tier 1 technicians.

The screenshots of this documentation come from the [lab](getting-started/lab.md): a Samba AD
domain `hardenbox.labo` and a Windows domain `powershell.labo`.
