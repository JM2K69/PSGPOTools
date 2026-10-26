<#
    The central backups of the GPOs (Backup.Path of the configuration of the domain): a share of a
    file server, for Tier 0 only (the approvers of the workflow, the administrators of the domain).
    The other accounts neither read nor write it: no History tab nor Deleted GPOs for them, and the
    changes they make are not backed up first (the approval backs up the approved version).

    Windows reaches \\server\share as a path. Linux reads and writes the share where it is mounted
    (mount.cifs, Kerberos: sec=krb5,multiuser, each account with its own ticket), found in
    /proc/mounts: the backups are folders of files, read and written in many places. Only root
    mounts a share: an administrator adds it once to /etc/fstab with x-systemd.automount
    (New-PSGPOShareMount.sh --fstab), and it is mounted when a console of Tier 0 first reaches it,
    found in /etc/fstab while it is not mounted yet.
#>

# The folder of the computer where a share is: the path itself on Windows or when it is not a
# share; on Linux the folder where //server/share is mounted, with the rest of the path.
function Resolve-PSGPOSharePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        # The lines of /proc/mounts, then of /etc/fstab (the tests give theirs).
        [string[]]$Mounts
    )

    $share = Get-PSGPOAuditShare -Path $Path
    if ($IsWindows -or -not $share) { return $Path }
    # What is mounted, then what mounts itself when it is reached (x-systemd.automount).
    if (-not $PSBoundParameters.ContainsKey('Mounts')) { $Mounts = @(Get-Content -LiteralPath '/proc/mounts', '/etc/fstab' -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^\s*#' }) }
    # A server by its full name or its short one: the first label is compared.
    $shortName = { param($Name) ("$Name" -split '\.')[0] }
    foreach ($line in $Mounts) {
        $fields = $line -split '\s+'
        if ($fields.Count -lt 3 -or $fields[2] -notin 'cifs', 'smb3') { continue }
        $source = [regex]::Match($fields[0], '^//([^/]+)/([^/]+)(?:/(.*))?$')
        if (-not $source.Success) { continue }
        if ((& $shortName $source.Groups[1].Value) -ne (& $shortName $share.Server) -or $source.Groups[2].Value -ne $share.Share) { continue }
        # \040 is a space in /proc/mounts.
        $mountPoint = $fields[1] -replace '\\040', ' '
        $mounted = ($source.Groups[3].Value -replace '/', '\').Trim('\')
        $wanted = $share.Folder
        if ($mounted -and -not ($wanted -eq $mounted -or $wanted.StartsWith("$mounted\", [System.StringComparison]::OrdinalIgnoreCase))) { continue }
        $rest = if ($mounted) { $wanted.Substring($mounted.Length).Trim('\') } else { $wanted }
        if (-not $rest) { return $mountPoint }
        return [System.IO.Path]::Combine([string[]](@($mountPoint) + @($rest -split '\\')))
    }
    throw "The share //$($share.Server)/$($share.Share) is not mounted on this computer: an administrator mounts it once (sudo ./New-PSGPOShareMount.sh //$($share.Server)/$($share.Share) --fstab), then it mounts itself; see the documentation of the central backups."
}

# Whether the account may use the backups: always, but with central backups (Backup.Path) for
# Tier 0 only. A directory whose tier was not read (a sample, a file) may.
function Test-PSGPOBackupAllowed {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] [GPOToolsDirectory]$Directory)

    if (-not "$((Get-PSGPOConfigurationData).Backup.Path)".Trim()) { return $true }
    if (-not $Directory -or -not $Directory.AuditTier) { return $true }
    $Directory.AuditTier -eq 'Tier0'
}

# The SDDL of the share of the backups: the administrators in full control, Tier 0 (the groups
# of the approvers) changes it, nobody else reaches it.
function Get-PSGPOBackupShareSddl {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$DomainAdminsSid,
        [AllowEmptyCollection()] [string[]]$Tier0 = @()
    )

    $right = $script:PSGPOAuditShareRight
    # Modify: read, write, create, delete (FILE_GENERIC_READ | FILE_GENERIC_WRITE | EXECUTE | DELETE).
    $modify = '0x1301bf'
    ('D:P(A;OICI;{0};;;SY)(A;OICI;{0};;;BA)(A;OICI;{0};;;{1})' -f $right.Full, $DomainAdminsSid) +
    ((@($Tier0) | Where-Object { $_ -and $_ -ne $DomainAdminsSid } | Select-Object -Unique | ForEach-Object { "(A;OICI;$modify;;;$_)" }) -join '')
}
