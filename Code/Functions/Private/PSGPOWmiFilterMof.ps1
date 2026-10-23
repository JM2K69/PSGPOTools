<#
    WMI filters as GPMC exports and imports them: a .mof file, UTF-16 LE with a BOM, holding an
    instance of MSFT_SomFilter (root\policy) whose Rules are instances of MSFT_Rule, the
    properties in alphabetical order, as Windows writes the text of the instance:

        instance of MSFT_SomFilter
        {
            Author = "CONTOSO\\Administrator";
            ChangeDate = "20261023183621.776344-000";
            CreationDate = "20261023183621.776344-000";
            Description = "Workstations \"Windows 11\"";
            Domain = "contoso.com";
            ID = "{CC133ED0-FA13-4196-841E-A087FE197F36}";
            Name = "Workstations";
            Rules = {
        instance of MSFT_Rule
        {
            Query = "SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1";
            QueryLanguage = "WQL";
            TargetNameSpace = "root\\CIMv2";
        }};
        };

    The reading takes the MOF syntax more widely: comments, #pragma lines, any order of the
    properties, strings put together ("a" "b"), values without quotes, several filters.
#>

# A MOF string literal of a text: \ and " escaped, the control characters as MOF escapes.
function ConvertTo-PSGPOMofString {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string]$Text)

    $builder = [System.Text.StringBuilder]::new('"')
    foreach ($char in "$Text".ToCharArray()) {
        switch ($char) {
            '\' { [void]$builder.Append('\\') }
            '"' { [void]$builder.Append('\"') }
            "`n" { [void]$builder.Append('\n') }
            "`r" { [void]$builder.Append('\r') }
            "`t" { [void]$builder.Append('\t') }
            default { [void]$builder.Append($char) }
        }
    }
    [void]$builder.Append('"')
    $builder.ToString()
}

# The text of a .mof file of a WMI filter of $Domain, as GPMC exports it (lines ending with CRLF).
function ConvertTo-PSGPOWmiFilterMof {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsWmiFilter]$Filter,
        [Parameter(Mandatory)] [string]$Domain
    )

    $created = if ($Filter.CreationDate) { $Filter.CreationDate } else { [GPOToolsWmiFilter]::GetDate() }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('')
    $lines.Add('instance of MSFT_SomFilter')
    $lines.Add('{')
    if ($Filter.Author) { $lines.Add("`tAuthor = $(ConvertTo-PSGPOMofString $Filter.Author);") }
    $lines.Add("`tChangeDate = $(ConvertTo-PSGPOMofString $(if ($Filter.ChangeDate) { $Filter.ChangeDate } else { $created }));")
    $lines.Add("`tCreationDate = $(ConvertTo-PSGPOMofString $created);")
    if ($Filter.Description) { $lines.Add("`tDescription = $(ConvertTo-PSGPOMofString $Filter.Description);") }
    $lines.Add("`tDomain = $(ConvertTo-PSGPOMofString $Domain);")
    $lines.Add("`tID = $(ConvertTo-PSGPOMofString ('{' + $Filter.Id.ToString().ToUpperInvariant() + '}'));")
    $lines.Add("`tName = $(ConvertTo-PSGPOMofString $Filter.Name);")
    $lines.Add("`tRules = {")
    $queries = @($Filter.Queries)
    for ($i = 0; $i -lt $queries.Count; $i++) {
        $lines.Add('instance of MSFT_Rule')
        $lines.Add('{')
        $lines.Add("`tQuery = $(ConvertTo-PSGPOMofString $queries[$i].Query);")
        $lines.Add("`tQueryLanguage = `"WQL`";")
        $lines.Add("`tTargetNameSpace = $(ConvertTo-PSGPOMofString $queries[$i].Namespace);")
        # '}, ' between two rules, its space included, as Windows writes it.
        $lines.Add($(if ($i -lt $queries.Count - 1) { '}, ' } else { '}};' }))
    }
    $lines.Add('};')
    ($lines -join "`r`n") + "`r`n"
}

# The bytes of a .mof file of a WMI filter: UTF-16 LE with its BOM, as GPMC writes it.
function ConvertTo-PSGPOWmiFilterMofByte {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)] [GPOToolsWmiFilter]$Filter,
        [Parameter(Mandatory)] [string]$Domain
    )

    $encoding = [System.Text.Encoding]::Unicode
    , [byte[]](@($encoding.GetPreamble()) + @($encoding.GetBytes((ConvertTo-PSGPOWmiFilterMof -Filter $Filter -Domain $Domain))))
}

# Name of the .mof file of a WMI filter: its name, without the characters a file name cannot hold.
function Get-PSGPOWmiFilterFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Name)

    $file = ("$Name".Trim() -replace '[\\/:*?"<>|\x00-\x1F]', '_').TrimEnd('.', ' ')
    if (-not $file) { $file = 'WMI filter' }
    "$file.mof"
}

