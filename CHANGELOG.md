# HGPM Release History

## Unreleased

### Added

* Policy Analyzer, as in the Security Compliance Toolkit of Microsoft, on Windows and Linux, with the same `.PolicyRules` files: `Get-PSGPOPolicyRuleSet` reads them (the security baselines of Microsoft) or makes a rule set from GPOs of the domain, backups of HGPM or of GPMC, the file `GPO2PolicyRules.exe` makes, byte for byte; `Compare-PSGPOPolicyRuleSet` compares sets setting by setting, a column per set (conflicts, differences, duplicates and `***CONFLICT***` in a set, lists of accounts in any order, `REG_DWORD` and `REG_SZ` told apart, the policies of the ADMX and the security settings by name); `Export-PSGPOPolicyRuleSet` saves a `.PolicyRules` file Policy Analyzer and `LGPO.exe /p` read, several sets merged; `Export-PSGPOPolicyRuleComparison` writes the comparison as an Excel workbook with the colours of Policy Analyzer, without Excel nor any module. A documentation page, Policy Analyzer
* The **Policy Analyzer** view of the console, a view of its own as Group Policy Management (the button in the header): the `.PolicyRules` files of a folder (`Documents\PolicyAnalyzer` by default, as Policy Analyzer), GPOs of the domain and GPMC backups as rule sets; the comparison of those checked, a column per set with the colours of Policy Analyzer, sorted and filtered (only the differences, only the conflicts, a search), the details of a setting (where GPMC shows it, the value of each GPO, its explanation); a set saved as `.PolicyRules`, the comparison exported to Excel

* `Start-HGPM` opens a launcher: a tile for each console of HGPM (Group Policy Management, Password Settings, WMI Filter Creator), a click opens it in the language of the launcher; several consoles can be open at once

* The **WMI filter creator**, `Show-WmiFilterCreatorAvalonia`, on Windows and Linux: a WMI filter written from more than sixty ready-made queries (operating system and its versions up to Windows 11 26H2 and Windows Server 2025, edition, architecture, language, domain and name, hardware, virtual machines of Hyper-V, Azure, VMware, VirtualBox, KVM, Nutanix, Xen and EC2, TPM, BitLocker, VBS, antivirus, IP subnet, gateway, time zone, programs, services, updates, roles, files, time), each with its parameters, its pitfalls and its source (Microsoft Learn first), or from a query builder (25 classes, their properties and known values); each query checked as it is typed (WQL syntax, namespace of the class, costly classes), the filter tested on the computer as Windows evaluates it, exported to a `.mof` file in the format of GPMC, a `.mof` file opened, the filter created in the domain. A documentation page, WMI filter creator
* `Get-PSGPOWmiQueryTemplate` gives the ready-made queries of the creator, their parameters filled; `Test-PSGPOWmiFilter` tests a WMI filter (queries, a filter of the domain, a `.mof` file) on this computer or another one, as Windows evaluates it; `Export-PSGPOWmiFilter -InputObject` exports a filter written without a domain

### Changed

* The theme chosen with **Dark mode** / **Light mode** in a window of HGPM is the one of all of them, those open and those opened after: the launcher, the GPO and PSO consoles, the WMI filter creator
* The central store of the domain is used by default when it holds ADMX files, as GPMC: the window that asks for the ADMX files selects it, before the folder chosen last, and says it is the central store; `Initialize-PSGPOAdmx` without `-Path` loads it (Windows, and the SYSVOL of a Samba domain controller)

### Fixed

* A `Registry.pol` with an entry without data (a key created without value, as the `Safer` key of the security baselines) could not be written
* On Windows, the windows of the consoles (ADMX files, GPO console, PSO console) opened behind the terminal that started them: they now open in front

## 0.1.9 - alpha

### Added

* Delegation of the WMI filters, as GPMC: a **Delegation** tab on WMI Filters (who creates filters: Creator owner, Full control) and on each filter (who changes it: Edit, Full control), and `Get-PSGPOWmiFilterPermission`, `Set-PSGPOWmiFilterPermission`. The ACEs are those the GPMC API writes, checked both ways on a Windows domain; the filters inherit the full control of WMI Filters. Audited as `SetWmiFilterPermission`

* Export and import WMI filters as `.mof` files, as GPMC does: **Export...** on a filter, **Import...** on WMI Filters, and `Export-PSGPOWmiFilter`, `Import-PSGPOWmiFilter`. The format is the one of GPMC (UTF-16, `MSFT_SomFilter` and its `MSFT_Rule`), checked on a Windows domain both ways: Windows creates a filter again from a file of HGPM, HGPM imports a file of Windows that GPMC then reads. An imported filter gets a new Id; the console imports a file of one filter, the command all of them
* Give a WMI filter to a GPO from the filter, **Use it in a GPO...**, and from the details of the GPO, its **WMI filter** list, as the Scope tab of GPMC
* The WMI filters keep their author and dates (`msWMI-Author`, `msWMI-CreationDate`, `msWMI-ChangeDate`), as the `.mof` files hold them

* Rename a GPO, as GPMC: **Rename...** in the context menu of a GPO or of a link to it, or F2 in the tree, and `Set-PSGPO -NewName`. Only its display name changes (its GUID, SYSVOL folder, links, backups and filtering groups are kept); the name of another GPO, or a GPO renamed in the domain meanwhile, is refused. Audited as `RenameGpo`
* Rename a WMI filter with **Rename...** (or F2) in its context menu, and **Edit this WMI filter** in its details
* Delete a GPO of the recycle bin for good: **Delete for good...** on a GPO of Deleted GPOs, and `Remove-PSGPOBackup`, deletes all its backups, the templates made from it too, after a confirmation that counts them. Refused for a GPO still in the domain. Audited as `RemoveDeletedGpoBackup`
* The editor of a GPO says when its status disables the part being edited: its settings are saved, but nobody applies them

### Changed

