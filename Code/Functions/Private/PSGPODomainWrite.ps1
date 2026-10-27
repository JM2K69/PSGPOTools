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
    # samba-tool and Remove-GPO delete the folder gPCFileSysPath gives, with the rights of the
    # account: read now (it may have changed since the domain was read), it is set back to the
    # folder of the GPO first, so that a redirected GPO does not delete another folder.
    Reset-PSGPODomainFileSysPath -Directory $Directory -Gpo $Gpo
    if ($IsWindows) {
        Remove-PSGPOWindowsGpo -Directory $Directory -Gpo $Gpo
    } else {
        $null = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'del', ('{' + $Gpo.Id.ToString().ToUpperInvariant() + '}'), '-H', "ldap://$($Directory.Server)", '--use-kerberos=required'
    }
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Base -Attribute 'displayName' -AllowMissing
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

    # Linux: a ticket that expired fails the change halfway, with an error that does not say it.
    if (-not $Directory.Credential) { Assert-PSGPOKerberosTicket }
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
    Set-PSGPOSomLinkFromDomain -Directory $Directory -Som $Som -GpLink $new -Link $Link
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
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Som.DistinguishedName -Scope Base -Attribute 'gPLink' -AllowMissing
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
    Set-PSGPOSomLinkFromDomain -Directory $Directory -Som $Som -GpLink $new
    Write-Verbose "Link of the GPO $($Link.GetDisplayName()) to $($Som.DistinguishedName) deleted."
}

# Sets the gPCFileSysPath of a GPO back to its folder in SYSVOL when it is another one (a
# redirected GPO, IsGpoRedirected), as the domain has it now; the value read removed in the same
# request, so that it fails if someone changes it meanwhile.
function Reset-PSGPODomainFileSysPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Base -Attribute 'gPCFileSysPath' -AllowMissing
        if (-not $entry) { return }
        $Gpo.FileSysPath = Get-PSGPOLdapValue $entry 'gPCFileSysPath'
        if (-not $Directory.IsGpoRedirected($Gpo)) { return }
        $canonical = $Directory.GetCanonicalFileSysPath($Gpo)
        if (-not $PSCmdlet.ShouldProcess($Gpo.DisplayName, "Set gPCFileSysPath back to $canonical")) { return }
        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Gpo.DistinguishedName
        $remove = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
        $remove.Name = 'gPCFileSysPath'
        $remove.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Delete
        [void]$remove.Add($Gpo.FileSysPath)
        [void]$request.Modifications.Add($remove)
        $add = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
        $add.Name = 'gPCFileSysPath'
        $add.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
        [void]$add.Add($canonical)
        [void]$request.Modifications.Add($add)
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            $code = if ($base.PSObject.Properties['Response']) { "$($base.Response.ResultCode)" }
            if ($code -in 'NoSuchAttribute', 'AttributeOrValueExists') { throw "The gPCFileSysPath of the GPO '$($Gpo.DisplayName)' changed in the domain meanwhile: read the domain again, then try again." }
            if ($code -eq 'InsufficientAccessRights') { throw "The GPO '$($Gpo.DisplayName)' is redirected to '$($Gpo.FileSysPath)', and the account cannot set its gPCFileSysPath back: $($base.Message)" }
            throw
        }
        Write-Warning "GPO '$($Gpo.DisplayName)': its gPCFileSysPath was '$($Gpo.FileSysPath)', set back to '$canonical'."
        $Gpo.FileSysPath = $canonical
    } finally {
        $connection.Dispose()
    }
}

# Renames a GPO in the domain: the displayName of its group policy container, the name read
# removed in the same request, so that it fails if someone renamed it meanwhile.
function Set-PSGPODomainGpoName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [string]$DisplayName
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Gpo.DistinguishedName
        $remove = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
        $remove.Name = 'displayName'
        $remove.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Delete
        [void]$remove.Add($Gpo.DisplayName)
        [void]$request.Modifications.Add($remove)
        $add = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
        $add.Name = 'displayName'
        $add.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
        [void]$add.Add($DisplayName)
        [void]$request.Modifications.Add($add)
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            $code = if ($base.PSObject.Properties['Response']) { "$($base.Response.ResultCode)" }
            if ($code -in 'NoSuchAttribute', 'AttributeOrValueExists') { throw "The GPO '$($Gpo.DisplayName)' changed in the domain meanwhile: read the domain again, then try again." }
            if ($code -eq 'InsufficientAccessRights') { throw "The account cannot rename the GPO '$($Gpo.DisplayName)': $($base.Message)" }
            if ($code -eq 'NoSuchObject') { throw "The GPO '$($Gpo.DisplayName)' is not in the domain anymore." }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "GPO '$($Gpo.DisplayName)' renamed '$DisplayName'."
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
            -Attribute 'displayName', 'versionNumber', 'flags', 'whenChanged', 'gPCMachineExtensionNames', 'gPCUserExtensionNames' -AllowMissing
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

