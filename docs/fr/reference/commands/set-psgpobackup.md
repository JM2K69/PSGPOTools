# Set-PSGPOBackup

Changes the comment and the labels of a backup of a GPO.

_L'aide de la commande, telle que `Get-Help Set-PSGPOBackup -Full` la donne (en anglais)._

## Syntaxe

```powershell
Set-PSGPOBackup [-Backup] <Backup> [[-Comment] <string>] [[-AddLabel] <string[]>] [[-RemoveLabel] <string[]>] [-Approve] [-Unapprove] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The notes of a backup (Get-PSGPOBackup) are kept beside it, in notes.json: its comment and its labels, with who changed them and when. The files of the backup and its manifest do not change. The approved label of the configuration (Backup.ApprovedLabel, or -Approve) makes the backup the approved version of the GPO, to which Get-PSGPODrift compares it.

## Paramètres

### -Backup

The backup (Get-PSGPOBackup).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object` | Oui | 1 | Aucune | Oui |

### -Comment

The new comment of the backup; an empty string removes it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -AddLabel

Labels to add.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 3 | Aucune | Non |

### -RemoveLabel

Labels to remove (case ignored).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 4 | Aucune | Non |

### -Approve

Adds the approved label of the configuration.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Unapprove

Removes the approved label of the configuration.

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
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy' | Select-Object -First 1 |
    Set-PSGPOBackup -Approve -Comment 'Reviewed with the security team'
```

## Sorties

- `PSGPOTools.Backup`

## Voir aussi

- [Get-PSGPOBackup](get-psgpobackup.md)
- [Get-PSGPODrift](get-psgpodrift.md)
- [Toutes les commandes](../commands.md)