* A documentation page, WMI filters and Linux clients: how a Windows computer evaluates a WMI filter, and what a Linux computer joined with Samba applies of a GPO (read in the code of Samba 4.22): it ignores the WMI filters, the GPO status and the *Apply Group Policy* right (only Read counts), and applies only the extensions of Samba (sudoers, scripts, messages, smb.conf, firewalld, Firefox, Chromium, GNOME, certificates, drive maps, VGP...); how to target or keep away the Linux computers
* The console, the help and the documentation say a WMI filter is true when each of its queries returns something (they said one of them): the queries are joined with AND, as Windows evaluates them
* The History tab names the versions of each node, `computer 3, user 0`, instead of `version 3 / 0` that read as a fraction

## 0.1.8 - alpha

### Added

* `View.ShowUnmanaged` in the configuration of the domain: `$true` (the default) shows every account the whole domain, what it does not manage greyed; `$false` shows each account only what it manages (the OUs where it links GPOs with their parents as the path to them, the GPOs it edits or that are linked there), and an account without delegation sees nothing. The console builds its tree again once the Settings window saved it

## 0.1.7 - alpha

### Changed

* The GPO console shows every account the whole domain, as GPMC: every OU, link and GPO. What the account does not manage (its delegations) is greyed and offers no action; it reads it. An account without any delegation reads the domain: the details say Delegation: None, the status bar (read only)

### Fixed

* New WMI Filter, Edit WMI filter and Delete WMI filter are offered only to an account the domain allows to (allowedChildClassesEffective of CN=SOM,CN=WMIPolicy,CN=System, allowedAttributesEffective of the filter); the commands refuse the others

## 0.1.6 - alpha

### Added

* The import of the module says its version, and, when the PowerShell Gallery has a newer one, the command that installs it (Update-PSResource, or Install-PSResource for a module not installed from the Gallery). The Gallery is read at most once a day (UpdateCheck.json in the local data folder of the user) and 8 seconds at most, never in a CI, a session started with -NonInteractive, or with PSGPOTOOLS_SKIP_UPDATE_CHECK=1; without network, the version only
* The Delegation tab of the GPO console gives the level Read and apply too: the account reads and applies the GPO (Apply Group Policy), as Set-PSGPOPermission -Permission GpoApply. The level is named Read and apply in the tab (GPMC: Read (from Security Filtering)). An Applies badge marks every account of the Delegation tab that applies the GPO, whatever its level (an editor in the security filtering, for instance)
* The status bar of both consoles (Show-GPOManagerAvalonia, Show-PSOManagerAvalonia) shows the version of HGPM with a dot: green when it is the latest of the PowerShell Gallery, orange when a newer one is there (its tooltip gives the command that installs it), grey when the Gallery was not read
* The consoles in French show the names of the security settings and options, of the preferences (types, items, their properties) and the descriptions of the configuration in French, from Resources/Strings/Catalogs/fr-FR.psd1 (683 names, those of the French Group Policy editor); the Settings and History tabs show their reports in French, the registry values and preview of the policy editor too. The commands and their reports stay in English
* The policy editor shows the tree of the Group Policy editor: Computer Configuration and User Configuration, each with Policies (Windows Settings > Security Settings, Administrative Templates and the ADMX policies under it) then Preferences
* The policy editor edits the advanced audit policy: Security Settings > Advanced Audit Policy Configuration > Audit Policies, the 60 subcategories of Windows in their 9 categories, written to Machine\Microsoft\Windows NT\Audit\audit.csv with the extension Audit Policy Configuration, as the Group Policy editor does (applied by a Windows member, checked with auditpol); the Settings and History tabs and the backups show it
* The policy editor edits the restricted groups: Security Settings > Restricted Groups, the groups of [Group Membership] in GptTmpl.inf with their members (or not defined) and the groups they are a member of, as the Group Policy editor writes them (applied by a Windows member); the Settings tab lists them instead of their raw keys
* The policy editor edits the public key policies: Security Settings > Public Key Policies, the certificate stores of the Group Policy editor for the computers (Encrypting File System, BitLocker Drive Encryption and its Network Unlock Certificate, Trusted Root, Enterprise Trust, Intermediate, Trusted Publishers, Untrusted Certificates, Third-Party Root, Trusted People) and the users (Enterprise Trust, Trusted People): their certificates listed, imported (.cer, .crt, .pem) and deleted, in Registry.pol as [MS-GPEF] describes them, with the EFSBlob of the EFS recovery agents (applied by a Windows member); the Settings tab lists them instead of extra registry settings
* A WMI filter can be changed: Edit WMI filter... in the context menu of a filter of the GPO console, and `Set-PSGPOWmiFilter` (-NewName, -Description, -Query, -Namespace). Its name, description and queries change in place, as GPMC edits a filter: the GPOs linked to it keep it; refused if the filter changed in the domain meanwhile. In the form, a query of another namespace is a line namespace: query

### Fixed

* In French, the title of the policy tree no longer runs over the check box Configured settings only, and a long name of the details of the console wraps instead of running over its value
* The name of the security option on PKU2U authentication ended with two line breaks
* Without network, the import and the consoles no longer wait for the PowerShell Gallery each time: a failed check is kept for an hour; the Gallery is waited 8 seconds at most (3 seconds were too short for a first connection)

## 0.1.5 - alpha

### Added

* `Test-PSGPOUpdate`: tells whether a newer version of HGPM is published on the PowerShell Gallery (Find-PSResource), comparing the version loaded with the latest as semantic versions (a prerelease before its release; the prereleases counted when the version loaded is one, or with -Prerelease), and gives the command that installs it (Update-PSResource, or Install-PSResource for a module not installed from the Gallery); -Quiet returns $true or $false. Documentation: Getting started > Installation > Updates

### Changed

* The icon of the module on the PowerShell Gallery (IconUri) is the logo of HGPM at 85 x 85 pixels with a transparent background, as the Gallery recommends (docs/assets/logo/hgpm-85.png)
* Documentation: the module is installed with PSResourceGet (`Install-PSResource -Name HGPM -Prerelease`, `Update-PSResource`), the module of PowerShell 7.4 that replaces PowerShellGet (`Install-Module`); the PowerShell Gallery is the first way in the installation page and in the README

## 0.1.4 - alpha

### Changed

