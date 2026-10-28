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
| `PSGPOTools.Hardening.tests.ps1` | what a hostile file, attribute, tool or domain could do ([hardening](hardening.md)) |
| `PSGPOTools.Workflow.tests.ps1` | the approval workflow |
| `PSGPOTools.Delegation.tests.ps1` | the rights read from the directory |
| `PSGPOTools.Ldap.tests.ps1` | LDAP, gPLink, samba-tool, RSAT (mocked), and against a domain controller |
| `PSGPOTools.PasswordPolicy.tests.ps1` | the fine-grained password policies: the values of the directory, the checks, the PSO that applies and why, the commands |
| `PSGPOTools.Gui.tests.ps1` | the real windows of both consoles (`-OnShown`) |
| `PSGPOTools.Health.tests.ps1` | the health of the GPOs and their replication between domain controllers (three simulated) |
| `PSGPOTools.AvaloniaInstall.tests.ps1` | the Avalonia runtime: its pinned packages and files, where they come from, the checks before it is loaded |
| `PSGPOTools.WellKnownSid.tests.ps1` | the well-known accounts: their table, the names typed in English or French, the suggestions while typing and the completion of the commands |
| `PSGPOTools.Release.tests.ps1` | the build reproducible, the package of a release (SHA256SUMS, signature, catalog), the rules of the workflows |
| `PSGPOTools.Public.tests.ps1` | the commands exported |
| `PSGPOTools.Update.tests.ps1` | the versions of HGPM and `Test-PSGPOUpdate` (the Gallery mocked) |

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
whatever failed. For the password policies (Linux, `samba-tool`), they create a user, a global and
a domain local security group, and PSOs named `PSO test ...`: protected from accidental deletion,
renamed, applied directly and through the groups, a change made meanwhile refused, the PSO the
console finds compared with `msDS-ResultantPSO`; then they delete them.

With `PSGPOTOOLS_TEST_LAB_SCRIPTS=1` too (Linux), they run the Linux scripts of the
[lab](../getting-started/lab.md), `New-PSGPOTierLab.ps1` and `Grant-PSGPOTierDelegation.ps1`, twice
each: the OUs, groups and accounts of the tiers, the password of the lab (a Kerberos ticket of
`tiers1`), the delegation of the links and of the creation of GPOs (the workflow enabled for the test). They change the domain for
good: the job `test-samba` of the CI sets it, on its throwaway domain only.

The writes of an approval (`PSGPOTools.Hardening.tests.ps1`) are tested with mocks: their order
(SYSVOL, the objects the GPO holds, then the GPO), the GPO left pending when SYSVOL fails, the
permissions removed and reported. The whole workflow, with its two accounts, runs against the domain
controller too (*Approval written to a domain controller*), after the scripts of the lab:

- `tiers1`, in a process of its own with its Kerberos ticket, creates a GPO: it waits, nobody
  applies it; `tiers1` adds a permission of its own (Domain Users, full control);
- the administrator approves it: Domain Admins owns the GPO and its SYSVOL folder, the permission
  `tiers1` added and its own rights are gone (and reported), Authenticated Users applies it;
- `tiers1` cannot write it anymore;
- a GPO `tiers1` changes after its review is not approved, and stays pending.

The configuration of the domain is kept and written back byte for byte. On a lab of your own,
`PSGPOTOOLS_TEST_TIER1_CCACHE` gives the ticket of a creator (`FILE:/tmp/krb5cc_tiers1`) instead of
the password of the lab.

### What a job must run

`CI/Invoke-Tests.ps1 -RequireRun` names the blocks (`Describe`, `Context`, wildcards) a run is
there for: a test of them skipped with its block (a runtime of Avalonia missing, a variable of the
domain misnamed) or not run, or no test of them at all, fails the run. A test that skips itself for
another platform (`-Skip:$IsWindows`) does not. Each run writes a table of its files (passed,
failed, skipped, not run) to the summary of its job on GitHub (`GITHUB_STEP_SUMMARY`).

## CI

`.github/workflows/ci.yml` runs four jobs on each push to `master` and `main`, and on each pull request
(with the rights to read the repository only; the actions pinned to a commit, Pester, PSScriptAnalyzer
and the site generator to a version):

| Job | Runs |
|---|---|
| `build` | builds the module once (`CI/03_Build.ps1`), checks its manifest is the one of the repository, and gives it to the other jobs (the artifact `module`): they test this one, and the release publishes it |
| `test` | builds the module again on Windows and checks it is the same bytes (the build is reproducible), PSScriptAnalyzer on `Code/` (`PSScriptAnalyzerSettings.psd1`: no error, no warning), then every test on `windows-latest`; the windows must run (`-RequireRun`) |
| `test-linux` | every test on `ubuntu-latest` (Avalonia on Xvfb); the windows must run |
| `test-samba` | the tests that write to a domain, against a Samba AD DC provisioned on the runner (`CI.TEST`), with a Kerberos ticket of its administrator; the reading of the domain, the scripts of the lab, the approval, the changes and the password policies must run |

The page of each public command (`docs/<language>/reference/commands/`, and its entry in the menu) is
written from its help by `CI/Update-CommandReference.ps1`, after `CI/03_Build.ps1`; the first `.LINK` of
the help of a command is its page, which `Get-Help <command> -Online` opens. A test checks that the pages
are those of the help.

`Install-PSGPOAdmx` downloads `sources/PolicyDefinitions` from GitHub and installs only the files that
`HGPM/Resources/PolicyDefinitions.json` pins (each set, the `.admx` files and each language: its
number of files and a SHA-256, line endings and case of the names aside). After a change of
`sources/PolicyDefinitions`, `CI/Update-AdmxCatalog.ps1` writes the catalog again; a test checks it.

`.github/workflows/release.yml` publishes the module on the PowerShell Gallery for a tag of a version
(`v0.1.3-alpha`) only, never for a commit. It runs the jobs of the CI on the tagged commit, then, on
Windows, with the rights it needs and those only:

1. `CI/04_Publish.ps1` checks the version (the tag is the version of the manifest, `CHANGELOG.md` has its
   section, the gallery does not have it yet);
2. `CI/05_Package.ps1` makes the package from the module the tests ran (the artifact `module`, never a
   build of its own): signed with Authenticode, with its catalog `HGPM.cat`, when the secrets
   `CODE_SIGNING_PFX` (the PFX in Base64) and `CODE_SIGNING_PASSWORD` are given; its archive, the
   [offline archives](../getting-started/offline.md) with the Avalonia runtime of each platform, and
   `SHA256SUMS`;
3. `actions/attest` attests every file of `SHA256SUMS` (`gh attestation verify`);
4. `CI/04_Publish.ps1` publishes the package with the secret `PSGALLERY_API_KEY`, and the release of
   GitHub is created with the notes of the version, the archives and `SHA256SUMS`.

The secrets are those of the environment `psgallery`, whose protection rules apply before they are
given.

The documentation is built and published by `.github/workflows/docs.yml`. It makes the Changelog page from
`CHANGELOG.md`, and puts the version of the module (`ModuleVersion` of its manifest) and the commit the
site is built from in the footer of every page.