# The links of a SOM as the domain has them ($GpLink), each one the link object the SOM had for its
# GPO (and $Link, a new link), updated: what holds a link (the window, a script) keeps it.
function Set-PSGPOSomLinkFromDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsSom]$Som,
        [AllowEmptyString()] [string]$GpLink,
        [GPOToolsGpoLink]$Link
    )

    $known = @{}
    foreach ($existing in $Som.Links) { $known[$existing.GpoDistinguishedName] = $existing }
    if ($Link) { $known[$Link.GpoDistinguishedName] = $Link }
    $Directory.SetLinks($Som, $GpLink)
    for ($i = 0; $i -lt $Som.Links.Count; $i++) {
        $read = $Som.Links[$i]
        $kept = $known[$read.GpoDistinguishedName]
        if (-not $kept) { continue }
        $kept.Order = $read.Order
        $kept.Enabled = $read.Enabled
        $kept.Enforced = $read.Enforced
        $kept.Gpo = $read.Gpo
        $Som.Links[$i] = $kept
    }
}

# gPLink with the link of a GPO changed: enabled or not, enforced or not, and moved to the link
# order $Order (1 is the highest precedence; 0 keeps it). The other links are kept as written;
# throws when the GPO is not linked there.
function Get-PSGPOChangedGpLink {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string]$Current,
        [Parameter(Mandatory)] [GPOToolsGpoLink]$Link,
        [Nullable[bool]]$Enabled,
        [Nullable[bool]]$Enforced,
        [int]$Order = 0
    )

    # In link order: the last entry of the value is link order 1.
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches("$Current", '\[LDAP://([^;\]]+);(\d+)\]', 'IgnoreCase')) {
        $entries.Insert(0, [pscustomobject]@{ Dn = $match.Groups[1].Value; Options = [int]$match.Groups[2].Value; Text = $match.Value })
    }
    $entry = $entries | Where-Object { [string]::Equals($_.Dn, $Link.GpoDistinguishedName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if (-not $entry) { throw "The GPO $($Link.GetDisplayName()) is not linked there anymore." }
    $options = $entry.Options
    if ($null -ne $Enabled) { $options = if ($Enabled) { $options -band (-bnot 1) } else { $options -bor 1 } }
    if ($null -ne $Enforced) { $options = if ($Enforced) { $options -bor 2 } else { $options -band (-bnot 2) } }
    if ($options -ne $entry.Options) { $entry.Text = '[LDAP://{0};{1}]' -f $entry.Dn, $options }
    if ($Order -gt 0) {
        [void]$entries.Remove($entry)
        $entries.Insert([math]::Min($Order, $entries.Count + 1) - 1, $entry)
    }
    $text = [System.Text.StringBuilder]::new()
    for ($i = $entries.Count - 1; $i -ge 0; $i--) { [void]$text.Append($entries[$i].Text) }
    $text.ToString()
}

# Changes a link of a SOM in the domain (Get-PSGPOChangedGpLink), then sets its links as the
# domain has them, the changed one being this link object.
function Set-PSGPODomainGpLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsSom]$Som,
        [Parameter(Mandatory)] [GPOToolsGpoLink]$Link,
        [Nullable[bool]]$Enabled,
        [Nullable[bool]]$Enforced,
        [int]$Order = 0
    )

    $new = Update-PSGPODomainGpLink -Directory $Directory -Som $Som -Action 'change the links of' -Change {
        param($Current) Get-PSGPOChangedGpLink -Current $Current -Link $Link -Enabled $Enabled -Enforced $Enforced -Order $Order
    }
    Set-PSGPOSomLinkFromDomain -Directory $Directory -Som $Som -GpLink $new -Link $Link
    Write-Verbose "Link of the GPO $($Link.GetDisplayName()) to $($Som.DistinguishedName): link order $($Link.Order), $(if ($Link.Enabled) { 'enabled' } else { 'disabled' })$(if ($Link.Enforced) { ', enforced' })."
}

# Blocks or unblocks the inheritance of a SOM (bit 0 of gPOptions), refused if gPOptions changed
# meanwhile. Returns whether it is blocked, as the domain has it.
function Set-PSGPODomainBlockInheritance {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsSom]$Som,
        [Parameter(Mandatory)] [bool]$Blocked
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Som.DistinguishedName -Scope Base -Attribute 'gPOptions' -AllowMissing
        if (-not $entry) { throw "$($Som.DistinguishedName) is not in the domain anymore." }
        $old = Get-PSGPOLdapValue $entry 'gPOptions'
        $options = if ($Blocked) { [int]$old -bor 1 } else { [int]$old -band (-bnot 1) }
        if ("$old" -eq "$options") { return $Blocked }
        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Som.DistinguishedName
        Add-PSGPOLdapValueChange -Request $request -Name 'gPOptions' -Old $old -New "$options"
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -in 'NoSuchAttribute', 'AttributeOrValueExists') {
                throw "The inheritance of $($Som.Name) changed in the domain meanwhile: read the domain again, then try again."
            }
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
                throw "The account cannot block the inheritance of $($Som.Name): $($base.Message)"
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "Inheritance of $($Som.DistinguishedName) $(if ($Blocked) { 'blocked' } else { 'not blocked' })."
    $Blocked
}
