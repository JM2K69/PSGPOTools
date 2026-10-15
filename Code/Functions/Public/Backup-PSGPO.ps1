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
    .PARAMETER Force
        Backs up a GPO even when it did not change.
    .EXAMPLE
        Backup-PSGPO -Path /srv/gpo-backups
    .EXAMPLE
        Backup-PSGPO -Path D:\GPO_Backup -Name 'C - *' -Server dc1.contoso.com
    .LINK
        Get-PSGPOBackup
    .LINK
        Compare-PSGPOBackup
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
                Save-PSGPOBackup -Directory $Directory -Gpo $gpo -Path $Path -Force:$Force
            } catch {
                Write-Error "The GPO '$($gpo.DisplayName)' is not backed up: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
