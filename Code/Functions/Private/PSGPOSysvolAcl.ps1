<#
    Security descriptors of the files and folders of SYSVOL, owner included: read, written, and
    the tree of a folder listed. Used by the approval workflow, which gives the GPO folder and
    every file in it to the owner of the approved GPOs, and by the delegation of the creation of
    GPOs (the ACL of the Policies folder).

    - Windows: .NET access control on the UNC path, the binary form of the descriptor.
    - Linux: the SMB client of Samba (its Python bindings, there with samba-tool), Kerberos only.
#>

# Commands of the Python helper: getacl <path> (the descriptor in hexadecimal), getacls - <path>...
# (one line each), setacl <path> <hex> <secinfo>, tree <path> (every file and folder below it:
# D|F<TAB>relative path).
$script:PSGPOSysvolAclPython = @'
import sys
from samba import param
from samba.credentials import Credentials, MUST_USE_KERBEROS, SMB_SIGNING_REQUIRED
from samba.dcerpc import security
from samba.ndr import ndr_pack, ndr_unpack
from samba.samba3 import param as s3param
from samba.samba3 import libsmb_samba_internal as libsmb

server, share, command, path = sys.argv[1:5]
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
everything = security.SECINFO_OWNER | security.SECINFO_GROUP | security.SECINFO_DACL
if command == 'getacl':
    print(ndr_pack(conn.get_acl(path, everything)).hex())
elif command == 'getacls':
    # One line per path given after it: the descriptor in hexadecimal, or ERROR and why.
    for item in sys.argv[5:]:
        try:
            print(ndr_pack(conn.get_acl(item, everything)).hex())
        except Exception as error:
            print('ERROR ' + ' '.join(str(error).split()))
elif command == 'setacl':
    descriptor = ndr_unpack(security.descriptor, bytes.fromhex(sys.argv[5]))
    conn.set_acl(path, descriptor, int(sys.argv[6]))
elif command == 'tree':
    def walk(folder, relative):
        for entry in conn.list(folder):
            name = entry['name']
            if name in ('.', '..'):
                continue
            inner = relative + '\\' + name if relative else name
            if entry['attrib'] & 0x10:
                print('D\t' + inner)
                walk(folder + '\\' + name, inner)
            else:
                print('F\t' + inner)
    walk(path, '')
'@

# SECINFO flags of the descriptor written ([MS-DTYP] 2.4.7).
# As unsigned numbers: 0x80000000 would be a negative Int32.
$script:PSGPOSecurityInformation = @{ Owner = [uint32]1; Group = [uint32]2; Dacl = [uint32]4; ProtectedDacl = [uint32]2147483648; UnprotectedDacl = [uint32]536870912 }