* The Project Site of the module on the PowerShell Gallery is the documentation site (ProjectUri), and its icon the logo of HGPM (IconUri)
* The data files of the languages of the interface hold more than 500 texts: read with `-SkipLimitCheck`
* The "Edit" links of the documentation site open the pages on master; the technical pages (architecture, user interface, tests) and the first steps cover the console of the password policies

### Added

* `Show-PSOManagerAvalonia`: a second console, for the fine-grained password policies (password settings objects, PSO), as the Active Directory Administrative Center manages them, for Windows and Samba AD (4.9 and later) domains, from Windows and Linux, over LDAP. Its Password Settings view lists the PSOs by order of priority with the password policy of the domain; New, Properties and Delete open the fields of "Create Password Settings" (precedence, minimum length, history, complexity, reversible encryption, minimum and maximum ages, lockout until a duration or until an administrator unlocks the account, protection from accidental deletion, description, Directly Applies To with a search of the users and groups), checked as the domain controllers check them. Its Resultant Password Settings view shows, for a user or a group, every PSO that concerns it (directly, or through which groups, nested ones included) by order of priority, the one that applies and why the others do not; the domain controller has the last word for a user (msDS-ResultantPSO). The groups that pass a PSO on follow the domain controller: global security groups for Windows, every security group but the built-in ones for Samba AD. Sample policies when no domain is discovered, the interface in French, the changes in the audit log, a change refused when another console made one meanwhile
* The commands of the PSOs: `Get-PSGPOFineGrainedPasswordPolicy`, `New-`, `Set-` and `Remove-PSGPOFineGrainedPasswordPolicy`, `Add-` and `Remove-PSGPOFineGrainedPasswordPolicySubject`, `Get-PSGPODefaultPasswordPolicy` and `Get-PSGPOResultantPasswordPolicy`
* Documentation: Features > Password policies, and the workflow "Password policies of the tiers" on the groups of the lab, step by step with the screenshots of both views and of the window of a PSO, in English and in French

## 0.1.3 - alpha

### Changed

* The module is named HGPM (`Install-Module HGPM`, `Import-Module HGPM`, the folder `HGPM` with `HGPM.psd1`): the name PSGPOTools is taken on the PowerShell Gallery by its first versions. The commands keep their names (`Get-PSGPODirectory`...), and so do the data: the configuration of the domain in `SYSVOL\<domain>\PSGPOTools`, the backups and their formats, the folders of the user, the variables `PSGPOTOOLS_*`, the repository and the documentation site

### Added

