<#
    .SYNOPSIS
        Writes the page of each public command on the documentation site, from its help.
    .DESCRIPTION
        For each command the module exports, docs/<language>/reference/commands/<command>.md (en and
        fr: the headings in the language of the site, the help as the command has it, in English):
        its synopsis, syntax, description, parameters, examples, outputs and related commands. The
        menu of the site (zensical.toml, zensical.fr.toml) lists the pages, and the table of
        reference/commands.md links each command to its page. The first .LINK of the help of each
        command is the address of its page: Get-Help <command> -Online opens it.

        Run it after a change of the help of a command (the build first: CI/03_Build.ps1); the tests
        (PSGPOTools.Public.tests.ps1) check that the pages are those of the help.
    .PARAMETER OutputPath
        Writes the pages only, in <OutputPath>/<language>, not the menu nor the table (for the tests).
    .EXAMPLE
        ./CI/03_Build.ps1; ./CI/Update-CommandReference.ps1
#>
[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$site = 'https://jm2k69.github.io/PSGPOTools'
$manifest = Join-Path $root 'HGPM' 'HGPM.psd1'
Import-Module $manifest -Force
$module = Get-Module HGPM
$names = @($module.ExportedFunctions.Keys | Sort-Object)

$text = @{
    en = @{ Syntax = 'Syntax'; Description = 'Description'; Parameters = 'Parameters'; Examples = 'Examples'; Example = 'Example'; Outputs = 'Outputs'; Related = 'Related'
        Type = 'Type'; Required = 'Required'; Position = 'Position'; Default = 'Default value'; Pipeline = 'Accepts pipeline input'; Yes = 'Yes'; No = 'No'; Named = 'Named'
        Note = 'The help of the command, as `Get-Help {0} -Full` gives it.'; All = 'All the commands'; Menu = 'Commands'; None = 'None' }
    fr = @{ Syntax = 'Syntaxe'; Description = 'Description'; Parameters = 'Paramètres'; Examples = 'Exemples'; Example = 'Exemple'; Outputs = 'Sorties'; Related = 'Voir aussi'
        Type = 'Type'; Required = 'Obligatoire'; Position = 'Position'; Default = 'Valeur par défaut'; Pipeline = 'Accepte le pipeline'; Yes = 'Oui'; No = 'Non'; Named = 'Nommé'
        Note = "L'aide de la commande, telle que ``Get-Help {0} -Full`` la donne (en anglais)."; All = 'Toutes les commandes'; Menu = 'Commandes'; None = 'Aucune' }
}

# The address of the page of a command on the site, as its help links to it.
function Get-CommandPageName { param([string]$Name) $Name.ToLowerInvariant() }

# A text of the help: its paragraphs, the lines of a paragraph joined (comment-based help keeps the
# line breaks of the source), the lists and the indented lines kept.
function ConvertTo-HelpMarkdown {
    param([string]$Value)
    $paragraphs = foreach ($block in @("$Value".Trim() -split '\r?\n\s*\r?\n')) {
        $lines = @($block -split '\r?\n' | ForEach-Object { $_.TrimEnd() })
        if (@($lines | Where-Object { $_ -match '^\s+\S' -or $_ -match '^\s*[-*] ' }).Count -gt 1) { ($lines | ForEach-Object { $_.Trim() }) -join "`n" }
        else { ($lines | ForEach-Object { $_.Trim() }) -join ' ' }
    }
    ($paragraphs | Where-Object { $_ }) -join "`n`n"
}

function ConvertTo-CommandPage {
    param([string]$Name, [string]$Language)
    $t = $text[$Language]
    $help = Get-Help -Name $Name -Full
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# $Name")
    $lines.Add('')
    $lines.Add((ConvertTo-HelpMarkdown $help.Synopsis))
    $lines.Add('')
    $lines.Add("_$($t.Note -f $Name)_")
    $lines.Add('')
    $lines.Add("## $($t.Syntax)")
    $lines.Add('')
    $lines.Add('```powershell')
    foreach ($syntax in @((Get-Command -Name $Name -Syntax) -split '\r?\n' | Where-Object { $_.Trim() })) { $lines.Add($syntax.Trim()) }
    $lines.Add('```')
    $description = ConvertTo-HelpMarkdown (@($help.description | ForEach-Object Text) -join "`n`n")
    if ($description) {
        $lines.Add('')
        $lines.Add("## $($t.Description)")
        $lines.Add('')
        $lines.Add($description)
    }
    $parameters = @($help.parameters.parameter | Where-Object { $_.name })
    if ($parameters.Count) {
        $lines.Add('')
        $lines.Add("## $($t.Parameters)")
        foreach ($parameter in $parameters) {
            $lines.Add('')
            $lines.Add("### -$($parameter.name)")
            $lines.Add('')
            $about = ConvertTo-HelpMarkdown (@($parameter.description | ForEach-Object Text) -join "`n`n")
            if ($about) { $lines.Add($about); $lines.Add('') }
            $position = if ($parameter.position -match '^\d+$') { $parameter.position } else { $t.Named }
            $default = if ("$($parameter.defaultValue)".Trim() -and $parameter.defaultValue -notin 'None', 'False') { "``$($parameter.defaultValue)``" } else { $t.None }
            $pipeline = if ("$($parameter.pipelineInput)" -match '^true') { $t.Yes } else { $t.No }
            $lines.Add("| $($t.Type) | $($t.Required) | $($t.Position) | $($t.Default) | $($t.Pipeline) |")
            $lines.Add('|---|---|---|---|---|')
            $lines.Add("| ``$($parameter.type.name)`` | $(if ($parameter.required -eq 'true') { $t.Yes } else { $t.No }) | $position | $default | $pipeline |")
        }
    }
    $examples = @($help.examples.example | Where-Object { $_.code })
    if ($examples.Count) {
        $lines.Add('')
        $lines.Add("## $($t.Examples)")
        $number = 0
        foreach ($example in $examples) {
            $number++
            $lines.Add('')
            $lines.Add("### $($t.Example) $number")
            $lines.Add('')
            $lines.Add('```powershell')
            $lines.Add("$($example.code)".Trim())
            $lines.Add('```')
            $remarks = ConvertTo-HelpMarkdown (@($example.remarks | ForEach-Object Text) -join "`n`n")
            if ($remarks) { $lines.Add(''); $lines.Add($remarks) }
        }
    }
    $outputs = @($help.returnValues.returnValue | ForEach-Object { "$($_.type.name)".Trim() } | Where-Object { $_ })
    if ($outputs.Count) {
        $lines.Add('')
        $lines.Add("## $($t.Outputs)")
        $lines.Add('')
        foreach ($output in $outputs) { $lines.Add("- ``$output``") }
    }
    # The related commands of the help (the first link is the page itself).
    $related = @($help.relatedLinks.navigationLink | ForEach-Object { "$($_.linkText)".Trim() } | Where-Object { $_ -and $names -contains $_ })
    $lines.Add('')
    $lines.Add("## $($t.Related)")
    $lines.Add('')
    foreach ($command in $related) { $lines.Add("- [$command]($(Get-CommandPageName $command).md)") }
    $lines.Add("- [$($t.All)](../commands.md)")
    ($lines -join "`n") + "`n"
}

foreach ($language in 'en', 'fr') {
    $folder = if ($OutputPath) { Join-Path $OutputPath $language } else { Join-Path $root 'docs' $language 'reference' 'commands' }
    $null = New-Item -ItemType Directory -Path $folder -Force
    foreach ($old in @(Get-ChildItem -LiteralPath $folder -Filter '*.md')) { if ($names -notcontains $old.BaseName -and @($names | Where-Object { (Get-CommandPageName $_) -eq $old.BaseName }).Count -eq 0) { Remove-Item -LiteralPath $old.FullName } }
    foreach ($name in $names) {
        [System.IO.File]::WriteAllText((Join-Path $folder "$(Get-CommandPageName $name).md"), (ConvertTo-CommandPage -Name $name -Language $language), [System.Text.UTF8Encoding]::new($false))
    }
    if ($OutputPath) { continue }

    # The menu of the site: the pages under Reference > Commands.
    $config = Join-Path $root $(if ($language -eq 'en') { 'zensical.toml' } else { 'zensical.fr.toml' })
    $menu = $text[$language].Menu
    $entries = ($names | ForEach-Object { "      ""reference/commands/$(Get-CommandPageName $_).md""," }) -join "`n"
    $block = "    # The pages of the commands, written by CI/Update-CommandReference.ps1.`n    { ""$menu"" = [`n$entries`n    ] },"
    $toml = [System.IO.File]::ReadAllText($config)
    $pattern = '(?s)    # The pages of the commands, written by CI/Update-CommandReference\.ps1\.\r?\n    \{ "[^"]+" = \[.*?\n    \] \},'
    $toml = if ($toml -match $pattern) { [regex]::Replace($toml, $pattern, { $block }) }
        else { [regex]::Replace($toml, '(    "reference/commands\.md",\r?\n)', { param($m) $m.Groups[1].Value + $block + "`n" }) }
    [System.IO.File]::WriteAllText($config, $toml, [System.Text.UTF8Encoding]::new($false))

    # The table of reference/commands.md: each command links to its page.
    $summary = Join-Path $root 'docs' $language 'reference' 'commands.md'
    $content = [System.IO.File]::ReadAllText($summary)
    foreach ($name in $names) {
        $content = [regex]::Replace($content, "(?m)^\| ``$([regex]::Escape($name))( [^``]*)?`` \|", {
                param($m)
                $rest = $m.Groups[1].Value.Trim()
                $parameters = if ($rest) { ' `' + $rest + '`' } else { '' }
                '| [`' + $name + '`](commands/' + (Get-CommandPageName $name) + '.md)' + $parameters + ' |'
            })
    }
    [System.IO.File]::WriteAllText($summary, $content, [System.Text.UTF8Encoding]::new($false))
}
Write-Host "Pages of $($names.Count) commands written."
