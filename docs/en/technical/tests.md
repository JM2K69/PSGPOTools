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

With `PSGPOTOOLS_TEST_LAB_SCRIPTS=1` too (Linux), they run the Linux scripts of the
[lab](../getting-started/lab.md), `New-PSGPOTierLab.ps1` and `Grant-PSGPOTierDelegation.ps1`, twice
each: the OUs, groups and accounts of the tiers, the password of the lab (a Kerberos ticket of
`tiers1`), the delegation of the links and of the creation of GPOs (the workflow enabled for the test). They change the domain for
good: the job `test-samba` of the CI sets it, on its throwaway domain only.

The writes of an approval (`PSGPOTools.Hardening.tests.ps1`) are tested with mocks: their order
(SYSVOL, the objects the GPO holds, then the GPO), the GPO left pending when SYSVOL fails, the
permissions removed and reported. The whole workflow, which needs two accounts (Tier 0 and
Tier 1), was tested step by step in the lab, `kinit` changing the account between the steps
([approval](../workflows/approval.md)).

## CI

`.github/workflows/ci.yml` runs three jobs on each push to `master` and `main`, and on each pull request:

| Job | Runs |
|---|---|
| `test` | PSScriptAnalyzer on `Code/` (`PSScriptAnalyzerSettings.psd1`: no error, no warning), then every test on `windows-latest`, the window included |
| `test-linux` | every test on `ubuntu-latest`, the window included (Avalonia on Xvfb) |
| `test-samba` | the tests that write to a domain, against a Samba AD DC provisioned on the runner (`CI.TEST`), with a Kerberos ticket of its administrator |

The page of each public command (`docs/<language>/reference/commands/`, and its entry in the menu) is
written from its help by `CI/Update-CommandReference.ps1`, after `CI/03_Build.ps1`; the first `.LINK` of
the help of a command is its page, which `Get-Help <command> -Online` opens. A test checks that the pages
are those of the help.

`Install-PSGPOAdmx` downloads `sources/PolicyDefinitions` from GitHub and installs only the files that
`HGPM/Resources/PolicyDefinitions.json` pins (each set, the `.admx` files and each language: its
number of files and a SHA-256, line endings and case of the names aside). After a change of
`sources/PolicyDefinitions`, `CI/Update-AdmxCatalog.ps1` writes the catalog again; a test checks it.

`.github/workflows/release.yml` publishes the module on the PowerShell Gallery for a tag of a version
(`v0.1.2-alpha`) only, never for a commit: it runs the three jobs of the CI on the tagged commit, then
`CI/04_Publish.ps1` (the tag is the version of the manifest, `CHANGELOG.md` has its section, the gallery
does not have it yet) with the secret `PSGALLERY_API_KEY` of the environment `psgallery`, and creates the
release of GitHub with the notes of the version.

The documentation is built and published by `.github/workflows/docs.yml`. It makes the Changelog page from
`CHANGELOG.md`, and puts the version of the module (`ModuleVersion` of its manifest) and the commit the
site is built from in the footer of every page.
