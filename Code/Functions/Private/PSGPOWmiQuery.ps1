<#
    The WQL queries of the WMI filters, for the WMI filter creator (Show-WmiFilterCreatorAvalonia):
    the catalog of Resources/WmiFilters.json (the namespaces, the classes and their properties for
    the query builder, the ready-made queries), the check of the syntax of a query, the literals
    and the conditions of WQL, and the test of the queries on a computer.

    A ready-made query holds its parameters as {Name} in its text: a Text parameter is written in a
    WQL string (the query has its quotes), a Number one as a number (times its Multiplier: GB in
    bytes), a Choice one as the Value of the choice.
#>

function Get-PSGPOWmiCatalog {
    [CmdletBinding()]
    param()

    if (-not $script:PSGPOWmiCatalog) {
        $path = Join-Path $PSScriptRoot 'Resources' 'WmiFilters.json'
        $script:PSGPOWmiCatalog = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    $script:PSGPOWmiCatalog
}

# The text of a WQL string literal: \ and ' escaped, between single quotes.
function ConvertTo-PSGPOWqlString {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string]$Text)

    "'" + "$Text".Replace('\', '\\').Replace("'", "\'") + "'"
}

# The query of a ready-made query, its parameters given by name ($Values; the default of a
# parameter otherwise); a value that is not right throws.
function New-PSGPOWmiTemplateQuery {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Template,
        [hashtable]$Values = @{}
    )

    $query = $Template.Query
    foreach ($parameter in @($Template.Parameters)) {
        if (-not $parameter) { continue }
        $value = if ($Values.ContainsKey($parameter.Name)) { "$($Values[$parameter.Name])".Trim() } else { "$($parameter.Default)" }
        if ($value -eq '') { throw (Get-PSGPOText 'Give a value to {0}.' (Get-PSGPOText $parameter.Label)) }
        $text = switch ($parameter.Kind) {
            'Number' {
                $number = 0.0
                if (-not [double]::TryParse($value.Replace(',', '.'), [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$number) -or $number -lt 0) {
                    throw (Get-PSGPOText '{0} is a number: {1} is not one.' (Get-PSGPOText $parameter.Label) $value)
                }
                $multiplier = if ($parameter.Multiplier) { [double]$parameter.Multiplier } else { 1 }
                ([decimal][math]::Round($number * $multiplier)).ToString([cultureinfo]::InvariantCulture)
            }
            'Choice' {
                $choice = @($parameter.Choices | Where-Object { $_.Value -eq $value -or $_.Text -eq $value }) | Select-Object -First 1
                if (-not $choice) { throw (Get-PSGPOText '{0} is not a choice of {1}.' $value (Get-PSGPOText $parameter.Label)) }
                "$($choice.Value)"
            }
            default {
                # Inside the quotes of the query.
                $value.Replace('\', '\\').Replace("'", "\'")
            }
        }
        $query = $query.Replace("{$($parameter.Name)}", $text)
    }
    $query
}

# A condition of the query builder: a property, its operator, a value written as its type wants
# it (String quoted, Number checked, Boolean TRUE or FALSE).
function New-PSGPOWqlCondition {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Property,
        [ValidateSet('String', 'Number', 'Boolean')] [string]$Type = 'String',
        [Parameter(Mandatory)] [ValidateSet('=', '<>', '<', '<=', '>', '>=', 'LIKE', 'NOT LIKE', 'IS NULL', 'IS NOT NULL')] [string]$Operator,
        [AllowNull()] [AllowEmptyString()] [string]$Value
    )

    if ($Operator -in 'IS NULL', 'IS NOT NULL') { return "$Property $Operator" }
    $Value = "$Value".Trim()
    if ($Operator -in 'LIKE', 'NOT LIKE') {
        if ($Operator -eq 'NOT LIKE') { return "NOT $Property LIKE $(ConvertTo-PSGPOWqlString $Value)" }
        return "$Property LIKE $(ConvertTo-PSGPOWqlString $Value)"
    }
    $literal = switch ($Type) {
        'Number' {
            $number = 0.0
            if (-not [double]::TryParse($Value.Replace(',', '.'), [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$number)) {
                throw (Get-PSGPOText '{0} is a number: {1} is not one.' $Property $Value)
            }
            ([decimal]$number).ToString([cultureinfo]::InvariantCulture)
        }
        'Boolean' {
            if ($Value -in 'TRUE', '1', 'Yes', 'Oui', (Get-PSGPOText 'True')) { 'TRUE' }
            elseif ($Value -in 'FALSE', '0', 'No', 'Non', (Get-PSGPOText 'False')) { 'FALSE' }
            else { throw (Get-PSGPOText '{0} is TRUE or FALSE: {1} is neither.' $Property $Value) }
        }
        default { ConvertTo-PSGPOWqlString $Value }
    }
    "$Property $Operator $literal"
}

# The tokens of a WQL query: Kind Word, String, Number or Symbol, Value, Position.
function Get-PSGPOWqlToken {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Query)

    $i = 0
    while ($i -lt $Query.Length) {
        $c = $Query[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        $start = $i
        if ($c -eq "'" -or $c -eq '"') {
            $builder = [System.Text.StringBuilder]::new()
            $i++
            while ($true) {
                if ($i -ge $Query.Length) { throw (Get-PSGPOText 'The string at position {0} is not closed.' ($start + 1)) }
                if ($Query[$i] -eq '\' -and $i + 1 -lt $Query.Length) { [void]$builder.Append($Query[$i + 1]); $i += 2; continue }
                if ($Query[$i] -eq $c) { $i++; break }
                [void]$builder.Append($Query[$i])
                $i++
            }
            [pscustomobject]@{ Kind = 'String'; Value = $builder.ToString(); Position = $start + 1 }
            continue
        }
        $match = [regex]::Match($Query.Substring($i), '^(0[xX][0-9a-fA-F]+|-?\d+(\.\d+)?)')
        if ($match.Success) {
            $i += $match.Length
            [pscustomobject]@{ Kind = 'Number'; Value = $match.Value; Position = $start + 1 }
            continue
        }
        $match = [regex]::Match($Query.Substring($i), '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*')
        if ($match.Success) {
            $i += $match.Length
            [pscustomobject]@{ Kind = 'Word'; Value = $match.Value; Position = $start + 1 }
            continue
        }
        $match = [regex]::Match($Query.Substring($i), '^(<>|!=|<=|>=|=|<|>|\(|\)|,|\*)')
        if ($match.Success) {
            $i += $match.Length
            [pscustomobject]@{ Kind = 'Symbol'; Value = $match.Value; Position = $start + 1 }
            continue
        }
        throw (Get-PSGPOText "The character '{0}' at position {1} has no meaning in WQL." $c ($start + 1))
    }
}

# The check of the syntax of a WQL query, as a WMI filter holds it: SELECT * (or properties) FROM
# a class, WHERE conditions joined by AND, OR, NOT and parentheses, a condition comparing a
# property with a value (=, <>, <, >, <=, >=, LIKE, IS [NOT] NULL, ISA). IsValid, Error, Class,
# Properties (those of the conditions) and Warning (the class of the catalog warns about).
function Test-PSGPOWqlSyntax {
    [CmdletBinding()]
    param(
        [AllowNull()] [AllowEmptyString()] [string]$Query,
        [string]$Namespace = 'root\CIMv2'
    )

    $result = [pscustomobject]@{ IsValid = $false; Error = $null; Class = $null; Properties = @(); Warning = $null }
    $Query = "$Query".Trim()
    if (-not $Query) { $result.Error = Get-PSGPOText 'The query is empty.'; return $result }
    if ($Query -match '^(ASSOCIATORS|REFERENCES)\s+OF\b') {
        $result.IsValid = $true
        $result.Warning = Get-PSGPOText 'ASSOCIATORS OF and REFERENCES OF queries are not checked: test them on a computer.'
        return $result
    }
    try {
        $tokens = @(Get-PSGPOWqlToken -Query $Query)
        $state = @{ Index = 0; Properties = [System.Collections.Generic.List[string]]::new() }
        $keywords = 'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'IS', 'NULL', 'LIKE', 'ISA', 'TRUE', 'FALSE'
        $peek = { if ($state.Index -lt $tokens.Count) { $tokens[$state.Index] } }
        $isWord = { param($Token, [string]$Word) $Token -and $Token.Kind -eq 'Word' -and $Token.Value -eq $Word }
        $isSymbol = { param($Token, [string]$Symbol) $Token -and $Token.Kind -eq 'Symbol' -and $Token.Value -eq $Symbol }
        $describe = { param($Token) if ($Token) { Get-PSGPOText "'{0}' at position {1}" $Token.Value $Token.Position } else { Get-PSGPOText 'the end of the query' } }
        $expect = {
            param([string]$Word)
            $token = & $peek
            if (-not (& $isWord $token $Word)) { throw (Get-PSGPOText '{0} expected, not {1}.' $Word (& $describe $token)) }
            $state.Index++
        }
        $readName = {
            param([string]$What)
            $token = & $peek
            if (-not $token -or $token.Kind -ne 'Word' -or $token.Value -in $keywords) { throw (Get-PSGPOText '{0} expected, not {1}.' $What (& $describe $token)) }
            $state.Index++
            $token.Value
        }
        $isLiteral = { param($Token) $Token -and ($Token.Kind -in 'String', 'Number' -or ($Token.Kind -eq 'Word' -and $Token.Value -in 'TRUE', 'FALSE', 'NULL')) }
        $readExpression = $null
        $readComparison = {
            $left = & $peek
            if (& $isSymbol $left '(') {
                $state.Index++
                & $readExpression
                $close = & $peek
                if (-not (& $isSymbol $close ')')) { throw (Get-PSGPOText '{0} expected, not {1}.' ')' (& $describe $close)) }
                $state.Index++
                return
            }
            if (& $isWord $left 'NOT') { $state.Index++; & $readComparison; return }
            $leftIsProperty = $left -and $left.Kind -eq 'Word' -and $left.Value -notin $keywords
            if (-not $leftIsProperty -and -not (& $isLiteral $left)) { throw (Get-PSGPOText 'A condition expected, not {0}.' (& $describe $left)) }
            $state.Index++
            $operator = & $peek
            if (& $isWord $operator 'IS') {
                if (-not $leftIsProperty) { throw (Get-PSGPOText 'A property expected before IS, not {0}.' (& $describe $left)) }
                $state.Index++
                if (& $isWord (& $peek) 'NOT') { $state.Index++ }
                & $expect 'NULL'
                $state.Properties.Add($left.Value)
                return
            }
            if (& $isWord $operator 'NOT') { $state.Index++; $operator = & $peek; if (-not (& $isWord $operator 'LIKE')) { throw (Get-PSGPOText '{0} expected, not {1}.' 'LIKE' (& $describe $operator)) } }
            if ((& $isWord $operator 'LIKE') -or (& $isWord $operator 'ISA')) {
                if (-not $leftIsProperty) { throw (Get-PSGPOText 'A property expected before {0}, not {1}.' $operator.Value (& $describe $left)) }
                $state.Index++
                $value = & $peek
                if (-not $value -or $value.Kind -ne 'String') { throw (Get-PSGPOText 'A string expected after {0}, not {1}.' $operator.Value (& $describe $value)) }
                $state.Index++
                $state.Properties.Add($left.Value)
                return
            }
            if (-not $operator -or $operator.Kind -ne 'Symbol' -or $operator.Value -notin '=', '<>', '!=', '<', '<=', '>', '>=') {
                throw (Get-PSGPOText 'An operator (=, <>, <, >, <=, >=, LIKE, IS NULL) expected, not {0}.' (& $describe $operator))
            }
            $state.Index++
            $right = & $peek
            $rightIsProperty = $right -and $right.Kind -eq 'Word' -and $right.Value -notin $keywords
            if (-not $rightIsProperty -and -not (& $isLiteral $right)) { throw (Get-PSGPOText 'A value expected after {0}, not {1}.' $operator.Value (& $describe $right)) }
            if ($leftIsProperty -eq $rightIsProperty) {
                throw (Get-PSGPOText 'A condition compares a property with a value: {0} {1} {2}.' $left.Value $operator.Value $right.Value)
            }
            $state.Index++
            $state.Properties.Add($(if ($leftIsProperty) { $left.Value } else { $right.Value }))
        }
        $readAnd = {
            & $readComparison
            while (& $isWord (& $peek) 'AND') { $state.Index++; & $readComparison }
        }
        $readExpression = {
            & $readAnd
            while (& $isWord (& $peek) 'OR') { $state.Index++; & $readAnd }
        }

        & $expect 'SELECT'
        if (& $isSymbol (& $peek) '*') { $state.Index++ }
        else {
            $null = & $readName (Get-PSGPOText 'A property or *')
            while (& $isSymbol (& $peek) ',') { $state.Index++; $null = & $readName (Get-PSGPOText 'A property') }
        }
        & $expect 'FROM'
        $result.Class = & $readName (Get-PSGPOText 'A class')
        if ($state.Index -lt $tokens.Count) {
            & $expect 'WHERE'
            & $readExpression
            if ($state.Index -lt $tokens.Count) { throw (Get-PSGPOText 'The query should end before {0}.' (& $describe (& $peek))) }
        }
        $result.Properties = @($state.Properties)
        $result.IsValid = $true
    } catch {
        $result.Error = $_.Exception.Message
        return $result
    }
    $class = @((Get-PSGPOWmiCatalog).Classes | Where-Object { $_.Name -eq $result.Class }) | Select-Object -First 1
    if ($class -and $class.Warning) { $result.Warning = Get-PSGPOText $class.Warning }
    if ($class -and $class.Namespace -ne $Namespace -and "$Namespace".Trim()) {
        $result.Warning = Get-PSGPOText 'The class {0} is in the namespace {1}, not {2}.' $class.Name $class.Namespace $Namespace
    }
    $result
}

# The test of WQL queries on a computer, as a computer evaluates a WMI filter: each query that
# returns at least one instance is True; an error (a namespace or a class the computer does not
# have) is False. Result (Match, NoMatch, Error), Error. Self-contained: the WMI filter creator
# runs it in a runspace of its own.
function Invoke-PSGPOWmiQueryTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]]$Query,
        [string]$ComputerName,
        [pscredential]$Credential
    )

    $session = $null
    $cim = @{ ErrorAction = 'Stop'; Verbose = $false }
    try {
        if ($ComputerName) {
            $options = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
            if ($Credential) { $options.Credential = $Credential }
            $session = New-CimSession @options
            $cim.CimSession = $session
        }
        foreach ($item in $Query) {
            $namespace = if ("$($item.Namespace)".Trim()) { "$($item.Namespace)".Trim() } else { 'root\CIMv2' }
            $row = [pscustomobject]@{ Namespace = $namespace; Query = "$($item.Query)"; Result = 'NoMatch'; Error = $null }
            try {
                $found = @(Get-CimInstance -Namespace $namespace -Query $row.Query @cim | Select-Object -First 1)
                if ($found.Count) { $row.Result = 'Match' }
            } catch {
                $row.Result = 'Error'
                $row.Error = $_.Exception.GetBaseException().Message.Trim()
            }
            $row
        }
    } finally {
        if ($session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
    }
}
