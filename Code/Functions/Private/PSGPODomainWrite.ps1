<#
    Changes written to the domain of a GPOToolsLdapDirectory (its hidden Save* methods).

    - GPO creation, against the domain controller of the directory: on Windows New-GPO of the
      Group Policy Management tools of RSAT (the GroupPolicy module), on Linux samba-tool gpo
      create. Both create the group policy container and its User/Machine containers in the
      directory, and the GPO folder in SYSVOL with the permissions of the GPO, as GPMC does,
      against Samba and Windows domain controllers.
    - GPO deletion, the same way: Remove-GPO on Windows, samba-tool gpo del on Linux (its
      container and its SYSVOL folder); its links are deleted over LDAP before.
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
            throw 'This change needs samba-tool, which runs on Linux: make it from a Linux computer of the domain, or with the Group Policy Management Console.'
        }
        throw 'This change needs samba-tool on this computer (Debian/Ubuntu: apt install python3-samba; RHEL/Fedora: dnf install samba-tools).'
    }

    $result = Invoke-PSGPONativeCommand -FilePath $platform.SambaToolPath -ArgumentList (@($ArgumentList) + '--no-pass') -TimeoutSeconds $TimeoutSeconds
    if ($result.ExitCode -ne 0) {
        $message = "$($result.Error)".Trim()
        if (-not $message) { $message = "$($result.Output -join [Environment]::NewLine)".Trim() }
        throw "samba-tool $($ArgumentList[0..1] -join ' ') failed ($($result.ExitCode)): $message"
    }
    $result.Output
}

# Creates a GPO from Windows with New-GPO (GroupPolicy module of RSAT, loaded in PowerShell 7
# through its Windows PowerShell compatibility), on the domain controller of the directory;
# returns its GUID.
function New-PSGPOWindowsGpo {
    [CmdletBinding()]
    [OutputType([guid])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Name
    )

    # -SkipEditionCheck: PowerShell 7 hides the Windows PowerShell modules not marked for Core
    # (GroupPolicy is one); Import-Module loads them through the Windows PowerShell compatibility.
    Import-PSGPOGroupPolicyModule -Action 'Creating a GPO'
    try {
        $created = New-GPO -Name $Name -Domain $Directory.DomainName -Server $Directory.Server -ErrorAction Stop
    } catch {
        throw "New-GPO failed on $($Directory.Server): $($_.Exception.Message)"
    }
    [guid]"$($created.Id)"
}

# Loads the GroupPolicy module of RSAT, or says how to install it.
function Import-PSGPOGroupPolicyModule {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Action)

    # -SkipEditionCheck: PowerShell 7 hides the Windows PowerShell modules not marked for Core
    # (GroupPolicy is one); Import-Module loads them through the Windows PowerShell compatibility.
    if (-not (Get-Module -ListAvailable -SkipEditionCheck -Name GroupPolicy)) {
        throw "$Action from Windows needs the Group Policy Management tools of RSAT (the GroupPolicy module): Add-WindowsCapability -Online -Name 'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0' on Windows 10/11, or Install-WindowsFeature GPMC on Windows Server."
    }
    Import-Module -Name GroupPolicy -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false
}

# Deletes a GPO from Windows with Remove-GPO (RSAT), on the domain controller of the directory.
function Remove-PSGPOWindowsGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    Import-PSGPOGroupPolicyModule -Action 'Deleting a GPO'
    try {
        Remove-GPO -Guid $Gpo.Id -Domain $Directory.DomainName -Server $Directory.Server -Confirm:$false -ErrorAction Stop
    } catch {
        throw "Remove-GPO failed on $($Directory.Server): $($_.Exception.Message)"
    }
}

# Deletes a GPO of the domain (GPOToolsDirectory.RemoveGpo, its links deleted before): its
# container in the directory and its folder in SYSVOL, then checks it is gone.
function Remove-PSGPODomainGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    if ($Directory.Credential) {
        throw "Deleting a GPO uses the identity of the session (Kerberos): $(if ($IsWindows) { 'read the domain' } else { "run kinit $($Directory.Credential.UserName), then read the domain" }) without -Credential."
    }
    if ($IsWindows) {
        Remove-PSGPOWindowsGpo -Directory $Directory -Gpo $Gpo
    } else {
        $null = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'del', ('{' + $Gpo.Id.ToString().ToUpperInvariant() + '}'), '-H', "ldap://$($Directory.Server)", '--use-kerberos=required'
    }
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Base -Attribute 'displayName'
    } finally {
        $connection.Dispose()
    }
    if ($entry) { throw "The GPO '$($Gpo.DisplayName)' is still in the domain after its deletion." }
    Write-Verbose "GPO $($Gpo.DisplayName) deleted from $($Directory.Server)."
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
        throw "Creating a GPO uses the identity of the session (Kerberos): $(if ($IsWindows) { 'read the domain' } else { "run kinit $($Directory.Credential.UserName), then read the domain" }) without -Credential."
    }
    $id = if ($IsWindows) {
        New-PSGPOWindowsGpo -Directory $Directory -Name $Gpo.DisplayName
    } else {
        ConvertFrom-PSGPOSambaToolGpoCreate -Output (Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'create', $Gpo.DisplayName, '-H', "ldap://$($Directory.Server)", '--use-kerberos=required')
    }

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

    $new = Update-PSGPODomainGpLink -Directory $Directory -Som $Som -Change { param($Current) Get-PSGPONewGpLink -Current $Current -Link $Link } -Action 'link GPOs to'

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