* The logo of HGPM (Resources/hgpm.png): the icon of every window (title bar, task bar) and the image of the header of the console; the header trims its title and subtitle (the whole subtitle in its tooltip) so that its buttons always keep their place in a narrow window. The screenshots of the documentation show it
* Documentation: enabling the approval workflow of the domain step by step in the Settings window (Workflow.Enabled, Workflow.Creators with the groups of the scripts of the lab), with its screenshots, those of the French pages in the French interface
* The scripts of the lab, shown and downloadable in Getting started > The lab: `New-PSGPOTierLab.ps1` creates the tiering of hardenbox.labo in any domain (its distinguished name read from the domain controller): OU=Tier 1 (Servers, Groups), OU=Tier 2 (Workstations, Users, Groups), the groups GPO-Tier1-Admins and GPO-Tier2-Admins, and the technicians tiers1 and tiers2 with the password of the lab; `Grant-PSGPOTierDelegation.ps1` delegates finely to each group the links of GPOs to the OUs of its tier and the creation of GPOs through the approval workflow (Initialize-PSGPOWorkflow), never Group Policy Creator Owners, checking the workflow before any change. a version for Windows (LDAP with the identity of the session, System.DirectoryServices: no RSAT, Active Directory or Samba AD) and one for Linux (samba-tool with Kerberos), in tabs; both can run again, with -WhatIf; the Linux ones run twice by the CI against its Samba domain
* `Install-PSGPOAdmx`: the ADMX files are not in the module (nor in its package of the PowerShell Gallery); the command downloads those of the repository (`sources/PolicyDefinitions`: 236 `.admx` files, 22 languages) from GitHub at the tag of the version of the module, with the languages chosen (`-UICulture`, by default en-US and the language of the session) or all of them (`-AllLanguages`), each set checked against the SHA-256 the module pins before anything is written. Into a folder (next to the module, else the data folder of the user, where the console finds them), or with `-CentralStore` into the central store of the domain (`SYSVOL\<domain>\Policies\PolicyDefinitions`, through the share on Windows and smbclient on Linux), the ADMX files of other products kept
* Publication on the PowerShell Gallery, only for a tag of a version (`v0.1.3-alpha`), never for a commit: the Release workflow runs every test on the tagged commit, then `CI/04_Publish.ps1` checks that the tag is the version of the manifest, that `CHANGELOG.md` has its section and that the gallery does not have it yet, publishes the module (without the Avalonia runtime) with the secret `PSGALLERY_API_KEY` of the environment `psgallery`, and creates the release of GitHub with the notes of the version
* The help of each public command on the documentation site (Reference > Commands, in English and French): its synopsis, syntax, description, parameters, examples and outputs, written from its help by `CI/Update-CommandReference.ps1`; the first `.LINK` of each command is its page, which `Get-Help <command> -Online` opens. The release notes of the manifest point to the Changelog page of the site
* Import of GPOs with a migration table, as "Import Settings" of GPMC and the import of AGPM into an existing GPO: `Import-PSGPO` and "Import Settings..." in the context menu of a GPO replace its settings with those of a backup of GPMC (`Backup-GPO`: bkupInfo.xml, Backup.xml, DomainSysvol) or of PSGPOTools, of this domain or another, the GPO backed up first, its links, permissions, status and WMI filter kept. A migration table (.migtable, read and written as the Migration Table Editor of GPMC: User, Computer, LocalGroup, GlobalGroup, UniversalGroup, UNCPath, Unknown; Same As Source, by relative name, none, or a destination) maps the accounts and UNC paths of the security settings (user rights, restricted groups, SDDL), of the preferences, scripts and folder redirection; the administrative templates are copied as they are, as GPMC does. -Exclusive requires every reference in the table; a destination that cannot be found stops the import before any change. `Get-PSGPOGpmcBackup`, `Get-PSGPOMigrationEntry`, `New-PSGPOMigrationTable` (Populate from Backup) and `Get-PSGPOMigrationTable`. Tested with backups and a table made by GPMC on Windows
* Permissions of an existing GPO, as the Scope and Delegation tabs of GPMC: a Delegation tab lists the security filtering and every account of its permissions with its level (Read, Read from Security Filtering, Edit settings, Edit settings + delete + modify security, Custom; inherited or not), adds and removes an account from the security filtering, sets or removes the level of an account, and says when no computer can read the GPO anymore (MS16-072). `Get-PSGPOPermission` and `Set-PSGPOPermission -Permission / -SecurityFiltering` do the same in scripts. A change reads the DACL of the GPO again, writes it, then gives its SYSVOL folder and everything in it the ACL derived from it; it goes to the audit log; a GPO waiting for its approval is refused
* The configuration of the domain is created at the first start of the console by an administrator of the domain (Domain Admins, Enterprise Admins or Administrators, read in the groups of the account), empty: every setting has its default. Settings is greyed for any other account, without a domain and for a directory that cannot be written; saving no value writes an empty configuration instead of removing the file
* The console in French: the texts of the interface come from Resources/Strings/<culture>.psd1 (fr-FR, with the words of the French GPMC), the English text being the key and the fallback. `Show-GPOManagerAvalonia -Language` chooses the language, by default the one of the PowerShell session; the commands and their errors stay in English
* WMI filters, as GPMC: a WMI Filters container in the tree (each filter with its description, queries and the GPOs using it; New WMI Filter... and Delete WMI filter... in the context menus), read from the domain (msWMI-Som of CN=SOM,CN=WMIPolicy,CN=System, gPCWQLFilter of the GPOs), shown in the details of a GPO, set from its context menu (WMI Filter) or `Set-PSGPO -WmiFilter / -NoWmiFilter`; `Get-PSGPOWmiFilter`, `New-PSGPOWmiFilter`, `Remove-PSGPOWmiFilter` (refused while a GPO of the domain uses it). The backups keep the filter of a GPO, the drift shows its changes, and a restore links it again
* Audit log: each change a domain accepted, from the console or a command (GPOs, links, inheritance, status, files of a GPO, restore, deletion, approval, filtering groups, configuration), is a JSON line, never rewritten: when, account, computer, domain controller, action, target and details (the SHA-256 of a saved file, the permissions removed at an approval...). In `Audit.Path` of the configuration of the domain (a share, for every console), else the folder Audit of the backups; `Get-PSGPOAuditLog` reads it
* Refresh (F5) in the Group Policy Management view: the domain read again from the same domain controller with the same account, the tree keeping what is expanded and selected
* Links and inheritance as GPMC changes them: Enforced, Link Enabled, Move link up / down in the context menu of a link, Block Inheritance in the context menu of the domain and of an OU, and GPO Status in the context menu of a GPO; `New-PSGPOLink`, `Set-PSGPOLink`, `Remove-PSGPOLink`, `Set-PSGPOInheritance` and `Set-PSGPO -Status` do the same in scripts (`-Target`: a distinguished name, the domain, or the name of an OU). Each change reads the `gPLink` (or `gPOptions`) again, sends only what changes, and writes it in one request that removes the value read: a change another console made meanwhile is kept, and the objects of the links stay those the window or a script holds
* Configuration of PSGPOTools for the domain, in a PowerShell data file: Resources/Configuration.psd1 of the module (every setting with its default, commented), and over it the configuration of the domain, SYSVOL\<domain>\PSGPOTools\Configuration.psd1 on the domain controller the console reads, with the settings it changes: the same for every console of the domain, written only by its administrators (SYSVOL), never a configuration of the user, and no local file to say where it is. Read as data and checked (a wrong one is reported and left out). It sets what the window proposes for a new GPO: its name and status, and its security filtering groups (created or not, container, prefixes, scope Global / DomainLocal / Universal, descriptions), and the labels of the approved versions and of the templates. `Get-PSGPOConfiguration` shows it
* Settings window of the console: every setting with its value, its default and where it comes from; a value is set (created or changed) or removed (the default applies again), checked before it is kept, and Save writes the configuration of the domain, refused to an account that is not an administrator of the domain; a directory that cannot be written shows it without saving it
* GPO creation from Windows with the Group Policy Management tools of RSAT (New-GPO, on the domain controller of the directory), and the security filtering groups from Windows: the ACL of the SYSVOL folder set through its UNC path, without the ACEs of the extended rights as GPMC does
* Approval workflow of the GPOs, with the rights of the domain only (Workflow in the configuration of the domain: Enabled, Approvers, Creators, ApprovedOwner, CreatorRights). The role of the account is read in its groups (tokenGroups). `Initialize-PSGPOWorkflow` (by an approver) delegates the creation of GPOs to the groups of creators without Group Policy Creator Owners: create groupPolicyContainer objects in CN=Policies, list, read and create folders in the Policies folder of SYSVOL, CREATOR OWNER full control of what it creates; it says what is there and what is missing, and adds it with -Apply. A GPO a creator makes waits for its approval: it applies to nobody ("Apply Group Policy" removed), the groups of creators of its creator edit it, its rights set on every file of its folder while the creator owns them (Samba only changes the POSIX ACL of a file for its owner); a workflow that cannot be read stops the creation of GPOs. `Approve-PSGPO`, and "Approve..." in the window for an approver: the GPO, the containers it holds, its SYSVOL folder and every file in it are owned by the owner of the approved GPOs (an owner can always change the permissions), the ACEs of the creator and of the creators are removed, the groups of creators read it or still edit its settings (each change then differs from its approved version), it applies to the group chosen and is denied to another, and it is backed up as its approved version. The approver can create the security filtering groups of the GPO there (`Approve-PSGPO -CreateFilteringGroups -GroupContainer`, a check box in the window), as the New GPO form does: the GPO applies to APPLY_<GPO> and is denied to DENY_<GPO>, and is not approved when they cannot be created; the groups APPLY_<GPO> and DENY_<GPO> that exist already are proposed. A creator is not offered the groups at the creation: a GPO waiting for its approval applies to nobody. A pending GPO shows "(waiting for approval)" in the tree, its state and owner in its details; the details of the domain show the role of the account
* Deletion of a GPO, as GPMC "Delete": its links in the domain first (refused when the account cannot delete one of them), then the GPO, its container and its SYSVOL folder (Remove-GPO of RSAT on Windows, samba-tool gpo del on Linux), checked gone; the Default Domain Policy and the Default Domain Controllers Policy are never deleted. `Remove-PSGPO`, and "Delete GPO..." in the context menu of Group Policy Objects, both backing the GPO up first, its last backup saying when and by whom it was deleted
* Recycle bin of the GPOs, from their backups: "Deleted GPOs" in the tree and `Get-PSGPOBackup -Deleted` list the GPOs deleted from the domain, and `Restore-PSGPO` (or "Restore..." in the window) creates one again from its backup: a new GPO (new GUID from the domain) with its name, settings, status and client-side extensions, linked again where it was with -RestoreLink when its security filtering was Authenticated Users and its links enabled (its security filtering is not restored: it says so); the new GPO is backed up at once, saying where it comes from
* Templates of new GPOs: the backups with the template label of the configuration (Backup.TemplateLabel, 'Template' by default; a check box in the notes of a backup) are proposed in "Start from" of the New GPO form, and `New-PSGPO -Template`: the new GPO starts with their settings, checked against their SHA-256, whatever domain they come from. `New-PSGPO` creates a GPO, empty or from a template, with its status
* Notes of the backups: a comment (why the GPO changed, the ticket of the change) and labels, kept in notes.json beside the backup (its manifest and files do not change, so a restore still checks them), with who changed them and when; `Backup-PSGPO -Comment -Label -Approve`, `Set-PSGPOBackup` to change them later, `Get-PSGPOBackup -Label / -Approved`. The backup made before a restore says so in its comment
* Approved versions and drift, as the uncontrolled changes of AGPM: the newest backup with the approved label of the configuration (Backup.ApprovedLabel, 'Approved' by default) is the approved version of the GPO; `Get-PSGPODrift` compares each GPO to it setting by setting (InSync, Drifted with the changes, NotApproved), whoever changed it and with what tool
* History tab: a comment for the next backup, the labels of each backup under its node and its comment as tool tip, the approved version in green, the notes of the selected backup to change (comment, labels, approved version), and over the timeline whether the GPO is its approved version or what changed since
* "Link an Existing GPO..." in the context menu of the domain and of the OUs the account can link to, as GPMC: the GPOs of the domain not linked there yet, searched by name; the link is added last (lowest precedence)

