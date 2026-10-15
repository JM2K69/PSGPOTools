function Get-PSGPOConfiguration {
    <#
    .SYNOPSIS
        Shows the configuration of PSGPOTools in use and where it comes from.
    .DESCRIPTION
        The configuration is the Resources/Configuration.psd1 of the module (every setting with its
        default, commented), with over it the Configuration.psd1 of the user, which holds only the
        settings it changes: in the configuration folder of the user (%APPDATA%\PSGPOTools on
        Windows, ~/.config/PSGPOTools on Linux), or at the path of PSGPOTOOLS_CONFIGURATION_PATH.
        Both are read as data, never run. A configuration of the user that cannot be read or holds
        a wrong value is reported and left out.

        It sets what the window proposes for a new GPO: its name and status, and its security
        filtering groups (created or not, where, their prefixes, scope and descriptions).
    .EXAMPLE
        Get-PSGPOConfiguration
    .EXAMPLE
        # The groups of the new GPOs in OU=GPO,OU=Groups, domain local, the box checked
        $Path = (Get-PSGPOConfiguration).UserPath
        New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
        Set-Content -Path $Path -Value "@{ NewGpo = @{ SecurityFilteringGroups = @{ Create = `$true; Container = 'OU=GPO,OU=Groups'; Scope = 'DomainLocal' } } }"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $paths = Get-PSGPOConfigurationPath
    [pscustomobject]@{
        DefaultPath = $paths.Default
        UserPath = $paths.User
        UserFileExists = Test-Path -LiteralPath $paths.User -PathType Leaf
        Configuration = Get-PSGPOConfigurationData
    }
}
