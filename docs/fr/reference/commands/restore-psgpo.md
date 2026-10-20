# Restore-PSGPO

Puts a GPO back as one of its backups has it (Backup-PSGPO).

_L'aide de la commande, telle que `Get-Help Restore-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
Restore-PSGPO [-Backup] <Backup> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-NoBackup] [-RestoreLink] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Like GPMC Restore-GPO: the files of the SYSVOL folder of the GPO are replaced by those of the backup (the files the backup does not have are deleted), and its status and client-side extensions are those of the backup. Its version increases in both scopes, so that the computers apply it again. Its links and permissions (security filtering) do not change.

The GPO as it is now is backed up first, in the same folder, so that the restore can be undone (unless -NoBackup). The files of the backup are checked against their SHA-256 first.

A backup of another domain is never restored, even when a GPO of this domain has its GUID (the Default Domain Policy and the Default Domain Controllers Policy have the same GUID in every domain): use it as a template of a new GPO (New-PSGPO -Template).

A backup of a deleted GPO (Get-PSGPOBackup -Deleted) creates it again: a new GPO, with a new GUID given by the domain, the name, settings, status and client-side extensions of the backup. Its security filtering is not restored (it applies to Authenticated Users); with -RestoreLink it is linked again to its containers that still exist, only when its security filtering was Authenticated Users and its links were enabled. The new GPO is backed up at once, and the deleted one leaves the recycle bin.

## Paramètres

### -Backup

The backup to restore (Get-PSGPOBackup).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object` | Oui | 1 | Aucune | Oui |

### -Directory

Directory of the GPO (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 2 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -NoBackup

Does not back up the GPO as it is now before restoring it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -RestoreLink

For a deleted GPO: links it again where it was (see the description).

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
# A deleted GPO, created again and linked where it was
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted | Where-Object DisplayName -EQ 'U - Lyon - Printers' | Restore-PSGPO -RestoreLink
```

### Exemple 2

```powershell
# The GPO as it was on 15 October
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'T1 - Servers - Baseline' |
    Where-Object { $_.Modified.Date -eq [datetime]'2026-10-15' } | Select-Object -First 1 | Restore-PSGPO
```

## Sorties

- `System.Management.Automation.PSObject`

## Voir aussi

- [Backup-PSGPO](backup-psgpo.md)
- [Toutes les commandes](../commands.md)
