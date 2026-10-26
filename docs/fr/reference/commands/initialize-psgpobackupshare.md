# Initialize-PSGPOBackupShare

Prepares the share of the central backups of the GPOs: for Tier 0 only.

_L'aide de la commande, telle que `Get-Help Initialize-PSGPOBackupShare -Full` la donne (en anglais)._

## Syntaxe

```powershell
Initialize-PSGPOBackupShare [-Path <string>] [-Server <string>] [-Credential <pscredential>] [-WhatIf] [-Confirm] [<CommonParameters>]
Initialize-PSGPOBackupShare -Directory <GPOToolsLdapDirectory> [-Path <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The backups of the GPOs of a domain are central on a share of a file server (Backup.Path of the configuration of the domain): the History tab, the approved versions (Get-PSGPODrift), the deleted GPOs and their restore. They are for Tier 0 only: Initialize-PSGPOBackupShare writes the permissions of the share (protected: nothing inherited from it):

- SYSTEM, Administrators and Domain Admins: full control;
- the approvers of the workflow (Workflow.Approvers): change (read, write, delete);
- nobody else: the accounts of Tier 1 and Tier 2 neither read nor write it. The console does
not show them the History tab nor the deleted GPOs, and does not back up a GPO before
they change it (the approval backs up the approved version).

Run it once by an account that can change the permissions of the share, and again when the approvers change: the backups are kept. The share is made first (New-PSGPOShare.ps1 on Windows, New-PSGPOShare.sh on Samba). On Linux, the consoles of Tier 0 mount the share (New-PSGPOShareMount.sh): HGPM finds where in /proc/mounts.

## Paramètres

### -Path

The share: \\server\share (//server/share on Linux too), or a folder in it. Backup.Path of the configuration of the domain by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | Nommé | Aucune | Non |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the approvers.

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
Initialize-PSGPOBackupShare -Path \\files\gpo-backups -WhatIf
```

### Exemple 2

```powershell
# Linux, Samba AD
kinit administrator@HARDENBOX.LABO
Initialize-PSGPOBackupShare -Path //dc.hardenbox.labo/gpo-backups -Server dc.hardenbox.labo
```

## Sorties

- `PSGPOTools.BackupShare`

## Voir aussi

- [Initialize-PSGPOAuditShare](initialize-psgpoauditshare.md)
- [Backup-PSGPO](backup-psgpo.md)
- [Toutes les commandes](../commands.md)
