<#
    Rows of the "Registry Values" grid of Show-GPOManagerAvalonia for one policy: the
    values written when the policy is enabled or disabled, then one row per element.
    Kept free of any Avalonia type so it can be tested without a UI.
#>

function Format-PSGPORegistryValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryValue]$Value
    )

    $Text = switch ($Value.Type) {
        'Delete' { '{0}\{1}: deleted' -f $Value.Key, $Value.ValueName }
        'DeleteAllValues' { '{0}\*: all values deleted' -f $Value.Key }
        'MultiString' { '{0}\{1} = {2} ({3})' -f $Value.Key, $Value.ValueName, ($Value.Value -join ' | '), $Value.Type }
        default { '{0}\{1} = {2} ({3})' -f $Value.Key, $Value.ValueName, $Value.Value, $Value.Type }
    }
    # An implicit value is not written in the ADMX: it is the editor's default behaviour.
    if ($Value.Implicit) { "$Text [default]" } else { $Text }
}

function Get-PSGPOPolicyRegistryRow {
    [CmdletBinding()]
    [OutputType([AvaloniaRegistryRow])]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicy]$Policy
    )

    foreach ($Value in $Policy.EnabledValues) {
        $Row = [AvaloniaRegistryRow]::new()
        $Row.Key = 'Enabled'
        $Row.Value = Format-PSGPORegistryValue $Value
        $Row
    }
    foreach ($Value in $Policy.DisabledValues) {
        $Row = [AvaloniaRegistryRow]::new()
        $Row.Key = 'Disabled'
        $Row.Value = Format-PSGPORegistryValue $Value
        $Row
    }
    foreach ($Element in $Policy.Elements) {
        $Row = [AvaloniaRegistryRow]::new()
        $Row.Key = if ($Element.Label) { $Element.Label } else { $Element.Id }
        $Target = if ($Element.Type -eq 'List') { '{0}\*' -f $Element.Key } else { '{0}\{1}' -f $Element.Key, $Element.ValueName }
        $Detail = switch ($Element.Type) {
            'Enum' { '{0} choices' -f $Element.Items.Count }
            { $_ -in 'Decimal', 'LongDecimal' } { '{0}..{1}' -f $Element.MinValue, $Element.MaxValue }
            default { $null }
        }
        $Row.Value = ('{0}{1}: {2} ({3})' -f $Element.Type, $(if ($Detail) { ", $Detail" }), $Target, $Element.ValueType)
        $Row
    }
}
