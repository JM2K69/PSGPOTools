# Audit log

![The Audit Log tile](../assets/screenshots/62-tile-audit-log.png){ align=right width="170" }

`Show-AuditLogAvalonia` (or the **Audit Log** tile of `Start-HGPM`) shows the audit log of HGPM:
each change the domain accepted, from a console or a command, newest first. Who, when, from which
computer, on which domain controller, what and on which GPO, OU or setting. It needs no right on the
domain: only the read of the folder of the log.

```powershell
Show-AuditLogAvalonia
Show-AuditLogAvalonia -Path \\files\gpo-audit                # another folder
Show-AuditLogAvalonia -Server dc.hardenbox.labo -Language fr-FR
```

![The audit log](../assets/screenshots/63-audit-log.png)

## The changes

| Column | |
|---|---|
| **Time** | when, in the time of the computer (the log keeps UTC) |
| **Account** | the account of the directory that made the change |
| **Action** | what, by its name: *GPO created*, *Link changed*, *Settings of a GPO saved*, *GPO approved*... |
| **GPO or object** | the GPO, else the OU, the domain or the configuration |
| **Tier** | the folder of the central log it is in: Tier 0, 1, 2, Unassigned |
| **Computer**, **Domain** | from where, on which domain |

- **The period**: the last 24 hours, 7 days, 30 days (at first) or everything.
- **The domain** and **the action**: those the log holds.
- **The search** reads every text of a change, its details included: each word must be found
  (`registry.pol tiers1`).
- **The details** of the selected change: everything the log keeps of it, as the domain controller,
  the GPO and its identifier, and its details (the options of a link changed, the file saved with
  its SHA-256 and its new version, the rights of the creators at an approval...).
- **Export to CSV...**: the changes shown, as they are filtered, the time in UTC (ISO 8601), the
  details as JSON.

## Where the log is

The folder is `Audit.Path` of the [configuration of the domain](configuration.md): the window
reads the domain once shown (`-Server`, else the domain of the computer). Without a domain, or when
the configuration sets no folder, it is the folder `Audit` of the backups of the account, which
only its console writes. **Browse...** and **Refresh** read another folder, or the same one again.

The log is **on by default**: `Audit.Enabled = $false` in the configuration of the domain stops it,
the changes still made. See [the audit log](backup-history.md#audit-log) for what each line holds.

```powershell
# The same changes in a script
Get-PSGPOAuditLog -After (Get-Date).AddDays(-7) -Action SaveGpoFile, ApproveGpo |
    Export-Csv .\audit.csv -NoTypeInformation
```

## The central log, a folder per tier

A log the consoles share is on **a share of a file server**, `Audit.Path` of the configuration of
the domain. Not SYSVOL: it is copied to every domain controller (DFSR), the log would grow on each
of them, and two domain controllers adding to the same file would lose lines; Samba does not copy
SYSVOL at all.

The share has a folder per tier, and the permissions of the roles:

| Folder | Writes there (its own file) | Reads it |
|---|---|---|
| `Tier0` | the approvers of the workflow (`Workflow.Approvers`), Domain Admins | Tier 0, the readers |
| `Tier1` | the groups of `Audit.Tiers.Tier1` | Tier 1, Tier 0, the readers |
| `Tier2` | the groups of `Audit.Tiers.Tier2` | Tier 2, Tier 0, the readers |
| `Unassigned` | an account in no tier | Tier 0, the readers |

- Each account adds its changes to **its own file**: `<tier>\<domain>-<yyyy-MM>-<account>-<computer>.jsonl`.
  No two consoles write the same file; nobody but the administrators deletes a file or changes its
  permissions.
- **Tier 0 reads every tier**, an account of Tier 1 or Tier 2 the changes of its tier only, the
  readers (`Audit.Readers`, the auditors) everything, without writing. The window shows what the
  account can read, and the tier of each change.
- The tier of an account is read in its groups when the domain is read: an administrator of the
  domain or an approver is Tier 0, then the groups of `Audit.Tiers`.

### 1. The share

=== "Windows"

    On a Windows file server, as an administrator:

    [Download windows/New-PSGPOShare.ps1](../assets/scripts/windows/New-PSGPOShare.ps1){ download }

    ```powershell
    .\New-PSGPOShare.ps1 -Name gpo-audit                     # \\<server>\gpo-audit, D:\Shares\gpo-audit
    .\New-PSGPOShare.ps1 -Name gpo-audit -Path E:\Shares\GPO-Audit -WhatIf
    ```

    ??? example "windows/New-PSGPOShare.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/windows/New-PSGPOShare.ps1"
        ```

=== "Linux"

    On a Samba server (a member server, or the domain controller of a lab), as root:

    [Download linux/New-PSGPOShare.sh](../assets/scripts/linux/New-PSGPOShare.sh){ download }

    ```bash
    sudo ./New-PSGPOShare.sh                             # //<server>/gpo-audit, /srv/gpo-audit
    sudo ./New-PSGPOShare.sh gpo-audit /srv/gpo-audit
    ```

    ??? example "linux/New-PSGPOShare.sh"

        ```bash
        --8<-- "docs/assets/scripts/linux/New-PSGPOShare.sh"
        ```

### 2. The roles, in the configuration of the domain

In **Settings** of the console (an administrator of the domain), or `Configuration.psd1`:

```powershell
Audit = @{
    Path = '\\files.contoso.com\gpo-audit'
    Tiers = @{ Tier1 = 'GPO-Tier1-Admins'; Tier2 = 'GPO-Tier2-Admins' }
    Readers = 'GPO-Auditors'
}
```

### 3. The folders and their permissions

`Initialize-PSGPOAuditShare` makes the folders of the tiers and writes their permissions from the
roles. Again each time the groups of the tiers change: the files are kept.

```powershell
Initialize-PSGPOAuditShare -WhatIf
Initialize-PSGPOAuditShare                                   # Audit.Path of the configuration
Initialize-PSGPOAuditShare -Path //files.contoso.com/gpo-audit -Server dc.contoso.com    # Linux
```

### 4. The logs of the consoles, moved into it

The changes the consoles wrote before, in the folder `Audit` of the backups of their account:

```powershell
Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -WhatIf
Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -Remove
```

Each change goes to the file of its account, computer and month, in the folder of the tier of its
account; a change already there is not written twice, and `-Remove` deletes the files read.
