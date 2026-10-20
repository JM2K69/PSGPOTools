# A GPO name matches a name given to a command: the same name (case-insensitive), or the wildcard
# pattern when it has * or ?. Brackets are part of the name ('Servers [Lyon]'), not a range of
# characters: as a -like pattern, such a name would match nothing, or throw.
function Test-PSGPONameMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()] [AllowEmptyString()] [string]$Name,
        [Parameter(Mandatory)] [string]$Pattern
    )

    if ($Pattern.IndexOfAny([char[]]'*?') -lt 0) { return [string]::Equals($Name, $Pattern, [System.StringComparison]::OrdinalIgnoreCase) }
    $escaped = $Pattern.Replace('`', '``').Replace('[', '`[').Replace(']', '`]')
    [System.Management.Automation.WildcardPattern]::new($escaped, [System.Management.Automation.WildcardOptions]::IgnoreCase).IsMatch("$Name")
}

# The GPOs of a directory named $Name (Test-PSGPONameMatch), each once.
function Find-PSGPOByName {
    [CmdletBinding()]
    [OutputType([GPOToolsGpo])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [string[]]$Name
    )

    # By Id, not Select-Object -Unique: two GPOs may have the same name (ToString).
    $seen = [System.Collections.Generic.HashSet[guid]]::new()
    foreach ($pattern in $Name) {
        $found = @($Directory.Gpos | Where-Object { Test-PSGPONameMatch -Name $_.DisplayName -Pattern $pattern })
        if (-not $found) { Write-Error "No GPO named '$pattern' in $($Directory.DomainName)." }
        foreach ($gpo in $found) { if ($seen.Add($gpo.Id)) { $gpo } }
    }
}