* The Avalonia runtime of the window is installed on its first opening, for the runtime of the computer (win-x64, win-arm64, linux-x64, linux-arm64, osx): the 21 NuGet packages of Resources/AvaloniaPackages.json, downloaded from nuget.org and each checked against its pinned SHA-512 (the hash of the nuget.org catalog) before anything is extracted, then put in place at once; in the module when it can be written to, else in the data folder of the user. PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1 forbids the download; Get-AvaloniaBinaries.ps1 installs it beforehand, or for another computer

* Group Policy Preferences ([MS-GPPREF]): the policy editor has, for the computers and the users, Preferences > Windows Settings and Control Panel Settings with the 21 preference types (Resources/Preferences.json: their file, elements, CLSIDs and client-side extensions from [MS-GPPREF] 1.9 and 2.2.1). The items of the GPO are listed in their order and created, edited, moved and deleted with a form generated from their type, for the 35 item types of the 21 preference types: Drive Maps, Environment, Files, Folders, Ini Files, Registry, Network Shares, Shortcuts, Data Sources, Devices, Local Users and Groups (with their members), Printers (shared, TCP/IP, local), Services, and Folder Options, Network Options, Power Options, Regional Options, Start Menu whose fields come from their [MS-GPPREF] schema; what an item holds as XML (the Task Scheduler definition of a scheduled or immediate task, the Reg values of Internet Settings, the elements of an application) is edited as XML, checked before it is written, a valid task given as a start. The common options of every item: description, continue after an error, user context, remove when no longer applied. The XML is read and written with System.Xml as GPMC writes it (clsid, uid, changed in UTC, image of the action), keeping what the console does not edit (item-level targeting, unknown attributes); the file is written in Preferences of the GPO, its version increases and the extension is declared with its tool, and under the null extension as GPMC does
* Passwords are never written in preferences: the cpassword attribute is encrypted with a key Microsoft published, readable by every user of the domain (MS14-025); an item that stores one is reported, and its password kept as it is
* The Settings tab, the backups and the history show the preference items, compared item by item (by their uid, the XML they hold by its hash)
* The preferences have their own icons and colour in the tree of the editor (Fluent UI icons toolbox and wrench)

* Backups of GPOs: `Backup-PSGPO` keeps the files of the SYSVOL folder of each GPO and a manifest (versions, status, security filtering, links, client-side extensions, SHA-256 of each file) in <root>/<GPO name> {<GUID>}/<last change>/, only when the GPO changed since its last backup; `Get-PSGPOBackup` lists them; `Compare-PSGPOBackup` tells what changed between two backups setting by setting (policies by category path, security settings, other files, status, security filtering, links), Added, Removed or Changed with the value before and after. From Windows and Linux, against Windows and Samba domain controllers
* `Restore-PSGPO`: puts a GPO back as a backup has it, like GPMC Restore-GPO (its files, the files the backup does not have deleted, its status and client-side extensions; its version increases in both scopes), after checking the files of the backup against their SHA-256 and backing up the GPO as it is now; its links and permissions do not change
* History tab of a GPO: its backups as a timeline, as a git graph (oldest on the left, the GPO now when it changed since its last backup), what changed at the selected one, Back up now / Back up all GPOs, and Restore this version once confirmed

