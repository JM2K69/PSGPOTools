<#
    The share of the central audit log, prepared by Initialize-PSGPOAuditShare: a folder per tier,
    and the permissions of the roles (the DACLs are protected: nothing is inherited from the
    share, nothing given to whoever is not named).

    - The share and each folder: the administrators (SYSTEM, Administrators, Domain Admins) have
      full control.
    - Tier0, Tier1, Tier2: the groups of the tier create their files there and read every file of
      their tier; Tier 0 (the approvers of the workflow, Domain Admins) and the readers (auditors)
      read every tier.
    - Unassigned: a user of the domain in no tier writes there (Domain Users: not the computers);
      Tier 0 and the readers read it.
    - The file of an account: its owner reads it and appends to it, without writing over it,
      deleting it nor changing its permissions (CREATOR OWNER, OWNER RIGHTS: FILE_APPEND_DATA
      without FILE_WRITE_DATA). Windows appends at its end; Samba refuses to open it to write,
      but lets a handle opened to append write anywhere: the lines are chained (Write-PSGPOAuditEntry).
    - The share itself: the groups of the tiers and the readers list it; any other account only
      goes through it, to the folder Unassigned, without seeing what it holds.
#>

# Access masks ([MS-DTYP] 2.4.3): read and list (FILE_GENERIC_READ | FILE_GENERIC_EXECUTE), the
# same and create files, the owner of a file (read and append, attributes; no write over it, no
# delete), the retention (read, delete a file and the files of a folder), the archives (modify).
$script:PSGPOAuditShareRight = @{ Full = '0x1f01ff'; Read = '0x1200a9'; Create = '0x1200ab'; Owner = '0x12019d'; Traverse = '0x1000a0'; Purge = '0x1300e9'; Modify = '0x1301bf' }

# The folders of the share and the SDDL of each: Folder ('' for the share), Sddl. The groups are
# lists of SIDs.
function Get-PSGPOAuditShareSddl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$DomainAdminsSid,
        [AllowEmptyCollection()] [string[]]$Tier0 = @(),
        [AllowEmptyCollection()] [string[]]$Tier1 = @(),
        [AllowEmptyCollection()] [string[]]$Tier2 = @(),
        [AllowEmptyCollection()] [string[]]$Readers = @(),
        # The groups that run the retention (Audit.Purgers): they read every folder and delete
        # its files, write the archives in Archive, and write their own changes in Unassigned.
        [AllowEmptyCollection()] [string[]]$Purgers = @()
    )

    $right = $script:PSGPOAuditShareRight
    $admins = "(A;OICI;$($right.Full);;;SY)(A;OICI;$($right.Full);;;BA)(A;OICI;$($right.Full);;;$DomainAdminsSid)"
    $readAll = (@($Tier0) + @($Readers) | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { "(A;OICI;$($right.Read);;;$_)" }) -join ''
    $purgers = @($Purgers | Where-Object { $_ } | Select-Object -Unique)
    $purge = ($purgers | ForEach-Object { "(A;OICI;$($right.Purge);;;$_)" }) -join ''
    # The owner of a file: CREATOR OWNER gives it its rights, OWNER RIGHTS takes away those an owner
    # has anyway (change the permissions).
    $owner = "(A;OIIO;$($right.Owner);;;CO)(A;OIIO;$($right.Owner);;;S-1-3-4)"
    $tier = {
        param([string[]]$Writers)
        $admins + $readAll + $purge + ((@($Writers) | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { "(A;;$($right.Create);;;$_)(A;OIIO;$($right.Read);;;$_)" }) -join '') + $owner
    }
    # Traverse: FILE_TRAVERSE | FILE_READ_ATTRIBUTES | SYNCHRONIZE, without listing.
    $listRoot = (@(@($Tier1) + @($Tier2)) | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { "(A;;$($right.Read);;;$_)" }) -join ''
    [pscustomobject]@{ Folder = ''; Sddl = "D:P$admins$readAll$purge$listRoot(A;;$($right.Traverse);;;AU)" }
    [pscustomobject]@{ Folder = 'Tier0'; Sddl = 'D:P' + (& $tier (@($Tier0) + $DomainAdminsSid)) }
    [pscustomobject]@{ Folder = 'Tier1'; Sddl = 'D:P' + (& $tier $Tier1) }
    [pscustomobject]@{ Folder = 'Tier2'; Sddl = 'D:P' + (& $tier $Tier2) }
    # Every user of the domain writes there, its own file only; not the computers (Authenticated Users).
    $domainUsers = $DomainAdminsSid -replace '-512$', '-513'
    # The retention writes its own changes there (a gMSA is no user of the domain).
    $purgersWrite = ($purgers | ForEach-Object { "(A;;$($right.Create);;;$_)" }) -join ''
    [pscustomobject]@{ Folder = 'Unassigned'; Sddl = "D:P$admins$readAll$purge(A;;$($right.Create);;;$domainUsers)$purgersWrite$owner" }
    # The archives of the old months (Invoke-PSGPOAuditRetention): written by the retention, read
    # by Tier 0 and the readers.
    [pscustomobject]@{ Folder = 'Archive'; Sddl = "D:P$admins$readAll" + (($purgers | ForEach-Object { "(A;OICI;$($right.Modify);;;$_)" }) -join '') }
}

