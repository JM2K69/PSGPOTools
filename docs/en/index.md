# HGPM

**HGPM** is a Group Policy management console, in the spirit of GPMC, written in
PowerShell 7 with an [Avalonia](https://avaloniaui.net/) interface. It runs on **Windows and
Linux**, and manages the GPOs of **Samba AD** and **Windows Active Directory** domains alike.

![The Group Policy Management view on a Samba AD domain](assets/screenshots/01-console-domain.png)

## What it does

<div class="grid cards" markdown>

- **The launcher**

    `Start-HGPM`: a tile for each tool of HGPM, in the language and the theme chosen for all of
    them.
    [The launcher](features/launcher.md)

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

    The console offers what the account manages (its delegations) and shows the rest read only, the configuration is the one of
    the domain (SYSVOL), and the workflow relies on the ACLs of the directory and of SYSVOL only.
    [Delegation](features/delegation.md)

- **Password policies (PSO)**

    A second console, `Show-PSOManagerAvalonia`, for the fine-grained password policies, as the
    Active Directory Administrative Center: create and apply them, and see which one applies to a
    user or a group, and why.
    [Password policies](features/password-policies.md)

- **WMI Filter Creator**

    WMI filters built from ready-made queries or a query builder, checked as they are typed,
    tested on the computer, exported to `.mof` or created in the domain.
    [WMI filter creator](features/wmi-filter-creator.md)

- **Policy Analyzer**

    GPOs, backups and the security baselines of Microsoft compared setting by setting, with the
    `.PolicyRules` files of the Security Compliance Toolkit; a baseline written in a GPO.
    [Policy Analyzer](features/policy-analyzer.md)

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
2. [Start the launcher](getting-started/first-steps.md) and open a tool on your domain.
3. Follow a [workflow](workflows/index.md): create and link a GPO, back it up and restore it,
   approve the GPOs of the Tier 1 technicians.

The screenshots of this documentation come from the [lab](getting-started/lab.md): a Samba AD
domain `hardenbox.labo` and a Windows domain `powershell.labo`.
