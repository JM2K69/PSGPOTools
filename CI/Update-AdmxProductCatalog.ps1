#Requires -Version 7.4
<#
    .SYNOPSIS
        Pins the package of a product (Office, Firefox...) and its ADMX files in HGPM/Resources/AdmxProducts.json, for Install-PSGPOProductAdmx.
    .DESCRIPTION
        Install-PSGPOProductAdmx installs only the package this catalog pins for a product (its
        address, size and SHA-256) and, from it, only the files pinned: the path of each .admx
        and .adml file in a PolicyDefinitions folder (<culture>/<name>.adml for an .adml file) and the
        SHA-256 of its content. Run it for a new package of a product, downloaded first, the module
        built first (CI/03_Build.ps1). Nothing of the package is run: a zip archive is read, a
        cabinet extracted (expand on Windows, cabextract or 7-Zip elsewhere), and the program of
        Office is read for the cabinet it holds.

        The package of Office holds the .adml files of its languages side by side, named
        word16.adml, word16.adml0, word16.adml1... in the alphabetical order of their languages:
        -NumberedLanguage gives those languages, in that order; the script checks each file is in
        its language before it pins it.
    .PARAMETER Name
        The product: Office, Firefox, AdobeAcrobat, AdobeReader, Edge, Chrome, GoogleUpdate, or a
        new one.
    .PARAMETER PackagePath
        The package downloaded.
    .PARAMETER Uri
        Its address on the site of the publisher; the one pinned by default.
    .PARAMETER Version
        Its version (the one of the product, or the date of the package when its address has no
        version); the one pinned by default.
    .PARAMETER DisplayName
        The name of the product; the one pinned by default.
    .PARAMETER Publisher
        Its publisher; the one pinned by default.
    .PARAMETER Page
        The page of the publisher to download it from; the one pinned by default.
    .PARAMETER Format
        Zip, Cabinet (a .cab, which may hold a zip archive) or CabinetExecutable (the program of
        Office); the one pinned by default.
    .PARAMETER NumberedLanguage
        The languages of the numbered .adml files, the file without a number first; the ones of
        the package pinned by default.
    .EXAMPLE
        ./CI/03_Build.ps1; ./CI/Update-AdmxProductCatalog.ps1 -Name Firefox -PackagePath ./policy_templates_v8.5.zip -Version 8.5 -Uri https://github.com/mozilla/policy-templates/releases/download/v8.5/policy_templates_v8.5.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string]$PackagePath,
    [string]$Uri,
    [string]$Version,
    [string]$DisplayName,
    [string]$Publisher,
    [string]$Page,
    [ValidateSet('Zip', 'Cabinet', 'CabinetExecutable')] [string]$Format,
    [string[]]$NumberedLanguage
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$catalogPath = Join-Path $root 'HGPM' 'Resources' 'AdmxProducts.json'
$catalog = if (Test-Path -LiteralPath $catalogPath) { Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{ Products = @() } }
$pinned = @($catalog.Products | Where-Object Name -EQ $Name)[0]
foreach ($field in 'Uri', 'Version', 'DisplayName', 'Publisher', 'Page', 'Format', 'NumberedLanguage') {
    if (-not (Get-Variable -Name $field -ValueOnly) -and $pinned -and $pinned.$field) { Set-Variable -Name $field -Value $pinned.$field }
    if ($field -ne 'NumberedLanguage' -and -not (Get-Variable -Name $field -ValueOnly)) { throw "Give -${field}: $Name is not pinned yet." }
}
$PackagePath = (Resolve-Path -LiteralPath $PackagePath).ProviderPath

# The words that tell the languages of Office apart, to check the order given.
$markers = @{
    'de-DE' = ' und '; 'en-US' = ' the '; 'es-ES' = ' los '; 'fr-FR' = ' les '; 'it-IT' = ' della '; 'ja-JP' = 'す。'; 'ko-KR' = '니다'
    'nl-NL' = ' het '; 'pt-BR' = 'arquivo'; 'pt-PT' = 'ficheiro'; 'ru-RU' = ' для '; 'zh-CN' = '设置'; 'zh-TW' = '設定'
}

