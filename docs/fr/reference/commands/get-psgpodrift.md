# Get-PSGPODrift

Finds the GPOs changed since their approved version.

_L'aide de la commande, telle que `Get-Help Get-PSGPODrift -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPODrift [-Path] <string> [[-Name] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [[-Label] <string>] [-IncludePermissions] [<CommonParameters>]
```

## Description

The approved version of a GPO is its newest backup with the approved label of the configuration (Backup.ApprovedLabel, 'Approved' by default: Backup-PSGPO -Approve, Set-PSGPOBackup -Approve, or the History tab). Each GPO, as it is now, is compared to it setting by setting, as Compare-PSGPOBackup does: what changed since, in the console or elsewhere (GPMC, samba-tool, a script), is its drift.

State of each GPO: InSync (it is its approved version), Drifted (Changes: what changed since, Added, Removed or Changed with the value before and after), or NotApproved (no approved version yet).

With -IncludePermissions, its owner and its permissions are compared too, as the Delegation tab lists them (Path Permissions: each account by its SID, its level, denied or inherited): an account added, removed or given another level since the approval, another owner. A backup keeps them since HGPM 0.1.26: when the approved version is older, Permissions says NotRecorded, and the permissions are not compared (approve the GPO again to record them).

## Paramètres

### -Path

Root folder of the backups (Backup-PSGPO).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Name

Display names of the GPOs (wildcards allowed); all the GPOs by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 2 | Aucune | Oui |

### -Directory

Directory of the GPOs (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 3 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

### -Label

Label of the approved versions, instead of the one of the configuration.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

### -IncludePermissions

Compares the owner and the permissions of each GPO to those of its approved version too.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
```

### Exemple 2

```powershell
# Who was given rights on a GPO since its approval
(Get-PSGPODrift -Path /srv/gpo-backups -IncludePermissions).Changes | Where-Object Path -EQ 'Permissions' | Format-Table Change, Name, Before, After
```

### Exemple 3

```powershell
(Get-PSGPODrift -Path D:\GPO_Backup -Name 'Default Domain Policy').Changes | Format-Table Change, Path, Name, Before, After
```

## Sorties

- `PSGPOTools.Drift`

## Voir aussi

- [Backup-PSGPO](backup-psgpo.md)
- [Set-PSGPOBackup](set-psgpobackup.md)
- [Toutes les commandes](../commands.md)
