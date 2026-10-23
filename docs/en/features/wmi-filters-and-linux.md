# WMI filters and Linux clients

A WMI filter is evaluated by the computer that applies the GPO, not by the domain controller nor
by the console. A Windows computer evaluates it; a Linux computer joined with Samba does not. This
page explains both, and what a Linux client applies of a GPO.

## How a WMI filter works

A WMI filter is an object of the domain (`msWMI-Som` in `CN=SOM,CN=WMIPolicy,CN=System`) with one
or more WQL queries, each in a WMI namespace (`root\CIMv2` by default). A GPO names its filter in
`gPCWQLFilter`; a GPO has one filter at most, a filter is used by any number of GPOs.

When a **Windows** computer processes Group Policy, for each GPO that applies to it (its links,
inheritance and security filtering) and has a WMI filter:

1. it runs each query of the filter on itself, through WMI;
2. the filter is **true when every query returns at least one instance** (the queries are joined
   with AND; an OR is written in one query, `WHERE ProductType = 1 OR ProductType = 3`);
3. a false filter: the GPO is not applied (`gpresult` shows it *Denied (WMI Filter)*); a filter
   the domain does not have anymore: the GPO is not applied either.

The filter is evaluated at each refresh of Group Policy, for the computer and for the user: keep
its queries cheap (`Win32_OperatingSystem`, `Win32_ComputerSystem`), as a slow query slows every
logon.

| Example | Query |
|---|---|
| Workstations | `SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1` |
| Servers | `SELECT * FROM Win32_OperatingSystem WHERE ProductType = 3` |
| Windows 11 | `SELECT * FROM Win32_OperatingSystem WHERE Version LIKE '10.0.2%' AND ProductType = 1` |
| Laptops | `SELECT * FROM Win32_Battery` |

Samba AD, as a domain controller, only keeps the filters: the Windows computers of a Samba domain
evaluate them as in a Windows domain. The console creates, changes, exports and delegates them
([WMI filters](gpo-management.md#wmi-filters)).

## Linux clients: what samba-gpupdate applies

A Linux computer joined to the domain with Samba (winbind) applies Group Policy with
`samba-gpupdate`, when its `smb.conf` has `apply group policies = yes` (at each refresh of winbind,
or by hand: `samba-gpupdate --force`; `samba-gpupdate --rsop` shows what it would apply). It builds
the list of the GPOs as Windows does, but checks less, and applies only the settings it has a
client-side extension for.

What follows was read in the code of Samba 4.22 (Debian 13, `samba/gp/gpclass.py` and the
extensions in `samba/gp/`); another version of Samba can differ.

| Of a GPO | Windows | Linux (samba-gpupdate) |
|---|---|---|
| Links, disabled links, enforced links, blocked inheritance | yes | yes |
| Security filtering: read the GPO | yes | yes: a GPO the computer cannot read is skipped |
| Security filtering: *Apply Group Policy* (allowed or denied) | yes | **no**: a GPO the computer reads is applied |
| WMI filter | yes | **no**: `gPCWQLFilter` is read, never evaluated |
| GPO status (user or computer configuration disabled) | yes | **no**: `flags` is read, never used |
| Settings | the client-side extensions of Windows | **only the extensions of Samba** (below) |

### The settings a Linux client applies

The other settings of a GPO (most administrative templates, the security settings of Windows, the
preferences, the scripts of Windows, the advanced audit policy...) are ignored by a Linux client.

| Extension of Samba | Read from the GPO | Does |
|---|---|---|
| Sudo rights | `Machine\Registry.pol`, `Software\Policies\Samba\Unix Settings\Sudo Rights` | sudoers rules |
| Scripts | `Software\Policies\Samba\Unix Settings\Daily Scripts` (Hourly, Weekly, Monthly) | scripts in `/etc/cron.*`; for the users too (`User\Registry.pol`) |
| Messages | `Software\Policies\Samba\Unix Settings\Messages` | `/etc/motd`, `/etc/issue` |
| smb.conf | `Software\Policies\Samba\smb_conf` | `[global]` options of `smb.conf` |
| firewalld | `Software\Policies\Samba\Unix Settings\Firewalld` | zones and rules |
| Firefox | `Software\Policies\Mozilla\Firefox` | the policies of Firefox |
| Chromium, Chrome | `Software\Policies\Google\Chrome` | the managed and recommended policies |
| GNOME | `GNOME Settings\Lock Down Settings` | dconf settings and locks |
| Certificate auto-enrollment | `Software\Policies\Microsoft\Cryptography\AutoEnrollment` | certificates of the enterprise CA (certmonger) |
| Centrify | `Software\Policies\Centrify\UnixSettings` (SuDo, CrontabEntries) | sudo rules, crontab entries |
| Drive maps | `User\Preferences\Drives\Drives.xml` | the drives of the users |
| VGP (Vintela) | `Machine\VGP\VTLA\...\manifest.xml` | sudoers, files, symbolic links, OpenSSH, motd, issue, startup scripts, host access |
| Kerberos and system access | `GptTmpl.inf`, `[Kerberos Policy]` and `[System Access]` | on a Samba domain controller only |

`samba-tool gpo manage` writes these settings (`samba-tool gpo manage sudoers add`, `motd set`,
`scripts startup add`, `symlink add`...), and `samba-tool gpo admxload` puts the administrative
templates of Samba in the central store, for the policy editor of the console.

## Why a test of a Linux client fails, and what to do

A GPO linked to the OU of a Linux computer with a WMI filter, or settings of Windows only, does not
do on Linux what it does on Windows. It is not a fault of the console: the client does not do it.

- **Target the Linux computers by their OU**, not by a WMI filter: an OU of the Linux computers,
  where the GPOs for them are linked.
- **Keep a GPO away from Linux computers** by denying them **Read** of the GPO (a group of the Linux
  computers, its Read denied), not only *Apply Group Policy*: a denial group made by the console
  (`DENY_<GPO>`) denies *Apply Group Policy*, which a Linux client does not check. Denying Read to a
  group of Linux computers only does not change the Windows computers (MS16-072: they must read
  the GPOs they apply).
- **The status of the GPO does not keep its user or computer part from a Linux client**: put the
  settings for Linux in their own GPO.
- **Use the settings of Samba** for the Linux computers (the table above): the policies of Windows
  are not translated. A WQL query cannot be translated either: Linux has no WMI.
