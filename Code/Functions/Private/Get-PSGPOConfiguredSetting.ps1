<#
    Settings report of a GPO, as the Settings tab of GPMC: the policies configured in a
    Registry.pol with their category path, state and option values, then the registry values
    no policy of the loaded ADMX explains ("Extra Registry Settings"). Kept free of any Avalonia
    type so it can be tested without a UI.

    Only the policies whose registry keys are in the file are read: an index key -> policies is
    built once for the loaded ADMX set.
#>

# Index of the policies by the registry keys they write, for a scope ("<scope>|<key>" in lower case).
function Get-PSGPOPolicyKeyIndex {
    [CmdletBinding()]
    param()

    $policies = [GPOToolsUtility]::Policies
    if ($script:PSGPOPolicyKeyIndex -and [object]::ReferenceEquals($script:PSGPOPolicyKeyIndexSource, $policies) -and $script:PSGPOPolicyKeyIndexCount -eq $policies.Count) {
        return $script:PSGPOPolicyKeyIndex
    }
    $index = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in $policies) {
        $footprint = Get-PSGPOPolicyFootprint -Policy $policy
        $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $footprint.ValueNames) { [void]$keys.Add($name.Substring(0, $name.IndexOf([char]0))) }
        foreach ($key in $footprint.ListKeys) { [void]$keys.Add($key) }
        foreach ($key in $keys) {
            $entry = "$($policy.Scope)|$key"
            if (-not $index.ContainsKey($entry)) { $index[$entry] = [System.Collections.Generic.List[object]]::new() }
            $index[$entry].Add($policy)
        }
    }
    $script:PSGPOPolicyKeyIndex = $index
    $script:PSGPOPolicyKeyIndexSource = $policies
    $script:PSGPOPolicyKeyIndexCount = $policies.Count
    $index
}

# Text of the value of an element, as GPMC shows it.
function Format-PSGPOElementValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicyElement]$Element,
        [AllowNull()] $Value
    )

    switch ($Element.Type) {
        'Boolean' { if ($Value) { 'Enabled' } else { 'Disabled' } }
        'Enum' {
            $index = [int]$Value
            if ($index -ge 0 -and $index -lt $Element.Items.Count) { "$($Element.Items[$index].DisplayName)" } else { "$Value" }
        }
        'List' {
            $items = @($Value | Where-Object { $null -ne $_ } | ForEach-Object { if ($_ -is [hashtable]) { "$($_.Name) = $($_.Value)" } else { "$_" } })
            if ($items.Count) { $items -join '; ' } else { '(empty)' }
        }
        'MultiText' { @($Value) -join '; ' }
        default { "$Value" }
    }
}

# Policies of the loaded ADMX set a Registry.pol configures for a scope: Policy and Read (its
# state and option values, Get-PSGPOPolicyState).
function Get-PSGPOConfiguredPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol,

        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope
    )

    $index = Get-PSGPOPolicyKeyIndex
    # Policies writing a key of the file, each once.
    $seen = [System.Collections.Generic.HashSet[object]]::new()
    foreach ($key in @($Pol.Entries.Key | Select-Object -Unique)) {
        $found = $null
        if (-not $index.TryGetValue("$Scope|$key", [ref]$found)) { continue }
        foreach ($policy in $found) {
            if (-not $seen.Add($policy)) { continue }
            $read = Get-PSGPOPolicyState -Policy $policy -Pol $Pol
            if ($read.State -ne 'NotConfigured') { [pscustomobject]@{ Policy = $policy; Read = $read } }
        }
    }
}

function Get-PSGPOConfiguredSetting {
    [CmdletBinding()]
    [OutputType([AvaloniaSettingRow])]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol,

        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope
    )

    $hive = if ($Scope -eq 'Machine') { 'HKLM' } else { 'HKCU' }

    $explained = [System.Collections.Generic.HashSet[object]]::new()
    $rows = foreach ($configured in @(Get-PSGPOConfiguredPolicy -Pol $Pol -Scope $Scope)) {
        $policy = $configured.Policy
        $read = $configured.Read
        foreach ($entry in @(Get-PSGPOPolicyEntry -Policy $policy -Pol $Pol)) { [void]$explained.Add($entry) }

        $path = [System.Collections.Generic.List[string]]::new()
        for ($category = $policy.Category; $category; $category = $category.ParentCategory) { $path.Insert(0, $category.DisplayName) }
        $path.Insert(0, 'Administrative Templates')
        $path.Insert(0, 'Policies')

        $options = if ($read.State -eq 'Enabled') {
            foreach ($element in $policy.Elements) {
                if (-not $read.Value.ContainsKey($element.Id)) { continue }
                $label = if ($element.Label) { $element.Label.TrimEnd(':', ' ') } else { $element.Id }
                "${label}: $(Format-PSGPOElementValue -Element $element -Value $read.Value[$element.Id])"
            }
        }
        $row = [AvaloniaSettingRow]::new()
        $row.Path = $path -join ' > '
        $row.Name = $policy.DisplayName
        $row.State = $read.State
        $row.Options = @($options) -join [Environment]::NewLine
        $row
    }
    # Sort-Object wraps its output in PSObjects, which Avalonia cannot bind: the rows themselves.
    foreach ($row in @($rows | Sort-Object Path, Name)) { $row.psobject.BaseObject }

    # Registry values no configured policy explains, as GPMC lists them.
    foreach ($entry in $Pol.Entries) {
        if ($explained.Contains($entry)) { continue }
        $row = [AvaloniaSettingRow]::new()
        $row.Path = 'Extra Registry Settings'
        $row.Name = "$hive\$($entry.Key)"
        $row.State = if ($entry.IsDeleteAllValues()) { 'Delete all values' } elseif ($entry.IsDelete()) { 'Delete value' } else { "$($entry.Type)" }
        $row.Options = if ($entry.IsDeleteAllValues()) { '' }
            elseif ($entry.IsDelete()) { $entry.GetTargetValueName() }
            else {
                $data = $entry.GetValue()
                if ($data -is [byte[]]) { $data = ($data | ForEach-Object { $_.ToString('X2') }) -join ' ' }
                $name = if ($entry.ValueName) { $entry.ValueName } else { '(Default)' }
                "$name = $(@($data) -join '; ')"
            }
        $row.IsExtra = $true
        $row
    }
}
