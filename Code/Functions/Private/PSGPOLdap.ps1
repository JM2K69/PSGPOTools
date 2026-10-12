<#
    LDAP access to the directory with System.DirectoryServices.Protocols: the same code for a
    Windows or a Samba domain controller, from Windows (wldap32) or Linux (OpenLDAP libldap).

    Authentication: Kerberos/Negotiate with the current identity (Windows session, or the ticket
    of kinit on Linux), Negotiate with -Credential on Windows, or a simple bind over LDAPS with
    -Credential. Samba refuses simple binds without TLS ("ldap server require strong auth"), and a
    password never goes over plain LDAP.
#>

# Opens and binds an LDAP connection.
function New-PSGPOLdapConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [pscredential]$Credential,

        # LDAPS (port 636): the server certificate must be trusted by the system.
        [switch]$UseSsl,

        [int]$Port,

        [int]$TimeoutSeconds = 30
    )

    Add-Type -AssemblyName System.DirectoryServices.Protocols
    if (-not $Port) { $Port = if ($UseSsl) { 636 } else { 389 } }

    if ($Credential -and -not $UseSsl -and -not $IsWindows) {
        throw "A password is only sent over LDAPS outside Windows: add -UseSsl, or authenticate with Kerberos (kinit $($Credential.UserName)) and omit -Credential."
    }

    $identifier = [System.DirectoryServices.Protocols.LdapDirectoryIdentifier]::new($Server, $Port, $false, $false)
    $connection = [System.DirectoryServices.Protocols.LdapConnection]::new($identifier)
    $connection.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $options = $connection.SessionOptions
    $options.ProtocolVersion = 3
    # Referrals to other partitions (DomainDnsZones...) would bind again elsewhere: not followed.
    $options.ReferralChasing = [System.DirectoryServices.Protocols.ReferralChasingOptions]::None

    if ($UseSsl) {
        $options.SecureSocketLayer = $true
    }
    if ($UseSsl -and $Credential) {
        $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Basic
    } else {
        $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
        if (-not $UseSsl -and $IsWindows) {
            # Signed and sealed session, as hardened AD and Samba require. On Linux, the SASL
            # layer of libldap protects the Kerberos session by itself.
            $options.Signing = $true
            $options.Sealing = $true
        }
    }
    if ($Credential) { $connection.Credential = $Credential.GetNetworkCredential() }

    try {
        $connection.Bind()
    } catch {
        $connection.Dispose()
        throw (Get-PSGPOLdapErrorMessage -Exception $_.Exception -Server $Server -Port $Port -UseSsl:$UseSsl -WithCredential:([bool]$Credential))
    }
    $connection
}

# Error message of a failed bind, with what to do about it.
function Get-PSGPOLdapErrorMessage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [Exception]$Exception,

        [string]$Server,
        [int]$Port,
        [switch]$UseSsl,
        [switch]$WithCredential
    )

    $base = $Exception.GetBaseException()
    $code = if ($base.PSObject.Properties['ErrorCode']) { [int]$base.ErrorCode } else { 0 }
    $message = "LDAP connection to ${Server}:$Port failed: $($base.Message)"
    $hint = switch ($code) {
        49 { 'The user name or the password is wrong.' }
        81 { "The server cannot be reached: check the name ($Server), the DNS and that port $Port is open." }
        8 { 'The server requires a stronger authentication: use Kerberos (without -Credential) or -UseSsl.' }
        default { $null }
    }
    if (-not $hint -and -not $IsWindows -and -not $WithCredential) {
        $hint = 'Kerberos needs a ticket (kinit user@REALM, see klist) and the SASL GSSAPI module (Debian/Ubuntu: apt install libsasl2-modules-gssapi-mit; RHEL/Fedora: dnf install cyrus-sasl-gssapi). Use the domain controller name, not an IP address.'
    }
    if (-not $hint -and $UseSsl) {
        $hint = 'With -UseSsl, the certificate of the server must be trusted by the system (Linux: TLS_CACERT in /etc/ldap/ldap.conf).'
    }
    if ($hint) { "$message $hint" } else { $message }
}

