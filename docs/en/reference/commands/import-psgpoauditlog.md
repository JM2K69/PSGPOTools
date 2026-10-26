# Import-PSGPOAuditLog

Moves the changes of an audit log of a console into the central audit log of the domain.

_The help of the command, as `Get-Help Import-PSGPOAuditLog -Full` gives it._

## Syntax

```powershell
Import-PSGPOAuditLog -Path <string> [-Destination <string>] [-Remove] [-Server <string>] [-Credential <pscredential>] [-WhatIf] [-Confirm] [<CommonParameters>]
Import-PSGPOAuditLog -Path <string> -Directory <GPOToolsLdapDirectory> [-Destination <string>] [-Remove] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

Before the central log (Audit.Path), each console wrote its changes in the folder Audit of the backups of its account. Import-PSGPOAuditLog adds them to the central log as the consoles write it now: each change in a file of its account, of its computer and of its month, in the folder of the tier of the account (read in its groups, as for a change made now; an account the domain does not know goes to Unassigned). The file is named ...-imported.jsonl: the account that runs the import owns it, and each account writes only the files it made.

It can run again: a change already in the central log (same time, account, action and target) is not written twice. With -Remove, the files read are deleted once their changes are written. Run it with an account that writes every tier (an administrator of the domain), as the files go in the folders of the accounts that made the changes.

## Parameters

### -Path

The folder of the log to import (the folder Audit of the backups of an account).

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | Yes | Named | None | No |

### -Destination

The central log: Audit.Path of the configuration of the domain by default.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Remove

Deletes the files read, once their changes are in the central log.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Directory

The domain (Get-PSGPODirectory), already read: its configuration gives the central log and the tiers.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsLdapDirectory` | Yes | Named | None | No |

### -Server

Domain controller to read the domain from. By default, the domain of the computer.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | Named | None | No |

### -Credential

Account to read the domain with, instead of the current identity.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `PSCredential` | No | Named | None | No |

### -WhatIf

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Confirm

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

## Examples

### Example 1

```powershell
Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -WhatIf
```

### Example 2

```powershell
Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -Server dc.hardenbox.labo -Remove
```

## Outputs

- `PSGPOTools.AuditImport`

## Related

- [Initialize-PSGPOAuditShare](initialize-psgpoauditshare.md)
- [Get-PSGPOAuditLog](get-psgpoauditlog.md)
- [All the commands](../commands.md)
