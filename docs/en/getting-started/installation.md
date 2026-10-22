# Installation

HGPM is a PowerShell module. It needs **PowerShell 7.4 or later** on every platform; what
else it needs depends on what you do with it and where.

## The module

Install it from the PowerShell Gallery, or build it from the repository (the branch `master`):

=== "PowerShell Gallery"

    With PSResourceGet, the module of PowerShell 7.4 and later that replaces PowerShellGet
    (`Install-Module`):

    ```powershell
    Install-PSResource -Name HGPM -Prerelease -Scope CurrentUser   # alpha versions
    Import-Module HGPM
    ```

    `-Prerelease` while HGPM has alpha versions only. Later, `Update-PSResource -Name HGPM -Prerelease`
    installs a newer version ([updates](#updates)).

=== "From the repository"

    ```powershell
    git clone https://github.com/JM2K69/PSGPOTools.git
    cd PSGPOTools
    pwsh -File CI/03_Build.ps1          # builds HGPM/HGPM.psm1 from Code/
    Import-Module ./HGPM/HGPM.psd1
    ```

## The Avalonia runtime

The window runs on Avalonia 11. Its assemblies are not shipped with the module: the first time a
window opens, the console downloads the 21 NuGet packages of `Resources/AvaloniaPackages.json`
for the runtime of the computer (`win-x64`, `win-arm64`, `linux-x64`, `linux-arm64`, `osx`),
checks each one against its pinned SHA-512 (the hash of the nuget.org catalog) before extracting
anything, then puts them in place at once.

- They go into the module folder when it can be written to, else into the data folder of the user.
- `PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1` forbids the download (offline computers).
- `Avalonia/Get-AvaloniaBinaries.ps1` installs them beforehand, or for another computer. It loads
  the module: from the repository, build it first (`CI/03_Build.ps1`).

```powershell
./HGPM/Avalonia/Get-AvaloniaBinaries.ps1 -Rid linux-x64
```

The commands that do not open a window (backups, drift, approval...) never need Avalonia.

## The ADMX files

The module does not ship ADMX files: the console reads those of the central store of the domain
(`\domain\SYSVOL\domain\Policies\PolicyDefinitions`), of Windows (`%windir%\PolicyDefinitions`)
or of the SYSVOL of a Samba domain controller, else asks for a folder. Where there are none (a
Linux computer, a domain without a central store), `Install-PSGPOAdmx` downloads the copy of the
repository from GitHub (`sources/PolicyDefinitions`: 236 `.admx` files, their `.adml` files in 22
languages), at the tag of the version of the module. Each set of files (the `.admx` files, each
language) is checked against the SHA-256 the module pins before anything is written.

```powershell
Install-PSGPOAdmx                                    # en-US and the language of the session, next to the module
Install-PSGPOAdmx -UICulture en-US, fr-FR            # the languages chosen
Install-PSGPOAdmx -AllLanguages -Path ~/PolicyDefinitions
Install-PSGPOAdmx -CentralStore -Server dc.hardenbox.labo -UICulture en-US, fr-FR   # the central store of the domain
```

Without `-Path`, the files go next to the module when it can be written to, else into the data
folder of the user (`PSGPOTools/PolicyDefinitions`): the console finds them there. With
`-CentralStore`, they go into `SYSVOL\<domain>\Policies\PolicyDefinitions` of the domain
controller (an account allowed to write SYSVOL: a domain administrator), as for GPMC: every
console of the domain then reads them. The ADMX files already there are kept, those of the same
name replaced; with files already there, give `-Force`. Before the first release of a version
(no tag yet), give the branch: `-Ref master`.

## Windows

| Need | Why | How |
|---|---|---|
| A domain account | the console reads the domain with the identity of the session (Kerberos) | log on with it, or `-Credential` with `-UseSsl` |
| RSAT Group Policy Management tools | create and delete GPOs (`New-GPO`, `Remove-GPO`) | `Add-WindowsCapability -Online -Name 'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'` (Windows 10/11), `Install-WindowsFeature GPMC` (Server) |
| RSAT Active Directory tools | optional: only the test scripts use them | `Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'` |

The GroupPolicy module is a Windows PowerShell module: PowerShell 7 hides it from
`Get-Module -ListAvailable` and loads it through its Windows PowerShell compatibility. The
console finds it with `-SkipEditionCheck`.

SYSVOL is read and written through its UNC path (`\\dc\SYSVOL\domain\Policies\{GUID}`), with the
identity of the session.

!!! warning "A session opened by SSH with a key"
    An OpenSSH session opened with a key has no network credentials (S4U logon): LDAP binds
    fail and SYSVOL cannot be reached. Run the console in an interactive session, or over SSH
    with a password.

## Linux

| Need | Why | Debian / Ubuntu | RHEL / Fedora |
|---|---|---|---|
| OpenLDAP client library | LDAP from .NET | `apt install libldap2` | `dnf install openldap` |
| SASL GSSAPI module | Kerberos over LDAP | `apt install libsasl2-modules-gssapi-mit` | `dnf install cyrus-sasl-gssapi` |
| Kerberos client | the ticket the console uses | `apt install krb5-user` | `dnf install krb5-workstation` |
| `smbclient` | read and write SYSVOL | `apt install smbclient` | `dnf install samba-client` |
| `samba-tool`, Samba Python bindings | create and delete GPOs, SYSVOL permissions | `apt install python3-samba samba-common-bin` | `dnf install samba-tools python3-samba` |
| A graphical session | the window (X11 or Wayland with XWayland) | | |

The console authenticates with **Kerberos**: get a ticket first, and give the domain controller
by its DNS name (Kerberos needs the name, not the IP address).

```bash
kinit administrator@HARDENBOX.LABO
klist
```

A password is never given to `samba-tool` or `smbclient`, and never sent over plain LDAP: with
`-Credential`, use `-UseSsl` (LDAPS), and the changes still need a Kerberos ticket.

!!! note "-Credential on Windows"
    On Windows, a domain read with `-Credential` (and `-UseSsl`) is changed with that account in
    the directory **and in SYSVOL**: the console opens an SMB connection to `\\<dc>\SYSVOL` with
    it, as `net use \\<dc>\SYSVOL /user:...` does. Windows has one account per server in a
    session: if the session already reaches that server with another account, the console says so
    (`net use \\<dc>\* /delete` closes those connections). Creating and deleting a GPO use RSAT,
    which only knows the identity of the session: they are refused with `-Credential`.

## Check the installation

```powershell
Import-Module HGPM
Get-Command -Module HGPM        # the public commands
Get-PSGPODirectory -Server dc.hardenbox.labo | Select-Object DomainName, Account, Source
```

The status bar of the window also says what the console found: this computer, its domain, the
domain controller and its directory service.

## Updates

The import of the module says its version, and the command that installs a newer one when the
PowerShell Gallery has it:

```text
PS> Import-Module HGPM
HGPM 0.1.5-alpha
HGPM 0.1.6-alpha is available on the PowerShell Gallery: Update-PSResource -Name HGPM -Prerelease, then open a new PowerShell session.
```

The import reads the Gallery at most once a day (`UpdateCheck.json` in the local data folder of
the user, `PSGPOTools`), and waits 8 seconds at most: without network, it gives the version only, and does not try again for an hour.
It does not read it in a CI, in a session started with `-NonInteractive`, nor with
`PSGPOTOOLS_SKIP_UPDATE_CHECK=1`. The new version is used by a new PowerShell session: the one
running keeps the module it imported.

`Test-PSGPOUpdate` tells whether a newer version of HGPM is published on the PowerShell Gallery,
and gives the command that installs it. It compares the version loaded with the latest of the
Gallery as semantic versions: `0.1.4-alpha` comes before `0.1.4-beta`, itself before `0.1.4`. The
prereleases count when the version loaded is one (or with `-Prerelease`).

```powershell
Test-PSGPOUpdate
# Name             : HGPM
# InstalledVersion : 0.1.4-alpha
# LatestVersion    : 0.1.5-alpha
# UpdateAvailable  : True
# UpdateCommand    : Update-PSResource -Name HGPM -Prerelease

if (Test-PSGPOUpdate -Quiet) { Update-PSResource -Name HGPM -Prerelease }
```

### Update HGPM

1. **Close** the consoles (`Show-GPOManagerAvalonia`, `Show-PSOManagerAvalonia`) and the PowerShell
   sessions that imported HGPM: a session keeps the module it imported.
2. **Install** the new version, as the module was installed:

    === "PowerShell Gallery"

        ```powershell
        Update-PSResource -Name HGPM -Prerelease
        ```

        The new version goes beside the old one (a folder per version in `Modules/HGPM`). A module
        installed for all users (`-Scope AllUsers`) is updated as an administrator, with
        `-Scope AllUsers` (`sudo pwsh` on Linux). Installed with PowerShellGet (`Install-Module`):
        `Update-Module -Name HGPM -AllowPrerelease`.

    === "From the repository"

        ```bash
        cd PSGPOTools
        git pull
        pwsh -File CI/03_Build.ps1
        ```

        The import of a checkout then suggests `Install-PSResource`: it installs the version of the
        Gallery beside the checkout, which keeps its own.

3. **Check** in a new PowerShell session: the import gives the new version, without the line
   `is available`, and the dot of the status bar of the consoles is green.

    ```powershell
    Import-Module HGPM
    Get-PSResource -Name HGPM          # the versions installed
    ```

4. Optionally, **remove** an old version: `Uninstall-PSResource -Name HGPM -Version <version>`.

The changes of each version are in the [changelog](../changelog.md).
