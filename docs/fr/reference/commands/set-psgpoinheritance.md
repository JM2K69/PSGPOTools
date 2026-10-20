# Set-PSGPOInheritance

Blocks the inheritance of the domain or of an OU, or not, as GPMC "Block Inheritance".

_L'aide de la commande, telle que `Get-Help Set-PSGPOInheritance -Full` la donne (en anglais)._

## Syntaxe

```powershell
Set-PSGPOInheritance [-Target] <string> [-Blocked] <bool> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Where the inheritance is blocked, the GPOs linked to the parents no longer apply, but for the enforced links. It is bit 0 of the gPOptions of the domain or OU, written only if it did not change meanwhile.

## Paramètres

### -Target

The domain or the OU: its distinguished name, the name of the domain, or the name of an OU when only one OU has it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Oui | 1 | Aucune | Non |

### -Blocked

$true blocks the inheritance, $false no longer does.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `Boolean` | Oui | 2 | Aucune | Non |

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
Set-PSGPOInheritance -Target 'OU=Kiosks,DC=contoso,DC=com' -Blocked $true
```

## Voir aussi

- [Toutes les commandes](../commands.md)
