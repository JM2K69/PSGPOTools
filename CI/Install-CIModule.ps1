#Requires -Version 7.4
<#
    Installs a module of the PowerShell Gallery for a job of the CI, tried three times: the Gallery
    fails a download now and then ("Source Location '.../api/v2/package/PSScriptAnalyzer/1.25.0' is
    not valid", "Package 'Pester' failed to download"), and the job failed with it. The CI gives
    -RequiredVersion: a new version of a module of the tests never changes a run by itself.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Name,
    [string]$MinimumVersion,
    [string]$RequiredVersion
)

$install = @{ Name = $Name; Scope = 'CurrentUser'; Force = $true; SkipPublisherCheck = $true; ErrorAction = 'Stop' }
if ($MinimumVersion) { $install.MinimumVersion = $MinimumVersion }
if ($RequiredVersion) { $install.RequiredVersion = $RequiredVersion }
for ($attempt = 1; ; $attempt++) {
    try {
        Install-Module @install
        break
    } catch {
        if ($attempt -ge 3) { throw }
        Write-Warning "$Name is not installed (attempt $attempt of 3): $($_.Exception.Message)"
        Start-Sleep -Seconds (15 * $attempt)
    }
}
$installed = if ($RequiredVersion) { $RequiredVersion } else { (Get-Module -Name $Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version }
"$Name $installed installed."
