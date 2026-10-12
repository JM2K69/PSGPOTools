<#
    Detection of the platform the module runs on (GPOToolsPlatform), kept in the module scope
    ($script:PSGPOPlatform): the operating system, the domain of the computer, whether it is a
    domain controller (Windows or Samba) and the tools available to reach the directory.

    Detected on first use rather than at import: it queries the system (CIM on Windows,
    configuration files and native libraries on Linux/macOS).
#>

# [global] parameters of a smb.conf, with the names normalized as Samba does (lower case,
# without spaces): 'server role', 'Server Role' and 'serverrole' are the same parameter.
function Read-PSGPOSambaConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parameters = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $parameters }
    $section = ''
    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        # A line ending with \ goes on with the next one.
        while ($line.EndsWith('\') -and $i + 1 -lt $lines.Count) {
            $i++
            $line = $line.Substring(0, $line.Length - 1) + $lines[$i].Trim()
        }
        if (-not $line -or $line[0] -in '#', ';') { continue }
        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim().ToLowerInvariant()
            continue
        }
        if ($section -notin '', 'global') { continue }
        $equal = $line.IndexOf('=')
        if ($equal -lt 1) { continue }
        $name = ($line.Substring(0, $equal) -replace '\s', '').ToLowerInvariant()
        $parameters[$name] = $line.Substring($equal + 1).Trim()
    }
    $parameters
}

# default_realm of a krb5.conf ($null when not set).
function Get-PSGPOKerberosDefaultRealm {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $section = ''
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $line = $line.Trim()
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1].Trim(); continue }
        if ($section -eq 'libdefaults' -and $line -match '^default_realm\s*=\s*(\S+)') { return $Matches[1] }
    }
}

# Linux/macOS part of the detection, from smb.conf and krb5.conf.
function Resolve-PSGPOUnixPlatform {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$SmbConfPath,

        [Parameter(Mandatory)]
        [string]$Krb5ConfPath
    )

    $samba = Read-PSGPOSambaConfig -Path $SmbConfPath
    $result = @{ IsDomainController = $false; DomainControllerType = $null; Realm = $null; DomainName = $null }
    # 'dc' is the short form of 'active directory domain controller'.
    if ($samba['serverrole'] -match '^\s*(active\s+directory\s+domain\s+controller|dc)\s*$') {
        $result.IsDomainController = $true
        $result.DomainControllerType = 'Samba'
    }
    $result.Realm = if ($samba['realm']) { $samba['realm'].ToUpperInvariant() } else { Get-PSGPOKerberosDefaultRealm -Path $Krb5ConfPath }
    if ($result.Realm) { $result.DomainName = $result.Realm.ToLowerInvariant() }
    $result
}

# Whether System.DirectoryServices.Protocols can load its native LDAP library.
function Test-PSGPOLdapLibrary {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Windows uses wldap32, part of the system; macOS its LDAP framework.
    if ($IsWindows -or $IsMacOS) { return }
    $handle = [IntPtr]::Zero
    foreach ($library in 'libldap.so.2', 'libldap-2.5.so.0', 'libldap-2.4.so.2') {
        if ([System.Runtime.InteropServices.NativeLibrary]::TryLoad($library, [ref]$handle)) { return }
    }
    'The OpenLDAP client library (libldap) is not installed: install libldap2 (Debian/Ubuntu: apt install libldap2; RHEL/Fedora: dnf install openldap).'
}

function Get-PSGPOPlatform {
    [CmdletBinding()]
    [OutputType([GPOToolsPlatform])]
    param(
        # Detects again instead of returning the platform detected before.
        [switch]$Force,

        # Configuration files read on Linux/macOS (parameters for the tests).
        [string]$SmbConfPath = '/etc/samba/smb.conf',
        [string]$Krb5ConfPath = '/etc/krb5.conf'
    )

    if ($script:PSGPOPlatform -and -not $Force) { return $script:PSGPOPlatform }

    $platform = [GPOToolsPlatform]::new()
    $platform.ComputerName = [Environment]::MachineName
    $platform.OperatingSystem = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }

    if ($IsWindows) {
        try {
            $computer = Get-CimInstance -ClassName Win32_ComputerSystem -Property Domain, PartOfDomain, DomainRole -ErrorAction Stop -Verbose:$false
            if ($computer.PartOfDomain) {
                $platform.DomainName = $computer.Domain
                $platform.Realm = $computer.Domain.ToUpperInvariant()
            }
            # DomainRole 4: backup domain controller, 5: primary domain controller
            if ($computer.DomainRole -ge 4) {
                $platform.IsDomainController = $true
                $platform.DomainControllerType = 'Windows'
            }
        } catch {
            Write-Verbose "Domain of the computer not detected: $($_.Exception.Message)"
        }
    } else {
        $unix = Resolve-PSGPOUnixPlatform -SmbConfPath $SmbConfPath -Krb5ConfPath $Krb5ConfPath
        foreach ($name in $unix.Keys) { $platform.$name = $unix[$name] }
    }

    $sambaTool = Get-Command -Name 'samba-tool' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sambaTool) { $platform.SambaToolPath = $sambaTool.Source }

    $platform.LdapUnavailableReason = Test-PSGPOLdapLibrary
    $platform.LdapAvailable = -not $platform.LdapUnavailableReason

    Write-Verbose "Platform: $platform"
    $script:PSGPOPlatform = $platform
    $platform
}
