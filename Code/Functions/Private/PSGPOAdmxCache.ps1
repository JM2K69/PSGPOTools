<#
    The ADMX files of a folder read once, then from a cache: parsing a PolicyDefinitions folder
    takes seconds (about a millisecond per policy), and each console opens in a process of its
    own. The cache holds what Initialize-PSGPOAdmx loads from a folder in a language: it is used
    while the .admx and .adml files keep their names, sizes and dates, for the same HGPM.psm1.
    <cache>/PSGPOTools/Admx/<hash>.json: %LOCALAPPDATA% on Windows, $XDG_CACHE_HOME or ~/.cache
    elsewhere ($env:PSGPOTOOLS_CACHE_PATH for the tests). The first line of a file is its stamp,
    the rest a GPOToolsAdmxCache as JSON. A load with an error, or with a file left out for a reason
    that may pass, is not written (Initialize-PSGPOAdmx).
#>

# Changed with the content of the cache files: a cache of another format is not read.
$script:PSGPOAdmxCacheFormat = 1

function Get-PSGPOAdmxCacheFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:PSGPOTOOLS_CACHE_PATH) { return $env:PSGPOTOOLS_CACHE_PATH }
    $root = if ($IsWindows) { [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) }
        elseif ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME }
        elseif ($HOME) { Join-Path $HOME '.cache' }
    if (-not $root) { return $null }
    Join-Path $root 'PSGPOTools' 'Admx'
}

# The cache file of a folder in a language, and the stamp of what it was made from: the format,
# HGPM.psm1, and the names, sizes and dates of the .admx files and of the .adml files the parser
# may read (the language and en-US, for the templates without the language).
function Get-PSGPOAdmxCacheEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Culture
    )

    $folder = Get-PSGPOAdmxCacheFolder
    if (-not $folder) { return }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("$script:PSGPOAdmxCacheFormat|$Culture")
    $module = Get-Item -LiteralPath (Join-Path $PSScriptRoot 'HGPM.psm1') -ErrorAction SilentlyContinue
    if ($module) { $lines.Add("$($module.Length)|$($module.LastWriteTimeUtc.Ticks)") }
    # The language folders as the ADML files are found, their names without regard to case (fr-FR
    # and fr-fr side by side on Linux), the hidden files too.
    $languages = @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Culture -or $_.Name -eq 'en-US' })
    $files = @([GPOToolsUtility]::GetAdmxFiles($Path)) + @(foreach ($language in $languages) { Get-ChildItem -LiteralPath $language.FullName -File -Force -ErrorAction SilentlyContinue })
    foreach ($file in $files | Sort-Object -Property FullName) { $lines.Add("$($file.FullName)|$($file.Length)|$($file.LastWriteTimeUtc.Ticks)") }

    $hash = { param($Text) [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))) }
    @{
        File = Join-Path $folder ((& $hash "$($Path.ToLowerInvariant())|$Culture").Substring(0, 32) + '.json')
        Stamp = & $hash ($lines -join "`n")
    }
}

