# Initialize-PSGPOWorkflow

Delegates the creation of GPOs to the creators of the approval workflow, and checks it.

_L'aide de la commande, telle que `Get-Help Initialize-PSGPOWorkflow -Full` la donne (en anglais)._

## Syntaxe

```powershell
Initialize-PSGPOWorkflow [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [-Apply] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The approval workflow (Workflow in the configuration of the domain: Get-PSGPOConfiguration) lets the creators (Tier 1 groups) create GPOs that wait for the approval of an approver (Tier 0). They need two rights, and not Group Policy Creator Owners, which would let them create GPOs outside the workflow:

- in the directory, CN=Policies,CN=System: create groupPolicyContainer objects; the
creator owns the GPO it creates and gets full control of it (CREATOR OWNER of the
class), until it is approved;
- in SYSVOL, the Policies folder: list, read and create folders (this folder only), and
CREATOR OWNER full control of the folders and files it creates.

Without -Apply, it says what is there and what is missing; with it, an administrator of the domain adds what is missing. One row per right: Target, Account, Right, State (Present, Added or Missing). Run it again after samba-tool ntacl sysvolreset, which gives SYSVOL its default ACL back.

## Paramètres

### -Apply

Adds the rights that are missing.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 1 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

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
Initialize-PSGPOWorkflow -Server dc1.contoso.com
```

### Exemple 2

```powershell
Initialize-PSGPOWorkflow -Apply
```

## Sorties

- `System.Management.Automation.PSObject`

## Voir aussi

- [Approve-PSGPO](approve-psgpo.md)
- [Get-PSGPOConfiguration](get-psgpoconfiguration.md)
- [Toutes les commandes](../commands.md)
