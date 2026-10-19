<#
    The texts of the interface, as the code has them (the keys of Resources/Strings/<culture>.psd1):
    the constant first argument of each Get-PSGPOText call (or of $T, the same command in the
    closures of the configuration window), the strings an if or an array gives it, and the texts
    of the attributes of the XAML that ConvertTo-PSGPOLocalizedXaml translates. A key given by a
    value (Get-PSGPOText $state) is not found here: the tests list those.
#>
function Get-PSGPOTextKey {
    param([Parameter(Mandatory)] [string]$Path)

    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.ps1' -Recurse) {
        $tokens = $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        $calls = $ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and (
                    $Node.GetCommandName() -eq 'Get-PSGPOText' -or
                    ($Node.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and $Node.CommandElements[0].VariablePath.UserPath -eq 'T'))
            }, $true)
        # The names of the rows of the details (New-Row translates them, but with -Name).
        foreach ($row in $ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'New-Row' }, $true)) {
            $name = $row.CommandElements[1]
            $named = @($row.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Name' }).Count
            if (-not $named -and $name -is [System.Management.Automation.Language.StringConstantExpressionAst]) { [void]$keys.Add($name.Value) }
        }
        foreach ($call in $calls) {
            if ($call.CommandElements.Count -lt 2) { continue }
            $argument = $call.CommandElements[1]
            # The strings the argument outputs: itself, or what an if, a subexpression or an array gives.
            $strings = @($argument) + @($argument.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
            foreach ($string in $strings) {
                if ($string -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -and $string -isnot [System.Management.Automation.Language.ExpandableStringExpressionAst]) { continue }
                if ($string -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and $string.NestedExpressions.Count) { continue }
                $parent = $string.Parent
                $output = [object]::ReferenceEquals($string, $argument) -or $parent -is [System.Management.Automation.Language.CommandExpressionAst] -or
                    $parent -is [System.Management.Automation.Language.ArrayLiteralAst]
                if ($output -and $string.Value) { [void]$keys.Add($string.Value) }
            }
        }
        # The XAML of the windows: the same attributes as ConvertTo-PSGPOLocalizedXaml.
        $text = [System.IO.File]::ReadAllText($file.FullName)
        if ($text -notmatch '<Window\b|<Grid\b|<StackPanel\b') { continue }
        foreach ($match in [regex]::Matches($text, "\b(Header|Text|Content|Watermark|PlaceholderText|ToolTip\.Tip|Title)='([^'{]*)'")) {
            # A $ of an expandable here-string is written `$.
            $value = [System.Net.WebUtility]::HtmlDecode($match.Groups[2].Value.Replace('`$', '$'))
            if ($value -and $value -notmatch '^\$|\$\(') { [void]$keys.Add($value) }
        }
    }
    , $keys
}
