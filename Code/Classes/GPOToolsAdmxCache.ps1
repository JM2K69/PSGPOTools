<#
    The content of a cache file of the ADMX files (PSGPOAdmxCache.ps1), read by System.Text.Json
    in one call: typed arrays, a row per object, so that no text becomes a date (ConvertFrom-Json
    reads "2016-01-01" as a DateTime) and $null stays apart from ''. The references between the
    tables are indexes in them, -1 for none. Export-PSGPOAdmxCache writes the columns in this order.
#>
class GPOToolsAdmxCache {
    [string[]]$TargetLoad
    # Path, namespace
    [string[][]]$NamespaceByFile
    [string[]]$Warnings
    # The files left out ([GPOToolsUtility]::SkippedFiles)
    [string[]]$SkippedFiles
    # Name, DisplayName
    [string[][]]$SupportedOn
    # Name, DisplayName, ExplainText, prefix, namespace
    [string[][]]$CategoryText
    [int[]]$CategoryParent
    # Key, ValueName, Value
    [string[][]]$ValueText
    # Type, Implicit
    [int[][]]$ValueNumber
    # Id, Type, Key, ValueName, ClientExtension, ValuePrefix, Control, Label, DefaultValue (a text)
    [string[][]]$ElementText
    # ValueType, Required, Soft, StoreAsText, Expandable, HasValuePrefix, Additive, ExplicitValue,
    # NoSort, DefaultValue (0 none, 1 a text, 2 $false, 3 $true), TrueValue, FalseValue
    [int[][]]$ElementNumber
    # MinValue, MaxValue, MaxLength, MaxStrings, SpinStep
    [uint64[][]]$ElementSize
    # TrueList, FalseList, Items
    [int[][][]]$ElementList
    # DisplayName, DisplayNameRef
    [string[][]]$ItemText
    # Value, then the ValueList
    [int[][]]$ItemValue
    # ID, Name, DisplayName, Description, Class, FileName, Path, RegistryKey, then Registry.Path,
    # Registry.Key, Registry.Value.Enable, Registry.Value.Disable
    [string[][]]$PolicyText
    # Scope, Category, Layout
    [int[][]]$PolicyNumber
    # EnabledValues, DisabledValues, Elements
    [int[][][]]$PolicyList
    # RefId, Control, Label of each line of a presentation layout, one after the other
    [string[][]]$Layout
}
