# Tests

The tests are [Pester](https://pester.dev) 5 tests, in `CI/tests`, run against the built module.

```powershell
pwsh -File CI/03_Build.ps1
$Config = New-PesterConfiguration
$Config.Run.Path = 'CI/tests'
$Config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $Config
```

| File | Covers |
|---|---|
| `PSGPOTools.Model.tests.ps1`, `GPOToolsUtility.tests.ps1` | ADMX, ADML, categories, policies |
| `PSGPOTools.RegistryPol.tests.ps1`, `PSGPOTools.Setting.tests.ps1` | Registry.pol, the state of every policy of the ADMX set, settings reports |
| `PSGPOTools.AccessControl.tests.ps1` | security descriptors, security filtering, SYSVOL ACL |
| `PSGPOTools.Backup.tests.ps1` | backups, comparison, restore, notes, drift, recycle bin, templates |
| `PSGPOTools.Configuration.tests.ps1` | the configuration of the domain |
| `PSGPOTools.Workflow.tests.ps1` | the approval workflow |
| `PSGPOTools.Delegation.tests.ps1` | the rights read from the directory |
| `PSGPOTools.Ldap.tests.ps1` | LDAP, gPLink, samba-tool, RSAT (mocked), and against a domain controller |
| `PSGPOTools.Gui.tests.ps1` | the real window (`-OnShown`) |
| `PSGPOTools.Public.tests.ps1` | the commands exported |

## Against a domain controller

The integration tests run when a domain controller is given, with a Kerberos ticket of an
administrator of the domain:

```bash
kinit administrator@HARDENBOX.LABO
export PSGPOTOOLS_TEST_LDAP_SERVER=dc.hardenbox.labo   # reads the domain
export PSGPOTOOLS_TEST_LDAP_WRITE=1                    # also creates, links, writes and deletes
pwsh -c 'Invoke-Pester CI/tests'
```

With `PSGPOTOOLS_TEST_LDAP_WRITE=1`, they create an OU and GPOs named `PSGPOTools test ...`, link
them, write their settings, delete and restore one, and delete everything they created at the end,
whatever failed.

The approval workflow, which needs two accounts (Tier 0 and Tier 1), was tested step by step in
the lab, `kinit` changing the account between the steps ([approval](../workflows/approval.md)).

## CI

`.github/workflows/ci.yml` runs the tests on `windows-latest` (the window included); the
documentation is built and published by `.github/workflows/docs.yml`.
