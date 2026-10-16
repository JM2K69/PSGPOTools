function Get-PSGPODirectory {
    <#
    .SYNOPSIS
        Reads the domain, its OUs, GPOs and GPO links from Active Directory over LDAP.
    .DESCRIPTION
        Reads the domain as GPMC shows it: the domain and its organizational units with their GPO
        links (gPLink, by link order, enforced and disabled links) and blocked inheritance
        (gPOptions), and the group policy containers (GPOs). Works with Windows and Samba domain
        controllers, from Windows and Linux, through System.DirectoryServices.Protocols.

        The configuration of PSGPOTools for the domain (Get-PSGPOConfiguration: SYSVOL\<domain>\
        PSGPOTools\Configuration.psd1) is read with it, and used from then on.

        Its changes are written to the domain: NewGpo creates a GPO with New-GPO of RSAT on
        Windows (the GroupPolicy module), with samba-tool on Linux (Kerberos), NewLink links a GPO
        to the domain or an OU over LDAP. Pass it to
        Show-GPOManagerAvalonia -Directory to manage it in the window.

        Authentication:
        - Windows: the identity of the session (Kerberos), or -Credential.
        - Linux: a Kerberos ticket (kinit user@REALM), which needs the SASL GSSAPI module
          (Debian/Ubuntu: libsasl2-modules-gssapi-mit); or -Credential with -UseSsl.
        A password is never sent over plain LDAP.
    .PARAMETER Server
        Domain controller to read from: its DNS name (Kerberos needs the name, not the IP address).
        By default, the computer itself when it is a domain controller, else the domain of the
        computer (Windows locates a domain controller).
    .PARAMETER Credential
        Account to read the directory with, instead of the current identity.
    .PARAMETER UseSsl
        LDAPS (port 636). The certificate of the server must be trusted by the system.
    .PARAMETER Port
        LDAP port, when not 389 (636 with -UseSsl).
    .EXAMPLE
        Show-GPOManagerAvalonia -Directory (Get-PSGPODirectory)
    .EXAMPLE
        # Linux, Samba AD: Kerberos ticket first
        kinit administrator@HARDENBOX.LABO
        Get-PSGPODirectory -Server dc.hardenbox.labo
    .EXAMPLE
        Get-PSGPODirectory -Server dc.contoso.com -Credential (Get-Credential) -UseSsl
    #>
    [CmdletBinding()]
    [OutputType([GPOToolsDirectory])]
    Param(
        [string]$Server,

        [pscredential]$Credential,

        [switch]$UseSsl,

        [ValidateRange(1, 65535)]
        [int]$Port
    )

    $platform = Get-PSGPOPlatform
    if (-not $platform.LdapAvailable) { throw $platform.LdapUnavailableReason }
    if (-not $Server) {
        $Server = if ($platform.IsDomainController) {
            # Kerberos needs the full DNS name (ldap/dc.domain service principal).
            $hostName = [System.Net.Dns]::GetHostEntry([Environment]::MachineName).HostName
            if ($hostName.Contains('.') -or -not $platform.DomainName) { $hostName } else { "$hostName.$($platform.DomainName)" }
        } else {
            $platform.DomainName
        }
        if (-not $Server) { throw 'This computer is not in a domain: give the domain controller with -Server.' }
        Write-Verbose "Domain controller: $Server"
    }

    $connection = New-PSGPOLdapConnection -Server $Server -Credential $Credential -UseSsl:$UseSsl -Port $Port
    try {
        $rootDse = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase '' -Scope Base -Attribute 'defaultNamingContext', 'dnsHostName', 'vendorName'
        $domainDN = Get-PSGPOLdapValue $rootDse 'defaultNamingContext'
        $dnsHostName = Get-PSGPOLdapValue $rootDse 'dnsHostName'
        if (-not $domainDN) { throw "$Server did not give its default naming context: is it a domain controller?" }

        # allowedAttributesEffective: the attributes the account may write, for its rights (RBAC).
        $domain = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $domainDN -Scope Base -Attribute 'gPLink', 'gPOptions', 'wellKnownObjects', 'allowedAttributesEffective'
        if (-not $domain) { throw "The domain object $domainDN cannot be read: the account has no access to the directory (anonymous bind?)." }
        $organizationalUnits = @(Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $domainDN -Scope Subtree `
                -Filter '(objectClass=organizationalUnit)' -Attribute 'name', 'ou', 'gPLink', 'gPOptions', 'allowedAttributesEffective')
        $gpos = @(Invoke-PSGPOLdapSearch -Connection $connection -SearchBase "CN=Policies,CN=System,$domainDN" -Scope OneLevel `
                -Filter '(objectClass=groupPolicyContainer)' -Attribute 'cn', 'displayName', 'versionNumber', 'flags', 'gPCFileSysPath', 'whenChanged', 'gPCMachineExtensionNames', 'gPCUserExtensionNames', 'allowedAttributesEffective')
        $policies = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase "CN=Policies,CN=System,$domainDN" -Scope Base -Attribute 'allowedChildClassesEffective'
        $account = Get-PSGPOLdapAccount -Connection $connection

        $directory = ConvertTo-PSGPOLdapDirectory -Server $(if ($dnsHostName) { $dnsHostName } else { $Server }) -VendorName (Get-PSGPOLdapValue $rootDse 'vendorName') -DomainEntry $domain `
            -OrganizationalUnitEntry $organizationalUnits -GpoEntry $gpos -PoliciesEntry $policies -EffectiveRights
        $directory.Account = $account
        # Security filtering of the GPOs, as GPMC shows it: not a reason to fail the reading.
        try {
            Read-PSGPODomainSecurityFiltering -Connection $connection -Directory $directory
        } catch {
            Write-Warning "The security filtering of the GPOs cannot be read: $($_.Exception.GetBaseException().Message)"
            foreach ($gpo in $directory.Gpos) { $gpo.SecurityFiltering = $null; $gpo.DeniedTo = $null }
        }
    } finally {
        $connection.Dispose()
    }
    # The changes connect again as the directory was read.
    $directory.Credential = $Credential
    $directory.UseSsl = [bool]$UseSsl
    $directory.Port = $Port
    # Container of the users and groups, where it may have been redirected (redirusr).
    foreach ($value in @($domain.Attributes['wellKnownObjects'])) {
        if ("$value" -match '^B:32:A9D1CA15768811D1ADED00C04FD8D5CD:(.+)$') { $directory.UsersContainer = $Matches[1] }
    }
    # The configuration of PSGPOTools for this domain, from its SYSVOL, and its approval workflow.
    Use-PSGPODomainConfiguration -Directory $directory
    if ((Get-PSGPOWorkflowSetting).Enabled) {
        $connection = New-PSGPODirectoryConnection -Directory $directory
        try { Update-PSGPODomainWorkflow -Connection $connection -Directory $directory } finally { $connection.Dispose() }
    }
    $directory
}
