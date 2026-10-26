# Security policy

HGPM writes the Group Policy of a domain: its permissions, its settings, the files of SYSVOL.
A flaw in it can let an account change what applies to every computer of a domain, so security
reports are handled first.

## Reporting a vulnerability

Do not open a public issue. Report it privately, through
[a security advisory of the repository](https://github.com/JM2K69/PSGPOTools/security/advisories/new)
(GitHub > Security > Report a vulnerability), with:

- what an attacker can do, with which account and which rights to start with;
- the steps to reproduce it, on Samba AD or Windows AD;
- the version of the module (`Get-Module HGPM -ListAvailable`) or the commit.

## What happens then

| When | What |
|---|---|
| within 7 days | an answer: the report is received, and whether it is confirmed |
| as soon as it is fixed, 90 days at most after the report | a new version on the PowerShell Gallery, the advisory published on GitHub (with a CVE when the flaw deserves one), and a **Security** section in `CHANGELOG.md` |
| then | the vulnerable versions are unlisted on the Gallery (`Install-PSResource` does not offer them anymore) |

The reporter is credited in the advisory and the changelog unless they ask not to be. If a fix
needs longer than 90 days, the advisory says so, with what to do meanwhile; it is agreed with the
reporter first.

## Supported versions

HGPM is in alpha: only the latest version published on the
[PowerShell Gallery](https://www.powershellgallery.com/packages/HGPM) (built from `master`) gets
security fixes. Update before reporting, and keep every console of a domain on the same version
(`Console.MinimumVersion` in the configuration of the domain stops the older ones).

## What the console relies on

The [security model](https://jm2k69.github.io/PSGPOTools/en/technical/security-model/) says what
HGPM protects and what the domain must protect; [hardening](https://jm2k69.github.io/PSGPOTools/en/technical/hardening/)
says what was tested, on Samba AD and on Active Directory. In short:

- **The domain decides**: the rights the console shows are those the domain computes for the
  account (`allowedAttributesEffective`, `tokenGroups`), and the domain controller refuses what the
  account may not do. A way around that is a vulnerability.
- **The approval workflow** approves what the approver reviewed, or nothing; it rebuilds the
  permissions of a GPO, gives it and its SYSVOL folder to Tier 0, and reports the permissions a
  creator added. A GPO whose `gPCFileSysPath` is not its folder is refused. While a GPO waits, its
  creator owns it: what an owner may do in the domain is a known limit.
- **The central configuration** (`SYSVOL\<domain>\PSGPOTools\Configuration.psd1`) is read as data,
  never run. Whoever can write it decides the roles of the workflow: give that right to Tier 0
  only. A configuration that cannot be used, or is missing while the domain delegates the creation
  of GPOs, stops the creation of GPOs (it fails closed).
- **The audit log** is append-only, its lines chained and checked when read; the log of the system
  (for a SIEM) gets each change first.
- **The backups** are checked against their SHA-256, and their paths must stay in the GPO folder.
  The hash is written by whoever writes the backup: whoever can write the backup folder can change
  a backup. Keep it where only Tier 0 writes (`Backup.Path`, `Initialize-PSGPOBackupShare`).
- **The Avalonia runtime** is downloaded from nuget.org on the first opening, each package checked
  against the SHA-512 pinned in `Resources/AvaloniaPackages.json`.
- **Authentication**: LDAP is signed and sealed (Kerberos or NTLM on Windows, Kerberos on Linux),
  or over LDAPS; a password is never sent over plain LDAP. SMB requires signing on Linux.
