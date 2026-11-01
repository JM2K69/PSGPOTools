function Set-PSGPO {
    <#
    .SYNOPSIS
        Renames GPOs, sets their status, their WMI filter and their comment, as GPMC does.
    .DESCRIPTION
        The new name (the Rename item of GPMC) is the display name of the GPO only: its GUID, its
        folder in SYSVOL, its links and its backups do not change. The status (the GPO Status
        menu of GPMC) says which part of the GPO the computers apply: all its settings, those of
        the computers only (User configuration settings disabled), those of the users only, or
        none. The WMI filter (the WMI Filtering of the Scope tab of GPMC) makes the computers
        apply the GPO only when each of its queries returns something. The comment (the Comment of
        the Details tab of GPMC) is in the file GPO.cmt of the folder of the GPO: it is not a
        setting the computers apply, and the version of the GPO does not change.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern).
    .PARAMETER NewName
        New display name of the GPO: -Name gives one GPO only.
    .PARAMETER Status
        Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer
        configuration settings disabled) or Disabled (all settings disabled).
    .PARAMETER WmiFilter
        Name (or Id) of the WMI filter of the domain the GPOs are linked to (Get-PSGPOWmiFilter).
    .PARAMETER NoWmiFilter
        The GPOs are linked to no WMI filter anymore.
    .PARAMETER Comment
        Comment of the GPOs (several lines allowed); an empty text removes it.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Set-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
    .EXAMPLE
        Set-PSGPO -Name 'C - Workstations - *' -WmiFilter 'Workstations'
    .EXAMPLE
        Set-PSGPO -Name 'C - Kiosks - Baseline' -NewName 'C - Kiosks - Hardening'
    .EXAMPLE
        Set-PSGPO -Name 'C - Kiosks - Baseline' -Comment 'CHG-2041: kiosks of the halls, owner: workplace team'
    .OUTPUTS
        GPOToolsGpo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/set-psgpo/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([GPOToolsGpo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string[]]$Name,
        [string]$NewName,
        [ValidateSet('Enabled', 'ComputerOnly', 'UserOnly', 'Disabled')] [string]$Status,
        [string]$WmiFilter,
        [switch]$NoWmiFilter,
        [AllowEmptyString()] [string]$Comment,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    begin {
        if ($PSBoundParameters.ContainsKey('NewName') -and -not "$NewName".Trim()) { throw 'The GPO name is required: -NewName is empty.' }
        $setComment = $PSBoundParameters.ContainsKey('Comment')
        if (-not $NewName -and -not $Status -and -not $WmiFilter -and -not $NoWmiFilter -and -not $setComment) { throw 'Give -NewName, -Status, -WmiFilter, -NoWmiFilter or -Comment: what changes.' }
        if ($WmiFilter -and $NoWmiFilter) { throw 'Give -WmiFilter or -NoWmiFilter, not both.' }
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
        $flags = if ($Status) { @{ Enabled = 0; ComputerOnly = 1; UserOnly = 2; Disabled = 3 }[$Status] }
        $filter = $null
        if ($WmiFilter) {
            $filter = $Directory.FindWmiFilter($WmiFilter)
            if (-not $filter) { throw "No WMI filter named '$WmiFilter' in $($Directory.DomainName): $(@($Directory.WmiFilters.Name) -join ', ')." }
        }
        # Two GPOs cannot get the same name: -NewName renames one GPO, in all the input.
        $renamed = @{ Gpo = $null }
    }
    process {
        $gpos = @(Find-PSGPOByName -Directory $Directory -Name $Name)
        if ($NewName -and ($gpos.Count -gt 1 -or ($gpos.Count -and $renamed.Gpo -and $renamed.Gpo -ne $gpos[0]))) {
            Write-Error "-NewName renames one GPO: '$($Name -join "', '")' gives more ($(@(@($renamed.Gpo) + $gpos | Where-Object { $_ } | ForEach-Object DisplayName | Select-Object -Unique) -join ', '))."
            return
        }
        foreach ($gpo in $gpos) {
            $what = @(
                if ($NewName) { "rename it '$("$NewName".Trim())'" }
                if ($Status) { "set its status to $Status" }
                if ($filter) { "link it to the WMI filter '$($filter.Name)'" }
                if ($NoWmiFilter) { 'unlink it from its WMI filter' }
                if ($setComment) { if ($Comment) { 'set its comment' } else { 'remove its comment' } }
            ) -join ', '
            if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", $what)) { continue }
            $oldName = $gpo.DisplayName
            try {
                if ($NewName) { $Directory.RenameGpo($gpo, $NewName); $renamed.Gpo = $gpo }
                if ($Status) { $Directory.SetGpoStatus($gpo, $flags) }
                if ($filter -or $NoWmiFilter) { $Directory.SetWmiFilter($gpo, $filter) }
                if ($setComment) { $Directory.WriteGpoComment($gpo, $Comment) }
                $gpo
            } catch {
                Write-Error "The GPO '$oldName' is not changed: $($_.Exception.GetBaseException().Message)"
            }
        }
    }
}
