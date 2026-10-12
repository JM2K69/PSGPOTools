<#
    Changes written to the domain of a GPOToolsLdapDirectory (its hidden Save* methods).

    - GPO creation: samba-tool gpo create, against the domain controller of the directory. It
      creates the group policy container and its User/Machine containers in the directory, and
      the GPO folder in SYSVOL over SMB with the permissions of the GPO, as GPMC does. It works
      against Samba and Windows domain controllers; it needs samba-tool on this computer.
    - GPO link: the gPLink of the domain or the OU, written over LDAP. The old value is removed
      and the new one added in one modify request: when someone changed the links meanwhile,
      the server refuses it instead of losing their change.

    The changes use Kerberos (kinit on Linux): a password is never given to samba-tool.
#>

# Runs samba-tool and returns its output; throws with its error output when it fails. It never
# asks for a password (--no-pass, no standard input): the changes use Kerberos.
function Invoke-PSGPOSambaTool {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [int]$TimeoutSeconds = 120
    )

    $platform = Get-PSGPOPlatform
    if (-not $platform.SambaToolPath) {
        if ($IsWindows) {
            throw 'Creating a GPO needs samba-tool, which runs on Linux: create it from a Linux computer of the domain, or with the Group Policy Management Console.'
        }
        throw 'Creating a GPO needs samba-tool on this computer (Debian/Ubuntu: apt install python3-samba; RHEL/Fedora: dnf install samba-tools).'
    }

    $result = Invoke-PSGPONativeCommand -FilePath $platform.SambaToolPath -ArgumentList (@($ArgumentList) + '--no-pass') -TimeoutSeconds $TimeoutSeconds
    if ($result.ExitCode -ne 0) {
        $message = "$($result.Error)".Trim()
        if (-not $message) { $message = "$($result.Output -join [Environment]::NewLine)".Trim() }
        throw "samba-tool $($ArgumentList[0..1] -join ' ') failed ($($result.ExitCode)): $message"
    }
    $result.Output
}

# GUID of the GPO in the output of samba-tool gpo create: "GPO 'name' created as {GUID}".
function ConvertFrom-PSGPOSambaToolGpoCreate {
    [CmdletBinding()]
    [OutputType([guid])]
    param(
        [AllowEmptyCollection()]
        [string[]]$Output
    )

    $match = [regex]::Match(($Output -join "`n"), 'created as (\{[0-9A-Fa-f-]{36}\})')
    if (-not $match.Success) { throw "samba-tool did not give the GUID of the new GPO: $($Output -join ' ')" }
    [guid]$match.Groups[1].Value
}

# Opens an LDAP connection like the one the directory was read with.
function New-PSGPODirectoryConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [GPOToolsLdapDirectory]$Directory
    )

    New-PSGPOLdapConnection -Server $Directory.Server -Credential $Directory.Credential -UseSsl:$Directory.UseSsl -Port $Directory.Port
}

# Creates the GPO in the domain and gives it the identity the domain chose.
function New-PSGPODomainGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [GPOToolsLdapDirectory]$Directory,

        [Parameter(Mandatory)]
        [GPOToolsGpo]$Gpo
    )

    if ($Directory.Credential) {
        throw "Creating a GPO uses Kerberos: run kinit $($Directory.Credential.UserName), then read the domain without -Credential."
    }
    $output = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'create', $Gpo.DisplayName, '-H', "ldap://$($Directory.Server)", '--use-kerberos=required'
    $id = ConvertFrom-PSGPOSambaToolGpoCreate -Output $output

    # The GPO as the domain stored it.
    $distinguishedName = 'CN={{{0}}},CN=Policies,CN=System,{1}' -f $id.ToString().ToUpperInvariant(), $Directory.Domain.DistinguishedName
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $distinguishedName -Scope Base `
            -Attribute 'displayName', 'versionNumber', 'flags', 'gPCFileSysPath'
    } finally {
        $connection.Dispose()
    }
    $Gpo.Id = $id
    $Gpo.DistinguishedName = if ($entry) { $entry.DistinguishedName } else { $distinguishedName }
    if ($entry) {
        $Gpo.DisplayName = Get-PSGPOLdapValue $entry 'displayName'
        $Gpo.FileSysPath = Get-PSGPOLdapValue $entry 'gPCFileSysPath'
        $Gpo.Version = [int](Get-PSGPOLdapValue $entry 'versionNumber')
        $Gpo.Flags = [int](Get-PSGPOLdapValue $entry 'flags')
    }
    Write-Verbose "GPO '$($Gpo.DisplayName)' created as {$id} in $($Directory.DomainName)."
}

# gPLink with a new link of lowest precedence: first in the value, as GPMC and samba-tool do.
function Get-PSGPONewGpLink {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string]$Current,

        [Parameter(Mandatory)]
        [GPOToolsGpoLink]$Link
    )

    foreach ($existing in [GPOToolsGpoLink]::Parse($Current)) {
        if ([string]::Equals($existing.GpoDistinguishedName, $Link.GpoDistinguishedName, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The GPO $($Link.GetDisplayName()) is already linked there."
        }
    }
    ('[LDAP://{0};{1}]' -f $Link.GpoDistinguishedName, $Link.GetOptions()) + "$Current".Trim()
}

# Adds the link to the gPLink of the SOM in the domain, then sets its links as the domain has them.
function Add-PSGPODomainGpLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [GPOToolsLdapDirectory]$Directory,

        [Parameter(Mandatory)]
        [GPOToolsSom]$Som,

        [Parameter(Mandatory)]
        [GPOToolsGpoLink]$Link
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Som.DistinguishedName -Scope Base -Attribute 'gPLink'
        if (-not $entry) { throw "$($Som.DistinguishedName) is not in the domain anymore." }
        $current = Get-PSGPOLdapValue $entry 'gPLink'
        $new = Get-PSGPONewGpLink -Current $current -Link $Link

        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Som.DistinguishedName
        if ($null -ne $current) {
            # Removing the value read makes the request fail if it changed meanwhile.
            $remove = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
            $remove.Name = 'gPLink'
            $remove.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Delete
            [void]$remove.Add($current)
            [void]$request.Modifications.Add($remove)
        }
        $add = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
        $add.Name = 'gPLink'
        $add.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
        [void]$add.Add($new)
        [void]$request.Modifications.Add($add)
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -in 'NoSuchAttribute', 'AttributeOrValueExists') {
                throw "The links of $($Som.Name) changed in the domain meanwhile: read the domain again, then link the GPO."
            }
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
                throw "The account cannot link GPOs to $($Som.Name): $($base.Message)"
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }

    # The links as the domain has them now, the new one being this link object.
    $Directory.SetLinks($Som, $new)
    for ($i = 0; $i -lt $Som.Links.Count; $i++) {
        if ([string]::Equals($Som.Links[$i].GpoDistinguishedName, $Link.GpoDistinguishedName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $Link.Order = $Som.Links[$i].Order
            $Link.Gpo = $Som.Links[$i].Gpo
            $Som.Links[$i] = $Link
        }
    }
    Write-Verbose "GPO $($Link.GetDisplayName()) linked to $($Som.DistinguishedName) (link order $($Link.Order))."
}