# Linux: the folders made and their DACLs written with the SMB client of Samba (its Python
# bindings), Kerberos only. Arguments: server, share, then folder and SDDL pairs.
$script:PSGPOAuditSharePython = @'
import re, sys
from samba import param
from samba.credentials import Credentials, MUST_USE_KERBEROS, SMB_SIGNING_REQUIRED
from samba.dcerpc import security
from samba.samba3 import param as s3param
from samba.samba3 import libsmb_samba_internal as libsmb

server, share = sys.argv[1:3]
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
domain = security.dom_sid('S-1-5-32')
pairs = sys.argv[3:]
for index in range(0, len(pairs), 2):
    path, sddl = pairs[index], pairs[index + 1]
    if path and not conn.chkpath(path):
        conn.mkdir(path)
    descriptor = security.descriptor.from_sddl(sddl, domain)
    conn.set_acl(path, descriptor, security.SECINFO_DACL | security.SECINFO_PROTECTED_DACL)
    print(path)
# Samba does not pass the permissions of a folder to the files it holds already: the owner of each
# file written before 0.1.15 loses FILE_WRITE_DATA (0x12019f becomes 0x12019d), it only appends;
# the purgers of the folder (its ACEs 0x1300e9) get their right on each file, to read and archive it.
for index in range(0, len(pairs), 2):
    path, sddl = pairs[index], pairs[index + 1]
    if not path:
        continue
    purgers = re.findall(r'\(A;OICI;0x1300e9;;;([^)]+)\)', sddl, flags=re.IGNORECASE)
    for item in conn.list(path):
        if item['attrib'] & 0x10:
            continue
        name = path + '\\' + item['name']
        current = conn.get_acl(name, security.SECINFO_DACL).as_sddl(domain)
        changed = re.sub(r';0x0*12019f;', ';0x12019d;', current, flags=re.IGNORECASE)
        for sid in purgers:
            if (';;;' + sid + ')').lower() not in changed.lower():
                changed += '(A;ID;0x1300e9;;;' + sid + ')'
        if changed != current:
            conn.set_acl(name, security.descriptor.from_sddl(changed, domain), security.SECINFO_DACL)
            print('append-only: ' + name)
'@

# The folders of the share made when needed, and their permissions written.
function Set-PSGPOAuditShareAcl {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [object[]]$Folder
    )

    $share = Get-PSGPOAuditShare -Path $Path
    if (-not $IsWindows) {
        if (-not $share) { throw "The audit log is prepared on a share (\\server\share or //server/share), not on '$Path'." }
        if (-not $PSCmdlet.ShouldProcess($Path, "Create the folders $(@($Folder.Folder | Where-Object { $_ }) -join ', ') and write their permissions")) { return }
        $python = Get-Command -Name 'python3' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $python) { throw 'The permissions of the share need python3 and the Samba Python bindings (Debian/Ubuntu: apt install python3-samba).' }
        $arguments = foreach ($item in $Folder) { (@($share.Folder, $item.Folder) | Where-Object { $_ }) -join '\'; $item.Sddl }
        $result = Invoke-PSGPONativeCommand -FilePath $python.Source -TimeoutSeconds 300 -ArgumentList (@('-c', $script:PSGPOAuditSharePython, $share.Server, $share.Share) + @($arguments))
        if ($result.ExitCode -ne 0) {
            $lines = @("$($result.Error)" -split '\r?\n' | Where-Object { $_ })
            throw "The share $Path is not prepared: $(if ($lines) { $lines[-1] } else { "exit code $($result.ExitCode)" })"
        }
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Path, "Create the folders $(@($Folder.Folder | Where-Object { $_ }) -join ', ') and write their permissions")) { return }
    foreach ($item in $Folder) {
        $full = if ($item.Folder) { Join-Path $Path $item.Folder } else { $Path }
        # The root of a share exists: New-Item would try to make \\server itself.
        $directory = if (Test-Path -LiteralPath $full -PathType Container) { Get-Item -LiteralPath $full -Force } else { New-Item -ItemType Directory -Path $full -Force -ErrorAction Stop }
        $security = [System.Security.AccessControl.DirectorySecurity]::new()
        $security.SetSecurityDescriptorSddlForm($item.Sddl, [System.Security.AccessControl.AccessControlSections]::Access)
        [System.IO.FileSystemAclExtensions]::SetAccessControl([System.IO.DirectoryInfo]$directory, $security)
    }
}
