<#
    Rows of the "Registry Values" grid of Show-GPOManagerAvalonia for one policy: the
    values written when the policy is enabled or disabled, then one row per element.
    Kept free of any Avalonia type so it can be tested without a UI. In the language of the
    interface (Get-PSGPOText): only the console shows them.
#>

function Format-PSGPORegistryValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryValue]$Value
    )

    $Text = switch ($Value.Type) {
        'Delete' { Get-PSGPOText '{0}\{1}: deleted' $Value.Key $Value.ValueName }
        'DeleteAllValues' { Get-PSGPOText '{0}\*: all values deleted' $Value.Key }
        'MultiString' { '{0}\{1} = {2} ({3})' -f $Value.Key, $Value.ValueName, ($Value.Value -join ' | '), $Value.Type }
        default { '{0}\{1} = {2} ({3})' -f $Value.Key, $Value.ValueName, $Value.Value, $Value.Type }
    }
    # An implicit value is not written in the ADMX: it is the editor's default behaviour.
    if ($Value.Implicit) { Get-PSGPOText '{0} [default]' $Text } else { $Text }
}

function Get-PSGPOPolicyRegistryRow {
    [CmdletBinding()]
    [OutputType([AvaloniaRegistryRow])]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicy]$Policy
    )

    foreach ($Value in $Policy.EnabledValues) {
        $Row = [AvaloniaRegistryRow]::new()
        $Row.Key = Get-PSGPOText 'Enabled'
        $Row.Value = Format-PSGPORegistryValue $Value
        $Row
    }
    foreach ($Value in $Policy.DisabledValues) {
        $Row = [AvaloniaRegistryRow]::new()
        $Row.Key = Get-PSGPOText 'Disabled'
        $Row.Value = Format-PSGPORegistryValue $Value
        $Row
    }
    foreach ($Element in $Policy.Elements) {
        $Row = [AvaloniaRegistryRow]::new()
        $Row.Key = if ($Element.Label) { $Element.Label } else { $Element.Id }
        $Target = if ($Element.Type -eq 'List') { '{0}\*' -f $Element.Key } else { '{0}\{1}' -f $Element.Key, $Element.ValueName }
        $Detail = switch ($Element.Type) {
            'Enum' { Get-PSGPOText '{0} choices' $Element.Items.Count }
            { $_ -in 'Decimal', 'LongDecimal' } { '{0}..{1}' -f $Element.MinValue, $Element.MaxValue }
            default { $null }
        }
        $Row.Value = ('{0}{1}: {2} ({3})' -f $Element.Type, $(if ($Detail) { ", $Detail" }), $Target, $Element.ValueType)
        $Row
    }
}

# Row of the "Registry Preview" list: full key with its hive, value name, Windows type and data.
function ConvertTo-PSGPOPreviewRow {
    [CmdletBinding()]
    [OutputType([AvaloniaPreviewRow])]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryValue]$Change,
        [Parameter(Mandatory)] [ScopePolicy]$Scope
    )

    $Hive = if ($Scope -eq [ScopePolicy]::Machine) { 'HKLM' } else { 'HKCU' }
    $RegType = @{
        String = 'REG_SZ'; ExpandString = 'REG_EXPAND_SZ'; MultiString = 'REG_MULTI_SZ'
        DWord = 'REG_DWORD'; QWord = 'REG_QWORD'
    }
    $Row = [AvaloniaPreviewRow]::new()
    $Row.Key = '{0}\{1}' -f $Hive, $Change.Key
    switch ($Change.Type) {
        'Delete' {
            $Row.Title = Get-PSGPOText 'Delete value'
            $Row.ValueName = $Change.ValueName
            $Row.Data = '-'
        }
        'DeleteAllValues' {
            $Row.Title = Get-PSGPOText 'Delete all values of the key'
            $Row.ValueName = Get-PSGPOText '(all values)'
            $Row.Data = '-'
        }
        default {
            $Row.Title = Get-PSGPOText 'Set {0}' $RegType["$($Change.Type)"]
            $Row.ValueName = $Change.ValueName
            $Row.Data = if ($Change.Type -eq [GPOToolsRegistryValueType]::MultiString) { $Change.Value -join ' | ' } else { "$($Change.Value)" }
        }
    }
    # Not written in the ADMX: the editor's default behaviour, to be confirmed against GPMC.
    if ($Change.Implicit) { $Row.Title += Get-PSGPOText ' (editor default)' }
    $Row
}
