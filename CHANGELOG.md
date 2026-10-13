# PSGPOTools Release History

## Unreleased

### Added

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

*Change description manifeste

### Feature's Module

  *[x] Read the principal content of ADMX and ADML files
    *[x] Categories
    *[x] SupportedOn
    *[x] Policy
    *[x] Simple Policy's key
  *[x] Choice the UICulture

### Features Repository

  *[ ] CI Task
    *[X] Build module
    *[ ] Test Module
    *[ ] Publish Module

## 0.01.0 - alpha

### Feature's Module

  *[x] Read the principal content of ADMX and ADML files
    *[x] Categories
    *[x] SupportedOn
    *[x] Policy
    *[x] Simple Policy's key
  *[x] Choice the UICulture

### Features Repository

  *[ ] CI Task
    *[ ] Build module
    *[ ] Test Module
    *[ ] Publish Module

