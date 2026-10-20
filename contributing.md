# Contributing

Thanks for taking the time to contribute. PSGPOTools changes the Group Policy of real domains,
often with the rights of a Tier 0 account: every change is reviewed with that in mind.

## Code of Conduct

This project follows its [code of conduct](code-of-conduct.md).

## Reporting a bug

Check the [issues](https://github.com/JM2K69/PSGPOTools/issues) first, then open one with the
bug report template. What helps most:

- the version of the module (or the commit), of PowerShell (`$PSVersionTable`) and of the system;
- the domain controller: **Samba AD** (its version, `samba -V`) or **Windows Server** (its version);
- the console runs on Windows or Linux, with which account (an administrator, a delegated Tier 1);
- the exact steps, the command or the action of the console, and the whole error
  (`$Error[0] | Format-List * -Force` gives its stack);
- what you expected instead.

Remove what is private (names, SIDs, addresses) from logs and screenshots, and say where you did.

A security issue is not reported in an issue: see [SECURITY.md](SECURITY.md).

## Suggesting a feature

Open an issue with the feature request template: what you need to do, how you do it today (GPMC,
AGPM, a script), and how it would work on Samba AD and on Windows AD.

## Code

### The constraints of the project

- **PowerShell 7.4+ and Avalonia only**: no WPF, no Windows PowerShell 5.1, no compiled .NET code.
- **Windows and Linux**, **Samba AD and Windows AD**: a feature works on all four, or says clearly
  where it does not.
- **The rights are those of the domain**: the console never decides alone what an account may do;
  it reads the rights the domain gives, and the domain controller refuses the rest.
- **Fail closed**: when something cannot be checked, the console refuses rather than risk a GPO
  that applies to everyone.

### Build and tests

The sources are in `Code/` (`Classes`, `Functions/Private`, `Functions/Public`).
`CI/03_Build.ps1` concatenates them into `PSGPOTools/PSGPOTools.psm1`, which is not versioned:
always edit `Code/`, then build.

```powershell
pwsh -File CI/03_Build.ps1
pwsh -File CI/Invoke-Tests.ps1                                   # every test (Pester 5.5+)
pwsh -File CI/Invoke-Tests.ps1 -Path CI/tests/PSGPOTools.Backup.tests.ps1
Invoke-ScriptAnalyzer -Path ./Code -Recurse -Settings ./PSScriptAnalyzerSettings.psd1   # no error, no warning
```

The GUI tests open the real window; they are skipped when the Avalonia runtime is not installed
(`PSGPOTools/Avalonia/Get-AvaloniaBinaries.ps1`, after the build). The tests that write to a
domain run when `PSGPOTOOLS_TEST_LDAP_SERVER` names a domain controller and
`PSGPOTOOLS_TEST_LDAP_WRITE=1` (with a Kerberos ticket on Linux): use a test domain, they create
and delete GPOs. The [technical documentation](https://jm2k69.github.io/PSGPOTools/en/technical/tests/)
describes the suite.

### Releases

A commit never publishes the module: the CI only tests it. A version is published on the
[PowerShell Gallery](https://www.powershellgallery.com/packages/PSGPOTools) when its tag is pushed:

1. In `PSGPOTools/PSGPOTools.psd1`, `ModuleVersion` (and `Prerelease`, `alpha` while the module is
   one); in `CHANGELOG.md`, the changes under `## <ModuleVersion> - <Prerelease>` (`## 0.1.2 - alpha`).
2. Check it: `./CI/03_Build.ps1; ./CI/04_Publish.ps1 -Tag v0.1.2-alpha` (without `-ApiKey`, nothing is sent).
3. Tag the commit and push the tag: `git tag v0.1.2-alpha; git push origin v0.1.2-alpha`.

The Release workflow (`.github/workflows/release.yml`) runs every test of the CI on the tagged
commit, then `CI/04_Publish.ps1`: the tag must be the version of the manifest, the version must have
its section in the changelog and not be on the gallery yet. It publishes the module without the
Avalonia runtime (downloaded at the first window), then creates the release of GitHub with the notes
of the changelog. The API key is the secret `PSGALLERY_API_KEY` of the environment `psgallery` of the
repository (Settings > Environments), whose rules (a reviewer to approve) apply before it is given.

### Pull requests

- One goal per pull request, with what it changes and why.
- Tests: a bug fix comes with the test that failed before it; a feature with tests of what it
  does and of what it refuses.
- The documentation (`docs/en` and `docs/fr`) and the `CHANGELOG.md` follow the change.
- A public command has a comment-based help (synopsis, each parameter, an example) whose first `.LINK` is
  its page on the site; after a change of a help, `./CI/03_Build.ps1; ./CI/Update-CommandReference.ps1`
  writes the pages of the commands again (a test checks they are those of the help).

- After a change of the ADMX files of the repository (`sources/PolicyDefinitions`),
  `./CI/03_Build.ps1; ./CI/Update-AdmxCatalog.ps1` pins them again for `Install-PSGPOAdmx`.
- Write like the code around: its names, its comments (why, not what), its error messages (what
  happened and what to do).
- The CI must pass on Windows, Linux and against Samba.
