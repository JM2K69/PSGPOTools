# Commandes

Chaque commande a sa page, son aide avec ses paramètres et ses exemples (en anglais) : cliquez sur
son nom. `Get-Help <commande> -Full` donne la même aide dans PowerShell, et `Get-Help <commande> -Online`
ouvre sa page. Les commandes qui modifient le domaine acceptent `-WhatIf` et `-Confirm`.

## Le domaine

| Commande | Fait |
|---|---|
| [`Get-PSGPODirectory`](commands/get-psgpodirectory.md) `[-Server] [-Credential] [-UseSsl] [-Port]` | lit le domaine en LDAP : ses OU, GPO, liens, les droits du compte, la configuration du domaine et son workflow d'approbation |
| [`Import-PSGPODirectory`](commands/import-psgpodirectory.md) `-Path` | lit un domaine depuis une description JSON (hors ligne, démonstrations, tests) |
| [`Show-GPOManagerAvalonia`](commands/show-gpomanageravalonia.md) `[-Server] [-Credential] [-UseSsl] [-Directory] [-NoDirectory] [-PolicyDefinitions] [-UICulture] [-Language]` | ouvre la console |
| [`Get-PSGPOConfiguration`](commands/get-psgpoconfiguration.md) `[-Directory] [-Server]` | la configuration utilisée, et d'où elle vient |

## Les GPO

