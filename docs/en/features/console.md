# The console

`Show-GPOManagerAvalonia` opens one window with three views, switched from its toolbar.

## Group Policy Management

The view it opens on, as GPMC:

![The Group Policy Management view](../assets/screenshots/01-console-domain.png)

- **The domain and its OUs**, sorted by name, each with its GPO links by link order (link order 1
  first, the highest precedence). An OU that blocks inheritance says so, and has its own icon.
  A link says when it is **enforced** or **disabled**.
- **Group Policy Objects**: every GPO of the domain your account can see.
- **Deleted GPOs**: the GPOs deleted from the domain that have a backup, to restore them
  ([recycle bin](gpo-management.md#the-recycle-bin)).

The details of a node depend on what it is:

| Node | Details |
|---|---|
| Domain | distinguished name, domain controller and directory service, the account connected, its delegation, its role in the approval workflow, the GPOs linked |
| OU | distinguished name, block inheritance, your rights there, the GPOs linked |
| GPO, link | unique ID, status, approval state and owner, your rights, security filtering, versions, distinguished name, SYSVOL path, every link of the GPO |
| Deleted GPO | its last backup, by whom, its comment, status, security filtering, where it was linked |

A GPO also has two tabs:

- **Settings**: its configured settings, as the GPMC report: the policies by category path, the
  security settings, the preferences, the extra registry values no ADMX explains.
- **History**: its backups as a timeline ([backups and history](backup-history.md)).

![The Settings tab](../assets/screenshots/03-gpo-settings.png)

## Policy editor

**Edit** (right click, or double click on a GPO) opens the GPO in the
[policy editor](policy-editor.md): the administrative templates, the security settings and the
preferences, read from the GPO and saved there.

## ADMX browser

**Browse the ADMX policies** shows the policies of the ADMX files loaded, without a GPO: search a
policy by its name, read its explanation and the registry value it sets, copy its name, its
registry path or the `Get-ItemProperty` command that reads it.

![The ADMX browser](../assets/screenshots/13-admx-browser.png)

## The status bar

At the bottom: this computer (name, system, addresses), its domain, the domain controller the
directory was read from and its directory service (`Samba AD` or `Active Directory`), and the
account connected.

## Themes and settings

The toolbar switches between the light and dark themes, and opens the **Settings** window: the
[configuration of the domain](configuration.md).

## Demonstration environment

Without a domain, the window shows `Samples/Directory.sample.json` under a banner: a fictitious
domain with OUs, links and GPOs, to discover the console. Its changes stay in memory.

```powershell
$Sample = Join-Path (Split-Path (Get-Module PSGPOTools).Path) 'Samples' 'Directory.sample.json'
Show-GPOManagerAvalonia -Directory (Import-PSGPODirectory -Path $Sample)
```
