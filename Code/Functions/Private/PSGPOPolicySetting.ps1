<#
    Setting of a policy in a Registry.pol (GPOToolsRegistryPol): read its state and the values
    of its elements from the entries, and write a new setting in place of its entries.

    It is the reverse of Get-PSGPOPolicyRegistryChange: the entries a policy owns are the values
    it can write (enabled/disabled values, its elements, their true/false and enum lists, their
    **del. deletions) and every value of the keys of its list elements.
#>

# Whether an entry holds a registry value of a policy setting.
function Test-PSGPOPolEntryMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [GPOToolsPolEntry]$Entry,
        [Parameter(Mandatory)] [GPOToolsRegistryValue]$Value
    )

    if (-not $Entry) { return $false }
    if (-not [string]::Equals($Entry.Key, $Value.Key, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    switch ($Value.Type) {
        'DeleteAllValues' { return $Entry.IsDeleteAllValues() }
        'Delete' { return $Entry.IsDelete() -and [string]::Equals($Entry.GetTargetValueName(), $Value.ValueName, [System.StringComparison]::OrdinalIgnoreCase) }
    }
    if ($Entry.IsDelete() -or $Entry.IsDeleteAllValues()) { return $false }
    if (-not [string]::Equals($Entry.ValueName, $Value.ValueName, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    # The same data in another type is another value: DWORD 0 is not the string "0".
    $types = switch ($Value.Type) {
        { $_ -in 'DWord', 'QWord' } { 'DWord', 'DWordBigEndian', 'QWord' }
        { $_ -in 'String', 'ExpandString' } { 'String', 'ExpandString' }
        'MultiString' { 'MultiString' }
    }
    if ("$($Entry.Type)" -notin $types) { return $false }
    $Data = $Entry.GetValue()
    switch ($Value.Type) {
        { $_ -in 'DWord', 'QWord' } {
            $Number = [uint64]0
            return [uint64]::TryParse("$Data", [ref]$Number) -and $Number -eq [uint64]$Value.Value
        }
        'MultiString' { return (@($Data) -join "`0") -ceq (@($Value.Value) -join "`0") }
        default { return "$Data" -ceq "$($Value.Value)" }
    }
}

# Every registry value a policy can write, and the keys of its list elements.
function Get-PSGPOPolicyFootprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsPolicy]$Policy)

    $values = [System.Collections.Generic.List[GPOToolsRegistryValue]]::new()
    foreach ($item in @($Policy.EnabledValues) + @($Policy.DisabledValues)) { if ($item) { $values.Add($item) } }
    $listKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($element in $Policy.Elements) {
        if ($element.Type -eq 'List') {
            [void]$listKeys.Add($element.Key)
            continue
        }
        if ($element.ValueName) { $values.Add([GPOToolsRegistryValue]::new($element.Key, $element.ValueName, [GPOToolsRegistryValueType]::String, $null)) }
        foreach ($item in @($element.TrueValue, $element.FalseValue) + @($element.TrueList) + @($element.FalseList)) { if ($item) { $values.Add($item) } }
        foreach ($choice in $element.Items) {
            foreach ($item in @($choice.Value) + @($choice.ValueList)) { if ($item) { $values.Add($item) } }
        }
    }
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    # An empty value name is the default value of the key.
    foreach ($value in $values) { if ($value.Type -ne 'DeleteAllValues') { [void]$names.Add("$($value.Key)`0$($value.ValueName)") } }
    [pscustomobject]@{ ValueNames = $names; ListKeys = $listKeys }
}

# Entries of the Registry.pol that belong to the policy.
function Get-PSGPOPolicyEntry {
    [CmdletBinding()]
    [OutputType([GPOToolsPolEntry])]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicy]$Policy,
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol
    )

    $footprint = Get-PSGPOPolicyFootprint -Policy $Policy
    foreach ($entry in $Pol.Entries) {
        if ($footprint.ListKeys.Contains($entry.Key) -or $footprint.ValueNames.Contains("$($entry.Key)`0$($entry.GetTargetValueName())")) { $entry }
    }
}

# Whether every value of the list is in the entries (an empty list is not).
function Test-PSGPOPolValueSet {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [GPOToolsPolEntry[]]$Entry,
        [AllowEmptyCollection()] [GPOToolsRegistryValue[]]$Value = @()
    )

    $values = @($Value | Where-Object { $_ })
    if (-not $values.Count) { return $false }
    foreach ($item in $values) {
        $found = $false
        foreach ($candidate in $Entry) { if (Test-PSGPOPolEntryMatch -Entry $candidate -Value $item) { $found = $true; break } }
        if (-not $found) { return $false }
    }
    $true
}

