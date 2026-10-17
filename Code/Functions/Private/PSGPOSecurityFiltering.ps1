<#
    GPO status and security filtering of a GPO in the domain (GPOToolsLdapDirectory), as GPMC
    sets them:

    - GPO status: the flags of the group policy container ([MS-GPOL] 2.2.2: 1 = user settings
      disabled, 2 = computer settings disabled). samba-tool gpo create has no option for it.
    - Security filtering: two global security groups, APPLY_<GPO> whose members apply the GPO and
      DENY_<GPO> whose members never apply it, in the DACL of the group policy container
      ("Apply Group Policy" extended right); Authenticated Users keep reading the GPO, as the
      computers must (MS16-072). The ACL of the SYSVOL folder of the GPO is derived from it as
      samba-tool and GPMC do, so that samba-tool gpo aclcheck still finds them consistent.
#>

# Name of a security filtering group: the prefix of its role in the configuration (APPLY_,
# DENY_ by default), then the name of the GPO, the characters a group name cannot hold replaced by _.
function Get-PSGPOFilteringGroupName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateSet('Apply', 'Deny')] [string]$Role,
        [Parameter(Mandatory)] [string]$GpoName,
        # The SecurityFilteringGroups table of the configuration
        [hashtable]$Settings = (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups
    )

    $name = '{0}{1}' -f $Settings["${Role}Prefix"], ("$GpoName".Trim() -replace '["/\\\[\]:;|=,+*?<>@]', '_')
    $name = $name.TrimEnd('.', ' ')
    # cn of a group: 64 characters at most.
    if ($name.Length -gt 64) { throw "The group name '$name' is longer than 64 characters: give the GPO a shorter name." }
    $name
}

# SID of the directory value objectSid.
function ConvertFrom-PSGPOBinarySid {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [byte[]]$Bytes)

    [GPOToolsSecurityDescriptor]::ConvertSidToString($Bytes, 0)
}

# Writes the flags of the group policy container (GPO status).
function Set-PSGPODomainGpoStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [ValidateRange(0, 3)] [int]$Flags
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new($Gpo.DistinguishedName,
            [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Replace, 'flags', "$Flags")
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
                throw "The account cannot change the status of the GPO '$($Gpo.DisplayName)': $($base.Message)"
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "GPO '$($Gpo.DisplayName)': flags $Flags ($($Gpo.GetStatus()))."
}

# Creates a global security group in a container of the domain; returns its distinguished name
# and SID.
function New-PSGPODomainGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Container,
        [string]$Description,
        # Scope of the security group
        [ValidateSet('Global', 'DomainLocal', 'Universal')] [string]$Scope = 'Global'
    )

    $distinguishedName = 'CN={0},{1}' -f ($Name -replace '([,\\#+<>;"=])', '\$1'), $Container
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $request = [System.DirectoryServices.Protocols.AddRequest]::new($distinguishedName)
        [void]$request.Attributes.Add([System.DirectoryServices.Protocols.DirectoryAttribute]::new('objectClass', 'group'))
        [void]$request.Attributes.Add([System.DirectoryServices.Protocols.DirectoryAttribute]::new('sAMAccountName', $Name))
        # A security group (GROUP_TYPE_SECURITY_ENABLED 0x80000000) of its scope ([MS-ADTS] 2.2.13):
        # global 0x2, domain local 0x4, universal 0x8.
        $groupType = @{ Global = -2147483646; DomainLocal = -2147483644; Universal = -2147483640 }[$Scope]
        [void]$request.Attributes.Add([System.DirectoryServices.Protocols.DirectoryAttribute]::new('groupType', "$groupType"))
        if ($Description) { [void]$request.Attributes.Add([System.DirectoryServices.Protocols.DirectoryAttribute]::new('description', $Description)) }
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            $code = if ($base.PSObject.Properties['Response']) { "$($base.Response.ResultCode)" }
            switch ($code) {
                'EntryAlreadyExists' { throw "The group $distinguishedName already exists." }
                'ConstraintViolation' { throw "The group '$Name' cannot be created, its name is already used in the domain: $($base.Message)" }
                'InsufficientAccessRights' { throw "The account cannot create groups in ${Container}: $($base.Message)" }
                'NoSuchObject' { throw "The container $Container does not exist anymore." }
            }
            throw
        }
        # objectSid is binary: read as bytes, not as text.
        $search = [System.DirectoryServices.Protocols.SearchRequest]::new($distinguishedName, '(objectClass=*)', 'Base', 'objectSid')
        $entries = $connection.SendRequest($search).Entries
    } finally {
        $connection.Dispose()
    }
    $sid = $null
    if ($entries.Count -and $entries[0].Attributes['objectSid']) {
        $sid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entries[0].Attributes['objectSid'].GetValues([byte[]])[0])
    }
    if (-not $sid) { throw "The group $distinguishedName was created but its SID cannot be read." }
    Write-Verbose "Group $distinguishedName created ($sid)."
    [pscustomobject]@{ Name = $Name; DistinguishedName = $distinguishedName; Sid = $sid }
}

