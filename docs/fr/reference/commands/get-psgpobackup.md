# Get-PSGPOBackup

Lists the backups of GPOs written by Backup-PSGPO, newest first.

_L'aide de la commande, telle que `Get-Help Get-PSGPOBackup -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOBackup [-Path] <string> [[-Name] <string>] [[-Id] <guid>] [[-Label] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Approved] [-Template] [-Deleted] [<CommonParameters>]
```

## Paramètres

### -Path

Root folder of the backups.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Name

Display name of the GPO (wildcards allowed), as it was when backed up.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | `*` | Non |

### -Id

GUID of the GPO: its backups even when it was renamed.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Guid` | Non | 3 | `[guid]::Empty` | Non |

### -Label

Only the backups with this label (wildcards allowed).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

### -Approved

Only the backups with the approved label of the configuration.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Template

Only the templates of new GPOs: the backups with the template label of the configuration.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Deleted

The recycle bin: the newest backup of each GPO of the domain that is not in it anymore (and was not created again since). Reads the domain, or uses -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Directory

With -Deleted: the directory of the domain (Get-PSGPODirectory).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 5 | Aucune | Non |

### -Server

With -Deleted: the domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 6 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
```

### Exemple 2

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Approved | Select-Object DisplayName, BackedUp, Comment
```

### Exemple 3

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted | Restore-PSGPO -RestoreLink
```

## Sorties

- `PSGPOTools.Backup`

## Voir aussi

- [Backup-PSGPO](backup-psgpo.md)
- [Compare-PSGPOBackup](compare-psgpobackup.md)
- [Toutes les commandes](../commands.md)
