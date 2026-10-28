#Requires -Version 7.4
# HGPM runs on PowerShell 7.4+ (pwsh), not Windows PowerShell 5.1 (powershell.exe).
Write-Host "[BUILD][START] Launching Build Process" -ForegroundColor RED -BackgroundColor White

# Retrieve parent folder
$Current = (Split-Path -Path $MyInvocation.MyCommand.Path)
$Root = ((Get-Item $Current).Parent).FullName
# The module is HGPM whatever the folder of the repository is called (a GitHub archive is
# extracted as PSGPOTools-<branch>, a worktree can have any name).
$ModuleName = 'HGPM'
Write-Host "[BUILD][START] Working on module $($ModuleName)" -ForegroundColor RED -BackgroundColor White

$ModuleFolderPath = Join-Path -Path $Root -ChildPath $ModuleName

$CodeSourcePath = Join-Path -Path $Root -ChildPath "Code"

$ExportPath = Join-Path -Path $ModuleFolderPath -ChildPath "$($ModuleName).psm1"

# The same bytes from the same sources, on any computer: no date, the files in a fixed order
# (ordinal, neither the order of the file system nor the one of the culture), LF line endings,
# UTF-8 without BOM. The release publishes the module the tests ran, and anyone can build it again
# from the tag and compare (docs: Offline installation).
Write-Host "[BUILD][Code] Loading Class, public and private functions" -ForegroundColor RED -BackgroundColor White
function Get-BuildSource {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $files = @(Get-ChildItem -LiteralPath $Path -Filter *.ps1 -File)
    [System.Linq.Enumerable]::ToArray([System.Linq.Enumerable]::OrderBy($files, [Func[object, string]] { param($File) $File.Name }, [System.StringComparer]::OrdinalIgnoreCase))
}
$ClassFolderPath = Join-Path -Path $CodeSourcePath -ChildPath 'Classes'
$PrivateFunctionsFolderPath = Join-Path -Path $CodeSourcePath -ChildPath 'Functions' -AdditionalChildPath 'Private'
$PublicFunctionsFolderPath = Join-Path -Path $CodeSourcePath -ChildPath 'Functions' -AdditionalChildPath 'Public'
$PublicFunctions = @(Get-BuildSource $PublicFunctionsFolderPath)
# Classes first (the functions use them), then the private and public functions, then the post content.
$Sources = @(Get-BuildSource $ClassFolderPath) + @(Get-BuildSource $PrivateFunctionsFolderPath) + $PublicFunctions
$PostContentPath = Join-Path -Path $Current -ChildPath '03_postContent.ps1'
if (Test-Path -LiteralPath $PostContentPath) { $Sources += Get-Item -LiteralPath $PostContentPath }

Write-Host "[BUILD][START][MAIN PSM1] Building main PSM1" -ForegroundColor RED -BackgroundColor White
$Content = [System.Text.StringBuilder]::new()
[void]$Content.Append("# Generated from Code/ by CI/03_Build.ps1 (build of Nicolas BAUDIN): edit Code/, not this file.`n")
foreach ($Source in $Sources) {
    $Text = [System.IO.File]::ReadAllText($Source.FullName) -replace "`r`n", "`n"
    if (-not $Text.EndsWith("`n")) { $Text += "`n" }
    [void]$Content.Append($Text)
}
[System.IO.File]::WriteAllText($ExportPath, $Content.ToString(), [System.Text.UTF8Encoding]::new($false))

Write-Host "[BUILD][START][PSD1] Adding functions to export" -ForegroundColor RED -BackgroundColor White

$FunctionsToExport = @($PublicFunctions.BaseName | Sort-Object)
$Manifest = Join-Path -Path $ModuleFolderPath -ChildPath "$($ModuleName).psd1"
# Only when the public functions changed: Update-ModuleManifest rewrites the whole file (its date
# included), so a build would otherwise always leave the manifest changed.
$Exported = @((Import-PowerShellDataFile -Path $Manifest).FunctionsToExport | Sort-Object)
if (($Exported -join ',') -ne ($FunctionsToExport -join ',')) {
    Update-ModuleManifest -Path $Manifest -FunctionsToExport $FunctionsToExport
    # Update-ModuleManifest comments out empty exports, which would fall back to '*'
    (Get-Content -Path $Manifest) -replace '^# VariablesToExport = @\(\)', 'VariablesToExport = @()' |
        Set-Content -Path $Manifest -Encoding utf8
    Write-Host "[BUILD][PSD1] FunctionsToExport updated" -ForegroundColor RED -BackgroundColor White
}

Write-Host "[BUILD][END][MAIN PSM1] building main PSM1 " -ForegroundColor RED -BackgroundColor White

Write-Host "[BUILD][END]End of Build Process" -ForegroundColor RED -BackgroundColor White