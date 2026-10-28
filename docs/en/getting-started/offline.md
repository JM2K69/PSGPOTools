# Offline installation

For an administration workstation (PAW) or a network without internet. Each release of GitHub has
the module with the Avalonia runtime of each platform, the SHA-256 of every file, and their
attestation: a proof, signed by GitHub, that they were built by the workflow of the repository from
the commit of the tag.

## What a release has

| File | What |
|---|---|
| `HGPM-<version>.zip` | the module, as on the PowerShell Gallery (without the Avalonia runtime) |
| `HGPM-<version>-win-x64.zip`, `-win-arm64`, `-linux-x64`, `-linux-arm64` | the module with the Avalonia runtime of the platform, in `Avalonia/bin/<rid>` |
| `SHA256SUMS` | the SHA-256 of each archive and of each file of the module |

The module of the archives, and of the PowerShell Gallery, is the one the tests of the CI ran: it is
built once, and the build is reproducible (the same bytes from the same sources, on Windows and on
Linux: the CI checks it at each commit).

## Check what you downloaded

The SHA-256 of an archive, against `SHA256SUMS`:

```powershell
$archive = 'HGPM-0.1.21-alpha-win-x64.zip'
$expected = (Get-Content SHA256SUMS | Where-Object { $_.EndsWith("  $archive") }).Split(' ')[0]
(Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -eq $expected
```

Its attestation, with the GitHub CLI (from a computer with internet):

```bash
gh attestation verify HGPM-0.1.21-alpha-win-x64.zip --repo JM2K69/PSGPOTools
```

It says the file was built by the Release workflow of the repository, from the commit of the tag,
and fails for any other file. A file of a module installed from the PowerShell Gallery is checked
the same way (`HGPM.psm1`, `HGPM.psd1`...): `SHA256SUMS` has each of them.

By default `gh` accepts any workflow of the repository, from any reference. On an administration
workstation, require the release workflow and the tag you expect: another tag, or a file attested
by another workflow, then fails.

```bash
gh attestation verify HGPM-0.1.21-alpha-win-x64.zip --repo JM2K69/PSGPOTools --signer-workflow JM2K69/PSGPOTools/.github/workflows/release.yml --source-ref refs/tags/v0.1.21-alpha
```

## Install it

Windows: unblock the archive before extracting it. Downloaded from the internet, its files would be
marked, and the execution policy `RemoteSigned` would refuse the scripts that are not signed.

```powershell
Unblock-File .\HGPM-0.1.21-alpha-win-x64.zip
Expand-Archive .\HGPM-0.1.21-alpha-win-x64.zip -DestinationPath $env:TEMP\HGPM-0.1.21
$modules = "$env:ProgramFiles\PowerShell\Modules\HGPM"      # all the users; $HOME\Documents\PowerShell\Modules\HGPM for one
New-Item -ItemType Directory -Path $modules -Force | Out-Null
Copy-Item $env:TEMP\HGPM-0.1.21\HGPM "$modules\0.1.21" -Recurse
```

Linux:

```bash
unzip HGPM-0.1.21-alpha-linux-x64.zip -d /tmp/hgpm
mkdir -p ~/.local/share/powershell/Modules/HGPM      # one user; /usr/local/share/powershell/Modules for all
cp -r /tmp/hgpm/HGPM ~/.local/share/powershell/Modules/HGPM/0.1.21
```

Then, so that nothing is ever looked for on the internet:

| Variable | Effect |
|---|---|
| `PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1` | the Avalonia runtime is never downloaded: the one of the archive is used |
| `PSGPOTOOLS_SKIP_UPDATE_CHECK=1` | the PowerShell Gallery is not read for a newer version |

The ADMX files come from the central store of the domain, or from `%windir%\PolicyDefinitions`;
on Linux, from a copy: the folder `sources/PolicyDefinitions` of the source archive of the release
(`Initialize-PSGPOAdmx -Path`, [Installation](installation.md#the-admx-files)).

## The runtime is checked each time

Each file of the Avalonia runtime has its SHA-256 pinned in the module
(`Resources/AvaloniaPackages.json`). The console checks them each time it loads them, and refuses
a library added next to them: an archive changed, or a file of the runtime replaced in a folder
others can write to, is never loaded. The message names what differs; delete the folder of the
runtime, and extract it again (or let the console install it, checked).

## An internal NuGet feed

Where the computers reach an internal feed but not nuget.org, `PSGPOTOOLS_NUGET_SOURCE` gives it:

- the address of its service index (`https://nuget.example.com/v3/index.json`: Artifactory,
  Nexus, ProGet, Azure Artifacts...), or the base address of its packages
  (`.../v3-flatcontainer/`);
- or a folder of `.nupkg` files (a share), flat or as a feed lays them out.

Whatever the source, a package is installed only with its pinned SHA-512, and each file with its
SHA-256. A download is tried three times, two minutes each, through the proxy of the system.

## The signature

When the release is signed with Authenticode (the certificate is a secret of the release
workflow), each script of the module is signed, and the catalog `HGPM.cat` lists every file of the
module:

```powershell
$module = "$env:ProgramFiles\PowerShell\Modules\HGPM\0.1.21"
Get-AuthenticodeSignature "$module\HGPM.psm1"
# The runtime of an offline archive is not in the catalog (the module checks it, above), nor the file Install-PSResource adds.
$skip = @(Get-ChildItem "$module\Avalonia\bin" -Recurse -File -ErrorAction SilentlyContinue).Name + 'PSGetModuleInfo.xml'
Test-FileCatalog -Path $module -CatalogFilePath "$module\HGPM.cat" -FilesToSkip $skip
```

The releases are not signed yet: under the execution policy `AllSigned`, sign the module with the
certificate of your organization (`Set-AuthenticodeSignature`) once checked as above.

## Build it again

Anyone can build the module again from the tag, and compare it with the release:

```powershell
git clone --branch v0.1.21-alpha https://github.com/JM2K69/PSGPOTools
cd PSGPOTools
./CI/03_Build.ps1
(Get-FileHash HGPM/HGPM.psm1 -Algorithm SHA256).Hash.ToLower()   # the line HGPM/HGPM.psm1 of SHA256SUMS
```

For a signed release, the signature added to the scripts changes their bytes: check the signature
instead (above).
