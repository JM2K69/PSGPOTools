<#
    The theme of the consoles, the same in every window of the session: the theme of the system at
    first, then the one chosen with the Dark mode / Light mode button of any of them (the launcher,
    the GPO and PSO consoles, the WMI filter creator). The windows open at that moment change with
    it, the label and icon of their button too; a window opened later starts on it.
#>

# Whether the consoles are dark: the choice of the session, else the theme of the system.
function Get-PSGPOThemeIsDark {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -ne $script:PSGPOThemeDark) { return [bool]$script:PSGPOThemeDark }
    $platformSettings = [Avalonia.Application]::Current.PlatformSettings
    $null -ne $platformSettings -and $platformSettings.GetColorValues().ThemeVariant -eq [Avalonia.Platform.PlatformThemeVariant]::Dark
}

# A window that follows the theme of the session, with the text and icon of its button when it
# has one: the theme is applied to it now, then each time it changes, until the window is closed.
function Register-PSGPOThemeWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Window,
        $ToggleText,
        $ToggleIcon
    )

    if (-not $script:PSGPOThemeWindows) { $script:PSGPOThemeWindows = [System.Collections.Generic.List[hashtable]]::new() }
    $entry = @{ Window = $Window; Text = $ToggleText; Icon = $ToggleIcon; Closed = $false }
    $script:PSGPOThemeWindows.Add($entry)
    # Only the entry: a closure does not see the functions of the module.
    $Window.add_Closed({ $entry.Closed = $true }.GetNewClosure())
    Update-PSGPOThemeWindow -Entry $entry -Dark (Get-PSGPOThemeIsDark)
}

function Update-PSGPOThemeWindow {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$Entry, [Parameter(Mandatory)] [bool]$Dark)

    $Entry.Window.RequestedThemeVariant = if ($Dark) { [Avalonia.Styling.ThemeVariant]::Dark } else { [Avalonia.Styling.ThemeVariant]::Light }
    # The button offers the other theme.
    if ($Entry.Text) { $Entry.Text.Text = Get-PSGPOText $(if ($Dark) { 'Light mode' } else { 'Dark mode' }) }
    if ($Entry.Icon) { $Entry.Icon.Data = [Avalonia.Media.Geometry]::Parse((Get-PSGPOIconData -Name $(if ($Dark) { 'weather-sunny' } else { 'weather-moon' }))) }
}

# The other theme, for every window open.
function Switch-PSGPOTheme {
    [CmdletBinding()]
    param()

    $script:PSGPOThemeDark = -not (Get-PSGPOThemeIsDark)
    foreach ($entry in @($script:PSGPOThemeWindows)) {
        if ($entry.Closed) { [void]$script:PSGPOThemeWindows.Remove($entry); continue }
        Update-PSGPOThemeWindow -Entry $entry -Dark $script:PSGPOThemeDark
    }
}