# Security descriptor (owner, group, DACL) of an object of the directory.
function Get-PSGPODomainSecurityDescriptor {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DistinguishedName
    )

    $request = [System.DirectoryServices.Protocols.SearchRequest]::new($DistinguishedName, '(objectClass=*)', 'Base', 'nTSecurityDescriptor')
    [void]$request.Controls.Add([System.DirectoryServices.Protocols.SecurityDescriptorFlagControl]::new([System.DirectoryServices.Protocols.SecurityMasks]'Owner,Group,Dacl'))
    $response = $Connection.SendRequest($request)
    if (-not $response.Entries.Count -or -not $response.Entries[0].Attributes['nTSecurityDescriptor']) {
        throw "The security descriptor of $DistinguishedName cannot be read."
    }
    [GPOToolsSecurityDescriptor]::Parse([byte[]]$response.Entries[0].Attributes['nTSecurityDescriptor'].GetValues([byte[]])[0])
}

# Writes the DACL of an object of the directory; its owner and group stay as they are.
function Set-PSGPODomainDacl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DistinguishedName,
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        # What the object is, for the access denied message
        [string]$Name = $DistinguishedName
    )

    $request = [System.DirectoryServices.Protocols.ModifyRequest]::new($DistinguishedName,
        [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Replace, 'nTSecurityDescriptor', [byte[]]$Descriptor.ToBytes())
    [void]$request.Controls.Add([System.DirectoryServices.Protocols.SecurityDescriptorFlagControl]::new([System.DirectoryServices.Protocols.SecurityMasks]::Dacl))
    try {
        [void]$Connection.SendRequest($request)
    } catch {
        $base = $_.Exception.GetBaseException()
        if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
            throw "The account cannot change the permissions of ${Name}: $($base.Message)"
        }
        throw
    }
}

# Sets the ACL of the SYSVOL folder of the GPO as samba-tool gpo create does: through the SMB
# client of Samba (its Python bindings, there with samba-tool), with the ACEs in the order given.
# smbcacls is not used: it sorts the ACEs and removes duplicates, and samba-tool gpo aclcheck
# compares the folder ACL with the directory one as they are written. The files and folders of
# the GPO keep their ACL: Authenticated Users read them, as the computers must.
$script:PSGPOSetSysvolAclPython = @'
import sys
from samba import param
from samba.credentials import Credentials, MUST_USE_KERBEROS, SMB_SIGNING_REQUIRED
from samba.dcerpc import security
from samba.samba3 import param as s3param
from samba.samba3 import libsmb_samba_internal as libsmb

server, share, path, sddl = sys.argv[1:5]
lp = param.LoadParm()
lp.load_default()
creds = Credentials()
creds.guess(lp)
creds.set_kerberos_state(MUST_USE_KERBEROS)
creds.set_smb_signing(SMB_SIGNING_REQUIRED)
s3_lp = s3param.get_context()
if lp.configfile:
    s3_lp.load(lp.configfile)
conn = libsmb.Conn(server, share, lp=s3_lp, creds=creds)
descriptor = security.descriptor.from_sddl(sddl, security.dom_sid('S-1-5-32'))
conn.set_acl(path, descriptor, security.SECINFO_DACL | security.SECINFO_PROTECTED_DACL)
'@