# What is loaded now ([GPOToolsUtility]), written in the cache file of the entry; $Warnings are
# those of the load, shown again when it is read from the cache.
function Export-PSGPOAdmxCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Entry,
        [string[]]$Warnings = @()
    )

    # Rows of object[]: $null stays apart from '' in them (a string array turns an assigned $null
    # into ''), and System.Text.Json writes them as the arrays of GPOToolsAdmxCache. The loops
    # call no .NET method (List.Add, Dictionary.ContainsKey...): on Windows, AMSI logs each one,
    # some ten microseconds a call. The indexes are hashtables of the objects themselves (their
    # identity: the classes do not redefine Equals). A value, an element or a layout is written
    # once, shared as loaded: a policy of class Both gives two policies with the same ones.
    $policies = [GPOToolsUtility]::Policies

    # The values of the policies and of their elements.
    $valueIndex = @{}
    $count = 0
    $values = @(foreach ($value in @(foreach ($policy in $policies) {
                    $policy.EnabledValues
                    $policy.DisabledValues
                    foreach ($element in $policy.Elements) {
                        $element.TrueValue
                        $element.FalseValue
                        $element.TrueList
                        $element.FalseList
                        foreach ($choice in $element.Items) { $choice.Value; $choice.ValueList }
                    }
                })) {
            if ($null -eq $value -or $null -ne $valueIndex[$value]) { continue }
            $valueIndex[$value] = $count
            $count++
            $value
        })
    $valueText = @(foreach ($value in $values) {
            $data = $value.Value
            if ($null -ne $data) { $data = [string]$data }
            , @($value.Key, $value.ValueName, $data)
        })
    $valueNumber = @(foreach ($value in $values) { , @([int]$value.Type, [int]$value.Implicit) })

    # A category by its name and target: unique among the categories loaded.
    $categories = [GPOToolsUtility]::Categories
    $categoryIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $count = 0
    foreach ($category in $categories) {
        $categoryIndex["$($category.Name)|$($category.target.prefix)|$($category.target.namespace)"] = $count
        $count++
    }
    $categoryText = @(foreach ($category in $categories) { , @($category.Name, $category.DisplayName, $category.ExplainText, $category.target.prefix, $category.target.namespace) })
    $categoryParent = @(foreach ($category in $categories) {
            $parent = $category.ParentCategory
            if ($null -eq $parent) { -1; continue }
            $index = $categoryIndex["$($parent.Name)|$($parent.target.prefix)|$($parent.target.namespace)"]
            if ($null -eq $index) { throw "The parent category of $($category.Name) is not loaded." }
            $index
        })

    # The elements, then their choices (enum).
    $elementIndex = @{}
    $count = 0
    $elements = @(foreach ($policy in $policies) {
            foreach ($element in $policy.Elements) {
                if ($null -ne $elementIndex[$element]) { continue }
                $elementIndex[$element] = $count
                $count++
                $element
            }
        })
    $elementText = @(foreach ($element in $elements) {
            # The default value proposed: none, a text or a check box.
            $default = $element.DefaultValue
            if ($null -ne $default -and $default -isnot [string] -and $default -isnot [bool]) { throw "DefaultValue of $($element.Id): $($default.GetType().Name)" }
            if ($default -isnot [string]) { $default = $null }
            , @($element.Id, $element.Type, $element.Key, $element.ValueName, $element.ClientExtension, $element.ValuePrefix, $element.Control, $element.Label, $default)
        })
    $elementNumber = @(foreach ($element in $elements) {
            $kind = 0
            if ($element.DefaultValue -is [string]) { $kind = 1 } elseif ($element.DefaultValue -is [bool]) { $kind = 2 + [int]$element.DefaultValue }
            $trueValue = -1
            if ($null -ne $element.TrueValue) { $trueValue = $valueIndex[$element.TrueValue] }
            $falseValue = -1
            if ($null -ne $element.FalseValue) { $falseValue = $valueIndex[$element.FalseValue] }
            , @([int]$element.ValueType, [int]$element.Required, [int]$element.Soft, [int]$element.StoreAsText, [int]$element.Expandable,
                [int]$element.HasValuePrefix, [int]$element.Additive, [int]$element.ExplicitValue, [int]$element.NoSort, $kind, $trueValue, $falseValue)
        })
    $elementSize = @(foreach ($element in $elements) { , @($element.MinValue, $element.MaxValue, $element.MaxLength, $element.MaxStrings, $element.SpinStep) })
    $count = 0
    $elementList = @(foreach ($element in $elements) {
            $items = @(foreach ($choice in $element.Items) { $count; $count++ })
            , @([int[]]@(foreach ($value in $element.TrueList) { $valueIndex[$value] }), [int[]]@(foreach ($value in $element.FalseList) { $valueIndex[$value] }), [int[]]$items)
        })
    $itemText = @(foreach ($element in $elements) { foreach ($choice in $element.Items) { , @($choice.DisplayName, $choice.DisplayNameRef) } })
    $itemValue = @(foreach ($element in $elements) {
            foreach ($choice in $element.Items) {
                $first = -1
                if ($null -ne $choice.Value) { $first = $valueIndex[$choice.Value] }
                , [int[]]@(@($first) + @(foreach ($value in $choice.ValueList) { $valueIndex[$value] }))
            }
        })

    # The presentation layout of a policy: the one of its other scope for a policy of class Both
    # (an array as a key of a hashtable would be a list of keys: by file and id instead).
    $layoutIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $count = 0
    $layouts = @(foreach ($policy in $policies) {
            $key = "$($policy.FileName)|$($policy.ID)"
            if (-not $policy.Layout.Count -or $null -ne $layoutIndex[$key]) { continue }
            $layoutIndex[$key] = $count
            $count++
            , @(foreach ($part in $policy.Layout) { $part.RefId; $part.Control; $part.Label })
        })

    $policyText = @(foreach ($policy in $policies) {
            , @($policy.ID, $policy.Name, $policy.DisplayName, $policy.Description, $policy.Class, $policy.FileName, $policy.Path, $policy.RegistryKey,
                $policy.Registry.Path, $policy.Registry.Key, $policy.Registry.Value.Enable, $policy.Registry.Value.Disable)
        })
    $policyNumber = @(foreach ($policy in $policies) {
            $category = -1
            if ($null -ne $policy.Category) { $category = $categoryIndex["$($policy.Category.Name)|$($policy.Category.target.prefix)|$($policy.Category.target.namespace)"] }
            $layout = -1
            if ($policy.Layout.Count) { $layout = $layoutIndex["$($policy.FileName)|$($policy.ID)"] }
            , @([int]$policy.Scope, $category, $layout)
        })
    $policyList = @(foreach ($policy in $policies) {
            , @([int[]]@(foreach ($value in $policy.EnabledValues) { $valueIndex[$value] }), [int[]]@(foreach ($value in $policy.DisabledValues) { $valueIndex[$value] }),
                [int[]]@(foreach ($element in $policy.Elements) { $elementIndex[$element] }))
        })

    # The names of GPOToolsAdmxCache.
    $content = [ordered]@{
        TargetLoad = @([GPOToolsUtility]::TargetLoad)
        NamespaceByFile = @(foreach ($file in [GPOToolsUtility]::NamespaceByFile.Keys) { , @($file, [GPOToolsUtility]::NamespaceByFile[$file]) })
        Warnings = @($Warnings)
        SkippedFiles = @([GPOToolsUtility]::SkippedFiles)
        SupportedOn = @(foreach ($support in [GPOToolsUtility]::SupportOnTable) { , @($support.Name, $support.DisplayName) })
        CategoryText = $categoryText
        CategoryParent = $categoryParent
        ValueText = $valueText
        ValueNumber = $valueNumber
        ElementText = $elementText
        ElementNumber = $elementNumber
        ElementSize = $elementSize
        ElementList = $elementList
        ItemText = $itemText
        ItemValue = $itemValue
        PolicyText = $policyText
        PolicyNumber = $policyNumber
        PolicyList = $policyList
        Layout = $layouts
    }

    # Written aside, then moved: a console opening meanwhile reads the former file or the new one.
    $temporary = "$($Entry.File).$PID.tmp"
    try {
        $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Entry.File))
        $json = [System.Text.Json.JsonSerializer]::SerializeToUtf8Bytes($content, [object], [System.Text.Json.JsonSerializerOptions]::Default)
        $stamp = [System.Text.Encoding]::UTF8.GetBytes($Entry.Stamp + "`n")
        $stream = [System.IO.File]::Create($temporary)
        try {
            $stream.Write($stamp, 0, $stamp.Length)
            $stream.Write($json, 0, $json.Length)
        } finally {
            $stream.Dispose()
        }
        [System.IO.File]::Move($temporary, $Entry.File, $true)
        Write-Verbose "ADMX cache written: $($Entry.File)"
    } catch {
        Write-Verbose "ADMX cache not written in $($Entry.File): $($_.Exception.Message)"
        try { [System.IO.File]::Delete($temporary) } catch { Write-Verbose $_.Exception.Message }
    }
}

