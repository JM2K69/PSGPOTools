# Remove-PSGPO

Deletes GPOs of the domain, backed up first: they stay in the recycle bin.

_L'aide de la commande, telle que `Get-Help Remove-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
Remove-PSGPO [-Name] <string[]> [[-BackupPath] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-NoBackup] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Like GPMC "Delete": the links of the GPO in the domain are deleted first (the GPO is not deleted when the account cannot delete one of them), then the GPO, its container in the directory and its folder in SYSVOL (on Windows with Remove-GPO of RSAT, on Linux with samba-tool and Kerberos). The Default Domain Policy and the Default Domain Controllers Policy are never deleted.

Each GPO is backed up first in -BackupPath (unless -NoBackup), and its last backup says when and by whom it was deleted: Get-PSGPOBackup -Deleted lists it, Restore-PSGPO creates it again.

## Paramètres

### -Name

Display names of the GPOs to delete (wildcards allowed).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -BackupPath

Root folder of the backups; by default the one of the History tab of the window.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -NoBackup

Does not back up the GPOs before deleting them: they cannot be created again.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 3 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

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
Remove-PSGPO -Name 'U - Lyon - Printers' -BackupPath /srv/gpo-backups
```

## Sorties

- `PSGPOTools.RemovedGpo`

## Voir aussi

- [Get-PSGPOBackup](get-psgpobackup.md)
- [Restore-PSGPO](restore-psgpo.md)
- [Toutes les commandes](../commands.md)
