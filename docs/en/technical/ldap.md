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
| rootDSE | `defaultNamingContext`, `dnsHostName`, `vendorName` (Samba sets it, to `Samba Team (https://www.samba.org)`: the console then says `Samba AD`) |
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

## Fine-grained password policies

The PSOs of [the PSO console](../features/password-policies.md) are `msDS-PasswordSettings` objects of
`CN=Password Settings Container,CN=System,<domain>`, read in one search with their
`allowedAttributesEffective` (the account may change them) and their DACL (protection from
accidental deletion); the password policy of the domain is read from the domain object
(`minPwdLength`, `pwdProperties`, `maxPwdAge`...). Windows and Samba AD (4.9 and later) have the
same schema.

- **Durations** are negative numbers of 100-nanosecond intervals; `-9223372036854775808` means
  never (a password that does not expire, a lockout until an administrator unlocks the account), as
  the Administrative Center writes it.
- **A change** removes the value read and adds the new one in one modify request: the domain refuses
  it when another console changed the value meanwhile. A new name is a modify DN request.
- **Protection from accidental deletion**: an explicit ACE denies Everyone *Delete* and *Delete
  subtree* on the PSO, and another *Delete all child objects* on the container (without it, who may
  delete the children of the container would still delete it).
- **The PSO that applies** to a user is `msDS-ResultantPSO`, computed by the domain controller. The
  console also orders every PSO that concerns the account, through its groups (`memberOf`, nested,
  and the primary group): Windows passes a PSO on through global security groups only ("account
  groups" of [MS-DRSR] 4.1.8.1.3), Samba AD through every security group but the built-in ones
  (`get_group_sids`, `ACCOUNT_GROUPS`).
