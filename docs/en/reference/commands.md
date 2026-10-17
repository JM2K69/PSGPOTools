# Commands

`Get-Help <command> -Full` gives the help of each one, with its examples. The commands that change
the domain support `-WhatIf` and `-Confirm`.

## The domain

| Command | Does |
|---|---|
| `Get-PSGPODirectory [-Server] [-Credential] [-UseSsl] [-Port]` | reads the domain over LDAP: its OUs, GPOs, links, the rights of the account, the configuration of the domain and its approval workflow |
| `Import-PSGPODirectory -Path` | reads a domain from a JSON description (offline, demonstrations, tests) |
| `Show-GPOManagerAvalonia [-Server] [-Credential] [-UseSsl] [-Directory] [-NoDirectory] [-PolicyDefinitions] [-UICulture]` | opens the console |
| `Get-PSGPOConfiguration [-Directory] [-Server]` | the configuration in use, and where it comes from |

## GPOs

| Command | Does |
|---|---|
| `New-PSGPO -Name [-Template] [-Status Enabled\|ComputerOnly\|UserOnly]` | creates a GPO, empty or from a template |
| `Remove-PSGPO -Name [-BackupPath] [-NoBackup]` | deletes GPOs and their links, backed up first |
| `Approve-PSGPO -Name [-CreatorRights ReadOnly\|EditSettings] [-ApplyTo] [-DenyTo] [-CreateFilteringGroups] [-GroupContainer] [-BackupPath]` | approves GPOs waiting for their approval, with their security filtering (and its groups) |
| `Initialize-PSGPOWorkflow [-Apply]` | checks, and with `-Apply` sets, the delegation of the creation of GPOs to the creators |

A name given with `-Name` is the name of the GPO, brackets included (`Servers [Lyon]`); with `*` or `?` it is a wildcard pattern. Two GPOs with the same name are each taken.

`-Directory` (from `Get-PSGPODirectory`) or `-Server` gives the domain to each of them; without
them, the domain of the computer is read.

```powershell
$Directory = Get-PSGPODirectory -Server dc.hardenbox.labo
New-PSGPO -Directory $Directory -Name 'T1 - Servers - Proxy' -Status ComputerOnly
Approve-PSGPO -Directory $Directory -Name 'T1 - Servers - Proxy' -ApplyTo 'APPLY_T1 - Servers - Proxy'
```

## Backups

| Command | Does |
|---|---|
| `Backup-PSGPO -Path [-Name] [-Comment] [-Label] [-Approve] [-Force]` | backs up the GPOs that changed since their last backup |
| `Get-PSGPOBackup -Path [-Name] [-Id] [-Label] [-Approved] [-Template] [-Deleted]` | lists the backups, newest first; `-Deleted`: the recycle bin |
| `Compare-PSGPOBackup -ReferenceBackup -DifferenceBackup` | what changed between two backups, setting by setting |
| `Restore-PSGPO -Backup [-NoBackup] [-RestoreLink]` | puts a GPO back as a backup has it, or creates a deleted GPO again |
| `Set-PSGPOBackup -Backup [-Comment] [-AddLabel] [-RemoveLabel] [-Approve] [-Unapprove]` | changes the notes of a backup |
| `Get-PSGPODrift -Path [-Name] [-Label]` | compares each GPO to its approved version: `InSync`, `Drifted`, `NotApproved` |

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Comment 'Nightly'
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted' | ForEach-Object Changes
```

## Administrative templates

| Command | Does |
|---|---|
| `Initialize-PSGPOAdmx -Path [-UICulture]` | loads the ADMX and ADML files of a folder (local PolicyDefinitions or the central store) |
| `Get-PSGPOPolicy [-Scope Machine\|User]` | the policies loaded |
| `Get-PSGPOCategory` | their categories |
| `Get-PSGPOSupportedOn` | the platforms they support |

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions -UICulture en-US
Get-PSGPOPolicy -Scope Machine | Where-Object DisplayName -Like '*biometrics*' | Select-Object DisplayName, Registry
```

## What they return

| Type | From | Main properties |
|---|---|---|
| `GPOToolsDirectory` | `Get-PSGPODirectory`, `Import-PSGPODirectory` | `DomainName`, `Domain`, `Gpos`, `Account`, `CanCreateGpo`, `Workflow` |
| `GPOToolsGpo` | `.Gpos`, `New-PSGPO` | `DisplayName`, `Id`, `Version`, `Flags`, `SecurityFiltering`, `DeniedTo`, `CanEdit`, `Owner`, `ApprovalState`, `RemovedAtApproval` |
| `PSGPOTools.Backup` | `Backup-PSGPO`, `Get-PSGPOBackup` | `Path`, `Id`, `DisplayName`, `BackedUp`, `BackedUpBy`, `Modified`, `Comment`, `Labels`, `Files` |
| `PSGPOTools.SettingChange` | `Compare-PSGPOBackup`, `Get-PSGPODrift` | `Change`, `Scope`, `Path`, `Name`, `Before`, `After` |
| `PSGPOTools.Drift` | `Get-PSGPODrift` | `DisplayName`, `State`, `Approved`, `ApprovedBy`, `Changes` |
| `PSGPOTools.Restore` | `Restore-PSGPO` | `DisplayName`, `Id`, `Version`, `BackupBefore`, `CreatedAgain`, `Linked`, `Problems` |
| `PSGPOTools.Approval` | `Approve-PSGPO` | `DisplayName`, `Owner`, `CreatedBy`, `CreatorRights`, `AppliedBy`, `DeniedTo`, `GroupsCreated`, `RemovedPermissions`, `Backup` |