function Set-PSGPOSysvolAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor
    )

    if ($IsWindows) {
        # Windows: the folder by its UNC path, with the access control of .NET; the ACEs of the
        # extended rights (Apply Group Policy) are left out, as GPMC does: they mean nothing to a
        # file. Windows propagates the inheritable ACEs to the files and folders of the GPO.
        $location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
        $files = [GPOToolsSecurityDescriptor]::Parse($Descriptor.ToBytes())
        $files.Dacl.RemoveAll([Predicate[GPOToolsAce]] { param($Ace) $Ace.IsObjectAce() }) | Out-Null
        $folder = [System.IO.DirectoryInfo]::new("\\$($Directory.Server)\$($location.Share)\$($location.Path)")
        if (-not $folder.Exists) { throw "The folder of the GPO '$($Gpo.DisplayName)' is not in SYSVOL: $($folder.FullName)" }
        $security = [System.Security.AccessControl.DirectorySecurity]::new()
        $security.SetSecurityDescriptorSddlForm($files.ToSddl(), [System.Security.AccessControl.AccessControlSections]::Access)
        try {
            [System.IO.FileSystemAclExtensions]::SetAccessControl($folder, $security)
        } catch {
            throw "The SYSVOL permissions of the GPO '$($Gpo.DisplayName)' cannot be set: $($_.Exception.Message)"
        }
        return
    }
    Assert-PSGPOKerberosOnly -Directory $Directory
    $python = Get-Command -Name 'python3' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) { throw 'Setting the SYSVOL permissions needs python3 and the Samba Python bindings (Debian/Ubuntu: apt install python3-samba).' }
    $location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
    $result = Invoke-PSGPONativeCommand -FilePath $python.Source -ArgumentList '-c', $script:PSGPOSetSysvolAclPython,
        $Directory.Server, $location.Share, ($location.Path -replace '/', '\'), $Descriptor.ToSddl()
    if ($result.ExitCode -ne 0) {
        $lines = @("$($result.Error)" -split '\r?\n' | Where-Object { $_ })
        $message = if ($lines -match 'ModuleNotFoundError') { 'the Samba Python bindings are missing (Debian/Ubuntu: apt install python3-samba)' } elseif ($lines) { $lines[-1] } else { "exit code $($result.ExitCode)" }
        throw "The SYSVOL permissions of the GPO '$($Gpo.DisplayName)' cannot be set: $message"
    }
}

# Security filtering of the GPO: Apply Group Policy for the members of $ApplySid only, never for
# the members of $DenySid; in the directory, then in SYSVOL.
function Set-PSGPODomainSecurityFiltering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [string]$ApplySid,
        [string]$DenySid
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $Gpo.DistinguishedName
        $descriptor.SetSecurityFiltering($ApplySid, $DenySid)
        Set-PSGPODomainDacl -Connection $connection -DistinguishedName $Gpo.DistinguishedName -Descriptor $descriptor -Name "the GPO '$($Gpo.DisplayName)'"
        # Read again: the ACL as the domain stored it gives the ACL of the folder.
        $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $connection -DistinguishedName $Gpo.DistinguishedName
    } finally {
        $connection.Dispose()
    }
    Set-PSGPOSysvolAcl -Directory $Directory -Gpo $Gpo -Descriptor $descriptor.ConvertToFileSystem()
    Write-Verbose "GPO '$($Gpo.DisplayName)': security filtering set (apply: $ApplySid, deny: $DenySid)."
}

# Creates the groups APPLY_<GPO> and DENY_<GPO> in $Container and sets the security filtering of
# the GPO with them; returns the groups.
function New-PSGPODomainFilteringGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [string]$Container,
        # The groups only: the approval of the GPO sets its security filtering.
        [switch]$NoFiltering
    )

    # Names, scope and descriptions from the configuration.
    $settings = (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups
    $applyName = Get-PSGPOFilteringGroupName -Role Apply -GpoName $Gpo.DisplayName -Settings $settings
    $denyName = Get-PSGPOFilteringGroupName -Role Deny -GpoName $Gpo.DisplayName -Settings $settings
    $apply = New-PSGPODomainGroup -Directory $Directory -Name $applyName -Container $Container -Scope $settings.Scope -Description ($settings.ApplyDescription -f $Gpo.DisplayName)
    $deny = New-PSGPODomainGroup -Directory $Directory -Name $denyName -Container $Container -Scope $settings.Scope -Description ($settings.DenyDescription -f $Gpo.DisplayName)
    if (-not $NoFiltering) { Set-PSGPODomainSecurityFiltering -Directory $Directory -Gpo $Gpo -ApplySid $apply.Sid -DenySid $deny.Sid }
    $apply, $deny
}

