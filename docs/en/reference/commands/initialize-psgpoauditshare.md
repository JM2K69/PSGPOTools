# Initialize-PSGPOAuditShare

Prepares the share of the central audit log: a folder per tier, the permissions of the roles.

_The help of the command, as `Get-Help Initialize-PSGPOAuditShare -Full` gives it._

## Syntax

```powershell
Initialize-PSGPOAuditShare [-Path <string>] [-Server <string>] [-Credential <pscredential>] [-WhatIf] [-Confirm] [<CommonParameters>]
Initialize-PSGPOAuditShare -Directory <GPOToolsLdapDirectory> [-Path <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The audit log of a domain is central on a share of a file server (Audit.Path of the configuration of the domain), not in SYSVOL, which is copied to every domain controller. Initialize-PSGPOAuditShare makes its folders and writes their permissions (protected: nothing inherited from the share), from the roles of the configuration of the domain:

- Tier0: the approvers of the workflow (Workflow.Approvers) and Domain Admins;
- Tier1, Tier2: the groups of Audit.Tiers.Tier1 and Audit.Tiers.Tier2;
- Unassigned: a user of the domain in no tier (Domain Users);
- Archive: the archives of the old months (Invoke-PSGPOAuditRetention);
- the readers (Audit.Readers, the auditors) and Tier 0 read every folder;
- the accounts of a tier create their own file in the folder of their tier, append to it,
and read the files of their tier, not those of the other tiers; the files already there
are made append-only too;
- the purgers (Audit.Purgers, the group of a gMSA) read every folder, delete the files of
the old months and write the archives, without being administrators of the domain;
nobody else but the administrators deletes a file or changes its permissions;
- SYSTEM, Administrators and Domain Admins have full control.

Run it once by an account that can change the permissions of the share (an administrator of the file server), and again when the groups of the tiers change: the permissions of the folders are written again, the files kept. The share itself is made first (the scripts New-PSGPOShare.ps1 on Windows and New-PSGPOShare.sh on Samba of the documentation), with share permissions that let the accounts of the domain change files: the NTFS or NT permissions written here decide. On Linux: smbclient's Python bindings (python3-samba) and a Kerberos ticket.

## Parameters

### -Path

The share: \\server\share (//server/share on Linux too), or a folder in it. Audit.Path of the configuration of the domain by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the groups.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsLdapDirectory` | Yes | Named | None | No |

### -Server

Domain controller to read the domain from. By default, the domain of the computer.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Credential

Account to read the domain with, instead of the current identity.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | Named | None | No |

### -WhatIf

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Confirm

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
Initialize-PSGPOAuditShare -Path \\files\gpo-audit -WhatIf
```

### Example 2

```powershell
# Linux, Samba AD
kinit administrator@HARDENBOX.LABO
Initialize-PSGPOAuditShare -Path //dc.hardenbox.labo/gpo-audit -Server dc.hardenbox.labo
```

## Outputs

- `PSGPOTools.AuditShareFolder`

## Related

- [Show-AuditLogAvalonia](show-auditlogavalonia.md)
- [Get-PSGPOAuditLog](get-psgpoauditlog.md)
- [All the commands](../commands.md)
