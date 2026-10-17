# Installation

PSGPOTools is a PowerShell module. It needs **PowerShell 7.4 or later** on every platform; what
else it needs depends on what you do with it and where.

## The module

Build it from the repository (the console is on the `avalonia` branch until its first release on
the PowerShell Gallery):

=== "From the repository"

    ```powershell
    git clone -b avalonia https://github.com/JM2K69/PSGPOTools.git
    cd PSGPOTools
    pwsh -File CI/03_Build.ps1          # builds PSGPOTools/PSGPOTools.psm1 from Code/
    Import-Module ./PSGPOTools/PSGPOTools.psd1
    ```

=== "PowerShell Gallery (once released)"

    ```powershell
    Install-Module PSGPOTools -Scope CurrentUser
    Import-Module PSGPOTools
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
./PSGPOTools/Avalonia/Get-AvaloniaBinaries.ps1 -Rid linux-x64
```

The commands that do not open a window (backups, drift, approval...) never need Avalonia.

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
Import-Module PSGPOTools
Get-Command -Module PSGPOTools        # the public commands
Get-PSGPODirectory -Server dc.hardenbox.labo | Select-Object DomainName, Account, Source
```

The status bar of the window also says what the console found: this computer, its domain, the
domain controller and its directory service.
