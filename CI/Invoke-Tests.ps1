#Requires -Version 7.4
# HGPM runs on PowerShell 7.4+ (pwsh), not Windows PowerShell 5.1 (powershell.exe).
<#
.SYNOPSIS
    Builds the module from Code/ and runs the Pester 5+ test suite (local and CI).
.PARAMETER OutputPath
    Optional NUnit XML result file, used by the CI to publish the results.
.PARAMETER Path
    Test files to run; every file of CI/tests by default.
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [string[]]$Path = @(Join-Path $PSScriptRoot 'tests')
)

$ErrorActionPreference = 'Stop'
# Each test file imports the module: its import must not read the PowerShell Gallery.
$env:PSGPOTOOLS_SKIP_UPDATE_CHECK = '1'
# The errors the tests make on purpose: in a technical log of their own, not in the log of the system.
$env:PSGPOTOOLS_LOG_PATH = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-tests-log-$PID"
$env:PSGPOTOOLS_SKIP_SYSTEM_LOG = '1'
# Their settings, backups and audit log too: not those of the user.
$env:PSGPOTOOLS_SETTINGS_PATH = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-tests-settings-$PID.json"
$env:PSGPOTOOLS_BACKUP_PATH = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-tests-backups-$PID"

& (Join-Path $PSScriptRoot '03_Build.ps1')

Import-Module Pester -MinimumVersion 5.5.0

$Configuration = New-PesterConfiguration
$Configuration.Run.Path = $Path
$Configuration.Run.Exit = $true
$Configuration.Output.Verbosity = 'Detailed'
if ($OutputPath) {
    $Configuration.TestResult.Enabled = $true
    $Configuration.TestResult.OutputFormat = 'NUnitXml'
    $Configuration.TestResult.OutputPath = $OutputPath
}

Invoke-Pester -Configuration $Configuration
