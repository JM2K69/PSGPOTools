<#
.SYNOPSIS
    Builds the module from Code/ and runs the Pester 5+ test suite (local and CI).
.PARAMETER OutputPath
    Optional NUnit XML result file, used by the CI to publish the results.
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot '03_Build.ps1')

Import-Module Pester -MinimumVersion 5.5.0

$Configuration = New-PesterConfiguration
$Configuration.Run.Path = Join-Path $PSScriptRoot 'tests'
$Configuration.Run.Exit = $true
$Configuration.Output.Verbosity = 'Detailed'
if ($OutputPath) {
    $Configuration.TestResult.Enabled = $true
    $Configuration.TestResult.OutputFormat = 'NUnitXml'
    $Configuration.TestResult.OutputPath = $OutputPath
}

Invoke-Pester -Configuration $Configuration
