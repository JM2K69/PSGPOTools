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
- the version of the module (or the commit).

You get an answer within a week. The fix is published with a note in the `CHANGELOG.md`, and
the reporter is credited unless they ask not to be.

## Supported versions

The project has no release yet: only the latest commit of the `avalonia` branch (then of
`master`) is supported.

## What the console relies on

- **The domain decides**: the rights the console shows are those the domain computes for the
  account (`allowedAttributesEffective`, `tokenGroups`), and the domain controller refuses what the
  account may not do. A way around that is a vulnerability.
- **The approval workflow** rebuilds the permissions of a GPO at its approval, and reports those a
  creator added. While a GPO waits, its creator owns it: what an owner may do in the domain is a
  known limit ([approval](https://jm2k69.github.io/PSGPOTools/en/workflows/approval/#limits)).
- **The central configuration** (`SYSVOL\<domain>\PSGPOTools\Configuration.psd1`) is read as data,
  never run. Whoever can write it decides the roles of the workflow: give that right to Tier 0 only.
- **The backups** are checked against their SHA-256, and their paths must stay in the GPO folder.
  The hash is written by whoever writes the backup: whoever can write the backup folder can change
  a backup. Keep it where only the administrators of the GPOs write.
- **The Avalonia runtime** is downloaded from nuget.org on the first opening, each package checked
  against the SHA-512 pinned in `Resources/AvaloniaPackages.json`.
- **Authentication**: LDAP is signed and sealed (Kerberos or NTLM on Windows, Kerberos on Linux),
  or over LDAPS; a password is never sent over plain LDAP. SMB requires signing on Linux.
