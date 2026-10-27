#Requires -Version 7.4
<#
    Installs a module of the PowerShell Gallery for a job of the CI, tried three times: the Gallery
    fails a download now and then ("Source Location '.../api/v2/package/PSScriptAnalyzer/1.25.0' is
    not valid", "Package 'Pester' failed to download"), and the job failed with it.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Name,
    [string]$MinimumVersion
)

$install = @{ Name = $Name; Scope = 'CurrentUser'; Force = $true; SkipPublisherCheck = $true; ErrorAction = 'Stop' }
if ($MinimumVersion) { $install.MinimumVersion = $MinimumVersion }
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
"$Name $((Get-Module -Name $Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version) installed."
