function Backup-PSGPO {
    <#
    .SYNOPSIS
        Backs up GPOs of the domain in a folder, when they changed since their last backup.
    .DESCRIPTION
        Each GPO is backed up in <Path>/<GPO name> {<GUID>}/<last change, UTC>/: the files of its
        SYSVOL folder as they are, and manifest.json with its versions, status, security filtering,
        links and the SHA-256 of each file. A GPO that did not change since its last backup is not
        backed up again (Result: Unchanged), unless -Force; run it on a schedule to keep the history
        of the GPOs, then compare two backups with Compare-PSGPOBackup or in the History tab of
        Show-GPOManagerAvalonia.

        A backup can have a comment (why the GPO changed) and labels; the approved label of the
        configuration (Backup.ApprovedLabel, 'Approved' by default, or -Approve) makes it the
        approved version of the GPO, to which Get-PSGPODrift compares it. When the GPO did not
        change, its last backup gets the labels, not the comment: Set-PSGPOBackup changes it.

        Works from Windows (UNC path) and Linux (smbclient with Kerberos), against Windows and Samba
        domain controllers. These backups are not GPMC backups: Restore-GPO / Import-GPO do not read them.
    .PARAMETER Path
        Root folder of the backups; created when missing.
    .PARAMETER Name
        Display names of the GPOs to back up (wildcards allowed); all the GPOs by default.
    .PARAMETER Directory
        Directory to back up the GPOs of (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .PARAMETER Comment
        Comment of the backup: why the GPO changed, the ticket of the change.
    .PARAMETER Label
        Labels of the backup.
    .PARAMETER Approve
        Adds the approved label of the configuration: the backup is the approved version of the GPO.
    .PARAMETER Force
        Backs up a GPO even when it did not change.
    .EXAMPLE
        Backup-PSGPO -Path /srv/gpo-backups
    .EXAMPLE
        Backup-PSGPO -Path /srv/gpo-backups -Name 'C - Servers - Security Baseline' -Comment 'CHG-1024: SMB signing' -Approve
    .EXAMPLE
        Backup-PSGPO -Path D:\GPO_Backup -Name 'C - *' -Server dc1.contoso.com
    .LINK
        Get-PSGPOBackup
    .LINK
        Compare-PSGPOBackup
    .LINK
        Get-PSGPODrift
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.Backup')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(ValueFromPipeline)]
        [string[]]$Name,

        [GPOToolsDirectory]$Directory,

        [string]$Server,

        [string]$Comment,

        [string[]]$Label,

        [switch]$Approve,

        [switch]$Force
    )

    begin {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        $null = New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop
        $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
        $names = [System.Collections.Generic.List[string]]::new()
        $labels = @($Label)
        if ($Approve) { $labels += Get-PSGPOApprovedLabel }
        $labels = ConvertTo-PSGPOBackupLabel -Label $labels
    }
    process {
        foreach ($item in $Name) { $names.Add($item) }
    }
    end {
        $gpos = if ($names.Count) {
            foreach ($pattern in $names) {
                $found = @($Directory.Gpos | Where-Object { $_.DisplayName -like $pattern })
                if (-not $found) { Write-Error "No GPO named '$pattern' in $($Directory.DomainName)." }
                $found
            }
        } else {
            $Directory.Gpos
        }
        foreach ($gpo in @($gpos | Select-Object -Unique)) {
            try {
                Save-PSGPOBackup -Directory $Directory -Gpo $gpo -Path $Path -Comment $Comment -Label $labels -Force:$Force
            } catch {
                Write-Error "The GPO '$($gpo.DisplayName)' is not backed up: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
