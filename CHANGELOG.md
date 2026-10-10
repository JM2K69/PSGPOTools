# PSGPOTools Release History

## Unreleased

### Added

* GUI setting form generated from the ADMX elements and the ADML presentation, in presentation order: Not Configured / Enabled / Disabled, check boxes, drop-down lists (sorted unless `noSort`), bounded numeric boxes, text, multi-line text, editable lists (with name/value pairs for `explicitValue` lists) and explanation texts
* GUI registry preview: what the setting writes (the future Registry.pol content), refreshed on every edit, with validation messages (required, bounds, length)
* `Get-PSGPOPolicyRegistryChange` (private): registry values written for a state and the entered values, including list encoding (`valuePrefix`, `explicitValue`, `additive`) and the editor defaults flagged `Implicit`
* Complete registry model of the policies: `EnabledValues` / `DisabledValues` (enabledValue, disabledValue, enabledList, disabledList; decimal, longDecimal, string and delete values) and `Elements` (boolean, decimal, longDecimal, text, multiText, enum, list) with the schema defaults and their ADML presentation (control, label, default value, localized enum choices)
* Values that the ADMX does not write but the policy editor does (DWORD 1 when enabled, deletion when disabled) are flagged `Implicit`, to be confirmed against the GPMC
* The GUI details grid shows every registry value of the selected policy
* Linux job in the CI (model and public functions)

### Fixed

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

