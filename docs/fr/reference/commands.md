# Commandes

`Get-Help <commande> -Full` donne l'aide de chacune, avec ses exemples (en anglais). Les commandes
qui modifient le domaine acceptent `-WhatIf` et `-Confirm`.

## Le domaine

| Commande | Fait |
|---|---|
| `Get-PSGPODirectory [-Server] [-Credential] [-UseSsl] [-Port]` | lit le domaine en LDAP : ses OU, GPO, liens, les droits du compte, la configuration du domaine et son workflow d'approbation |
| `Import-PSGPODirectory -Path` | lit un domaine depuis une description JSON (hors ligne, démonstrations, tests) |
| `Show-GPOManagerAvalonia [-Server] [-Credential] [-UseSsl] [-Directory] [-NoDirectory] [-PolicyDefinitions] [-UICulture] [-Language]` | ouvre la console |
| `Get-PSGPOConfiguration [-Directory] [-Server]` | la configuration utilisée, et d'où elle vient |

## Les GPO

| Commande | Fait |
|---|---|
| `New-PSGPO -Name [-Template] [-Status Enabled\|ComputerOnly\|UserOnly]` | crée une GPO, vide ou à partir d'un modèle |
| `Remove-PSGPO -Name [-BackupPath] [-NoBackup]` | supprime des GPO et leurs liens, sauvegardées d'abord |
| `Approve-PSGPO -Name [-CreatorRights ReadOnly\|EditSettings] [-ApplyTo] [-DenyTo] [-CreateFilteringGroups] [-GroupContainer] [-BackupPath]` | approuve des GPO en attente d'approbation, avec leur filtrage de sécurité (et ses groupes) |
| `Initialize-PSGPOWorkflow [-Apply]` | vérifie, et avec `-Apply` pose, la délégation de la création de GPO aux créateurs |
| `New-PSGPOLink -Name -Target [-Enforced] [-Disabled]` | lie des GPO au domaine ou à une OU, avec la plus faible priorité |
| `Set-PSGPOLink -Name -Target [-Enabled] [-Enforced] [-Order]` | active, désactive, applique (Enforced) ou déplace des liens |
| `Remove-PSGPOLink -Name -Target` | supprime des liens, les GPO restent |
| `Set-PSGPOInheritance -Target -Blocked` | bloque l'héritage du domaine ou d'une OU, ou non |
| `Set-PSGPO -Name [-Status Enabled\|ComputerOnly\|UserOnly\|Disabled] [-WmiFilter] [-NoWmiFilter]` | règle le statut et le filtre WMI de GPO |
| `Get-PSGPOPermission -Name` | les autorisations de GPO, comme l'onglet Délégation de GPMC : chaque compte et son niveau |
| `Set-PSGPOPermission -Name -Account [-Permission GpoRead\|GpoApply\|GpoEdit\|GpoEditDeleteModifySecurity\|None] [-SecurityFiltering Add\|Remove]` | donne un niveau à un compte sur des GPO, ou change leur filtrage de sécurité, dans l'annuaire et dans SYSVOL |
| `Get-PSGPOWmiFilter [-Name]` | les filtres WMI du domaine, leurs requêtes et leurs GPO |
| `New-PSGPOWmiFilter -Name -Query [-Namespace] [-Description]` | crée un filtre WMI |
| `Remove-PSGPOWmiFilter -Name` | supprime des filtres WMI qu'aucune GPO n'utilise |

Un nom donné avec `-Name` est le nom de la GPO, crochets compris (`Servers [Lyon]`) ; avec `*` ou `?`, c'est un motif. Deux GPO de même nom sont prises chacune.

`-Directory` (venant de `Get-PSGPODirectory`) ou `-Server` donne le domaine à chacune ; sans eux,
le domaine de l'ordinateur est lu.

```powershell
$Directory = Get-PSGPODirectory -Server dc.hardenbox.labo
New-PSGPO -Directory $Directory -Name 'T1 - Servers - Proxy' -Status ComputerOnly
Approve-PSGPO -Directory $Directory -Name 'T1 - Servers - Proxy' -ApplyTo 'APPLY_T1 - Servers - Proxy'
```

## Les sauvegardes

| Commande | Fait |
|---|---|
| `Backup-PSGPO -Path [-Name] [-Comment] [-Label] [-Approve] [-Force]` | sauvegarde les GPO qui ont changé depuis leur dernière sauvegarde |
| `Get-PSGPOBackup -Path [-Name] [-Id] [-Label] [-Approved] [-Template] [-Deleted]` | liste les sauvegardes, la plus récente d'abord ; `-Deleted` : la corbeille |
| `Compare-PSGPOBackup -ReferenceBackup -DifferenceBackup` | ce qui a changé entre deux sauvegardes, paramètre par paramètre |
| `Restore-PSGPO -Backup [-NoBackup] [-RestoreLink]` | remet une GPO comme une sauvegarde la contient, ou recrée une GPO supprimée |
| `Set-PSGPOBackup -Backup [-Comment] [-AddLabel] [-RemoveLabel] [-Approve] [-Unapprove]` | modifie les notes d'une sauvegarde |
| `Get-PSGPODrift -Path [-Name] [-Label]` | compare chaque GPO à sa version approuvée : `InSync`, `Drifted`, `NotApproved` |
| `Get-PSGPOGpmcBackup -Path [-Name]` | les sauvegardes de GPMC (`Backup-GPO`) d'un dossier |
| `Import-PSGPO -Path -TargetName [-SourceName] [-BackupId] [-MigrationTable] [-Exclusive] [-CreateIfNeeded] [-BackupPath] [-NoBackup]` | importe les paramètres d'une sauvegarde (GPMC ou PSGPOTools) dans une GPO, avec une table de migration |
| `Get-PSGPOMigrationEntry -Path [-Name] [-IncludePermission]` | les comptes et chemins UNC que référencent les paramètres de sauvegardes |
| `New-PSGPOMigrationTable -Path -BackupPath [-Name] [-IncludePermission] [-MapByRelativeName] [-Force]` | écrit une table de migration (`.migtable`) pour des sauvegardes, comme GPMC l'écrit |
| `Get-PSGPOMigrationTable -Path` | lit une table de migration de GPMC, vérifiée |
| `Get-PSGPOAuditLog [-Path] [-Domain] [-Name] [-Action] [-Account] [-After] [-Before]` | ce que les consoles et les commandes ont modifié dans le domaine, le plus récent d'abord |

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Comment 'Chaque nuit'
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted' | ForEach-Object Changes
```

## Modèles d'administration

| Commande | Fait |
|---|---|
| `Initialize-PSGPOAdmx -Path [-UICulture]` | charge les fichiers ADMX et ADML d'un dossier (PolicyDefinitions local ou magasin central) |
| `Get-PSGPOPolicy [-Scope Machine\|User]` | les stratégies chargées |
| `Get-PSGPOCategory` | leurs catégories |
| `Get-PSGPOSupportedOn` | les plateformes qu'elles prennent en charge |

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions -UICulture fr-FR
Get-PSGPOPolicy -Scope Machine | Where-Object DisplayName -Like '*biom*' | Select-Object DisplayName, Registry
```

## Ce qu'elles renvoient

| Type | Venant de | Propriétés principales |
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
