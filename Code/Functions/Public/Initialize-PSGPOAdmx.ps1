Function Initialize-PSGPOAdmx {
    <#
    .SYNOPSIS
        Loads the ADMX/ADML files of a folder (local PolicyDefinitions or a SYSVOL central store).
    .DESCRIPTION
        The language is detected from the names of the language folders of PolicyDefinitions
        (en-US, fr-FR...): the language of the session, else the same language in another
        country, else en-US, else the only one there is. When several languages remain, give
        -UICulture.
    .PARAMETER Path
        Folder containing the .admx files and one sub-folder per culture for the .adml files.
        Defaults to %windir%\PolicyDefinitions on Windows; required on Linux and macOS.
    .PARAMETER UICulture
        Culture of the ADML files to load (sub-folder name, for example en-US or fr-FR); detected
        when not given.
    .EXAMPLE
        Initialize-PSGPOAdmx -Path '\\contoso.com\SYSVOL\contoso.com\Policies\PolicyDefinitions' -UICulture 'fr-FR'
    .EXAMPLE
        # Linux: a copy of the PolicyDefinitions folder, in the language of the session
        Initialize-PSGPOAdmx -Path ~/PolicyDefinitions
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/initialize-psgpoadmx/
    #>
    [cmdletbinding()]
    Param(
        [ValidateScript( { Test-Path -Path $_ -PathType Container })]
        [String]$Path,

        [string]$UICulture
    )

    if (-not $Path) {
        if (-not $IsWindows) {
            $found = @(Get-PSGPOAdmxCandidate)
            $hint = if ($found.Count) { " Found on this computer: $($found -join ', ')." } else { '' }
            throw "Specify -Path: there is no local PolicyDefinitions folder outside Windows (use a copy of the ADMX files or the SYSVOL central store).$hint"
        }
        $Path = Join-Path -Path $Env:windir -ChildPath 'PolicyDefinitions'
    }
    $Item = Get-Item -Path $Path
    $Language = Resolve-PSGPOAdmxCulture -Path $Item.FullName -Requested $UICulture
    if (-not $Language.Culture) {
        throw "Several languages in '$($Item.FullName)' ($($Language.Available -join ', ')) and none of them is the language of the session: give -UICulture."
    }
    Write-Verbose "ADMX files of $($Item.FullName) in $($Language.Culture)."

    # Empty Statics properties
    [GPOToolsUtility]::RemoveAll()
    [GPOToolsUtility]::InitiateAdmxAdml($Item, [cultureinfo]::GetCultureInfo($Language.Culture))
}
