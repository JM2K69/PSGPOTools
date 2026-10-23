# Remove-PSGPOBackup

Deletes for good a GPO of the recycle bin: all its backups.

_L'aide de la commande, telle que `Get-Help Remove-PSGPOBackup -Full` la donne (en anglais)._

## Syntaxe

```powershell
Remove-PSGPOBackup [-Backup] <Backup> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

A GPO deleted from the domain stays in the recycle bin (Get-PSGPOBackup -Deleted) as long as its backups are in the folder: Remove-PSGPOBackup deletes every backup of its GUID in the folder of the backup given, made before or after a rename, the templates made from it too. It cannot be restored afterwards.

The backups of a GPO that is still in the domain are its history: they are not deleted, nor those of another domain.

## Paramètres

### -Backup

A backup of the deleted GPO (Get-PSGPOBackup -Deleted).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object` | Oui | 1 | Aucune | Oui |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 2 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

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
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted -Name 'U - Lyon - Printers' | Remove-PSGPOBackup
```

## Sorties

- `PSGPOTools.RemovedBackup`

## Voir aussi

- [Get-PSGPOBackup](get-psgpobackup.md)
- [Restore-PSGPO](restore-psgpo.md)
- [Toutes les commandes](../commands.md)
