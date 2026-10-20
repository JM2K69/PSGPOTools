# Backup-PSGPO

Backs up GPOs of the domain in a folder, when they changed since their last backup.

_L'aide de la commande, telle que `Get-Help Backup-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
Backup-PSGPO [-Path] <string> [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [[-Comment] <string>] [[-Label] <string[]>] [-Approve] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Each GPO is backed up in <Path>/<GPO name> {<GUID>}/<last change, UTC>/: the files of its SYSVOL folder as they are, and manifest.json with its versions, status, security filtering, links and the SHA-256 of each file. A GPO that did not change since its last backup is not backed up again (Result: Unchanged), unless -Force; run it on a schedule to keep the history of the GPOs, then compare two backups with Compare-PSGPOBackup or in the History tab of Show-GPOManagerAvalonia.

A backup can have a comment (why the GPO changed) and labels; the approved label of the configuration (Backup.ApprovedLabel, 'Approved' by default, or -Approve) makes it the approved version of the GPO, to which Get-PSGPODrift compares it. When the GPO did not change, its last backup gets the labels, not the comment: Set-PSGPOBackup changes it.

Works from Windows (UNC path) and Linux (smbclient with Kerberos), against Windows and Samba domain controllers. These backups are not GPMC backups: Restore-GPO / Import-GPO do not read them.

## Paramètres

### -Path

Root folder of the backups; created when missing.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Name

Display names of the GPOs to back up (wildcards allowed); all the GPOs by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 2 | Aucune | Oui |

### -Directory

Directory to back up the GPOs of (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 3 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

### -Comment

Comment of the backup: why the GPO changed, the ticket of the change.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

### -Label

Labels of the backup.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 6 | Aucune | Non |

### -Approve

Adds the approved label of the configuration: the backup is the approved version of the GPO.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Force

Backs up a GPO even when it did not change.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

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
Backup-PSGPO -Path /srv/gpo-backups
```

### Exemple 2

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Name 'C - Servers - Security Baseline' -Comment 'CHG-1024: SMB signing' -Approve
```

### Exemple 3

```powershell
Backup-PSGPO -Path D:\GPO_Backup -Name 'C - *' -Server dc1.contoso.com
```

## Sorties

- `PSGPOTools.Backup`

## Voir aussi

- [Get-PSGPOBackup](get-psgpobackup.md)
- [Compare-PSGPOBackup](compare-psgpobackup.md)
- [Get-PSGPODrift](get-psgpodrift.md)
- [Toutes les commandes](../commands.md)
