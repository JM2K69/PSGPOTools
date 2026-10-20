<#
    Versions of HGPM, as semantic versions (0.1.4-alpha): the one loaded, and those of the PowerShell
    Gallery (Test-PSGPOUpdate). A prerelease comes before its release (0.1.4-alpha < 0.1.4), and the
    prereleases sort by their label (alpha < beta < rc).
#>

# A semantic version from the version and the prerelease label of a manifest or of the Gallery.
function ConvertTo-PSGPOSemanticVersion {
    [CmdletBinding()]
    [OutputType([semver])]
    param(
        [Parameter(Mandatory)] [version]$Version,
        [AllowNull()] [AllowEmptyString()] [string]$Prerelease
    )

    $label = "$Prerelease".Trim().TrimStart('-')
    [semver]::new($Version.Major, [Math]::Max($Version.Minor, 0), [Math]::Max($Version.Build, 0), $(if ($label) { $label } else { $null }))
}

# The version of the module loaded, and the folder it is loaded from.
function Get-PSGPOModuleVersion {
    [CmdletBinding()]
    param()

    $module = $MyInvocation.MyCommand.Module
    [pscustomobject]@{
        Version = ConvertTo-PSGPOSemanticVersion -Version $module.Version -Prerelease $module.PrivateData.PSData.Prerelease
        Path = $module.ModuleBase
    }
}
