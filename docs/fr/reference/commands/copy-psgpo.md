# Copy-PSGPO

Copies a GPO into a new GPO of its domain, as Copy and Paste of GPMC: its settings, status, client-side extensions, WMI filter and comment; not its links.

_L'aide de la commande, telle que `Get-Help Copy-PSGPO -Full` la donne (en anglais)._

## Syntaxe

```powershell
Copy-PSGPO [-Name] <string> [-TargetName] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-CopyAcl] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The new GPO gets the files of the folder of the GPO in SYSVOL (its settings and its comment), its status, the client-side extensions it declares and its WMI filter. Its links are not copied: link the copy where it applies (New-PSGPOLink). Its permissions are those of a new GPO, as GPMC gives by default; -CopyAcl gives it those of the GPO instead (Preserve the existing permissions, in GPMC), but the ones a level of permission cannot give (denied, custom), which are said. With the approval workflow, the copy of a creator waits for its approval as any new GPO, and the approval gives its security filtering: -CopyAcl is refused to a creator.

## Paramètres

### -Name

Display name of the GPO to copy (one GPO).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -TargetName

Display name of the new GPO.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 2 | Aucune | Non |

### -CopyAcl

The permissions of the GPO copied, not those of a new GPO.

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
Copy-PSGPO -Name 'C - Workstations - BitLocker' -TargetName 'C - Laptops - BitLocker'
```

### Exemple 2

```powershell
Copy-PSGPO -Name 'C - Servers - Baseline' -TargetName 'C - Servers - Baseline (test)' -CopyAcl
```

## Sorties

- `GPOToolsGpo`

## Voir aussi

- [New-PSGPOLink](new-psgpolink.md)
- [Toutes les commandes](../commands.md)