# LDAP filter value of a binary attribute: each byte escaped (\xx).
function ConvertTo-PSGPOLdapBinaryFilter {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [byte[]]$Bytes)

    -join ($Bytes | ForEach-Object { '\{0:x2}' -f $_ })
}

# Names of SIDs: the well-known ones, the others read in the domain (sAMAccountName), by groups
# of 50 in one search each; a SID found nowhere keeps its string form.
function Resolve-PSGPODomainSid {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DomainDistinguishedName,
        [AllowEmptyCollection()] [string[]]$Sid = @()
    )

    $names = @{}
    $unknown = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @($Sid | Select-Object -Unique)) {
        if ([GPOToolsSecurityDescriptor]::WellKnownNames.ContainsKey($value)) { $names[$value] = [GPOToolsSecurityDescriptor]::WellKnownNames[$value] }
        else { $unknown.Add($value) }
    }
    for ($start = 0; $start -lt $unknown.Count; $start += 50) {
        $chunk = $unknown.GetRange($start, [Math]::Min(50, $unknown.Count - $start))
        $filter = '(|{0})' -f (-join ($chunk | ForEach-Object { "(objectSid=$(ConvertTo-PSGPOLdapBinaryFilter -Bytes ([GPOToolsSecurityDescriptor]::ConvertSidToBytes($_))))" }))
        $request = [System.DirectoryServices.Protocols.SearchRequest]::new($DomainDistinguishedName, $filter, 'Subtree', 'objectSid', 'sAMAccountName')
        foreach ($entry in $Connection.SendRequest($request).Entries) {
            if (-not $entry.Attributes['objectSid'] -or -not $entry.Attributes['sAMAccountName']) { continue }
            $found = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entry.Attributes['objectSid'].GetValues([byte[]])[0])
            $names[$found] = "$($entry.Attributes['sAMAccountName'].GetValues([string])[0])"
        }
    }
    foreach ($value in $unknown) { if (-not $names.ContainsKey($value)) { $names[$value] = $value } }
    $names
}

# Security filtering of every GPO of the directory (SecurityFiltering, DeniedTo), from their
# DACL read in one paged search; a GPO whose DACL cannot be read gets $null (not read).
function Read-PSGPODomainSecurityFiltering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory
    )

    $request = [System.DirectoryServices.Protocols.SearchRequest]::new("CN=Policies,CN=System,$($Directory.Domain.DistinguishedName)",
        '(objectClass=groupPolicyContainer)', 'OneLevel', 'nTSecurityDescriptor')
    [void]$request.Controls.Add([System.DirectoryServices.Protocols.SecurityDescriptorFlagControl]::new([System.DirectoryServices.Protocols.SecurityMasks]::Dacl))
    $page = [System.DirectoryServices.Protocols.PageResultRequestControl]::new(500)
    [void]$request.Controls.Add($page)
    $filtering = @{}
    do {
        $response = $Connection.SendRequest($request)
        foreach ($entry in $response.Entries) {
            if (-not $entry.Attributes['nTSecurityDescriptor']) { continue }
            $descriptor = [GPOToolsSecurityDescriptor]::Parse([byte[]]$entry.Attributes['nTSecurityDescriptor'].GetValues([byte[]])[0])
            $filtering[$entry.DistinguishedName.ToLowerInvariant()] = $descriptor.GetSecurityFiltering()
        }
        $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] } | Select-Object -First 1).Cookie
        $page.Cookie = $cookie
    } while ($cookie -and $cookie.Length)

    $names = Resolve-PSGPODomainSid -Connection $Connection -DomainDistinguishedName $Directory.Domain.DistinguishedName `
        -Sid @($filtering.Values | ForEach-Object { $_.Apply; $_.Deny })
    foreach ($gpo in $Directory.Gpos) {
        $found = $filtering["$($gpo.DistinguishedName)".ToLowerInvariant()]
        if (-not $found) {
            $gpo.SecurityFiltering = $null
            $gpo.DeniedTo = $null
            continue
        }
        $gpo.SecurityFiltering = @($found.Apply | ForEach-Object { $names[$_] })
        $gpo.DeniedTo = @($found.Deny | ForEach-Object { $names[$_] })
    }
}
