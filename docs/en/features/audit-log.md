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
