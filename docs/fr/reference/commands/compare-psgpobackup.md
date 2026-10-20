# Compare-PSGPOBackup

Shows what changed between two backups of a GPO, setting by setting.

_L'aide de la commande, telle que `Get-Help Compare-PSGPOBackup -Full` la donne (en anglais)._

## Syntaxe

```powershell
Compare-PSGPOBackup [-ReferenceBackup] <Backup> [-DifferenceBackup] <Backup> [<CommonParameters>]
```

## Description

Compares the settings of two backups (Get-PSGPOBackup) as the Settings tab shows them: the policies of the Registry.pol files by category path (with the ADMX files loaded by Initialize-PSGPOAdmx; otherwise as extra registry values), the security settings (GptTmpl.inf), the other files of the GPO by their content, and its name, status, security filtering and links. Each change is Added, Removed or Changed, with the value before and after.

## Paramètres

### -ReferenceBackup

The older backup.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object` | Oui | 1 | Aucune | Non |

### -DifferenceBackup

The newer backup.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object` | Oui | 2 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
$Backups = Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
Compare-PSGPOBackup -ReferenceBackup $Backups[1] -DifferenceBackup $Backups[0]
```

## Sorties

- `PSGPOTools.SettingChange`

## Voir aussi

- [Backup-PSGPO](backup-psgpo.md)
- [Toutes les commandes](../commands.md)
