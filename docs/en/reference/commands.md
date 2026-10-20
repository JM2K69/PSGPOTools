# Commands

Each command has its page, its help with its parameters and examples: click its name.
`Get-Help <command> -Full` gives the same help in PowerShell, and `Get-Help <command> -Online` opens its
page. The commands that change the domain support `-WhatIf` and `-Confirm`.

## The domain

| Command | Does |
|---|---|
| [`Get-PSGPODirectory`](commands/get-psgpodirectory.md) `[-Server] [-Credential] [-UseSsl] [-Port]` | reads the domain over LDAP: its OUs, GPOs, links, the rights of the account, the configuration of the domain and its approval workflow |
| [`Import-PSGPODirectory`](commands/import-psgpodirectory.md) `-Path` | reads a domain from a JSON description (offline, demonstrations, tests) |
| [`Show-GPOManagerAvalonia`](commands/show-gpomanageravalonia.md) `[-Server] [-Credential] [-UseSsl] [-Directory] [-NoDirectory] [-PolicyDefinitions] [-UICulture] [-Language]` | opens the console |
| [`Get-PSGPOConfiguration`](commands/get-psgpoconfiguration.md) `[-Directory] [-Server]` | the configuration in use, and where it comes from |

## GPOs

| Command | Does |
|---|---|
| [`New-PSGPO`](commands/new-psgpo.md) `-Name [-Template] [-Status Enabled\|ComputerOnly\|UserOnly]` | creates a GPO, empty or from a template |
| [`Remove-PSGPO`](commands/remove-psgpo.md) `-Name [-BackupPath] [-NoBackup]` | deletes GPOs and their links, backed up first |
| [`Approve-PSGPO`](commands/approve-psgpo.md) `-Name [-CreatorRights ReadOnly\|EditSettings] [-ApplyTo] [-DenyTo] [-CreateFilteringGroups] [-GroupContainer] [-BackupPath]` | approves GPOs waiting for their approval, with their security filtering (and its groups) |
| [`Initialize-PSGPOWorkflow`](commands/initialize-psgpoworkflow.md) `[-Apply]` | checks, and with `-Apply` sets, the delegation of the creation of GPOs to the creators |
| [`New-PSGPOLink`](commands/new-psgpolink.md) `-Name -Target [-Enforced] [-Disabled]` | links GPOs to the domain or an OU, with the lowest precedence |
| [`Set-PSGPOLink`](commands/set-psgpolink.md) `-Name -Target [-Enabled] [-Enforced] [-Order]` | enables, disables, enforces or moves links |
| [`Remove-PSGPOLink`](commands/remove-psgpolink.md) `-Name -Target` | deletes links, the GPOs kept |
| [`Set-PSGPOInheritance`](commands/set-psgpoinheritance.md) `-Target -Blocked` | blocks the inheritance of the domain or an OU, or not |
| [`Set-PSGPO`](commands/set-psgpo.md) `-Name [-Status Enabled\|ComputerOnly\|UserOnly\|Disabled] [-WmiFilter] [-NoWmiFilter]` | sets the status and the WMI filter of GPOs |
| [`Get-PSGPOPermission`](commands/get-psgpopermission.md) `-Name` | the permissions of GPOs, as the Delegation tab of GPMC: each account and its level |
| [`Set-PSGPOPermission`](commands/set-psgpopermission.md) `-Name -Account [-Permission GpoRead\|GpoApply\|GpoEdit\|GpoEditDeleteModifySecurity\|None] [-SecurityFiltering Add\|Remove]` | gives an account a level on GPOs, or changes their security filtering, in the directory and in SYSVOL |
| [`Get-PSGPOWmiFilter`](commands/get-psgpowmifilter.md) `[-Name]` | the WMI filters of the domain, their queries and their GPOs |
| [`New-PSGPOWmiFilter`](commands/new-psgpowmifilter.md) `-Name -Query [-Namespace] [-Description]` | creates a WMI filter |
| [`Remove-PSGPOWmiFilter`](commands/remove-psgpowmifilter.md) `-Name` | deletes WMI filters no GPO uses |

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
| [`Backup-PSGPO`](commands/backup-psgpo.md) `-Path [-Name] [-Comment] [-Label] [-Approve] [-Force]` | backs up the GPOs that changed since their last backup |
| [`Get-PSGPOBackup`](commands/get-psgpobackup.md) `-Path [-Name] [-Id] [-Label] [-Approved] [-Template] [-Deleted]` | lists the backups, newest first; `-Deleted`: the recycle bin |
| [`Compare-PSGPOBackup`](commands/compare-psgpobackup.md) `-ReferenceBackup -DifferenceBackup` | what changed between two backups, setting by setting |
| [`Restore-PSGPO`](commands/restore-psgpo.md) `-Backup [-NoBackup] [-RestoreLink]` | puts a GPO back as a backup has it, or creates a deleted GPO again |
| [`Set-PSGPOBackup`](commands/set-psgpobackup.md) `-Backup [-Comment] [-AddLabel] [-RemoveLabel] [-Approve] [-Unapprove]` | changes the notes of a backup |
| [`Get-PSGPODrift`](commands/get-psgpodrift.md) `-Path [-Name] [-Label]` | compares each GPO to its approved version: `InSync`, `Drifted`, `NotApproved` |
| [`Get-PSGPOAuditLog`](commands/get-psgpoauditlog.md) `[-Path] [-Domain] [-Name] [-Action] [-Account] [-After] [-Before]` | what the consoles and the commands changed in the domain, newest first |
| [`Get-PSGPOGpmcBackup`](commands/get-psgpogpmcbackup.md) `-Path [-Name]` | the backups of GPMC (`Backup-GPO`) of a folder |
| [`Import-PSGPO`](commands/import-psgpo.md) `-Path -TargetName [-SourceName] [-BackupId] [-MigrationTable] [-Exclusive] [-CreateIfNeeded] [-BackupPath] [-NoBackup]` | imports the settings of a backup (GPMC or PSGPOTools) into a GPO, with a migration table |
| [`Get-PSGPOMigrationEntry`](commands/get-psgpomigrationentry.md) `-Path [-Name] [-IncludePermission]` | the accounts and UNC paths the settings of backups reference |
| [`New-PSGPOMigrationTable`](commands/new-psgpomigrationtable.md) `-Path -BackupPath [-Name] [-IncludePermission] [-MapByRelativeName] [-Force]` | writes a migration table (`.migtable`) for backups, as GPMC writes it |
| [`Get-PSGPOMigrationTable`](commands/get-psgpomigrationtable.md) `-Path` | reads a migration table of GPMC, checked |

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Comment 'Nightly'
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted' | ForEach-Object Changes
```

## Administrative templates

| Command | Does |
|---|---|
| [`Initialize-PSGPOAdmx`](commands/initialize-psgpoadmx.md) `-Path [-UICulture]` | loads the ADMX and ADML files of a folder (local PolicyDefinitions or the central store) |
| [`Get-PSGPOPolicy`](commands/get-psgpopolicy.md) `[-Scope Machine\|User]` | the policies loaded |
| [`Get-PSGPOCategory`](commands/get-psgpocategory.md) | their categories |
| [`Get-PSGPOSupportedOn`](commands/get-psgposupportedon.md) | the platforms they support |

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions -UICulture en-US
Get-PSGPOPolicy -Scope Machine | Where-Object DisplayName -Like '*biometrics*' | Select-Object DisplayName, Registry
```

