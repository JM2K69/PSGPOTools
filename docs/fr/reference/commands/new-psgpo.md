# New-PSGPO

Creates a GPO in the domain, empty or from a template.

_L'aide de la commande, telle que `Get-Help New-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
New-PSGPO [-Name] <string> [[-Template] <Backup>] [[-Status] <string>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Like GPMC "New GPO": the GPO is created in the domain (on Windows with New-GPO of RSAT, on Linux with samba-tool and Kerberos), not linked. With -Template, it starts with the settings of a backup (Get-PSGPOBackup -Template: the backups with the template label of the configuration, Backup.TemplateLabel), whatever GPO or domain it comes from: its files, checked against their SHA-256, and their client-side extensions.

## Paramètres

### -Name

Display name of the new GPO.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Template

Backup whose settings the GPO starts with.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Object` | Non | 2 | Aucune | Non |

### -Status

GPO status: Enabled (default), ComputerOnly (user settings disabled) or UserOnly (computer settings disabled).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | `Enabled` | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 4 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

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
New-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
```

### Exemple 2

```powershell
$Template = Get-PSGPOBackup -Path /srv/gpo-backups -Template -Name 'Template - Servers' | Select-Object -First 1
New-PSGPO -Name 'C - Servers - Lyon' -Template $Template
```

## Sorties

- `GPOToolsGpo`

## Voir aussi

- [Remove-PSGPO](remove-psgpo.md)
- [Get-PSGPOBackup](get-psgpobackup.md)
- [Toutes les commandes](../commands.md)
