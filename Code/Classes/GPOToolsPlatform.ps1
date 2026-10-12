<#
    What the module runs on, as detected by Get-PSGPOPlatform: it decides how the directory is
    reached (LDAP from Windows or Linux, samba-tool on a Samba domain controller).
#>

class GPOToolsPlatform {
    # Windows, Linux or MacOS
    [string]$OperatingSystem
    [string]$ComputerName
    # DNS name of the domain of the computer ($null outside a domain)
    [string]$DomainName
    # Kerberos realm (Linux/macOS: smb.conf realm, else krb5.conf default_realm)
    [string]$Realm
    [bool]$IsDomainController
    # Samba or Windows when the computer is a domain controller
    [string]$DomainControllerType
    # Path of samba-tool when installed
    [string]$SambaToolPath
    # System.DirectoryServices.Protocols can reach LDAP (libldap on Linux)
    [bool]$LdapAvailable
    # Why LDAP is not available, with what to install
    [string]$LdapUnavailableReason

    [string] ToString() {
        $Role = if ($this.IsDomainController) { "$($this.DomainControllerType) domain controller" } elseif ($this.DomainName) { 'domain member' } else { 'not in a domain' }
        $Domain = if ($this.DomainName) { " of $($this.DomainName)" } else { '' }
        return "$($this.ComputerName) ($($this.OperatingSystem), $Role$Domain)"
    }
}
