function Start-HGPM {
    <#
    .SYNOPSIS
        Opens the launcher of HGPM: a tile for each graphical console of the module.
    .DESCRIPTION
        A window with a tile for each console of HGPM: Group Policy Management
        (Show-GPOManagerAvalonia), the fine-grained password policies (Show-PSOManagerAvalonia) and
        the WMI filter creator (Show-WmiFilterCreatorAvalonia).
        A click on a tile opens the console with its default parameters, in the language of the
        launcher; several consoles can be open at once, and the tile of an open console is
        disabled until its window is closed. To give a console parameters (-Server, -Credential,
        -PolicyDefinitions...), run its command instead.

        Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks
        until the launcher and the consoles opened from it are closed.
    .PARAMETER Language
        Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the
        language of the session, English when the module has no translation for it.
    .EXAMPLE
        Start-HGPM
    .EXAMPLE
        Start-HGPM -Language fr-FR
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/start-hgpm/
    .LINK
        Show-GPOManagerAvalonia
    .LINK
        Show-PSOManagerAvalonia
    .LINK
        Show-WmiFilterCreatorAvalonia
    #>
    [CmdletBinding()]
    param(
        [string]$Language = [cultureinfo]::CurrentUICulture.Name
    )

    $Language = Set-PSGPOLanguage -Language $Language
    Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -Language $Language
}
