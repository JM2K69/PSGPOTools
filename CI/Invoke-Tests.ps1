#Requires -Version 7.4
# HGPM runs on PowerShell 7.4+ (pwsh), not Windows PowerShell 5.1 (powershell.exe).
<#
.SYNOPSIS
    Builds the module from Code/ and runs the Pester 5+ test suite (local and CI).
.PARAMETER OutputPath
    Optional NUnit XML result file, used by the CI to publish the results.
.PARAMETER Path
    Test files to run; every file of CI/tests by default.
.PARAMETER RequireRun
    Blocks (names of Describe or Context, wildcards allowed; a list, or one text separated by
    commas for pwsh -File) whose tests must run here: a test of them skipped or not run, or no test
    of them at all, fails the run. A CI job gives what it is there to test (the windows of the
    GUI, the tests against a domain controller): a runtime or a variable missing does not turn it
    into a green run that tested nothing.
.PARAMETER NoBuild
    Tests the module already built (the CI builds it once, then tests and publishes that one).
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [string[]]$Path = @(Join-Path $PSScriptRoot 'tests'),

    [string[]]$RequireRun = @(),

    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
# Each test file imports the module: its import must not read the PowerShell Gallery.
$env:PSGPOTOOLS_SKIP_UPDATE_CHECK = '1'
# The errors the tests make on purpose: in a technical log of their own, not in the log of the system.
$env:PSGPOTOOLS_LOG_PATH = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-tests-log-$PID"
$env:PSGPOTOOLS_SKIP_SYSTEM_LOG = '1'
# Their settings, backups, cache of the ADMX files and audit log too: not those of the user.
$env:PSGPOTOOLS_SETTINGS_PATH = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-tests-settings-$PID.json"
$env:PSGPOTOOLS_BACKUP_PATH = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-tests-backups-$PID"
$env:PSGPOTOOLS_CACHE_PATH = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-tests-cache-$PID"

if ($NoBuild) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..' 'HGPM' 'HGPM.psm1'))) { throw 'The module is not built: run CI/03_Build.ps1, or omit -NoBuild.' }
} else {
    & (Join-Path $PSScriptRoot '03_Build.ps1')
}
# The ADMX files of Windows many tests read: not in the repository, the files of Microsoft.
if (-not (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..' 'sources' 'PolicyDefinitions') -File -Filter '*.admx' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    throw 'No ADMX file in sources/PolicyDefinitions: run CI/Get-AdmxSource.ps1 once (it installs those of the package of Microsoft).'
}

Import-Module Pester -MinimumVersion 5.5.0

$Configuration = New-PesterConfiguration
$Configuration.Run.Path = $Path
$Configuration.Run.PassThru = $true
$Configuration.Output.Verbosity = 'Detailed'
if ($OutputPath) {
    $Configuration.TestResult.Enabled = $true
    $Configuration.TestResult.OutputFormat = 'NUnitXml'
    $Configuration.TestResult.OutputPath = $OutputPath
}

$Result = Invoke-Pester -Configuration $Configuration
# The cache of the ADMX files of this run: some ten megabytes.
Remove-Item -LiteralPath $env:PSGPOTOOLS_CACHE_PATH -Recurse -Force -ErrorAction SilentlyContinue

# What each file did, in the summary of the job on GitHub.
$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('| Tests | Passed | Failed | Skipped | Not run |')
$Lines.Add('|---|---:|---:|---:|---:|')
foreach ($Container in $Result.Containers) {
    $Lines.Add(('| {0} | {1} | {2} | {3} | {4} |' -f (Split-Path -Leaf "$($Container.Item)"), $Container.PassedCount, $Container.FailedCount, $Container.SkippedCount, $Container.NotRunCount))
}
$Lines.Add(('| **All** | **{0}** | **{1}** | **{2}** | **{3}** |' -f $Result.PassedCount, $Result.FailedCount, $Result.SkippedCount, $Result.NotRunCount))

# The blocks this run must test.
$Problems = [System.Collections.Generic.List[string]]::new()
if ($Result.FailedCount -or $Result.FailedContainersCount) { $Problems.Add("$($Result.FailedCount) test(s) failed, $($Result.FailedContainersCount) file(s) failed.") }
foreach ($Pattern in @($RequireRun | ForEach-Object { "$_" -split ',' } | ForEach-Object Trim | Where-Object { $_ })) {
    # The blocks of a test, from its Describe to its Context: Path ends with the name of the test.
    $Tests = @($Result.Tests | Where-Object { @($_.Path | Select-Object -SkipLast 1 | Where-Object { $_ -like $Pattern }).Count })
    # Not run, or skipped with its block (a runtime or a variable missing); a test that skips
    # itself (-Skip:$IsWindows: it is for another platform) is not.
    $NotRun = @($Tests | Where-Object {
            if ($_.Result -eq 'NotRun') { return $true }
            if ($_.Result -ne 'Skipped') { return $false }
            for ($Block = $_.Block; $Block; $Block = $Block.Parent) { if ($Block.Skip) { return $true } }
            $false
        })
    if (-not $Tests.Count) { $Problems.Add("No test of '$Pattern' was found: it must run here.") }
    elseif ($NotRun.Count) { $Problems.Add("$($NotRun.Count) of the $($Tests.Count) test(s) of '$Pattern' did not run here: $(@($NotRun | Select-Object -First 3 | ForEach-Object ExpandedName) -join '; ')") }
    else { $Lines.Add(""); $Lines.Add("Ran here, as required: ``$Pattern`` ($($Tests.Count) test(s))") }
}
foreach ($Problem in $Problems) { $Lines.Add(''); $Lines.Add("**$Problem**") }
if ($env:GITHUB_STEP_SUMMARY) { $Lines -join "`n" | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
foreach ($Problem in $Problems) { Write-Host $Problem -ForegroundColor Red }
exit $(if ($Problems.Count) { 1 } else { 0 })
