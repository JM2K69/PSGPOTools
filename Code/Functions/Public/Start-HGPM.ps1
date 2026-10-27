function Start-HGPM {
    <#
    .SYNOPSIS
        Opens the launcher of HGPM: a tile for each graphical console of the module.
    .DESCRIPTION
        A window with a tile for each console of HGPM: Group Policy Management
        (Show-GPOManagerAvalonia), the fine-grained password policies (Show-PSOManagerAvalonia) and
        the WMI filter creator (Show-WmiFilterCreatorAvalonia), Policy Analyzer
        (Show-PolicyAnalyzerAvalonia) and the audit log (Show-AuditLogAvalonia).
        A click on a tile opens the console with its default parameters, in the language of the
        launcher, chosen in its list of languages and kept for the next time. Each console runs in
        a PowerShell process of its own (the same pwsh and HGPM, without the profile): several
        consoles can be open at once, one that fails does not close the others, and they stay open
        once the launcher is closed; the tile of an open console is disabled until its window is
        closed. The theme (Dark mode / Light mode) is kept in the settings of the user, and the open
        consoles follow it. To give a console parameters (-Server, -Credential,
        -PolicyDefinitions...), run its command instead.

        Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks
        until the launcher is closed.
    .PARAMETER Language
        Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the
        one last chosen in the launcher, else the language of the session, English when the module
        has no translation for it.
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
    .LINK
        Show-PolicyAnalyzerAvalonia
    .LINK
        Show-AuditLogAvalonia
    #>
    [CmdletBinding()]
    param(
        [string]$Language
    )

    if (-not $PSBoundParameters.ContainsKey('Language')) {
        $Language = (Get-PSGPOUserSetting).Language
        if (-not $Language) { $Language = [cultureinfo]::CurrentUICulture.Name }
    }
    $Language = Set-PSGPOLanguage -Language $Language
    Start-PSGPOLauncherWindow -Tools (Get-PSGPOLauncherTool) -Language $Language
}