# Loads ([GPOToolsUtility]) the content of the cache file of the entry when its stamp is the one of
# the entry: @{ Warnings } then, else $null (no file, another stamp, or a file that cannot be read).
function Import-PSGPOAdmxCache {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$Entry)

    if (-not [System.IO.File]::Exists($Entry.File)) { return $null }
    try {
        # The UTF-8 bytes to System.Text.Json: from a string, PowerShell makes it some fifty times slower.
        $bytes = [System.IO.File]::ReadAllBytes($Entry.File)
        $newline = [System.Array]::IndexOf($bytes, [byte]10)
        if ($newline -lt 0 -or [System.Text.Encoding]::UTF8.GetString($bytes, 0, $newline) -ne $Entry.Stamp) {
            Write-Verbose "ADMX cache $($Entry.File) out of date: the files changed."
            return $null
        }
        $stream = [System.IO.MemoryStream]::new($bytes, $newline + 1, $bytes.Length - $newline - 1, $false)
        try { $content = [System.Text.Json.JsonSerializer]::Deserialize($stream, [GPOToolsAdmxCache], [System.Text.Json.JsonSerializerOptions]::Default) }
        finally { $stream.Dispose() }

        # The loops build the objects without calling a function or a .NET method for each one
        # (AMSI logs each method call on Windows), and without assigning the result of a
        # statement ($x = if...): the cache is there to be fast, and either costs more than the
        # object. A [string] property is left unset for $null: an assigned $null turns into ''.
        $types = [GPOToolsRegistryValueType[]][enum]::GetValues([GPOToolsRegistryValueType])
        $dword = [int][GPOToolsRegistryValueType]::DWord
        $qword = [int][GPOToolsRegistryValueType]::QWord
        $rows = $content.ValueText
        $numbers = $content.ValueNumber
        $values = [GPOToolsRegistryValue[]]::new($rows.Count)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            $number = $numbers[$i]
            $value = [GPOToolsRegistryValue]::new()
            if ($null -ne $row[0]) { $value.Key = $row[0] }
            if ($null -ne $row[1]) { $value.ValueName = $row[1] }
            $value.Type = $types[$number[0]]
            $data = $row[2]
            if ($number[0] -eq $dword) { $data = [uint32]$data } elseif ($number[0] -eq $qword) { $data = [uint64]$data }
            $value.Value = $data
            $value.Implicit = $number[1]
            $values[$i] = $value
        }

        $rows = $content.ElementText
        $numbers = $content.ElementNumber
        $sizes = $content.ElementSize
        $lists = $content.ElementList
        $itemRows = $content.ItemText
        $itemValues = $content.ItemValue
        $elements = [GPOToolsPolicyElement[]]::new($rows.Count)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            $number = $numbers[$i]
            $size = $sizes[$i]
            $list = $lists[$i]
            $element = [GPOToolsPolicyElement]::new()
            if ($null -ne $row[0]) { $element.Id = $row[0] }
            if ($null -ne $row[1]) { $element.Type = $row[1] }
            if ($null -ne $row[2]) { $element.Key = $row[2] }
            if ($null -ne $row[3]) { $element.ValueName = $row[3] }
            if ($null -ne $row[4]) { $element.ClientExtension = $row[4] }
            if ($null -ne $row[5]) { $element.ValuePrefix = $row[5] }
            if ($null -ne $row[6]) { $element.Control = $row[6] }
            if ($null -ne $row[7]) { $element.Label = $row[7] }
            if ($number[9] -eq 1) { $element.DefaultValue = $row[8] } elseif ($number[9] -ge 2) { $element.DefaultValue = $number[9] -eq 3 }
            $element.ValueType = $types[$number[0]]
            $element.Required = $number[1]
            $element.Soft = $number[2]
            $element.StoreAsText = $number[3]
            $element.Expandable = $number[4]
            $element.HasValuePrefix = $number[5]
            $element.Additive = $number[6]
            $element.ExplicitValue = $number[7]
            $element.NoSort = $number[8]
            if ($number[10] -ge 0) { $element.TrueValue = $values[$number[10]] }
            if ($number[11] -ge 0) { $element.FalseValue = $values[$number[11]] }
            $element.MinValue = $size[0]
            $element.MaxValue = $size[1]
            $element.MaxLength = $size[2]
            $element.MaxStrings = $size[3]
            $element.SpinStep = $size[4]
            if ($list[0].Count) { $element.TrueList = @(foreach ($index in $list[0]) { $values[$index] }) }
            if ($list[1].Count) { $element.FalseList = @(foreach ($index in $list[1]) { $values[$index] }) }
            if ($list[2].Count) {
                $element.Items = @(foreach ($index in $list[2]) {
                        $item = [GPOToolsEnumItem]::new()
                        $itemRow = $itemRows[$index]
                        $itemValue = $itemValues[$index]
                        if ($null -ne $itemRow[0]) { $item.DisplayName = $itemRow[0] }
                        if ($null -ne $itemRow[1]) { $item.DisplayNameRef = $itemRow[1] }
                        if ($itemValue[0] -ge 0) { $item.Value = $values[$itemValue[0]] }
                        $item.ValueList = @(for ($j = 1; $j -lt $itemValue.Count; $j++) { $values[$itemValue[$j]] })
                        $item
                    })
            }
            $elements[$i] = $element
        }

        foreach ($row in $content.SupportedOn) {
            $support = [GPOToolsSupportedOn]::new()
            if ($null -ne $row[0]) { $support.Name = $row[0] }
            if ($null -ne $row[1]) { $support.DisplayName = $row[1] }
            [GPOToolsUtility]::SupportOnTable.Add($support)
        }

        $targets = @{}
        $rows = $content.CategoryText
        $categories = [GPOToolsCategory[]]::new($rows.Count)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            $category = [GPOToolsCategory]::new()
            if ($null -ne $row[0]) { $category.Name = $row[0] }
            if ($null -ne $row[1]) { $category.DisplayName = $row[1] }
            if ($null -ne $row[2]) { $category.ExplainText = $row[2] }
            $key = "$($row[3])|$($row[4])"
            if (-not $targets.ContainsKey($key)) {
                $target = [AdmxNamespace]::new()
                if ($null -ne $row[3]) { $target.prefix = $row[3] }
                if ($null -ne $row[4]) { $target.namespace = $row[4] }
                $targets[$key] = $target
            }
            $category.target = $targets[$key]
            $categories[$i] = $category
        }
        for ($i = 0; $i -lt $categories.Count; $i++) {
            $parent = $content.CategoryParent[$i]
            if ($parent -ge 0) { $categories[$i].ParentCategory = $categories[$parent] }
            [GPOToolsUtility]::AddCategory($categories[$i])
        }

        $layoutRows = $content.Layout
        $layouts = [object[]]::new($layoutRows.Count)
        $rows = $content.PolicyText
        $numbers = $content.PolicyNumber
        $lists = $content.PolicyList
        $policies = [GPOToolsPolicy[]]::new($rows.Count)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            $number = $numbers[$i]
            $list = $lists[$i]
            $policy = [GPOToolsPolicy]::new()
            if ($null -ne $row[0]) { $policy.ID = $row[0] }
            if ($null -ne $row[1]) { $policy.Name = $row[1] }
            if ($null -ne $row[2]) { $policy.DisplayName = $row[2] }
            if ($null -ne $row[3]) { $policy.Description = $row[3] }
            if ($null -ne $row[4]) { $policy.Class = $row[4] }
            if ($null -ne $row[5]) { $policy.FileName = $row[5] }
            if ($null -ne $row[6]) { $policy.Path = $row[6] }
            if ($null -ne $row[7]) { $policy.RegistryKey = $row[7] }
            $registry = [GPOToolsRegistry]::new()
            $registry.Path = $row[8]
            $registry.Key = $row[9]
            $registry.Value = @{ Enable = $row[10]; Disable = $row[11] }
            $policy.Registry = $registry
            $policy.Scope = $number[0]
            if ($number[1] -ge 0) { $policy.Category = $categories[$number[1]] }
            if ($number[2] -ge 0) {
                if ($null -eq $layouts[$number[2]]) {
                    $layoutRow = $layoutRows[$number[2]]
                    $layouts[$number[2]] = @(for ($j = 0; $j -lt $layoutRow.Count; $j += 3) { @{ RefId = $layoutRow[$j]; Control = $layoutRow[$j + 1]; Label = $layoutRow[$j + 2] } })
                }
                $policy.Layout = $layouts[$number[2]]
            }
            if ($list[0].Count) { $policy.EnabledValues = @(foreach ($index in $list[0]) { $values[$index] }) }
            if ($list[1].Count) { $policy.DisabledValues = @(foreach ($index in $list[1]) { $values[$index] }) }
            if ($list[2].Count) { $policy.Elements = @(foreach ($index in $list[2]) { $elements[$index] }) }
            $policies[$i] = $policy
        }
        [GPOToolsUtility]::Policies.AddRange($policies)

        foreach ($namespace in $content.TargetLoad) { $null = [GPOToolsUtility]::TargetLoad.Add($namespace) }
        foreach ($file in $content.SkippedFiles) { [GPOToolsUtility]::SkippedFiles.Add($file) }
        foreach ($row in $content.NamespaceByFile) { [GPOToolsUtility]::NamespaceByFile[$row[0]] = $row[1] }
        Write-Verbose "ADMX files read from the cache $($Entry.File)."
        @{ Warnings = @($content.Warnings) }
    } catch {
        # A file cut short, or of another version: the ADMX files are read again.
        Write-Verbose "ADMX cache $($Entry.File) ignored: $($_.Exception.Message)"
        [GPOToolsUtility]::RemoveAll()
        $null
    }
}
