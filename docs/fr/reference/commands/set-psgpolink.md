# Set-PSGPOLink

Enables, disables, enforces or moves the links of GPOs, as GPMC does on a link.

_L'aide de la commande, telle que `Get-Help Set-PSGPOLink -Full` la donne (en anglais)._

## Syntaxe

```powershell
Set-PSGPOLink [-Name] <string[]> [-Target] <string> [[-Enabled] <bool>] [[-Enforced] <bool>] [[-Order] <int>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Like the Link Enabled and Enforced items of a link in GPMC, and the arrows of its Linked Group Policy Objects tab. The change is written to the gPLink of the domain or OU, refused when the links changed in the domain meanwhile.

## Paramètres

### -Name

Display names of the GPOs (* and ? make a pattern).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -Target

The domain or the OU: its distinguished name, the name of the domain, or the name of an OU when only one OU has it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 2 | Aucune | Non |

### -Enabled

$true enables the link, $false disables it: the GPO no longer applies there.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Nullable`1` | Non | 3 | Aucune | Non |

### -Enforced

$true enforces the link (the GPO applies even where the inheritance is blocked, and wins over the GPOs linked below), $false no longer does.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Nullable`1` | Non | 4 | Aucune | Non |

### -Order

The link order to move the link to: 1 is the highest precedence.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Int32` | Non | 5 | `0` | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 6 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 7 | Aucune | Non |

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
Set-PSGPOLink -Name 'C - Servers - Baseline' -Target Servers -Enforced $true -Order 1
```

### Exemple 2

```powershell
# Disable a link for a while, without deleting it
Set-PSGPOLink -Name 'U - Lyon - Printers' -Target Lyon -Enabled $false
```

## Sorties

- `PSGPOTools.Link`

## Voir aussi

- [New-PSGPOLink](new-psgpolink.md)
- [Toutes les commandes](../commands.md)
