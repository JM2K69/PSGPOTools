<#
    The search of GPOs, as the Search of GPMC (Find-PSGPO, Search... in the console): the GPOs of a
    directory that match every criterion given. What the domain read has (name, links, WMI filter,
    status, approval, client-side extensions) first; then what is read for each GPO left: its
    permissions in the directory, its settings and its comment in SYSVOL.
#>

# A text found in another, case-insensitive; a pattern with * and ? matches the whole text.
function Test-PSGPOSearchText {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()] [AllowEmptyString()] [string]$Text,
        [Parameter(Mandatory)] [string]$Search
    )

    if ($Search.IndexOfAny([char[]]'*?') -ge 0) { return Test-PSGPONameMatch -Name $Text -Pattern $Search }
    "$Text".IndexOf($Search, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

# The GPOs of $Directory that match $Criteria, by name: Name, Id, LinkedTo (a GPOToolsSom), Linked,
# NotLinked, WmiFilter (a GPOToolsWmiFilter), Account and Permission, Extension, Setting, Status,
# ApprovalState, Comment; a criterion empty or $false is not one.
function Find-PSGPOMatch {
    [CmdletBinding()]
    [OutputType([GPOToolsGpo])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [hashtable]$Criteria
    )

    $flags = if ($Criteria.Status) { @{ Enabled = 0; ComputerOnly = 1; UserOnly = 2; Disabled = 3 }[$Criteria.Status] }
    $linkedThere = $null
    if ($Criteria.LinkedTo) {
        $linkedThere = [System.Collections.Generic.HashSet[object]]::new()
        foreach ($link in $Criteria.LinkedTo.Links) { if ($link.Gpo) { [void]$linkedThere.Add($link.Gpo) } }
    }
    $extension = if ($Criteria.Extension) { "$($Criteria.Extension)".Trim().Trim('{', '}') }

    # What the domain read has.
    $left = foreach ($gpo in $Directory.Gpos) {
        if ($Criteria.Name -and -not (Test-PSGPOSearchText -Text $gpo.DisplayName -Search $Criteria.Name)) { continue }
        if ($Criteria.Id -and $gpo.Id -ne $Criteria.Id) { continue }
        if ($linkedThere -and -not $linkedThere.Contains($gpo)) { continue }
        if ($Criteria.Linked -or $Criteria.NotLinked) {
            # A GPO linked to a site only applies there: linked.
            $isLinked = @($Directory.GetLinksOf($gpo)).Count -gt 0 -or @($Directory.GetSiteLinksOf($gpo)).Count -gt 0
            if ($Criteria.Linked -and -not $isLinked) { continue }
            if ($Criteria.NotLinked -and $isLinked) { continue }
        }
        if ($Criteria.WmiFilter -and $gpo.WmiFilterId -ne $Criteria.WmiFilter.Id) { continue }
        if ($null -ne $flags -and ($gpo.Flags -band 3) -ne $flags) { continue }
        if ($Criteria.ApprovalState -and $gpo.ApprovalState -ne $Criteria.ApprovalState) { continue }
        if ($extension) {
            $declared = @(Get-PSGPODeclaredExtension -MachineExtensionNames $gpo.MachineExtensionNames -UserExtensionNames $gpo.UserExtensionNames)
            if (-not @($declared | Where-Object { [string]::Equals($_.Guid.Trim('{', '}'), $extension, [System.StringComparison]::OrdinalIgnoreCase) -or (Test-PSGPOSearchText -Text $_.Name -Search $extension) }).Count) { continue }
        }
        $gpo
    }

    # What is read for each GPO left.
    $left = @($left)
    $index = 0
    foreach ($gpo in $left) {
        $index++
        if ($Criteria.Account -or $Criteria.Setting -or $Criteria.Comment) {
            Write-Progress -Activity 'Searching the GPOs' -Status $gpo.DisplayName -PercentComplete (100 * $index / [Math]::Max(1, $left.Count))
        }
        if ($Criteria.Account) {
            $account = "$($Criteria.Account)".Trim()
            $isSid = $account -match '^S-1-'
            $rows = @(Get-PSGPOPermissionRow -Directory $Directory -Gpo $gpo | Where-Object {
                    -not $_.Denied -and
                    ($(if ($isSid) { [string]::Equals($_.Sid, $account, [System.StringComparison]::OrdinalIgnoreCase) }
                        else { (Test-PSGPONameMatch -Name $_.Trustee -Pattern $account) -or (Test-PSGPONameMatch -Name ("$($_.Trustee)" -replace '^.*\\', '') -Pattern $account) })) -and
                    (-not $Criteria.Permission -or $_.Permission -eq $Criteria.Permission)
                })
            if (-not $rows.Count) { continue }
        }
        if ($Criteria.Setting) {
            $settings = Get-PSGPOFolderSetting -Files $Directory.ReadGpoFolder($gpo) -MachineExtensionNames $gpo.MachineExtensionNames -UserExtensionNames $gpo.UserExtensionNames
            $found = $false
            foreach ($row in @($settings.Machine) + @($settings.User) + @($settings.Uninterpreted)) {
                if (-not $row) { continue }
                foreach ($text in $row.Path, $row.Name, $row.State, $row.Options) {
                    if (Test-PSGPOSearchText -Text $text -Search $Criteria.Setting) { $found = $true; break }
                }
                if ($found) { break }
            }
            if (-not $found) { continue }
        }
        if ($Criteria.Comment -and -not (Test-PSGPOSearchText -Text $Directory.ReadGpoComment($gpo) -Search $Criteria.Comment)) { continue }
        $gpo
    }
    Write-Progress -Activity 'Searching the GPOs' -Completed
}
