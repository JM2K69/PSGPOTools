<#
    The copy of a GPO in its domain, as Copy and Paste of GPMC (Copy-PSGPO, Copy... in the
    console): a new GPO with the files of the folder of the source (its settings and its comment),
    its status, its client-side extensions and its WMI filter; not its links. Its permissions are
    those of a new GPO, or those of the source (-CopyAcl: Preserve the existing permissions of
    GPMC).
#>

# What the source gives the new GPO $Target, created already. -CopyAcl: the permissions of the
# source, not inherited, in place of those of a new GPO, its security filtering with them; the
# rows of the source a level cannot give (denied, custom) are returned, not copied.
function Copy-PSGPOContent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Source,
        [Parameter(Mandatory)] [GPOToolsGpo]$Target,
        [switch]$CopyAcl
    )

    $files = $Directory.ReadGpoFolder($Source)
    foreach ($name in @($files.Keys)) { if ($name -ieq 'GPT.INI') { $files.Remove($name) } }
    if ($files.Count) {
        $Directory.RestoreGpo($Target, $files, ($Source.Flags -band 3), $Source.MachineExtensionNames, $Source.UserExtensionNames)
    } elseif (($Target.Flags -band 3) -ne ($Source.Flags -band 3)) {
        $Directory.SetGpoStatus($Target, ($Source.Flags -band 3))
    }
    $filter = $Directory.GetWmiFilter($Source)
    if ($filter) { $Directory.SetWmiFilter($Target, $filter) }
    if (-not $CopyAcl) { return }

    $levels = 'GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity'
    $before = @{}
    foreach ($row in @($Directory.GetGpoPermissions($Target) | Where-Object { -not $_.Inherited })) { $before[$row.Sid] = $row }
    $copied = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($Directory.GetGpoPermissions($Source) | Where-Object { -not $_.Inherited })) {
        if ($row.Denied -or $row.Permission -notin $levels) { $row; continue }
        [void]$copied.Add($row.Sid)
        $had = $before[$row.Sid]
        if ($had -and -not $had.Denied -and $had.Permission -eq $row.Permission -and $had.Applies -eq $row.Applies) { continue }
        $Directory.SetGpoPermission($Target, $row.Sid, $row.Permission)
        # An editor keeps the security filtering it had: it takes that of the source.
        if ($row.Permission -in 'GpoEdit', 'GpoEditDeleteModifySecurity' -and [bool]($had -and $had.Applies) -ne $row.Applies) {
            $Directory.SetGpoSecurityFiltering($Target, $row.Sid, $row.Applies)
        }
    }
    # What a new GPO gives that the source does not: taken back.
    foreach ($row in $before.Values) {
        if (-not $row.Denied -and $row.Permission -in $levels -and -not $copied.Contains($row.Sid)) { $Directory.SetGpoPermission($Target, $row.Sid, 'None') }
    }
}

# A row of permissions not copied, as Copy-PSGPO and the console say it: the account, its level.
function Get-PSGPOCopySkippedText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [object]$Row)

    $level = Get-PSGPOText (Get-PSGPOPermissionText -Permission $Row.Permission)
    if ($Row.Denied) { $level = Get-PSGPOText '{0}, denied' $level }
    "$($Row.Name) ($level)"
}
