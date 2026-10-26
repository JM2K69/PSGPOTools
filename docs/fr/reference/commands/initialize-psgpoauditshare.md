# Initialize-PSGPOAuditShare

Prepares the share of the central audit log: a folder per tier, the permissions of the roles.

_L'aide de la commande, telle que `Get-Help Initialize-PSGPOAuditShare -Full` la donne (en anglais)._

## Syntaxe

```powershell
Initialize-PSGPOAuditShare [-Path <string>] [-Server <string>] [-Credential <pscredential>] [-WhatIf] [-Confirm] [<CommonParameters>]
Initialize-PSGPOAuditShare -Directory <GPOToolsLdapDirectory> [-Path <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The audit log of a domain is central on a share of a file server (Audit.Path of the configuration of the domain), not in SYSVOL, which is copied to every domain controller. Initialize-PSGPOAuditShare makes its folders and writes their permissions (protected: nothing inherited from the share), from the roles of the configuration of the domain:

- Tier0: the approvers of the workflow (Workflow.Approvers) and Domain Admins;
- Tier1, Tier2: the groups of Audit.Tiers.Tier1 and Audit.Tiers.Tier2;
- Unassigned: an account in no tier;
- the readers (Audit.Readers, the auditors) and Tier 0 read every folder;
- the accounts of a tier create their own file in the folder of their tier and read the
files of their tier, not those of the other tiers; nobody but the administrators deletes
a file or changes its permissions;
- SYSTEM, Administrators and Domain Admins have full control.

Run it once by an account that can change the permissions of the share (an administrator of the file server), and again when the groups of the tiers change: the permissions of the folders are written again, the files kept. The share itself is made first (New-SmbShare on Windows; a [gpo-audit] section of smb.conf on Samba), with share permissions that let the accounts of the domain change files: the NTFS or NT permissions written here decide. On Linux: smbclient's Python bindings (python3-samba) and a Kerberos ticket.

## Paramètres

### -Path

The share: \\server\share (//server/share on Linux too), or a folder in it. Audit.Path of the configuration of the domain by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the groups.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsLdapDirectory` | Oui | Nommé | Aucune | Non |

### -Server

Domain controller to read the domain from. By default, the domain of the computer.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Credential

Account to read the domain with, instead of the current identity.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `PSCredential` | Non | Nommé | Aucune | Non |

### -WhatIf

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Confirm

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Initialize-PSGPOAuditShare -Path \\files\gpo-audit -WhatIf
```

### Exemple 2

```powershell
# Linux, Samba AD
kinit administrator@HARDENBOX.LABO
Initialize-PSGPOAuditShare -Path //dc.hardenbox.labo/gpo-audit -Server dc.hardenbox.labo
```

## Sorties

- `PSGPOTools.AuditShareFolder`

## Voir aussi

- [Show-AuditLogAvalonia](show-auditlogavalonia.md)
- [Get-PSGPOAuditLog](get-psgpoauditlog.md)
- [Toutes les commandes](../commands.md)