# The text of a .mof file: UTF-16 (LE or BE) or UTF-8 by its BOM, else UTF-16 LE when its
# second byte is 0 (no BOM), else UTF-8.
function ConvertFrom-PSGPOMofByte {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Bytes)

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) { return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2) }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3) }
    if ($Bytes.Length -ge 2 -and $Bytes[1] -eq 0) { return [System.Text.Encoding]::Unicode.GetString($Bytes) }
    [System.Text.Encoding]::UTF8.GetString($Bytes)
}

# The tokens of a MOF text: strings (Kind String, Value unescaped), the punctuation { } ( ) [ ] = ;
# , : (Kind Symbol), and the words, numbers and the rest (Kind Word); without the comments and the
# #pragma lines.
function Get-PSGPOMofToken {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)

    $i = 0
    $length = $Text.Length
    while ($i -lt $length) {
        $c = $Text[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq '/' -and $i + 1 -lt $length -and $Text[$i + 1] -eq '/') {
            while ($i -lt $length -and $Text[$i] -ne "`n") { $i++ }
            continue
        }
        if ($c -eq '/' -and $i + 1 -lt $length -and $Text[$i + 1] -eq '*') {
            $end = $Text.IndexOf('*/', $i + 2)
            if ($end -lt 0) { throw 'Not a MOF file: a comment /* is not closed.' }
            $i = $end + 2
            continue
        }
        if ($c -eq '#') {
            while ($i -lt $length -and $Text[$i] -ne "`n") { $i++ }
            continue
        }
        if ($c -eq '"') {
            $builder = [System.Text.StringBuilder]::new()
            $i++
            while ($true) {
                if ($i -ge $length) { throw 'Not a MOF file: a string is not closed.' }
                $c = $Text[$i]
                if ($c -eq '"') { $i++; break }
                if ($c -eq '\' -and $i + 1 -lt $length) {
                    $next = $Text[$i + 1]
                    $i += 2
                    switch -CaseSensitive ($next) {
                        'n' { [void]$builder.Append("`n") }
                        'r' { [void]$builder.Append("`r") }
                        't' { [void]$builder.Append("`t") }
                        'b' { [void]$builder.Append("`b") }
                        'f' { [void]$builder.Append("`f") }
                        { $_ -eq 'x' -or $_ -eq 'X' } {
                            $hex = [regex]::Match($Text.Substring($i), '^[0-9A-Fa-f]{1,4}').Value
                            if (-not $hex) { throw 'Not a MOF file: \x without its hexadecimal digits.' }
                            [void]$builder.Append([char][Convert]::ToInt32($hex, 16))
                            $i += $hex.Length
                        }
                        default { [void]$builder.Append($next) }
                    }
                    continue
                }
                [void]$builder.Append($c)
                $i++
            }
            [pscustomobject]@{ Kind = 'String'; Value = $builder.ToString() }
            continue
        }
        if ('{}()[]=;,:'.Contains($c)) {
            [pscustomobject]@{ Kind = 'Symbol'; Value = [string]$c }
            $i++
            continue
        }
        $start = $i
        while ($i -lt $length -and -not [char]::IsWhiteSpace($Text[$i]) -and -not '{}()[]=;,:"'.Contains($Text[$i])) { $i++ }
        [pscustomobject]@{ Kind = 'Word'; Value = $Text.Substring($start, $i - $start) }
    }
}