# Searches the directory, page by page. Each entry: DistinguishedName and Attributes, a
# case-insensitive hashtable of string arrays (Samba returns the attribute names in lower case).
function Invoke-PSGPOLdapSearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Connection,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SearchBase,

        [ValidateSet('Base', 'OneLevel', 'Subtree')]
        [string]$Scope = 'Subtree',

        [string]$Filter = '(objectClass=*)',

        [Parameter(Mandatory)]
        [string[]]$Attribute,

        [int]$PageSize = 500
    )

    $request = [System.DirectoryServices.Protocols.SearchRequest]::new()
    $request.DistinguishedName = $SearchBase
    $request.Filter = $Filter
    $request.Scope = [System.DirectoryServices.Protocols.SearchScope]$Scope
    foreach ($name in $Attribute) { [void]$request.Attributes.Add($name) }
    $page = $null
    if ($Scope -ne 'Base') {
        $page = [System.DirectoryServices.Protocols.PageResultRequestControl]::new($PageSize)
        [void]$request.Controls.Add($page)
    }

    do {
        $response = $Connection.SendRequest($request)
        foreach ($entry in $response.Entries) {
            $attributes = @{}
            foreach ($name in $entry.Attributes.AttributeNames) {
                $attributes[$name] = [string[]]$entry.Attributes[$name].GetValues([string])
            }
            [pscustomobject]@{ DistinguishedName = $entry.DistinguishedName; Attributes = $attributes }
        }
        $cookie = $null
        if ($page) {
            $pageResponse = $response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] } | Select-Object -First 1
            if ($pageResponse -and $pageResponse.Cookie.Length) {
                $cookie = $pageResponse.Cookie
                $page.Cookie = $cookie
            }
        }
    } while ($cookie)
}

# First value of an attribute of a search entry ($null when absent).
function Get-PSGPOLdapValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Entry,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $values = $Entry.Attributes[$Name]
    if ($values) { $values[0] }
}

# Builds the directory from the search entries; no network, so that it can be tested.
function ConvertTo-PSGPOLdapDirectory {
    [CmdletBinding()]
    [OutputType([GPOToolsLdapDirectory])]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        # The domain object (gPLink)
        [Parameter(Mandatory)]
        $DomainEntry,

        # organizationalUnit objects (name, gPLink, gPOptions)
        [AllowEmptyCollection()]
        [object[]]$OrganizationalUnitEntry = @(),

        # groupPolicyContainer objects (cn, displayName, versionNumber, flags, gPCFileSysPath)
        [AllowEmptyCollection()]
        [object[]]$GpoEntry = @()
    )

    $domainDN = $DomainEntry.DistinguishedName
    $domainName = (@([regex]::Matches($domainDN, '(?i)(?:^|,)DC=([^,]+)') | ForEach-Object { $_.Groups[1].Value }) -join '.').ToLowerInvariant()
    $directory = [GPOToolsLdapDirectory]::new($domainName, $domainDN, $Server)

    foreach ($entry in $GpoEntry) {
        $cn = Get-PSGPOLdapValue $entry 'cn'
        $id = [guid]::Empty
        if (-not [guid]::TryParse("$cn".Trim('{', '}'), [ref]$id)) {
            Write-Warning "Group policy container ignored, its name is not a GUID: $($entry.DistinguishedName)"
            continue
        }
        $gpo = [GPOToolsGpo]::new()
        $gpo.Id = $id
        $gpo.DistinguishedName = $entry.DistinguishedName
        $displayName = Get-PSGPOLdapValue $entry 'displayName'
        $gpo.DisplayName = if ($displayName) { $displayName } else { $cn }
        $gpo.FileSysPath = Get-PSGPOLdapValue $entry 'gPCFileSysPath'
        $gpo.Version = [int](Get-PSGPOLdapValue $entry 'versionNumber')
        $gpo.Flags = [int](Get-PSGPOLdapValue $entry 'flags')
        [void]$directory.AddExistingGpo($gpo)
    }

    $directory.SetLinks($directory.Domain, (Get-PSGPOLdapValue $DomainEntry 'gPLink'))

    # Parents before children: by number of RDNs.
    $depth = { @([regex]::Matches($_.DistinguishedName, '(?<!\\),')).Count }
    foreach ($entry in @($OrganizationalUnitEntry | Sort-Object $depth, { $_.DistinguishedName })) {
        $parent = $directory.FindSom([GPOToolsDirectory]::GetParentDistinguishedName($entry.DistinguishedName))
        if (-not $parent) {
            Write-Warning "Organizational unit ignored, its parent is not the domain or an OU: $($entry.DistinguishedName)"
            continue
        }
        $name = Get-PSGPOLdapValue $entry 'name'
        if (-not $name) { $name = Get-PSGPOLdapValue $entry 'ou' }
        $som = $directory.AddOrganizationalUnit($parent, $name, $entry.DistinguishedName)
        $som.BlockInheritance = ([int](Get-PSGPOLdapValue $entry 'gPOptions') -band 1) -eq 1
        $directory.SetLinks($som, (Get-PSGPOLdapValue $entry 'gPLink'))
    }

    # OUs by name, as GPMC shows them.
    $stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
    $stack.Push($directory.Domain)
    while ($stack.Count) {
        $som = $stack.Pop()
        $som.Children.Sort([System.Comparison[GPOToolsSom]] { param($a, $b) [string]::Compare($a.Name, $b.Name, $true) })
        foreach ($child in $som.Children) { $stack.Push($child) }
    }
    $directory
}