* Delegation (RBAC): the console shows what the account it reads the domain with manages, from the delegations of the domain (the attributes and classes it may write, allowedAttributesEffective and allowedChildClassesEffective). A Tier 1 or Tier 2 technician sees the OUs where it links GPOs, their parents greyed as the path to them, and the GPOs it edits or that are linked to its OUs; the menus offer only what it may do (create, link, edit, delete a link), and the directory refuses the rest before asking the domain. A domain administrator sees everything. This is not a security boundary: the permissions of the domain are
* The account the directory is read with ("Who am I?", RFC 4532) in the title, the status bar and the details of the domain, with the rights of the account in the details of each OU and GPO
* `CI/New-TierDelegationLab.ps1`: builds a tiered delegation lab in a test domain (OU=Tier 1 and OU=Tier 2, their delegated groups with "Link GPOs" on their OUs, a GPO per tier they edit)

* `Show-GPOManagerAvalonia` asks for the ADMX files when none is loaded: a window proposes the PolicyDefinitions folders found on this computer (the central store of the domain on Windows, the folder chosen last, the folder of Windows, the SYSVOL of a Samba domain controller, the copy next to the module) or another one (typed, or picked with the folder picker of the system), and the language of its ADML files; it loads them and remembers the choice for the next time (settings.json in the configuration folder of the user). The console does not open without them; `-PolicyDefinitions` and `-UICulture` load a folder without asking
* `Initialize-PSGPOAdmx` detects the language from the names of the language folders of PolicyDefinitions when `-UICulture` is not given: the language of the session, else the same language in another country, else en-US, else the only one there is; it asks for `-UICulture` when several languages remain

* Security filtering in the details of a GPO, as the Scope tab of GPMC: who applies it and who is denied it (the "Apply Group Policy" extended right of its DACL), by name; read for every GPO with the domain, in one search, the names resolved in the domain
* Deleting a link from the context menu of a link, once confirmed, as GPMC: the GPO itself is kept, the following links move up one link order; the gPLink is removed with the last link, as samba-tool gpo dellink does, and the change is refused when the links changed in the domain meanwhile

* New GPO: its GPO status (computer settings only, user settings only), written to the flags of the group policy container as samba-tool gpo create has no option for it; and optionally its security filtering groups APPLY_<GPO> (only its members apply the GPO) and DENY_<GPO> (its members never apply it), global security groups created in the users container or an OU. Authenticated Users keep reading the GPO (MS16-072); the ACL of its SYSVOL folder is derived from the directory one as samba-tool does, so that samba-tool gpo aclcheck finds them consistent. A GPO whose filtering failed is not linked, and the window says what was done and what failed
* `GPOToolsSecurityDescriptor`: security descriptors read and written byte for byte on any platform (the ACL classes of .NET are Windows-only), with their SDDL and the SYSVOL ACL of a GPO derived from its directory ACL

* Policy editor on a GPO: "Configured settings only" shows only the policies its Registry.pol files configure and the security settings its GptTmpl.inf defines, their folders expanded; it combines with the search
* Security settings of a GPO (GptTmpl.inf, [MS-GPSB]): read and written byte for byte (`GPOToolsSecurityTemplate`), with a catalog of 189 settings as the Group Policy editor shows them (password, account lockout and Kerberos policies, audit policy, user rights assignment, security options, event logs). Edited in the policy editor under Machine > Windows Settings > Security Settings ("Not Defined" / "Define this policy setting", the value checked against its range or choices) and listed in the Settings tab; saving increases the computer version and declares the Security client-side extension. Checked on a Samba 4.22 domain controller, which reads back the file (samba-tool gpo manage security list)
* `CI/Update-SecurityOptionCatalog.ps1` generates the catalog of the security options stored as registry values from the catalog of Windows (SeCEdit Reg Values, or sceregvl.inf)
* GPO creation in the domain (samba-tool gpo create against the domain controller of the directory: group policy container, SYSVOL folder and its permissions) and GPO links written to the gPLink of the domain or OU over LDAP, with the lowest precedence; the links are read again before writing and the change is refused when they changed meanwhile
* Registry.pol read and written byte for byte on any platform (`GPOToolsRegistryPol`): header, entries of every type, **del. / **delvals. deletions
* Setting of a policy read from and written to a Registry.pol: state and option values (Get-PSGPOPolicyState), and a new setting replacing only the entries of the policy (Set-PSGPOPolicyState); checked on every policy of the Windows ADMX set (written, read back and cleared, enabled and disabled)
* Policy editor on a GPO: each policy shows the setting its Registry.pol holds, and Apply saves it in SYSVOL (smbclient with Kerberos on Linux, UNC path on Windows), increasing the version of the GPO in GPT.INI and in the directory and declaring the Registry client-side extension
* GPMC-like Settings tab of a GPO: configured policies by Computer / User Configuration with their category path, state and option values, and the Extra Registry Settings
* `Show-GPOManagerAvalonia` reads the domain at launch (domain of the computer, the domain controller it runs on, or `-Server` with `-Credential` / `-UseSsl`) and opens on the Group Policy Management view; it shows why when the domain cannot be read, and the sample directory under a "demonstration environment" banner when no domain is discovered; `-NoDirectory` opens the policy editor only
* The window names the directory service of the domain controller, Active Directory or Samba AD (vendorName of the rootDSE), in its subtitle and in the details of the domain
* GUI status bar: this computer (name, system, domain controller role), its addresses, its domain and the domain controller the directory was read from
* `Get-PSGPODirectory`: reads the domain, its OUs, GPO links (gPLink by link order, enforced and disabled links, links to missing GPOs) and blocked inheritance, and the GPOs (versions, status, SYSVOL path) over LDAP, from Windows and Linux, for Windows and Samba domain controllers; Kerberos with the current identity, or a password over LDAPS only. The directory is read-only for now: the window offers no GPO creation on it
* Platform detection (private `Get-PSGPOPlatform`, kept in `$script:PSGPOPlatform`): operating system, domain of the computer, Windows or Samba domain controller (smb.conf server role), Kerberos realm, samba-tool and the native LDAP library
* Tests against a real domain controller, run when `PSGPOTOOLS_TEST_LDAP_SERVER` names one
* GUI Group Policy Management view (proof of concept): domain, OUs, GPO links by link order and the Group Policy Objects container, with a details panel (links of an OU, links and versions of a GPO) and a context menu to create a GPO (linked to the selected domain or OU, or unlinked) and to edit a GPO in the policy editor
* `Import-PSGPODirectory`: reads the domain of the view from JSON; `Samples/Directory.sample.json` describes a realistic domain (tiering, sites, servers by role, blocked inheritance, enforced and disabled links)
* GUI setting form generated from the ADMX elements and the ADML presentation, in presentation order: Not Configured / Enabled / Disabled, check boxes, drop-down lists (sorted unless `noSort`), bounded numeric boxes, text, multi-line text, editable lists (with name/value pairs for `explicitValue` lists) and explanation texts
* GUI registry preview: what the setting writes (the future Registry.pol content), refreshed on every edit, with validation messages (required, bounds, length)
* `Get-PSGPOPolicyRegistryChange` (private): registry values written for a state and the entered values, including list encoding (`valuePrefix`, `explicitValue`, `additive`) and the editor defaults flagged `Implicit`
* Complete registry model of the policies: `EnabledValues` / `DisabledValues` (enabledValue, disabledValue, enabledList, disabledList; decimal, longDecimal, string and delete values) and `Elements` (boolean, decimal, longDecimal, text, multiText, enum, list) with the schema defaults and their ADML presentation (control, label, default value, localized enum choices)
* Values that the ADMX does not write but the policy editor does (DWORD 1 when enabled, deletion when disabled) are flagged `Implicit`, to be confirmed against the GPMC
* The GUI details grid shows every registry value of the selected policy
* Linux job in the CI running every test, the GUI included (Avalonia X11 backend under Xvfb)

