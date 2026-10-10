<#
    Registry values a policy setting writes, for a state and the values entered for its
    elements: the content of Registry.pol for this policy. Kept free of any Avalonia type.

    -Value maps element Id -> value:
      Boolean     [bool]
      Decimal     number (checked against MinValue/MaxValue)
      Text        [string]
      MultiText   [string[]]
      Enum        index of the choice in $Element.Items (ADMX order)
      List        [string[]]; with ExplicitValue, @(@{ Name; Value }) pairs
    An element without value takes its ADML default (checkBox, dropdownList, decimalTextBox,
    textBox), otherwise false / MinValue / empty.

    What the editor writes when the ADMX is silent (disabled elements deleted, list keys
    cleared) is flagged Implicit, like the enabled/disabled defaults.
#>

function Get-PSGPOElementDefault {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsPolicyElement]$Element)

    $Default = $Element.DefaultValue
    switch ($Element.Type) {
        'Boolean' { [bool]$Default }
        { $_ -in 'Decimal', 'LongDecimal' } { if ("$Default" -ne '') { [uint64]$Default } else { $Element.MinValue } }
        'Enum' { if ("$Default" -ne '') { [int]$Default } else { 0 } }
        'Text' { "$Default" }
        default { $null }
    }
}

function Get-PSGPOPolicyRegistryChange {
    [CmdletBinding()]
    [OutputType([GPOToolsRegistryValue])]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicy]$Policy,

        [Parameter(Mandatory)]
        [ValidateSet('NotConfigured', 'Enabled', 'Disabled')]
        [string]$State,

        [hashtable]$Value = @{}
    )

    if ($State -eq 'NotConfigured') { return }

    if ($State -eq 'Disabled') {
        foreach ($Item in $Policy.DisabledValues) { $Item }
        foreach ($Element in $Policy.Elements) {
            $Change = if ($Element.Type -eq 'List') {
                [GPOToolsRegistryValue]::new($Element.Key, '', [GPOToolsRegistryValueType]::DeleteAllValues, $null)
            } elseif ($Element.ValueName) {
                [GPOToolsRegistryValue]::new($Element.Key, $Element.ValueName, [GPOToolsRegistryValueType]::Delete, $null)
            }
            if ($Change) {
                $Change.Implicit = $true
                $Change
            }
        }
        return
    }

    foreach ($Item in $Policy.EnabledValues) { $Item }

    foreach ($Element in $Policy.Elements) {
        $Label = if ($Element.Label) { $Element.Label } else { $Element.Id }
        # Plain assignments: assigning an if statement would unroll a one-item array.
        $Entered = Get-PSGPOElementDefault -Element $Element
        if ($Value.ContainsKey($Element.Id)) { $Entered = $Value[$Element.Id] }

        switch ($Element.Type) {
            'Boolean' {
                if ([bool]$Entered) {
                    if ($Element.TrueValue) { $Element.TrueValue }
                    foreach ($Item in $Element.TrueList) { $Item }
                } else {
                    if ($Element.FalseValue) { $Element.FalseValue }
                    foreach ($Item in $Element.FalseList) { $Item }
                }
            }
            { $_ -in 'Decimal', 'LongDecimal' } {
                if ("$Entered" -eq '') {
                    if ($Element.Required) { throw "'$Label' is required." }
                    continue
                }
                $Number = [uint64]0
                if (-not [uint64]::TryParse("$Entered", [ref]$Number)) { throw "'$Label' must be a positive whole number." }
                if ($Number -lt $Element.MinValue -or $Number -gt $Element.MaxValue) {
                    throw "'$Label' must be between $($Element.MinValue) and $($Element.MaxValue)."
                }
                $Data = switch ($Element.ValueType) {
                    'String' { "$Number" }
                    'QWord' { $Number }
                    default { [uint32]$Number }
                }
                [GPOToolsRegistryValue]::new($Element.Key, $Element.ValueName, $Element.ValueType, $Data)
            }
            'Text' {
                $Text = "$Entered"
                if ($Element.Required -and $Text -eq '') { throw "'$Label' is required." }
                if ($Text.Length -gt $Element.MaxLength) { throw "'$Label' is limited to $($Element.MaxLength) characters." }
                [GPOToolsRegistryValue]::new($Element.Key, $Element.ValueName, $Element.ValueType, $Text)
            }
            'MultiText' {
                $Lines = @($Entered | Where-Object { "$_" -ne '' } | ForEach-Object { "$_" })
                if ($Element.Required -and $Lines.Count -eq 0) { throw "'$Label' is required." }
                if ($Element.MaxStrings -gt 0 -and $Lines.Count -gt $Element.MaxStrings) { throw "'$Label' is limited to $($Element.MaxStrings) lines." }
                if (@($Lines | Where-Object Length -GT $Element.MaxLength).Count) { throw "'$Label' lines are limited to $($Element.MaxLength) characters." }
                [GPOToolsRegistryValue]::new($Element.Key, $Element.ValueName, $Element.ValueType, [string[]]$Lines)
            }
            'Enum' {
                $Index = [int]$Entered
                if ($Index -lt 0 -or $Index -ge $Element.Items.Count) { throw "'$Label': choice $Index does not exist." }
                $Choice = $Element.Items[$Index]
                if ($Choice.Value) { $Choice.Value }
                foreach ($Item in $Choice.ValueList) { $Item }
            }
            'List' {
                # Name/value pairs: explicit names, or generated from the entries.
                $Pairs = [System.Collections.Generic.List[object]]::new()
                if ($Element.ExplicitValue) {
                    foreach ($Pair in @($Entered)) {
                        if ("$($Pair.Name)" -eq '') { throw "'$Label': every entry needs a value name." }
                        $Pairs.Add(@{ Name = "$($Pair.Name)"; Value = "$($Pair.Value)" })
                    }
                } else {
                    $Index = 0
                    foreach ($Entry in @($Entered | Where-Object { "$_" -ne '' })) {
                        $Index++
                        # valuePrefix (even "") gives prefix1, prefix2...; without it the entry is both name and data.
                        $Name = if ($Element.HasValuePrefix) { '{0}{1}' -f $Element.ValuePrefix, $Index } else { "$Entry" }
                        $Pairs.Add(@{ Name = $Name; Value = "$Entry" })
                    }
                }
                # A non additive list replaces the content of its key.
                if (-not $Element.Additive) {
                    $Clear = [GPOToolsRegistryValue]::new($Element.Key, '', [GPOToolsRegistryValueType]::DeleteAllValues, $null)
                    $Clear.Implicit = $true
                    $Clear
                }
                foreach ($Pair in $Pairs) {
                    [GPOToolsRegistryValue]::new($Element.Key, $Pair.Name, $Element.ValueType, $Pair.Value)
                }
            }
        }
    }
}