| Commande | Fait |
|---|---|
| [`New-PSGPO`](commands/new-psgpo.md) `-Name [-Template] [-Status Enabled\|ComputerOnly\|UserOnly]` | crée une GPO, vide ou à partir d'un modèle |
| [`Remove-PSGPO`](commands/remove-psgpo.md) `-Name [-BackupPath] [-NoBackup]` | supprime des GPO et leurs liens, sauvegardées d'abord |
| [`Approve-PSGPO`](commands/approve-psgpo.md) `-Name [-CreatorRights ReadOnly\|EditSettings] [-ApplyTo] [-DenyTo] [-CreateFilteringGroups] [-GroupContainer] [-BackupPath]` | approuve des GPO en attente d'approbation, avec leur filtrage de sécurité (et ses groupes) |
| [`Initialize-PSGPOWorkflow`](commands/initialize-psgpoworkflow.md) `[-Apply]` | vérifie, et avec `-Apply` pose, la délégation de la création de GPO aux créateurs |
| [`New-PSGPOLink`](commands/new-psgpolink.md) `-Name -Target [-Enforced] [-Disabled]` | lie des GPO au domaine ou à une OU, avec la plus faible priorité |
| [`Set-PSGPOLink`](commands/set-psgpolink.md) `-Name -Target [-Enabled] [-Enforced] [-Order]` | active, désactive, applique (Enforced) ou déplace des liens |
| [`Remove-PSGPOLink`](commands/remove-psgpolink.md) `-Name -Target` | supprime des liens, les GPO restent |
| [`Set-PSGPOInheritance`](commands/set-psgpoinheritance.md) `-Target -Blocked` | bloque l'héritage du domaine ou d'une OU, ou non |
| [`Set-PSGPO`](commands/set-psgpo.md) `-Name [-NewName] [-Status Enabled\|ComputerOnly\|UserOnly\|Disabled] [-WmiFilter] [-NoWmiFilter]` | renomme une GPO, règle le statut et le filtre WMI de GPO |
| [`Get-PSGPOPermission`](commands/get-psgpopermission.md) `-Name` | les autorisations de GPO, comme l'onglet Délégation de GPMC : chaque compte et son niveau |
| [`Set-PSGPOPermission`](commands/set-psgpopermission.md) `-Name -Account [-Permission GpoRead\|GpoApply\|GpoEdit\|GpoEditDeleteModifySecurity\|None] [-SecurityFiltering Add\|Remove]` | donne un niveau à un compte sur des GPO, ou change leur filtrage de sécurité, dans l'annuaire et dans SYSVOL |
| [`Get-PSGPOWmiFilter`](commands/get-psgpowmifilter.md) `[-Name]` | les filtres WMI du domaine, leurs requêtes et leurs GPO |
| [`New-PSGPOWmiFilter`](commands/new-psgpowmifilter.md) `-Name -Query [-Namespace] [-Description]` | crée un filtre WMI |
| [`Set-PSGPOWmiFilter`](commands/set-psgpowmifilter.md) `-Name [-NewName] [-Description] [-Query] [-Namespace]` | modifie le nom, la description ou les requêtes d'un filtre WMI |
| [`Remove-PSGPOWmiFilter`](commands/remove-psgpowmifilter.md) `-Name` | supprime des filtres WMI qu'aucune GPO n'utilise |
| [`Export-PSGPOWmiFilter`](commands/export-psgpowmifilter.md) `-Name -Path [-Force]`, `-InputObject -Path [-Domain]` | exporte des filtres WMI en fichiers `.mof`, comme GPMC ; avec `-InputObject`, des filtres écrits sans domaine |
| [`Import-PSGPOWmiFilter`](commands/import-psgpowmifilter.md) `-Path [-Name]` | crée des filtres WMI à partir de fichiers `.mof` de GPMC ou de HGPM |
| [`Get-PSGPOWmiFilterPermission`](commands/get-psgpowmifilterpermission.md) `[-Name]` | qui crée des filtres WMI (sans `-Name`), qui modifie chaque filtre, comme les onglets Délégation de GPMC |
| [`Show-WmiFilterCreatorAvalonia`](commands/show-wmifiltercreatoravalonia.md) `[-Path] [-Server] [-Credential] [-UseSsl] [-Language]` | ouvre le créateur de filtres WMI : requêtes prêtes à l'emploi, générateur de requête, vérification, test, export `.mof`, création dans le domaine |
| [`Get-PSGPOWmiQueryTemplate`](commands/get-psgpowmiquerytemplate.md) `[-Id] [-Category] [-Value]` | les requêtes WQL prêtes à l'emploi du créateur, leurs paramètres remplis |
| [`Test-PSGPOWmiFilter`](commands/test-psgpowmifilter.md) `-Query [-Namespace]`, `-InputObject`, `-Path` `[-ComputerName] [-Credential]` | teste un filtre WMI sur un ordinateur, comme Windows l'évalue (Windows) |
| [`Set-PSGPOWmiFilterPermission`](commands/set-psgpowmifilterpermission.md) `[-Name] -Account -Permission WmiCreate\|WmiEdit\|WmiFullControl\|None` | délègue la création des filtres WMI, ou la modification d'un filtre, avec les ACE de GPMC |

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
| [`Backup-PSGPO`](commands/backup-psgpo.md) `-Path [-Name] [-Comment] [-Label] [-Approve] [-Force]` | sauvegarde les GPO qui ont changé depuis leur dernière sauvegarde |
| [`Get-PSGPOBackup`](commands/get-psgpobackup.md) `-Path [-Name] [-Id] [-Label] [-Approved] [-Template] [-Deleted]` | liste les sauvegardes, la plus récente d'abord ; `-Deleted` : la corbeille |
| [`Compare-PSGPOBackup`](commands/compare-psgpobackup.md) `-ReferenceBackup -DifferenceBackup` | ce qui a changé entre deux sauvegardes, paramètre par paramètre |
| [`Restore-PSGPO`](commands/restore-psgpo.md) `-Backup [-NoBackup] [-RestoreLink]` | remet une GPO comme une sauvegarde la contient, ou recrée une GPO supprimée |
| [`Remove-PSGPOBackup`](commands/remove-psgpobackup.md) `-Backup` | supprime définitivement une GPO de la corbeille : toutes ses sauvegardes |
| [`Set-PSGPOBackup`](commands/set-psgpobackup.md) `-Backup [-Comment] [-AddLabel] [-RemoveLabel] [-Approve] [-Unapprove]` | modifie les notes d'une sauvegarde |
| [`Get-PSGPODrift`](commands/get-psgpodrift.md) `-Path [-Name] [-Label]` | compare chaque GPO à sa version approuvée : `InSync`, `Drifted`, `NotApproved` |
| [`Get-PSGPOGpmcBackup`](commands/get-psgpogpmcbackup.md) `-Path [-Name]` | les sauvegardes de GPMC (`Backup-GPO`) d'un dossier |
| [`Import-PSGPO`](commands/import-psgpo.md) `-Path -TargetName [-SourceName] [-BackupId] [-MigrationTable] [-Exclusive] [-CreateIfNeeded] [-BackupPath] [-NoBackup]` | importe les paramètres d'une sauvegarde (GPMC ou HGPM) dans une GPO, avec une table de migration |
| [`Get-PSGPOMigrationEntry`](commands/get-psgpomigrationentry.md) `-Path [-Name] [-IncludePermission]` | les comptes et chemins UNC que référencent les paramètres de sauvegardes |
| [`New-PSGPOMigrationTable`](commands/new-psgpomigrationtable.md) `-Path -BackupPath [-Name] [-IncludePermission] [-MapByRelativeName] [-Force]` | écrit une table de migration (`.migtable`) pour des sauvegardes, comme GPMC l'écrit |
| [`Get-PSGPOMigrationTable`](commands/get-psgpomigrationtable.md) `-Path` | lit une table de migration de GPMC, vérifiée |
| [`Get-PSGPOAuditLog`](commands/get-psgpoauditlog.md) `[-Path] [-Domain] [-Name] [-Action] [-Account] [-After] [-Before]` | ce que les consoles et les commandes ont modifié dans le domaine, le plus récent d'abord |
| [`Show-AuditLogAvalonia`](commands/show-auditlogavalonia.md) `[-Path] [-Directory \| -Server] [-Language]` | ouvre le journal d'audit dans une fenêtre : filtré par période, domaine, action et une recherche, les détails d'une modification, les modifications affichées exportées en CSV |

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Comment 'Chaque nuit'
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted' | ForEach-Object Changes
```

## Policy Analyzer

| Commande | Fait |
|---|---|
| [`Show-PolicyAnalyzerAvalonia`](commands/show-policyanalyzeravalonia.md) `[-Path] [-Directory \| -Server] [-PolicyDefinitions] [-Language]` | ouvre Policy Analyzer : des jeux de règles comparés dans une fenêtre, comme le fait Policy Analyzer |
| [`Get-PSGPOPolicyRuleSet`](commands/get-psgpopolicyruleset.md) `-Path \| -Name \| -Backup \| -GpmcBackupPath [-SetName]` | lit des fichiers `.PolicyRules` (les baselines de sécurité de Microsoft), ou fait un jeu de règles de GPO du domaine, de sauvegardes HGPM ou GPMC |
| [`Compare-PSGPOPolicyRuleSet`](commands/compare-psgpopolicyruleset.md) `-RuleSet [-DifferenceOnly] [-ConflictOnly]` | compare des jeux de règles paramètre par paramètre, une colonne par jeu, comme Policy Analyzer |
| [`Export-PSGPOPolicyRuleSet`](commands/export-psgpopolicyruleset.md) `-RuleSet -Path [-Force]` | enregistre des jeux de règles dans un fichier `.PolicyRules`, que Policy Analyzer et `LGPO.exe /p` lisent |
| [`Export-PSGPOPolicyRuleComparison`](commands/export-psgpopolicyrulecomparison.md) `-InputObject -Path [-All] [-Force]` | enregistre une comparaison dans un classeur Excel, avec les couleurs de Policy Analyzer |
| [`Import-PSGPOPolicyRuleSet`](commands/import-psgpopolicyruleset.md) `-RuleSet -TargetName [-PolicyName] [-Replace] [-CreateIfNeeded] [-BackupPath] [-NoBackup]` | écrit les paramètres d'un jeu de règles dans une GPO du domaine, comme `LGPO.exe /p` l'applique à un ordinateur |

```powershell
$baseline = Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules
$domaine = Get-PSGPOPolicyRuleSet -Name 'Postes - *' -SetName 'Domaine'
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domaine -DifferenceOnly | Export-PSGPOPolicyRuleComparison -Path ./Differences.xlsx
```

## Modèles d'administration

| Commande | Fait |
|---|---|
| [`Initialize-PSGPOAdmx`](commands/initialize-psgpoadmx.md) `-Path [-UICulture]` | charge les fichiers ADMX et ADML d'un dossier (PolicyDefinitions local ou magasin central) |
| [`Install-PSGPOAdmx`](commands/install-psgpoadmx.md) `[-UICulture] [-AllLanguages] [-Path] [-CentralStore] [-Ref] [-Force]` | télécharge les fichiers ADMX de HGPM depuis GitHub (vérifiés), dans un dossier ou le magasin central du domaine |
| [`Get-PSGPOPolicy`](commands/get-psgpopolicy.md) `[-Scope Machine\|User]` | les stratégies chargées |
| [`Get-PSGPOCategory`](commands/get-psgpocategory.md) | leurs catégories |
| [`Get-PSGPOSupportedOn`](commands/get-psgposupportedon.md) | les plateformes qu'elles prennent en charge |

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions -UICulture fr-FR
Get-PSGPOPolicy -Scope Machine | Where-Object DisplayName -Like '*biom*' | Select-Object DisplayName, Registry
```

