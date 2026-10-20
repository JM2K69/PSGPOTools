# New-PSGPOLink

Links GPOs to the domain or to an OU, as GPMC "Link an Existing GPO".

_L'aide de la commande, telle que `Get-Help New-PSGPOLink -Full` la donne (en anglais)._

## Syntaxe

```powershell
New-PSGPOLink [-Name] <string[]> [-Target] <string> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Enforced] [-Disabled] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The link has the lowest precedence (the last link order), like in GPMC. It is written to the gPLink of the domain or OU in one LDAP request that also removes the value read, so that a link someone else added meanwhile is never lost: the change is refused instead.

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

### -Enforced

Enforces the link: the GPO applies even where the inheritance is blocked.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Disabled

Creates the link disabled.

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
New-PSGPOLink -Name 'C - Servers - Baseline' -Target 'OU=Servers,DC=contoso,DC=com'
```

## Sorties

- `PSGPOTools.Link`

## Voir aussi

- [Set-PSGPOLink](set-psgpolink.md)
- [Remove-PSGPOLink](remove-psgpolink.md)
- [Toutes les commandes](../commands.md)