### Fixed

* Windows, a domain read with -Credential: SYSVOL was written with the identity of the session while the directory was written with the account given. SYSVOL is now reached with that account too, through an SMB connection to the share (as net use); a conflict with another account of the session is said, with how to close it
* Security: the approval of a GPO now rebuilds its permissions from what an approved GPO may hold (the allow ACEs of its possible owners and of CREATOR OWNER, the read of Authenticated Users and of the domain controllers), instead of only removing the ACEs of the creator and of the creators: an ACE the creator added outside the console while it owned the GPO (full control for another account, a deny ACE, OWNER RIGHTS) kept it in control of the approved GPO. Those ACEs are removed and reported (`RemovedPermissions` of `Approve-PSGPO`, a warning, the window, the comment of the approved backup); on Windows, the files of the SYSVOL folder lose their explicit ACEs and only inherit the folder
* Security: the approval writes SYSVOL first, then the containers the GPO holds, then the GPO, whose owner makes it approved: a failure left a GPO approved, and applied, with a SYSVOL folder its creator still owned. It now stays pending, and can be approved again
* Security: a pending GPO someone gave "Apply Group Policy" back to (its creator owns it) was shown as applying to nobody; the tree ("(waiting for approval, but it applies)", in red), its details and the approval form now say who it applies to, and the approval form shows where it is linked
* Security: the role of the account failed open when the server did not say which account the console used (LDAP "Who am I?") or that account was not found: neither creator nor approver, it created approved GPOs. No GPO can be created then, until it is fixed; an answer in the dn: form is resolved
* Security: the SID of the domain was taken from the owner of the approved GPOs: with a builtin group (Administrators), every GPO of Domain Admins was shown pending. It is read from the domain
* Security: an error other than a missing group, looking for the APPLY_ and DENY_ groups of a GPO to approve, made it apply to Authenticated Users; it now stops the approval
* Security: the paths of the files of a backup (manifest.json) were not checked: `..` wrote outside the GPO folder in SYSVOL (another GPO, or outside Policies) at a restore or from a template. A path outside the GPO folder makes the backup ignored, with a warning, and SYSVOL writes refuse it
* Security: `Restore-PSGPO` restored a backup of another domain on a GPO of this domain with its GUID, as the Default Domain Policy and the Default Domain Controllers Policy have in every domain; a backup of another domain is never restored (a template instead)
* Saving a setting wrote the whole file from the copy read with the GPO, without checking the GPO had not changed since: a setting another console or GPMC wrote meanwhile was lost without a word. The version of the GPO in the domain is now compared with the one read, and nothing is written when it changed
* A deleted GPO left the recycle bin even when its settings could not be restored; it now stays there
* A file the restore could not delete on Windows was kept without an error
* One damaged manifest made Get-PSGPOBackup, the drift and the recycle bin fail; it is ignored, with a warning
* `Backup-PSGPO` and `Get-PSGPODrift` skipped one of two GPOs with the same name; a GPO name with brackets (`Servers [Lyon]`) was taken as a wildcard pattern by the commands (`-Name`), matching nothing or failing: it is the name, and `*` or `?` make a pattern
* The user version of a GPO was negative from 0x8000
* `Get-PSGPOCategory`, `Get-PSGPOPolicy` and `Get-PSGPOSupportedOn` had no help
* The CI did not run on master, without a time limit, and its cache of the Avalonia runtime was not renewed when its packages changed
* The documentation said the vendorName of Samba is "Samba AD", the read mask of a file 0x1200A9 for every ACE, the tests run on Windows only, and that the status of a GPO is set at any time (at its creation only)

