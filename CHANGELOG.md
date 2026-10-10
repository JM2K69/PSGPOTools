# PSGPOTools Release History

## Unreleased

### Fixed

* `Get-PSGPOPolicy` without `-Scope` returned only User policies; it now returns all policies
* Category loading from `Code/` loaded no category (`[void]` cast on the pipeline input)
* Parent categories defined later in the same ADMX were silently dropped (22 orphan categories on the Windows ADMX set)
* Category presence check never matched because of a wrong overload parameter type
* `Code/` was missing the DataGrid fix and the `-Scope` parameter present only in the generated module

### Changed

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