# The instances of a MOF text: Class and Properties (by name, case ignored; a value is a string,
# a list, or an instance), its qualifiers ignored.
function ConvertFrom-PSGPOMofInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)

    $tokens = @(Get-PSGPOMofToken -Text $Text)
    $state = @{ Index = 0 }
    $peek = { if ($state.Index -lt $tokens.Count) { $tokens[$state.Index] } }
    $take = {
        param([string]$Expected)
        $token = & $peek
        if (-not $token) { throw "Not a WMI filter: the MOF text ends before '$Expected'." }
        if ($Expected -and $token.Value -ne $Expected) { throw "Not a WMI filter: '$Expected' expected in the MOF text, not '$($token.Value)'." }
        $state.Index++
        $token
    }
    # [qualifiers]: skipped, brackets nested.
    $skipQualifiers = {
        while ((& $peek) -and (& $peek).Kind -eq 'Symbol' -and (& $peek).Value -eq '[') {
            $depth = 0
            do {
                $token = & $take
                if ($token.Kind -eq 'Symbol' -and $token.Value -eq '[') { $depth++ }
                elseif ($token.Kind -eq 'Symbol' -and $token.Value -eq ']') { $depth-- }
            } while ($depth -gt 0)
        }
    }
    $readInstance = $null
    $readValue = {
        $token = & $peek
        if (-not $token) { throw 'Not a WMI filter: the MOF text ends before a value.' }
        if ($token.Kind -eq 'Word' -and $token.Value -eq 'instance') { return , (& $readInstance) }
        if ($token.Kind -eq 'Symbol' -and $token.Value -eq '{') {
            $null = & $take '{'
            $items = [System.Collections.Generic.List[object]]::new()
            while (-not ((& $peek).Kind -eq 'Symbol' -and (& $peek).Value -eq '}')) {
                $items.Add((& $readValue))
                if ((& $peek).Kind -eq 'Symbol' -and (& $peek).Value -eq ',') { $null = & $take ',' }
            }
            $null = & $take '}'
            return , $items.ToArray()
        }
        if ($token.Kind -eq 'String') {
            # "a" "b" is one string.
            $builder = [System.Text.StringBuilder]::new()
            while ((& $peek) -and (& $peek).Kind -eq 'String') { [void]$builder.Append((& $take).Value) }
            return $builder.ToString()
        }
        if ($token.Kind -eq 'Word') { return (& $take).Value }
        throw "Not a WMI filter: a value expected in the MOF text, not '$($token.Value)'."
    }
    $readInstance = {
        & $skipQualifiers
        $null = & $take 'instance'
        $null = & $take 'of'
        $class = (& $take).Value
        if ((& $peek).Kind -eq 'Word' -and (& $peek).Value -eq 'as') { $null = & $take 'as'; $null = & $take }
        $null = & $take '{'
        $properties = [ordered]@{}
        while (-not ((& $peek).Kind -eq 'Symbol' -and (& $peek).Value -eq '}')) {
            & $skipQualifiers
            $name = & $take
            if ($name.Kind -ne 'Word') { throw "Not a WMI filter: a property name expected in the MOF text, not '$($name.Value)'." }
            $null = & $take '='
            $properties[$name.Value] = & $readValue
            $null = & $take ';'
        }
        $null = & $take '}'
        [pscustomobject]@{ Class = $class; Properties = $properties }
    }
    while ($state.Index -lt $tokens.Count) {
        & $skipQualifiers
        $token = & $peek
        if ($token.Kind -eq 'Word' -and $token.Value -eq 'instance') {
            & $readInstance
            if ((& $peek) -and (& $peek).Value -eq ';') { $null = & $take ';' }
        } else {
            throw "Not a WMI filter: 'instance of MSFT_SomFilter' expected in the MOF text, not '$($token.Value)'."
        }
    }
}

# The WMI filters of a .mof file (its bytes, or its text): Name, Description, Author, Domain, Id,
# CreationDate, ChangeDate and Queries (Namespace and Query), checked.
function ConvertFrom-PSGPOWmiFilterMof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Bytes')] [AllowEmptyCollection()] [byte[]]$Bytes,
        [Parameter(Mandatory, ParameterSetName = 'Text')] [AllowEmptyString()] [string]$Text
    )

    if ($PSCmdlet.ParameterSetName -eq 'Bytes') { $Text = ConvertFrom-PSGPOMofByte -Bytes $Bytes }
    $value = { param($Properties, [string]$Name) foreach ($key in $Properties.Keys) { if ($key -eq $Name) { return $Properties[$key] } } }
    $filters = @(foreach ($instance in @(ConvertFrom-PSGPOMofInstance -Text $Text)) {
            if ($instance.Class -ne 'MSFT_SomFilter') { throw "Not a WMI filter: the MOF text holds an instance of $($instance.Class), not of MSFT_SomFilter." }
            $properties = $instance.Properties
            $name = "$(& $value $properties 'Name')".Trim()
            if (-not $name) { throw 'Not a WMI filter: the MSFT_SomFilter of the MOF text has no Name.' }
            $queries = @(foreach ($rule in @(& $value $properties 'Rules')) {
                    if ($rule -isnot [pscustomobject] -or $rule.Class -ne 'MSFT_Rule') { throw "The WMI filter '$name' of the MOF text has a rule that is not an instance of MSFT_Rule." }
                    $language = "$(& $value $rule.Properties 'QueryLanguage')"
                    if ($language -and $language -ne 'WQL') { throw "The WMI filter '$name' of the MOF text has a rule in ${language}: only WQL is applied." }
                    $query = "$(& $value $rule.Properties 'Query')".Trim()
                    if (-not $query) { throw "The WMI filter '$name' of the MOF text has a rule without its query." }
                    $namespace = "$(& $value $rule.Properties 'TargetNameSpace')".Trim()
                    [pscustomobject]@{ Namespace = $(if ($namespace) { $namespace } else { 'root\CIMv2' }); Query = $query }
                })
            if (-not $queries.Count) { throw "The WMI filter '$name' of the MOF text has no query." }
            $id = [guid]::Empty
            $null = [guid]::TryParse("$(& $value $properties 'ID')".Trim('{', '}', ' '), [ref]$id)
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.WmiFilterMof'
                Name = $name
                Description = "$(& $value $properties 'Description')"
                Author = & $value $properties 'Author'
                Domain = & $value $properties 'Domain'
                Id = $id
                CreationDate = & $value $properties 'CreationDate'
                ChangeDate = & $value $properties 'ChangeDate'
                Queries = $queries
            }
        })
    if (-not $filters.Count) { throw 'Not a WMI filter: the MOF text holds no instance of MSFT_SomFilter.' }
    $filters
}