# gPLink without the link of a GPO, the other links kept as written; throws when the GPO is not
# linked there.
function Get-PSGPORemovedGpLink {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string]$Current,

        [Parameter(Mandatory)]
        [GPOToolsGpoLink]$Link
    )

    $kept = [System.Text.StringBuilder]::new()
    $found = $false
    foreach ($match in [regex]::Matches("$Current", '\[LDAP://([^;\]]+);(\d+)\]', 'IgnoreCase')) {
        if (-not $found -and [string]::Equals($match.Groups[1].Value, $Link.GpoDistinguishedName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found = $true
            continue
        }
        [void]$kept.Append($match.Value)
    }
    if (-not $found) { throw "The GPO $($Link.GetDisplayName()) is not linked there anymore." }
    $kept.ToString()
}

# Changes the gPLink of a SOM in the domain: $Change gets the value read and returns the new one
# (empty: no link left, the attribute is removed, as samba-tool gpo dellink does). The value read
# is removed in the same request, so that it fails if the links changed meanwhile. Returns the
# new value.
function Update-PSGPODomainGpLink {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsSom]$Som,
        [Parameter(Mandatory)] [scriptblock]$Change,
        # What the account does, for the access denied message ('link GPOs to')
        [Parameter(Mandatory)] [string]$Action
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Som.DistinguishedName -Scope Base -Attribute 'gPLink'
        if (-not $entry) { throw "$($Som.DistinguishedName) is not in the domain anymore." }
        $current = Get-PSGPOLdapValue $entry 'gPLink'
        $new = "$(& $Change $current)"

        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Som.DistinguishedName
        if ($null -ne $current) {
            $remove = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
            $remove.Name = 'gPLink'
            $remove.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Delete
            [void]$remove.Add($current)
            [void]$request.Modifications.Add($remove)
        }
        if ($new) {
            $add = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
            $add.Name = 'gPLink'
            $add.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
            [void]$add.Add($new)
            [void]$request.Modifications.Add($add)
        }
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -in 'NoSuchAttribute', 'AttributeOrValueExists') {
                throw "The links of $($Som.Name) changed in the domain meanwhile: read the domain again, then try again."
            }
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
                throw "The account cannot $Action $($Som.Name): $($base.Message)"
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    $new
}

# Removes the link from the gPLink of the SOM in the domain, then sets its links as the domain
# has them.
function Remove-PSGPODomainGpLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [GPOToolsLdapDirectory]$Directory,

        [Parameter(Mandatory)]
        [GPOToolsSom]$Som,

        [Parameter(Mandatory)]
        [GPOToolsGpoLink]$Link
    )

    $new = Update-PSGPODomainGpLink -Directory $Directory -Som $Som -Change { param($Current) Get-PSGPORemovedGpLink -Current $Current -Link $Link } -Action 'delete the links of'
    $Directory.SetLinks($Som, $new)
    Write-Verbose "Link of the GPO $($Link.GetDisplayName()) to $($Som.DistinguishedName) deleted."
}

# The GPO as the directory has it now: display name, version, status and last change.
function Update-PSGPODomainGpoState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Base `
            -Attribute 'displayName', 'versionNumber', 'flags', 'whenChanged', 'gPCMachineExtensionNames', 'gPCUserExtensionNames'
    } finally {
        $connection.Dispose()
    }
    if (-not $entry) { throw "The GPO '$($Gpo.DisplayName)' is not in the domain anymore." }
    $displayName = Get-PSGPOLdapValue $entry 'displayName'
    if ($displayName) { $Gpo.DisplayName = $displayName }
    $Gpo.Version = [int](Get-PSGPOLdapValue $entry 'versionNumber')
    $Gpo.Flags = [int](Get-PSGPOLdapValue $entry 'flags')
    $Gpo.Modified = ConvertFrom-PSGPOGeneralizedTime (Get-PSGPOLdapValue $entry 'whenChanged')
    $Gpo.MachineExtensionNames = Get-PSGPOLdapValue $entry 'gPCMachineExtensionNames'
    $Gpo.UserExtensionNames = Get-PSGPOLdapValue $entry 'gPCUserExtensionNames'
}
