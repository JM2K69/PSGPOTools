# The directory (LDAP)

The console reads and writes the directory with **System.DirectoryServices.Protocols**: wldap32
on Windows, the OpenLDAP library (`libldap`) on Linux, against Windows and Samba domain
controllers alike.

## Connection

| | |
|---|---|
| Windows | Negotiate (Kerberos) with the identity of the session, or `-Credential` |
| Linux | SASL GSSAPI with the Kerberos ticket of the session (`kinit`): signing and sealing come from the SASL layer |
| `-Credential` | LDAPS only (`-UseSsl`): a password is never sent over plain LDAP |
| Server | its DNS name: Kerberos needs the service `ldap/<dc>` |

`Get-PSGPOLdapErrorMessage` turns the LDAP errors into what to do: no ticket (`kinit`), the SASL
GSSAPI module missing, an IP address given instead of a name, a server unreachable.

## What is read

`Get-PSGPODirectory` reads, in a few paged searches:

| Object | Attributes |
|---|---|
| rootDSE | `defaultNamingContext`, `dnsHostName`, `vendorName` (Samba sets it: `Samba AD`) |
| the domain | `gPLink`, `gPOptions`, `wellKnownObjects` (the users container), `allowedAttributesEffective` |
| the OUs | `name`, `gPLink`, `gPOptions`, `allowedAttributesEffective` |
| `CN=Policies` | `allowedChildClassesEffective` (can the account create GPOs) |
| the GPOs | `displayName`, `versionNumber`, `flags`, `gPCFileSysPath`, `whenChanged`, `gPC*ExtensionNames`, `allowedAttributesEffective`, `nTSecurityDescriptor` (DACL: security filtering; owner: approval state) |

The account connected comes from the "Who am I?" extended operation (RFC 4532,
`1.3.6.1.4.1.4203.1.11.3`); its groups, for the approval workflow, from `tokenGroups` (nested groups
included).

## gPLink

A `gPLink` is a list of `[LDAP://<GPO DN>;<options>]`, the **last one being link order 1**;
option bit 0 disables the link, bit 1 enforces it. A link whose GPO is missing is kept and shown.
The console adds a link first in the value (the lowest precedence), and removes one keeping the
others as they are. The write is one modify request with **delete of the old value and add of the
new one**: the server refuses it when the value changed meanwhile, and the console reads the
links the domain has.

## Security descriptors

`nTSecurityDescriptor` is read and written with the **SD flags control**
(`1.2.840.113556.1.4.801`): only the parts needed (DACL; owner and DACL for an approval), so that
the SACL, which needs a privilege, is never asked for. The descriptor is parsed and written by the
console itself ([security descriptors](security-descriptors.md)).

## Groups

The security filtering groups are created over LDAP (`group`, `groupType` of the configuration:
Global `-2147483646`, DomainLocal `-2147483644`, Universal `-2147483640`), with their description.

## GPOs

The creation and the deletion of a GPO go through the tools of the platform (`New-GPO` /
`Remove-GPO`, `samba-tool gpo create / del`), which create or delete its container **and** its SYSVOL
folder with their permissions, as GPMC does. Then the console reads the GPO as the directory has
it, or checks that it is gone (a search of a missing object returns nothing with `-AllowMissing`).