# State of the policy in the Registry.pol and the values of its elements, in the form
# Get-PSGPOPolicyRegistryChange -Value expects.
function Get-PSGPOPolicyState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicy]$Policy,
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol
    )

    $entries = @(Get-PSGPOPolicyEntry -Policy $Policy -Pol $Pol)
    if (-not $entries.Count) { return [pscustomobject]@{ State = 'NotConfigured'; Value = @{} } }

    $enabled = Test-PSGPOPolValueSet -Entry $entries -Value @($Policy.EnabledValues)
    # What disabling writes, duplicates removed: the ADMX may declare a value twice.
    $disabledValues = @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State Disabled | Where-Object { -not $_.Implicit })
    $disabled = $disabledValues.Count -and (Test-PSGPOPolValueSet -Entry $entries -Value $disabledValues)
    $state = if ($enabled) { 'Enabled' }
        elseif ($disabled) { 'Disabled' }
        # No enabled/disabled value: enabled when an element holds a value, else disabled (deletions).
        elseif (@($entries | Where-Object { -not $_.IsDelete() -and -not $_.IsDeleteAllValues() }).Count) { 'Enabled' }
        else { 'Disabled' }

    $values = @{}
    if ($state -eq 'Enabled') {
        foreach ($element in $Policy.Elements) {
            $read = Get-PSGPOElementState -Element $element -Pol $Pol
            if ($null -ne $read) { $values[$element.Id] = $read }
        }
    }
    [pscustomobject]@{ State = $state; Value = $values }
}

# Value of an element in the Registry.pol ($null when it holds none).
function Get-PSGPOElementState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicyElement]$Element,
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol
    )

    $entries = @($Pol.GetEntries($Element.Key))
    $entry = if ($Element.ValueName) { $Pol.FindValue($Element.Key, $Element.ValueName) }
    $held = $entry -and -not $entry.IsDelete()
    switch ($Element.Type) {
        'Boolean' {
            if ($Element.TrueValue -and (Test-PSGPOPolEntryMatch -Entry $entry -Value $Element.TrueValue)) { return $true }
            if ($Element.FalseValue -and (Test-PSGPOPolEntryMatch -Entry $entry -Value $Element.FalseValue)) { return $false }
            if (Test-PSGPOPolValueSet -Entry @($Pol.Entries) -Value @($Element.TrueList)) { return $true }
            if (Test-PSGPOPolValueSet -Entry @($Pol.Entries) -Value @($Element.FalseList)) { return $false }
            return $null
        }
        { $_ -in 'Decimal', 'LongDecimal' } {
            if (-not $held) { return $null }
            $number = [uint64]0
            if ([uint64]::TryParse("$($entry.GetValue())", [ref]$number)) { return $number }
            return $null
        }
        'Text' { if ($held) { return "$($entry.GetValue())" } else { return $null } }
        'MultiText' { if ($held) { return [string[]]@($entry.GetValue()) } else { return $null } }
        'Enum' {
            for ($i = 0; $i -lt $Element.Items.Count; $i++) {
                $choice = $Element.Items[$i]
                if ($choice.Value) {
                    if (Test-PSGPOPolEntryMatch -Entry $entry -Value $choice.Value) { return $i }
                } elseif (Test-PSGPOPolValueSet -Entry @($Pol.Entries) -Value @($choice.ValueList)) {
                    return $i
                }
            }
            return $null
        }
        'List' {
            $items = @($entries | Where-Object { -not $_.IsDelete() -and -not $_.IsDeleteAllValues() })
            if ($Element.ExplicitValue) {
                return @($items | ForEach-Object { @{ Name = $_.ValueName; Value = "$($_.GetValue())" } })
            }
            if ($Element.HasValuePrefix) {
                # prefix1, prefix2...: in the order of their number.
                $prefix = $Element.ValuePrefix
                $items = @($items | Sort-Object {
                        $suffix = if ($_.ValueName.Length -gt $prefix.Length) { $_.ValueName.Substring($prefix.Length) } else { '' }
                        $number = 0
                        if ([int]::TryParse($suffix, [ref]$number)) { $number } else { [int]::MaxValue }
                    })
            }
            return [string[]]@($items | ForEach-Object { "$($_.GetValue())" })
        }
    }
}

# Writes a setting of the policy in the Registry.pol: its entries are replaced by the values of
# the new setting (none when not configured). The setting is checked before anything changes.
function Set-PSGPOPolicyState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicy]$Policy,
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol,
        [Parameter(Mandatory)] [ValidateSet('NotConfigured', 'Enabled', 'Disabled')] [string]$State,
        [hashtable]$Value = @{}
    )

    $changes = @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State $State -Value $Value)
    $owned = [System.Collections.Generic.HashSet[object]]::new()
    foreach ($entry in @(Get-PSGPOPolicyEntry -Policy $Policy -Pol $Pol)) { [void]$owned.Add($entry) }
    [void]$Pol.Entries.RemoveAll([Predicate[GPOToolsPolEntry]] { param($e) $owned.Contains($e) })
    foreach ($change in $changes) { $Pol.Entries.Add([GPOToolsPolEntry]::FromRegistryValue($change)) }
}
