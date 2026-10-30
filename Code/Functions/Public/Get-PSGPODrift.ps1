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

        With -IncludePermissions, its owner and its permissions are compared too, as the
        Delegation tab lists them (Path Permissions: each account by its SID, its level, denied or
        inherited): an account added, removed or given another level since the approval, another
        owner. A backup keeps them since HGPM 0.1.26: when the approved version is older,
        Permissions says NotRecorded, and the permissions are not compared (approve the GPO again
        to record them).
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
    .PARAMETER IncludePermissions
        Compares the owner and the permissions of each GPO to those of its approved version too.
    .EXAMPLE
        Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
    .EXAMPLE
        # Who was given rights on a GPO since its approval
        (Get-PSGPODrift -Path /srv/gpo-backups -IncludePermissions).Changes | Where-Object Path -EQ 'Permissions' | Format-Table Change, Name, Before, After
    .EXAMPLE
        (Get-PSGPODrift -Path D:\GPO_Backup -Name 'Default Domain Policy').Changes | Format-Table Change, Path, Name, Before, After
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpodrift/
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

        [string]$Label,

        [switch]$IncludePermissions
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
            Find-PSGPOByName -Directory $Directory -Name $names
        } else {
            $Directory.Gpos
        }
        foreach ($gpo in @($gpos)) {
            try {
                $state = Get-PSGPODriftState -Directory $Directory -Gpo $gpo -Path $Path -Label $Label -Permission:$IncludePermissions
                if ($state.Permissions -eq 'NotRecorded') { Write-Warning "GPO '$($gpo.DisplayName)': its approved version was backed up before the permissions were kept, they are not compared. Approve it again to record them." }
                $state
            } catch {
                Write-Error "The GPO '$($gpo.DisplayName)' is not compared to its approved version: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
