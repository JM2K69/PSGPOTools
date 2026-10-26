# Register-PSGPOEventSource

Registers the event source HGPM in the Windows event log of this computer, once.

_The help of the command, as `Get-Help Register-PSGPOEventSource -Full` gives it._

## Syntax

```powershell
Register-PSGPOEventSource [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Description

The consoles send each change of the audit log and each error of their technical log to the log of the system (Log.SystemLog of the configuration), for a SIEM: on Windows, the Application event log, source HGPM, an event ID per action. Only an administrator creates an event source: run Register-PSGPOEventSource once per computer, in PowerShell run as an administrator (a deployment script, a GPO startup script). Until then, the consoles of the computer write nothing to the event log, and say so in their technical log.

On Linux there is nothing to register: the consoles send their events to syslog/journald with logger (tag hgpm), as any account may.

## Parameters

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
Register-PSGPOEventSource
```

### Example 2

```powershell
# The events of HGPM, newest first
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'HGPM' } -MaxEvents 20
```

## Outputs

- `PSGPOTools.EventSource`

## Related

- [Invoke-PSGPOAuditRetention](invoke-psgpoauditretention.md)
- [All the commands](../commands.md)
