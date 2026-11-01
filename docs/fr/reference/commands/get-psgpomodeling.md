# Get-PSGPOModeling

Models the GPOs a computer and a user would apply, as Group Policy Modeling of GPMC, from the directory alone.

_L'aide de la commande, telle que `Get-Help Get-PSGPOModeling -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOModeling [[-Computer] <string>] [[-ComputerGroup] <string[]>] [[-User] <string>] [[-UserGroup] <string[]>] [[-Site] <string>] [[-Loopback] <string>] [[-FalseWmiFilter] <string[]>] [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

The links of the site, of the domain and of the OUs above the computer and the user, in the order Windows applies them: the enforced links from the site down, the others from the OU up to an OU that blocks the inheritance. Each GPO is Applied, with its precedence (1 wins), or denied, with its reason: Disabled link, Disabled GPO (that part disabled by its status), Denied (security), Not applied (security filtering), Inaccessible (the computer cannot read a user GPO, MS16-072), WMI filter not found, WMI filter false, Empty (no settings in that part: its version is 0, or no client-side extension declares it), Not found (a GPO of another domain).

The security filtering is checked against the token of the account: its SID and its groups, the nested ones included (tokenGroups), Everyone and Authenticated Users. For the domain or an OU in place of an account (a container, as GPMC allows it), the token is the group of every computer or user of the domain and the groups given. A directory in memory (Import-PSGPODirectory) has no accounts: containers only. The WMI filters are not run: assumed true, but those given false. Loopback processing comes from the computer GPOs applied (Configure user Group Policy loopback processing mode), or is given: Merge adds the user GPOs of the computer after those of the user, Replace takes them alone.

## Paramètres

### -Computer

The computer: its name, its distinguished name, or the domain or an OU (a container).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

### -ComputerGroup

Groups the computer is in, for a container (or added to the groups of an account).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 2 | `@()` | Non |

### -User

The user: its name (DOMAIN\name or name), its distinguished name, or the domain or an OU.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

### -UserGroup

Groups the user is in, for a container (or added to the groups of an account).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 4 | `@()` | Non |

### -Site

The site of the computer (its name): its GPOs apply before those of the domain.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 5 | Aucune | Non |

### -Loopback

Loopback processing, in place of what the computer GPOs set: None, Merge or Replace.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 6 | Aucune | Non |

### -FalseWmiFilter

Names of the WMI filters that would be false on the computer: the GPOs that use them are denied.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 7 | `@()` | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 8 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 9 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOModeling -Computer 'PC-LYON-042' -User 'CONTOSO\jdoe' -Site 'Lyon-Site'
```

### Exemple 2

```powershell
(Get-PSGPOModeling -Computer 'OU=Kiosks,OU=Workstations,DC=contoso,DC=com' -ComputerGroup 'APPLY_C - Kiosks').ComputerGpos | Format-Table Precedence, Name, Link, Reason
```

## Sorties

- `PSGPOTools.Modeling`

## Voir aussi

- [Get-PSGPOInheritance](get-psgpoinheritance.md)
- [Toutes les commandes](../commands.md)
