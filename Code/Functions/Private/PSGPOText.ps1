<#
    Language of the interface of the console. The texts are written in English in the code and
    the XAML, and that English text is the key of its translation: Resources/Strings/<culture>.psd1
    maps it to the text of a language (fr-FR.psd1: 'Refresh' = 'Actualiser'). A text without
    translation shows in English, never empty. The language is the one Show-GPOManagerAvalonia
    is given (-Language), by default the language of the session; the commands, their messages and
    their errors stay in English, as those of PowerShell.

    A text with values takes them as -f does: Get-PSGPOText "GPO '{0}' created." $Name.
#>

$script:PSGPOLanguage = 'en-US'
$script:PSGPOTexts = $null

# The languages the interface has: en-US, and one per file of Resources/Strings.
function Get-PSGPOLanguage {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    'en-US'
    $folder = Join-Path $PSScriptRoot 'Resources' 'Strings'
    if (Test-Path -LiteralPath $folder) { Get-ChildItem -LiteralPath $folder -Filter '*.psd1' | ForEach-Object BaseName | Sort-Object }
}

# Sets the language of the interface: a culture (fr-FR), or a language (fr) that a file of
# Resources/Strings has; English when there is none. Returns the language set.
function Set-PSGPOLanguage {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string]$Language)

    $script:PSGPOLanguage = 'en-US'
    $script:PSGPOTexts = $null
    if (-not $Language) { return $script:PSGPOLanguage }
    $culture = $null
    try { $culture = [cultureinfo]::GetCultureInfo($Language) } catch { Write-Warning "Unknown language '$Language': the interface is in English."; return $script:PSGPOLanguage }
    # The culture, else another country of the same language (fr-CA: fr-FR).
    $available = @(Get-PSGPOLanguage | Where-Object { $_ -ne 'en-US' })
    $file = $available | Where-Object { $_ -eq $culture.Name } | Select-Object -First 1
    if (-not $file) { $file = $available | Where-Object { ([cultureinfo]::GetCultureInfo($_)).TwoLetterISOLanguageName -eq $culture.TwoLetterISOLanguageName } | Select-Object -First 1 }
    if (-not $file) { return $script:PSGPOLanguage }
    $script:PSGPOTexts = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    # The names of the catalogs (security settings, preferences: Resources/Strings/Catalogs), then
    # the texts of the interface, which win when both have a text. More than 500 texts: past the
    # limit of a data file without -SkipLimitCheck.
    foreach ($path in (Join-Path $PSScriptRoot 'Resources' 'Strings' 'Catalogs' "$file.psd1"), (Join-Path $PSScriptRoot 'Resources' 'Strings' "$file.psd1")) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $texts = Import-PowerShellDataFile -LiteralPath $path -SkipLimitCheck
        foreach ($key in $texts.Keys) { $script:PSGPOTexts[$key] = $texts[$key] }
    }
    $script:PSGPOLanguage = $file
    $file
}

# A text of the interface in its language; with -Argument, its values put in place ({0}, {1}...).
function Get-PSGPOText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)] [AllowEmptyString()] [string]$Text,
        [Parameter(Position = 1, ValueFromRemainingArguments)] [object[]]$Argument
    )

    $translated = $null
    if ($script:PSGPOTexts -and $Text -and $script:PSGPOTexts.TryGetValue($Text, [ref]$translated) -and $translated) { $Text = $translated }
    # Not "if ($Argument)": one value of 0 or empty would be false.
    if ($Argument.Count) { return $Text -f $Argument }
    $Text
}

# A text the console shows but that functions shared with the commands write in English (the
# Settings tab, the History tab): in the language of the interface, line by line. A line is
# translated whole, else by its parts: a path (Policies > Windows Settings > ...), a number and its
# unit (8 hours), a list (Success, Failure), a label and its value (Hive: HKEY_LOCAL_MACHINE), a
# note in brackets (Update (disabled)). What has no translation stays as it is (names, values).
function ConvertTo-PSGPODisplayText {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string]$Text)

    if (-not $script:PSGPOTexts -or -not $Text) { return $Text }
    $translate = {
        param([string]$Part)
        $translated = $null
        if ($Part -and $script:PSGPOTexts.TryGetValue($Part, [ref]$translated) -and $translated) { return $translated }
        if ($Part.Contains(' > ')) { return (@($Part -split ' > ' | ForEach-Object { & $translate $_ }) -join ' > ') }
        if ($Part -match '^(-?[\d.,]+) (.+)$' -and $script:PSGPOTexts.ContainsKey($Matches[2])) { return "$($Matches[1]) $($script:PSGPOTexts[$Matches[2]])" }
        if ($Part.Contains(', ')) {
            $items = @($Part -split ', ')
            if (@($items | Where-Object { $script:PSGPOTexts.ContainsKey($_) }).Count -eq $items.Count) { return (@($items | ForEach-Object { $script:PSGPOTexts[$_] }) -join ', ') }
        }
        if ($Part -match '^([^:]+): (.*)$' -and $script:PSGPOTexts.ContainsKey($Matches[1])) { return "$($script:PSGPOTexts[$Matches[1]]) : $(& $translate $Matches[2])" }
        if ($Part -match '^(.+) \(([^()]+)\)$' -and $script:PSGPOTexts.ContainsKey("($($Matches[2]))")) { return "$(& $translate $Matches[1]) $($script:PSGPOTexts["($($Matches[2]))"])" }
        $Part
    }
    @($Text -split '\r?\n' | ForEach-Object { & $translate $_ }) -join [Environment]::NewLine
}

# The XAML of a window with its texts in the language of the interface: the values of its Header,
# Text, Content, Watermark, PlaceholderText, ToolTip.Tip and Title attributes, but the bindings ({...}).
function ConvertTo-PSGPOLocalizedXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Xaml)

    if (-not $script:PSGPOTexts) { return $Xaml }
    [regex]::Replace($Xaml, "\b(Header|Text|Content|Watermark|PlaceholderText|ToolTip\.Tip|Title)='([^'{]*)'", {
            param($Match)
            $text = [System.Net.WebUtility]::HtmlDecode($Match.Groups[2].Value)
            "$($Match.Groups[1].Value)='$([System.Security.SecurityElement]::Escape((Get-PSGPOText $text)))'"
        })
}
