function Get-PSGPODrift {
    <#
    .SYNOPSIS
        Finds the GPOs changed since their approved version.
    .DESCRIPTION
        The approved version of a GPO is its newest backup with the approved label of the
        configuration (Backup.ApprovedLabel, 'Approved' by default: Backup-PSGPO -Approve,
        Set-PSGPOBackup -Approve, or the History tab). Each GPO, as it is now, is compared to it
        setting by setting, as Compare-PSGPOBackup does: what changed since, in the console or
        elsewhere (GPMC, samba-tool, a script), is its drift.

        State of each GPO: InSync (it is its approved version), Drifted (Changes: what changed
        since, Added, Removed or Changed with the value before and after), or NotApproved (no
        approved version yet).
    .PARAMETER Path
        Root folder of the backups (Backup-PSGPO).
    .PARAMETER Name
        Display names of the GPOs (wildcards allowed); all the GPOs by default.
    .PARAMETER Directory
        Directory of the GPOs (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .PARAMETER Label
        Label of the approved versions, instead of the one of the configuration.
    .EXAMPLE
        Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
    .EXAMPLE
        (Get-PSGPODrift -Path D:\GPO_Backup -Name 'Default Domain Policy').Changes | Format-Table Change, Path, Name, Before, After
    .LINK
        Backup-PSGPO
    .LINK
        Set-PSGPOBackup
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.Drift')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(ValueFromPipeline)]
        [string[]]$Name,

        [GPOToolsDirectory]$Directory,

        [string]$Server,

        [string]$Label
    )

    begin {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "No folder of backups: $Path" }
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
        if (-not $Label) { $Label = Get-PSGPOApprovedLabel }
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
                Get-PSGPODriftState -Directory $Directory -Gpo $gpo -Path $Path -Label $Label
            } catch {
                Write-Error "The GPO '$($gpo.DisplayName)' is not compared to its approved version: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