$module = Import-Module (Join-Path $root 'HGPM' 'HGPM.psd1') -Force -PassThru
$work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-ProductCatalog-$([guid]::NewGuid().ToString('N'))"
try {
    # Every .admx and .adml file of the package: its path in the package, its content.
    $entries = [System.Collections.Generic.List[object]]::new()
    $readZip = {
        param([string]$Zip, [string]$Prefix)
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.ZipFile
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
        try {
            foreach ($entry in $archive.Entries | Where-Object Name -Match '\.adm[lx]$') {
                $stream = $entry.Open()
                $memory = [System.IO.MemoryStream]::new()
                try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
                $entries.Add([pscustomobject]@{ Path = "$Prefix$($entry.FullName -replace '\\', '/')"; Bytes = $memory.ToArray() })
            }
        } finally {
            $archive.Dispose()
        }
    }
    if ($Format -eq 'Zip') {
        & $readZip $PackagePath ''
    } else {
        $expanded = Join-Path $work 'expanded'
        $cabinet = $PackagePath
        if ($Format -eq 'CabinetExecutable') {
            $null = New-Item -ItemType Directory -Path $work -Force
            $cabinet = Join-Path $work 'package.cab'
            & $module { param($Path, $Destination) Save-PSGPOAdmxEmbeddedCabinet -Path $Path -Destination $Destination } $PackagePath $cabinet
        }
        & $module { param($Path, $Folder) Expand-PSGPOAdmxCabinet -Path $Path -Folder $Folder } $cabinet $expanded
        foreach ($file in @(Get-ChildItem -LiteralPath $expanded -File -Recurse)) {
            $relative = $file.FullName.Substring($expanded.Length + 1) -replace '\\', '/'
            if ($file.Name -match '\.adm[lx]\d*$') { $entries.Add([pscustomobject]@{ Path = $relative; Bytes = [System.IO.File]::ReadAllBytes($file.FullName) }) }
            elseif (& $module { param($Path) Test-PSGPOZipFile -Path $Path } $file.FullName) { & $readZip $file.FullName "$relative/" }
        }
    }

    # Their paths in a PolicyDefinitions folder.
    $files = [ordered]@{}
    $add = {
        param([string]$Path, [byte[]]$Bytes)
        $sha256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes))
        if ($files.Contains($Path) -and $files[$Path] -ne $sha256) { throw "Two files of the package would be $Path, with other contents." }
        $files[$Path] = $sha256
    }
    foreach ($entry in $entries) {
        $leaf = $entry.Path.Split('/')[-1]
        if ($leaf -match '\.admx$') { & $add $leaf $entry.Bytes; continue }
        if ($leaf -match '^(.+\.adml)(\d*)$' -and $NumberedLanguage) {
            $index = if ($Matches[2] -eq '') { 0 } else { [int]$Matches[2] + 1 }
            if ($index -ge $NumberedLanguage.Count) { throw "$($entry.Path): no language for its number (-NumberedLanguage gives $($NumberedLanguage.Count))." }
            $culture = [cultureinfo]::GetCultureInfo($NumberedLanguage[$index]).Name
            $text = [System.Text.Encoding]::UTF8.GetString($entry.Bytes)
            if ($markers.ContainsKey($culture)) {
                $own = ([regex]::Matches($text, [regex]::Escape($markers[$culture]))).Count
                foreach ($other in $markers.Keys | Where-Object { $_ -ne $culture -and $_ -ne 'en-US' -and $_ -ne 'ja-JP' }) {
                    if (([regex]::Matches($text, [regex]::Escape($markers[$other]))).Count -gt $own) { throw "$($entry.Path) reads as $other, not ${culture}: check the order of -NumberedLanguage." }
                }
            }
            & $add "$culture/$($Matches[1])" $entry.Bytes
            continue
        }
        $folder = $entry.Path.Split('/')[-2]
        $culture = try { [cultureinfo]::GetCultureInfo("$folder").Name } catch { $null }
        if ($leaf -match '\.adml$' -and $culture) { & $add "$culture/$leaf" $entry.Bytes } else { Write-Warning "Not pinned (not in a folder named after a language): $($entry.Path)" }
    }
    $admx = @($files.Keys | Where-Object { $_ -notmatch '/' })
    if (-not $admx.Count) { throw "No .admx file in $PackagePath." }
    foreach ($file in $admx) {
        if (-not $files.Contains("en-US/$([System.IO.Path]::ChangeExtension($file, '.adml'))")) { Write-Warning "$file has no en-US .adml file." }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

$entry = [ordered]@{
    Name        = $Name
    DisplayName = $DisplayName
    Publisher   = $Publisher
    Version     = $Version
    Page        = $Page
    Uri         = $Uri
    FileName    = [uri]::UnescapeDataString(([uri]$Uri).Segments[-1])
    Size        = (Get-Item -LiteralPath $PackagePath).Length
    Sha256      = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
    Format      = $Format
}
if ($NumberedLanguage) { $entry.NumberedLanguage = @($NumberedLanguage) }
# The .admx files first, then the languages, each in the ordinal order.
$entry.Files = @($files.Keys | Sort-Object { if ($_ -match '/') { 1 } else { 0 } }, { $_ } -CaseSensitive | ForEach-Object { [ordered]@{ Path = $_; Sha256 = $files[$_] } })

$products = [System.Collections.Generic.List[object]]::new()
$replaced = $false
foreach ($product in @($catalog.Products)) {
    if ($product.Name -eq $Name) { $products.Add($entry); $replaced = $true } else { $products.Add($product) }
}
if (-not $replaced) { $products.Add($entry) }
$json = [ordered]@{ Products = $products.ToArray() } | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($catalogPath, "$json`n", [System.Text.UTF8Encoding]::new($false))
$languages = @($files.Keys | Where-Object { $_ -match '/' } | ForEach-Object { $_.Split('/')[0] } | Sort-Object -Unique)
Write-Host "$DisplayName $Version pinned: $($admx.Count) .admx files ($($admx -join ', ')), $($languages.Count) languages, $($files.Count) files."
