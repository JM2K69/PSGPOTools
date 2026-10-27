function Get-PSGPODirectory {
    <#
    .SYNOPSIS
        Reads the domain, its OUs, GPOs and GPO links from Active Directory over LDAP.
    .DESCRIPTION
        Reads the domain as GPMC shows it: the domain and its organizational units with their GPO
        links (gPLink, by link order, enforced and disabled links) and blocked inheritance
        (gPOptions), and the group policy containers (GPOs). Works with Windows and Samba domain
        controllers, from Windows and Linux, through System.DirectoryServices.Protocols.

        The configuration of HGPM for the domain (Get-PSGPOConfiguration: SYSVOL\<domain>\
        PSGPOTools\Configuration.psd1) is read with it, and used from then on.

        As GPMC, the domain is read from its PDC emulator (the fSMORoleOwner of the domain), where
        the changes go, unless -Server gives another domain controller: a warning then says it,
        as the other domain controllers replicate the GPOs from the PDC emulator (and Samba does
        not replicate SYSVOL).

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
        By default, the PDC emulator of the domain, found by the computer itself when it is a
        domain controller, else by a domain controller of the domain of the computer (Windows
        locates one); the domain controller found when the PDC emulator cannot be reached.
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
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpodirectory/
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

    # Without -Server, as GPMC: the PDC emulator of the domain, once a domain controller says which.
    $chosen = [bool]$Server
    $Server = Resolve-PSGPODomainServer -Server $Server

    $connection = New-PSGPOLdapConnection -Server $Server -Credential $Credential -UseSsl:$UseSsl -Port $Port
    $retarget = $null
    try {
        $rootDse = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase '' -Scope Base -Attribute 'defaultNamingContext', 'dnsHostName', 'vendorName'
        $domainDN = Get-PSGPOLdapValue $rootDse 'defaultNamingContext'
        $dnsHostName = Get-PSGPOLdapValue $rootDse 'dnsHostName'
        if (-not $domainDN) { throw "$Server did not give its default naming context: is it a domain controller?" }
        $reached = if ($dnsHostName) { $dnsHostName } else { $Server }

        # allowedAttributesEffective: the attributes the account may write, for its rights (RBAC).
        $domain = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $domainDN -Scope Base -Attribute 'gPLink', 'gPOptions', 'wellKnownObjects', 'allowedAttributesEffective', 'fSMORoleOwner'
        if (-not $domain) { throw "The domain object $domainDN cannot be read: the account has no access to the directory (anonymous bind?)." }
        $pdc = Get-PSGPOPdcEmulator -Connection $connection -DomainEntry $domain
        # Found by another domain controller: read from it (below).
        if (-not $chosen -and $pdc -and -not [string]::Equals($pdc, $reached, [System.StringComparison]::OrdinalIgnoreCase)) { $retarget = $pdc }
        if (-not $retarget) {
            $organizationalUnits = @(Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $domainDN -Scope Subtree `
                    -Filter '(objectClass=organizationalUnit)' -Attribute 'name', 'ou', 'gPLink', 'gPOptions', 'allowedAttributesEffective')
            $gpos = @(Invoke-PSGPOLdapSearch -Connection $connection -SearchBase "CN=Policies,CN=System,$domainDN" -Scope OneLevel `
                    -Filter '(objectClass=groupPolicyContainer)' -Attribute 'cn', 'displayName', 'versionNumber', 'flags', 'gPCFileSysPath', 'whenChanged', 'gPCMachineExtensionNames', 'gPCUserExtensionNames', 'gPCWQLFilter', 'allowedAttributesEffective')
            $policies = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase "CN=Policies,CN=System,$domainDN" -Scope Base -Attribute 'allowedChildClassesEffective'
            $account = Get-PSGPOLdapAccount -Connection $connection

            $directory = ConvertTo-PSGPOLdapDirectory -Server $(if ($dnsHostName) { $dnsHostName } else { $Server }) -VendorName (Get-PSGPOLdapValue $rootDse 'vendorName') -DomainEntry $domain `
                -OrganizationalUnitEntry $organizationalUnits -GpoEntry $gpos -PoliciesEntry $policies -EffectiveRights
            $directory.Account = $account
            # The configuration of HGPM for the domain is changed by its administrators only.
            $directory.IsDomainAdministrator = Test-PSGPODomainAdministrator -Connection $connection -DomainDistinguishedName $domainDN -Account $account
            # Security filtering of the GPOs, as GPMC shows it: not a reason to fail the reading.
            try {
                Read-PSGPODomainSecurityFiltering -Connection $connection -Directory $directory
            } catch {
                Write-Warning "The security filtering of the GPOs cannot be read: $($_.Exception.GetBaseException().Message)"
                foreach ($gpo in $directory.Gpos) { $gpo.SecurityFiltering = $null; $gpo.DeniedTo = $null }
            }
            # The WMI filters: not a reason to fail the reading either.
            try {
                Read-PSGPODomainWmiFilter -Connection $connection -Directory $directory
            } catch {
                Write-Warning "The WMI filters of the domain cannot be read: $($_.Exception.GetBaseException().Message)"
            }
        }
    } catch {
        Write-PSGPOLogEntry -Level Error -Source 'LDAP' -Message "The domain cannot be read from ${Server}." -ErrorRecord $_
        throw
    } finally {
        $connection.Dispose()
    }
    if ($retarget) {
        $again = @{}
        foreach ($name in 'Credential', 'UseSsl', 'Port') { if ($PSBoundParameters.ContainsKey($name)) { $again[$name] = $PSBoundParameters[$name] } }
        try {
            return Get-PSGPODirectory -Server $retarget @again
        } catch {
            Write-Warning "The PDC emulator of the domain, $retarget, cannot be read ($($_.Exception.GetBaseException().Message)): the domain is read from $reached."
            return Get-PSGPODirectory -Server $reached @again
        }
    }
    # A domain controller given that is not the PDC emulator: GPMC changes the GPOs on the PDC
    # emulator, which the other domain controllers replicate from.
    $directory.PdcEmulator = $pdc
    if ($pdc -and -not $directory.IsPdcEmulator()) {
        Write-Warning "$reached is not the PDC emulator of $($directory.DomainName) ($pdc): GPMC changes the GPOs on the PDC emulator, which the other domain controllers replicate from (Samba does not replicate SYSVOL). Give -Server $pdc, or no -Server."
    }
    # The changes connect again as the directory was read.
    $directory.Credential = $Credential
    $directory.UseSsl = [bool]$UseSsl
    $directory.Port = $Port
    # Container of the users and groups, where it may have been redirected (redirusr).
    foreach ($value in @($domain.Attributes['wellKnownObjects'])) {
        if ("$value" -match '^B:32:A9D1CA15768811D1ADED00C04FD8D5CD:(.+)$') { $directory.UsersContainer = $Matches[1] }
    }
    # The configuration of HGPM for this domain, from its SYSVOL, and its approval workflow.
    Use-PSGPODomainConfiguration -Directory $directory
    # And the tier of the account in the central audit log and backups.
    $workflow = (Get-PSGPOWorkflowSetting).Enabled
    # Without a configuration of the domain it can use, the workflow may be unknown: checked for
    # the accounts that are not administrators (Get-PSGPOUnknownWorkflowProblem).
    $state = $script:PSGPOConfigurationState
    if (-not $directory.IsDomainAdministrator -and ($state.Problem -or -not $state.Exists)) { $workflow = $true }
    $configuration = Get-PSGPOConfigurationData
    $central = [bool]("$($configuration.Audit.Path)".Trim() -or "$($configuration.Backup.Path)".Trim())
    if ($workflow -or $central) {
        $connection = New-PSGPODirectoryConnection -Directory $directory
        try {
            if ($workflow) { Update-PSGPODomainWorkflow -Connection $connection -Directory $directory }
            if ($central) { Update-PSGPOAuditTier -Connection $connection -Directory $directory }
        } finally {
            $connection.Dispose()
        }
    }
    $directory
}
