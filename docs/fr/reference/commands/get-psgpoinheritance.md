# Get-PSGPOInheritance

The GPOs linked to the domain or to an OU, and those that apply there by inheritance, as the Linked Group Policy Objects and Group Policy Inheritance tabs of GPMC (Get-GPInheritance).

_L'aide de la commande, telle que `Get-Help Get-PSGPOInheritance -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOInheritance [-Target] <string[]> [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

One object per domain or OU: Name, ContainerType (Domain, OrganizationalUnit), Path (its distinguished name), GpoInheritanceBlocked, and:

- GpoLinks: the links of the domain or OU, by link order (1 wins): Order, DisplayName,
GpoId, Enabled, Enforced, Target;
- InheritedGpoLinks: the GPOs that apply there, by precedence (1 wins), as the Group Policy
Inheritance tab lists them: first the enforced links, from the domain down (the one
nearest the domain wins), then the other links, from the domain or OU up to the domain,
until an OU that blocks the inheritance (its own links included). Precedence,
DisplayName, GpoId, Enforced, Status (a GPO whose settings are all disabled is listed
with it), Target (where it is linked). The disabled links are left out.

The security filtering and the WMI filters, which depend on each computer or user, are not taken into account; neither are the links of the sites.

## Paramètres

### -Target

The domain or the OU: its distinguished name, the name of the domain, or the name of an OU when only one OU has it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Oui | 1 | Aucune | Oui |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 2 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 3 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
(Get-PSGPOInheritance -Target 'OU=Workstations,OU=Tier 2,DC=contoso,DC=com').InheritedGpoLinks | Format-Table Precedence, DisplayName, Enforced, Target
```

### Exemple 2

```powershell
Get-PSGPOInheritance -Target contoso.com | Select-Object -ExpandProperty GpoLinks
```

## Sorties

- `PSGPOTools.GpoInheritance`

## Voir aussi

- [Set-PSGPOLink](set-psgpolink.md)
- [Set-PSGPOInheritance](set-psgpoinheritance.md)
- [Toutes les commandes](../commands.md)
