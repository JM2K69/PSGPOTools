function Initialize-PSGPOAdmx {
    <#
    .SYNOPSIS
        Loads the ADMX/ADML files of a folder (local PolicyDefinitions or a SYSVOL central store).
    .PARAMETER Path
        Folder containing the .admx files and one sub-folder per culture for the .adml files.
        Defaults to %windir%\PolicyDefinitions on Windows; required on Linux and macOS.
    .PARAMETER UICulture
        Culture of the ADML files to load (sub-folder name, for example en-US or fr-FR).
    .EXAMPLE
        Initialize-PSGPOAdmx -Path '\contoso.com\SYSVOL\contoso.com\Policies\PolicyDefinitions' -UICulture 'fr-FR'
    #>
    [cmdletbinding()]
    Param(
        [ValidateScript( { Test-Path -Path $_ -PathType Container })]
        [String]$Path,

        [cultureinfo]$UICulture = [cultureinfo]::CurrentUICulture
    )

    ### VAR ###
    if (-not $Path) {
        if (-not $IsWindows) {
            throw 'Specify -Path: there is no local PolicyDefinitions folder outside Windows (use a copy of the ADMX files or the SYSVOL central store).'
        }
        $Path = Join-Path -Path $Env:windir -ChildPath 'PolicyDefinitions'
    }
    $Item = Get-Item -Path $Path
    ### MAIN ###
    # Empty Statics properties
    [GPOToolsUtility]::RemoveAll()
    [GPOToolsUtility]::InitiateAdmxAdml($Item, $UICulture)
}