## Le module

| Commande | Fait |
|---|---|
| [`Start-HGPM`](commands/start-hgpm.md) `[-Language]` | ouvre le lanceur : une tuile par outil de HGPM |
| [`Test-PSGPOUpdate`](commands/test-psgpoupdate.md) `[-Prerelease] [-Quiet] [-Repository]` | dit si une version plus récente de HGPM est sur la PowerShell Gallery, et la commande qui l'installe |

## Stratégies de mot de passe

| Commande | Fait |
|---|---|
| [`Show-PSOManagerAvalonia`](commands/show-psomanageravalonia.md) `[-Server] [-Credential] [-UseSsl] [-View Policies\|Resultant] [-Language]` | ouvre la console des stratégies de mot de passe affinées (PSO) |
| [`Get-PSGPOFineGrainedPasswordPolicy`](commands/get-psgpofinegrainedpasswordpolicy.md) `[-Name]` | les PSO du domaine, par ordre de priorité, avec les utilisateurs et groupes auxquels ils s'appliquent |
| [`Get-PSGPODefaultPasswordPolicy`](commands/get-psgpodefaultpasswordpolicy.md) | la stratégie de mot de passe du domaine, pour les comptes qu'aucun PSO ne concerne |
| [`New-PSGPOFineGrainedPasswordPolicy`](commands/new-psgpofinegrainedpasswordpolicy.md) `-Name -Precedence [-MinPasswordLength] [-MaxPasswordAge] [-LockoutThreshold] [-AppliesTo]...` | crée un PSO, avec par défaut les paramètres du Centre d'administration |
| [`Set-PSGPOFineGrainedPasswordPolicy`](commands/set-psgpofinegrainedpasswordpolicy.md) `-Name [-NewName] [-Precedence] [-ProtectedFromAccidentalDeletion]...` | modifie, renomme, protège des PSO |
| [`Remove-PSGPOFineGrainedPasswordPolicy`](commands/remove-psgpofinegrainedpasswordpolicy.md) `-Name` | supprime des PSO non protégés contre la suppression accidentelle |
| [`Add-PSGPOFineGrainedPasswordPolicySubject`](commands/add-psgpofinegrainedpasswordpolicysubject.md) `-Name -Subject` | applique des PSO à des utilisateurs et des groupes |
| [`Remove-PSGPOFineGrainedPasswordPolicySubject`](commands/remove-psgpofinegrainedpasswordpolicysubject.md) `-Name -Subject` | cesse de les appliquer |
| [`Get-PSGPOResultantPasswordPolicy`](commands/get-psgporesultantpasswordpolicy.md) `-Identity` | le PSO qui s'applique à un utilisateur ou un groupe, et pourquoi pas les autres |