function Invoke-PSGPOSysvolAclPython {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Share,
        [Parameter(Mandatory)] [ValidateSet('getacl', 'getacls', 'setacl', 'tree')] [string]$Command,
        [Parameter(Mandatory)] [string]$Path,
        [string[]]$Argument = @()
    )

    Assert-PSGPOKerberosOnly -Directory $Directory
    $python = Get-Command -Name 'python3' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) { throw 'The SYSVOL permissions need python3 and the Samba Python bindings (Debian/Ubuntu: apt install python3-samba).' }
    $result = Invoke-PSGPONativeCommand -FilePath $python.Source -TimeoutSeconds 600 -ArgumentList (@('-c', $script:PSGPOSysvolAclPython, $Directory.Server, $Share, $Command, ($Path -replace '/', '\')) + $Argument)
    if ($result.ExitCode -ne 0) {
        $lines = @("$($result.Error)" -split '\r?\n' | Where-Object { $_ })
        $message = if ($lines -match 'ModuleNotFoundError') { 'the Samba Python bindings are missing (Debian/Ubuntu: apt install python3-samba)' } elseif ($lines) { $lines[-1] } else { "exit code $($result.ExitCode)" }
        throw "SYSVOL $Path`: $message"
    }
    @($result.Output)
}

# The security descriptor (owner, group, DACL) of a file or folder of a SYSVOL share.
function Get-PSGPOSysvolItemAcl {
    [CmdletBinding()]
    [OutputType([GPOToolsSecurityDescriptor])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Share,
        [Parameter(Mandatory)] [string]$Path
    )

    if ($IsWindows) {
        Use-PSGPOSysvolCredential -Directory $Directory -Share $Share
        $item = Get-Item -LiteralPath "\\$($Directory.Server)\$Share\$Path" -Force -ErrorAction Stop
        $sections = [System.Security.AccessControl.AccessControlSections]'Owner, Group, Access'
        $security = if ($item -is [System.IO.DirectoryInfo]) { [System.IO.FileSystemAclExtensions]::GetAccessControl($item, $sections) } else { [System.IO.FileSystemAclExtensions]::GetAccessControl([System.IO.FileInfo]$item, $sections) }
        return [GPOToolsSecurityDescriptor]::Parse($security.GetSecurityDescriptorBinaryForm())
    }
    $hex = (Invoke-PSGPOSysvolAclPython -Directory $Directory -Share $Share -Command getacl -Path $Path | Select-Object -Last 1).Trim()
    [GPOToolsSecurityDescriptor]::Parse([Convert]::FromHexString($hex))
}

# The security descriptors of files or folders of a SYSVOL share, by path: a descriptor, or why
# it cannot be read (a string). On Linux, all in one connection.
function Get-PSGPOSysvolItemAclSet {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Share,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Path
    )

    $acls = @{}
    if (-not $Path.Count) { return $acls }
    if ($IsWindows) {
        foreach ($item in $Path) {
            try { $acls[$item] = Get-PSGPOSysvolItemAcl -Directory $Directory -Share $Share -Path $item } catch { $acls[$item] = $_.Exception.GetBaseException().Message }
        }
        return $acls
    }
    $lines = @(Invoke-PSGPOSysvolAclPython -Directory $Directory -Share $Share -Command getacls -Path '-' -Argument @($Path | ForEach-Object { $_ -replace '/', '\' }))
    for ($i = 0; $i -lt $Path.Count; $i++) {
        $line = "$($lines[$i])".Trim()
        $acls[$Path[$i]] = if (-not $line) { 'not read' } elseif ($line.StartsWith('ERROR ')) { $line.Substring(6) } else { [GPOToolsSecurityDescriptor]::Parse([Convert]::FromHexString($line)) }
    }
    $acls
}

# Writes the owner and/or the DACL of a file or folder of a SYSVOL share. On Windows the
# inheritable ACEs of a folder are propagated to what it holds; on Linux they are not.
function Set-PSGPOSysvolItemAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Share,
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor,
        [switch]$Owner,
        [switch]$Dacl
    )

    if (-not $Owner -and -not $Dacl) { throw 'Set-PSGPOSysvolItemAcl writes the owner, the DACL, or both.' }
    if ($IsWindows) {
        Use-PSGPOSysvolCredential -Directory $Directory -Share $Share
        $item = Get-Item -LiteralPath "\\$($Directory.Server)\$Share\$Path" -Force -ErrorAction Stop
        $windows = [GPOToolsSecurityDescriptor]::Parse($Descriptor.ToBytes())
        # The ACEs of extended rights (Apply Group Policy) mean nothing to a file: left out, as GPMC does.
        if ($windows.Dacl) { $windows.Dacl.RemoveAll([Predicate[GPOToolsAce]] { param($Ace) $Ace.IsObjectAce() }) | Out-Null }
        $security = if ($item -is [System.IO.DirectoryInfo]) { [System.Security.AccessControl.DirectorySecurity]::new() } else { [System.Security.AccessControl.FileSecurity]::new() }
        $sections = [System.Security.AccessControl.AccessControlSections]::None
        if ($Owner) { $sections = $sections -bor [System.Security.AccessControl.AccessControlSections]::Owner }
        if ($Dacl) { $sections = $sections -bor [System.Security.AccessControl.AccessControlSections]::Access }
        $security.SetSecurityDescriptorBinaryForm($windows.ToBytes(), $sections)
        try {
            if ($item -is [System.IO.DirectoryInfo]) { [System.IO.FileSystemAclExtensions]::SetAccessControl($item, [System.Security.AccessControl.DirectorySecurity]$security) }
            else { [System.IO.FileSystemAclExtensions]::SetAccessControl([System.IO.FileInfo]$item, [System.Security.AccessControl.FileSecurity]$security) }
        } catch {
            throw "SYSVOL $Path`: $($_.Exception.Message)"
        }
        return
    }
    $flags = [uint32]0
    if ($Owner) { $flags = $flags -bor $script:PSGPOSecurityInformation.Owner }
    if ($Dacl) {
        $flags = $flags -bor $script:PSGPOSecurityInformation.Dacl
        $flags = $flags -bor $(if ($Descriptor.Control -band [GPOToolsSecurityDescriptor]::DaclProtected) { $script:PSGPOSecurityInformation.ProtectedDacl } else { $script:PSGPOSecurityInformation.UnprotectedDacl })
    }
    $null = Invoke-PSGPOSysvolAclPython -Directory $Directory -Share $Share -Command setacl -Path $Path -Argument ([Convert]::ToHexString($Descriptor.ToBytes())), ([uint32]$flags).ToString()
}

# Every file and folder below a folder of a SYSVOL share, parents before what they hold:
# Path (relative, with \) and IsFolder.
function Get-PSGPOSysvolTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Share,
        [Parameter(Mandatory)] [string]$Path
    )

    if ($IsWindows) {
        Use-PSGPOSysvolCredential -Directory $Directory -Share $Share
        $root = "\\$($Directory.Server)\$Share\$Path"
        $prefix = $root.TrimEnd('\').Length + 1
        foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop | Sort-Object FullName)) {
            [pscustomobject]@{ Path = $item.FullName.Substring($prefix); IsFolder = $item -is [System.IO.DirectoryInfo] }
        }
        return
    }
    foreach ($line in @(Invoke-PSGPOSysvolAclPython -Directory $Directory -Share $Share -Command tree -Path $Path)) {
        if ($line -match '^([DF])\t(.+)$') { [pscustomobject]@{ Path = $Matches[2]; IsFolder = $Matches[1] -eq 'D' } }
    }
}