* The policy editor was empty without ADMX files loaded (Linux without `Initialize-PSGPOAdmx`), so the security settings of a GPO (the Default Domain Policy for example) could not be edited: they are now always shown, the breadcrumb saying that no ADMX policy is loaded
* The window froze when creating a GPO from a terminal: samba-tool gpo create asks for a password on it even with Kerberos. samba-tool and smbclient now run without standard input (samba-tool also with --no-pass) and are stopped after a time limit, with an error, instead of waiting forever
* Writing a file deeper than one folder in SYSVOL from Linux (Split-Path turned its \ into /, so smbclient created no intermediate folder)
* The registry preview wrote a value twice when an element writes the value of the policy itself (valueName without enabledValue): the element value is kept, the editor default of the policy dropped
* GUI details panels: the end of long values (distinguished names, SYSVOL paths) was cut under the right border: Avalonia measured the content of a padded scroll viewer on its full width; the padding is now a margin of the content
* GUI tests: a check of the preview position could pass without proof when the row could not be placed in the window
* GUI trees: selecting a node with a long name scrolled the tree horizontally and cut the domain and the OUs (seen on Linux); long names are now trimmed, with the full name as tooltip
* GUI: the Not Configured / Enabled / Disabled radio buttons shared a group name with those of the previously opened windows, so opening a window could run a handler of a closed one
* GUI copy to the clipboard: a failed copy is now reported with a warning instead of being silently lost
* Linux: `Get-AvaloniaBinaries.ps1 -Rid linux-x64` did not download `Tmds.DBus.Protocol`, required by Avalonia.FreeDesktop, and built its package paths with `\`
* Linux: ADML files whose case differs from their ADMX (InetRes.adml, KDC.adml, Messaging.adml, as shipped by Microsoft) and culture folders are now found on case-sensitive file systems; the .admx extension is compared case-insensitively
* GUI registry preview rows were never displayed (the DataGrid kept its header height inside the scroll viewer): the preview is now a list showing the key with its hive, the value name, the Windows type and the data, as selectable text
* GUI details: the setting form and the ADMX details are split into Setting / Details tabs, and the "Registry Key" field that showed the value name is now labelled "Value Name"
* `Show-GPOManagerAvalonia` failed with "Setup was already called" after the module was re-imported in the same session
* Policies of class `Both` (about a third of the Windows ADMX set) only existed in the User scope; they now exist once per scope, with the matching hive
* ADML paths, the Avalonia runtime path and the build no longer rely on `\` separators (Linux/macOS)
* `Initialize-PSGPOAdmx` requires `-Path` outside Windows instead of failing on `$Env:windir`
* `Get-PSGPOCategory` and `Get-PSGPOSupportedOn` never warned that nothing was loaded
* Parent categories referenced through a local prefix alias (e.g. `netcon:NetworkConnections`) were not found: Windows Defender Firewall and Preference snap-in extensions are no longer root categories
* GUI tree skipped each policy's own category: policies were shown one level too high
* GUI theme toggle assumed a light start while the window follows the OS theme
* `Get-PSGPOPolicy` without `-Scope` returned only User policies; it now returns all policies
* Category loading from `Code/` loaded no category (`[void]` cast on the pipeline input)
* Parent categories defined later in the same ADMX were silently dropped (22 orphan categories on the Windows ADMX set)
* Category presence check never matched because of a wrong overload parameter type
* `Code/` was missing the DataGrid fix and the `-Scope` parameter present only in the generated module

### Changed

* The policy editor shows Computer Configuration (Machine) first, then User Configuration, as the Group Policy editor does
* CI: PSScriptAnalyzer checks the sources (`PSScriptAnalyzerSettings.psd1`, no error and no warning allowed), and a test that every command that writes supports -WhatIf and -Confirm; `Backup-PSGPO` now does. Fixed what it found: comparisons with $null on the right, ConvertTo-Json without -InputObject, a dynamic member call, empty catch blocks, `$sender` assigned in event handlers, private functions with plural nouns
* Performance: the Settings tab of a GPO and the comparison of backups read a Registry.pol of a security baseline (380 entries) in under a second, instead of 34 s: the registry values of each policy are computed once for the loaded ADMX, and its entries found by key. Reading a domain of 2 000 GPOs sorts them once (it sorted them at each one: 140 s), and resolves the links and the OUs by distinguished name; the GPOs a delegated account sees are found in one pass over the tree
* The ADMX of Windows 11 26H2 in `sources/PolicyDefinitions` (236 ADMX files, the language folders in lower case)
* CI: a third job, `test-samba`, runs the tests that write to a domain against a Samba AD DC provisioned on the runner, with a Kerberos ticket; `CI/Invoke-Tests.ps1 -Path` runs some test files
* The build updates the exports of the manifest only when the public functions change; the manifest names this repository, its license, its changes and its authors
* README, contributing and the bug report template rewritten for the console; SECURITY.md says how to report a vulnerability and what the console relies on

* GUI icons: Microsoft Fluent UI System Icons (the Windows 11 icons, MIT license) are shipped with the module in `Resources/Icons` and drawn as vector paths, coloured by kind (OUs, blocked inheritance, links, enforced and disabled links, GPOs, User / Machine); they replace the emoji, drawn as empty boxes on Linux desktops without an emoji font
* Tests rewritten for Pester 5+, with new tests for the public functions and the Avalonia GUI (real window driven through a private test hook); `CI/Invoke-Tests.ps1` builds and runs them, also in a GitHub Actions workflow
* `Initialize-PSGPOAdmx` is about 5x faster (~20 s -> ~4 s on the Windows ADMX set): categories and ADMX namespaces are indexed, ADML strings are read through the hashtable indexer
* GUI context menu: the Enable/Disable/Create GPO placeholders (they only wrote to the console) are replaced by working copy actions (policy name, registry path, PowerShell command)
* GUI text is English only, the tree is built in linear time and a warning is shown when no policy is loaded
* Avalonia is the only GUI: the WPF `Show-GPOManager` and its notes were removed
* The manifest targets PowerShell 7.4+ (`Core` edition) and exports only the public functions
* `PSGPOTools.psm1` is no longer versioned; build it with `CI/03_Build.ps1`

## 0.01.1 - alpha

### Fixed

### Added

### Changed

- Change description manifeste

### Feature's Module

- [x] Read the principal content of ADMX and ADML files
    - [x] Categories
    - [x] SupportedOn
    - [x] Policy
    - [x] Simple Policy's key
- [x] Choice the UICulture

### Features Repository

- [ ] CI Task
    - [x] Build module
    - [ ] Test Module
    - [ ] Publish Module

## 0.01.0 - alpha

### Feature's Module

- [x] Read the principal content of ADMX and ADML files
    - [x] Categories
    - [x] SupportedOn
    - [x] Policy
    - [x] Simple Policy's key
- [x] Choice the UICulture

### Features Repository

- [ ] CI Task
    - [ ] Build module
    - [ ] Test Module
    - [ ] Publish Module

