# Invoke-PSGPOUpdate

Has computers apply their GPOs now, as Group Policy Update of GPMC and gpupdate.

_L'aide de la commande, telle que `Get-Help Invoke-PSGPOUpdate -Full` la donne (en anglais)._

## Syntaxe

```powershell
Invoke-PSGPOUpdate [[-ComputerName] <string[]>] [[-Target] <string>] [[-User] <string>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Windows: gpupdate on this computer; on other computers (-ComputerName), Invoke-GPUpdate of RSAT when it is there, as GPMC does (a scheduled task on the computer, for it and for each user logged on), else gpupdate through PowerShell remoting (the computer part, and the user of the remote session). Linux, a member of a domain: samba-gpupdate, which applies the policy with the machine account: root only (sudo pwsh); the user part for the user given. -Force applies every setting again, not only those of the GPOs that changed.

## Paramètres

### -ComputerName

The computers, on Windows; this computer when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 1 | Aucune | Non |

### -Target

Computer, User or All (default): the parts to apply.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | `All` | Non |

### -User

On Linux, the user whose part is applied (samba-gpupdate -U).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -Force

Every setting applied again (gpupdate /force, samba-gpupdate --force).

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
Invoke-PSGPOUpdate -Target Computer -Force
```

### Exemple 2

```powershell
Invoke-PSGPOUpdate -ComputerName PC-LYON-041, PC-LYON-042
```

## Sorties

- `PSGPOTools.UpdateResult`

## Voir aussi

- [Get-PSGPOResult](get-psgporesult.md)
- [Toutes les commandes](../commands.md)
