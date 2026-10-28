# Initialize-PSGPOWorkflow

Delegates the creation of GPOs to the creators of the approval workflow, and checks it.

_The help of the command, as `Get-Help Initialize-PSGPOWorkflow -Full` gives it._

## Syntax

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

The central store (Policies\PolicyDefinitions, the ADMX files every console reads) must exist before: a creator that creates folders in Policies could create it, and own it. It is not created here, as an empty central store hides the administrative templates of GPMC: create it with Install-PSGPOAdmx -CentralStore, or a copy of a PolicyDefinitions folder. Without it, -Apply changes nothing and stops with an error that says why; when the creators create folders already, it warns. Its last row says whether the Tier 0 owns it.

Without -Apply, it says what is there and what is missing; with it, an administrator of the domain adds what is missing. One row per right: Target, Account, Right, State (Present, Added or Missing). Run it again after samba-tool ntacl sysvolreset, which gives SYSVOL its default ACL back.

## Parameters

### -Apply

Adds the rights that are missing.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `SwitchParameter` | No | Named | None | No |

### -Directory

Directory of the domain (Get-PSGPODirectory); the domain is read when not given.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `GPOToolsDirectory` | No | 1 | None | No |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Required | Position | Default value | Accepts pipeline input |
|---|---|---|---|---|
| `String` | No | 2 | None | No |

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
Initialize-PSGPOWorkflow -Server dc1.contoso.com
```

### Example 2

```powershell
Initialize-PSGPOWorkflow -Apply
```

## Outputs

- `System.Management.Automation.PSObject`

## Related

- [Approve-PSGPO](approve-psgpo.md)
- [Get-PSGPOConfiguration](get-psgpoconfiguration.md)
- [Test-PSGPOSecurityPosture](test-psgposecurityposture.md)
- [All the commands](../commands.md)