## What they return

| Type | From | Main properties |
|---|---|---|
| `GPOToolsDirectory` | `Get-PSGPODirectory`, `Import-PSGPODirectory` | `DomainName`, `Domain`, `Gpos`, `Account`, `CanCreateGpo`, `Workflow` |
| `GPOToolsGpo` | `.Gpos`, `New-PSGPO` | `DisplayName`, `Id`, `Version`, `Flags`, `SecurityFiltering`, `DeniedTo`, `CanEdit`, `Owner`, `ApprovalState`, `RemovedAtApproval`, `WmiFilterId` |
| `PSGPOTools.Permission` | `Get-PSGPOPermission`, `Set-PSGPOPermission` | `GpoName`, `GpoId`, `Trustee`, `Sid`, `Permission`, `Inherited`, `Denied` |
| `PSGPOTools.Backup` | `Backup-PSGPO`, `Get-PSGPOBackup` | `Path`, `Id`, `DisplayName`, `BackedUp`, `BackedUpBy`, `Modified`, `Comment`, `Labels`, `Files` |
| `PSGPOTools.SettingChange` | `Compare-PSGPOBackup`, `Get-PSGPODrift` | `Change`, `Scope`, `Path`, `Name`, `Before`, `After` |
| `PSGPOTools.Drift` | `Get-PSGPODrift` | `DisplayName`, `State`, `Approved`, `ApprovedBy`, `Changes` |
| `PSGPOTools.Restore` | `Restore-PSGPO` | `DisplayName`, `Id`, `Version`, `BackupBefore`, `CreatedAgain`, `Linked`, `Problems` |
| `PSGPOTools.Link` | `New-PSGPOLink`, `Set-PSGPOLink` | `DisplayName`, `Target`, `Order`, `Enabled`, `Enforced` |
| `PSGPOTools.AuditEntry` | `Get-PSGPOAuditLog` | `Time`, `Account`, `Computer`, `Server`, `Action`, `Target`, `GpoName`, `GpoId`, `Details` |
| `PSGPOTools.WmiFilter` | `Get-PSGPOWmiFilter`, `New-PSGPOWmiFilter` | `Name`, `Id`, `Description`, `Queries`, `Gpos`, `DistinguishedName` |
| `PSGPOTools.Approval` | `Approve-PSGPO` | `DisplayName`, `Owner`, `CreatedBy`, `CreatorRights`, `AppliedBy`, `DeniedTo`, `GroupsCreated`, `RemovedPermissions`, `Backup` |
