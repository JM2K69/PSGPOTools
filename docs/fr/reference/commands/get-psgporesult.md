# Get-PSGPOResult

Gets what a computer and a user applied the last time, as Group Policy Results of GPMC.

_L'aide de la commande, telle que `Get-Help Get-PSGPOResult -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOResult [[-ComputerName] <string>] [[-User] <string>] [[-Scope] <string>] [[-Path] <string>] [<CommonParameters>]
```

## Description

The RSoP the computer logged: the GPOs of each part, applied with their precedence (1 wins) or denied with their reason (Disabled link, Disabled GPO, Denied (security), Empty, WMI filter false, Not valid), where they are linked; with gpresult, the security groups of the computer and the user, their SOM and site, the status of each client-side extension.

Windows: gpresult /x, on this computer or another one (-ComputerName; its firewall lets RSoP through), for the user given or the one running it; the computer part needs an administrator. Linux, a member of a domain: samba-gpupdate --rsop, which reads the policy with the machine account: root only (sudo pwsh); it also gives the settings of each GPO. -Path reads a file made elsewhere: the XML of gpresult /x, or what samba-gpupdate --rsop printed.

## Paramètres

### -ComputerName

The computer, on Windows (gpresult /s); this computer when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

### -User

The user (DOMAIN\name): gpresult /user, samba-gpupdate -U; the one running it when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

### -Scope

Computer, User or All (default).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | `All` | Non |

### -Path

A file to read in place of running gpresult or samba-gpupdate: the XML of gpresult /x, or the output of samba-gpupdate --rsop (one part: -Scope says which, Computer by default).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 4 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOResult | Select-Object -ExpandProperty ComputerGpos | Format-Table Precedence, Name, Link, Reason
```

### Exemple 2

```powershell
Get-PSGPOResult -ComputerName PC-LYON-042 -User 'CONTOSO\jdoe'
```

### Exemple 3

```powershell
Get-PSGPOResult -Path ./rsop-computer.txt -Scope Computer
```

## Sorties

- `PSGPOTools.Result`

## Voir aussi

- [Get-PSGPOModeling](get-psgpomodeling.md)
- [Invoke-PSGPOUpdate](invoke-psgpoupdate.md)
- [Toutes les commandes](../commands.md)