```powershell
New-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 1 Admins' -Precedence 10 -MinPasswordLength 16 -AppliesTo 'GPO-Tier1-Admins'
(Get-PSGPOResultantPasswordPolicy -Identity tiers1).Candidates | Format-Table Order, Name, Precedence, AppliesThrough, Status
```

## Ce qu'elles renvoient

| Type | Venant de | Propriétés principales |
|---|---|---|
| `GPOToolsDirectory` | `Get-PSGPODirectory`, `Import-PSGPODirectory` | `DomainName`, `Domain`, `Gpos`, `Account`, `CanCreateGpo`, `Workflow` |
| `GPOToolsGpo` | `.Gpos`, `New-PSGPO` | `DisplayName`, `Id`, `Version`, `Flags`, `SecurityFiltering`, `DeniedTo`, `CanEdit`, `Owner`, `ApprovalState`, `RemovedAtApproval`, `WmiFilterId` |
| `PSGPOTools.Permission` | `Get-PSGPOPermission`, `Set-PSGPOPermission` | `GpoName`, `GpoId`, `Trustee`, `Sid`, `Permission`, `Inherited`, `Denied` |
| `PSGPOTools.Backup` | `Backup-PSGPO`, `Get-PSGPOBackup` | `Path`, `Id`, `DisplayName`, `BackedUp`, `BackedUpBy`, `Modified`, `Comment`, `Labels`, `Files` |
| `PSGPOTools.SettingChange` | `Compare-PSGPOBackup`, `Get-PSGPODrift` | `Change`, `Scope`, `Path`, `Name`, `Before`, `After` |
| `GPOToolsPolicyRuleSet` | `Get-PSGPOPolicyRuleSet` | `Name`, `Path`, `Rules`, `Extensions`, `GetPolicyNames()` |
| `PSGPOTools.PolicyRuleComparison` | `Compare-PSGPOPolicyRuleSet` | `Scope`, `Path`, `Name`, `Option`, une propriété par jeu, `Conflict`, `Difference`, `PolicyType`, `Group`, `Setting`, `Explain`, `Cells` |
| `PSGPOTools.Drift` | `Get-PSGPODrift` | `DisplayName`, `State`, `Approved`, `ApprovedBy`, `Changes` |
| `PSGPOTools.Restore` | `Restore-PSGPO` | `DisplayName`, `Id`, `Version`, `BackupBefore`, `CreatedAgain`, `Linked`, `Problems` |
| `PSGPOTools.RemovedBackup` | `Remove-PSGPOBackup` | `DisplayName`, `Id`, `Backups`, `Templates`, `Path` |
| `PSGPOTools.Link` | `New-PSGPOLink`, `Set-PSGPOLink` | `DisplayName`, `Target`, `Order`, `Enabled`, `Enforced` |
| `PSGPOTools.AuditEntry` | `Get-PSGPOAuditLog` | `Time`, `Account`, `Computer`, `Server`, `Action`, `Target`, `GpoName`, `GpoId`, `Details` |
| `PSGPOTools.WmiFilter` | `Get-PSGPOWmiFilter`, `New-PSGPOWmiFilter`, `Set-PSGPOWmiFilter` | `Name`, `Id`, `Description`, `Queries`, `Gpos`, `DistinguishedName` |
| `PSGPOTools.Approval` | `Approve-PSGPO` | `DisplayName`, `Owner`, `CreatedBy`, `CreatorRights`, `AppliedBy`, `DeniedTo`, `GroupsCreated`, `RemovedPermissions`, `Backup` |
