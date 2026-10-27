<#
    The theme of the consoles, the same in every window: the theme of the system at first, then the
    one chosen with the Dark mode / Light mode button of any of them (the launcher, the GPO and PSO
    consoles, the WMI filter creator...). The windows open at that moment change with it, the label
    and icon of their button too; a window opened later starts on it.

    The choice is kept in the settings of the user (Theme): the consoles the launcher starts run in
    processes of their own, and start on it; and while a process has a window, it looks at the
    settings once a second, so that its windows follow a theme chosen in another one.
#>

# Whether the consoles are dark: the choice of the session, else the one of the settings of the
# user, else the theme of the system.
function Get-PSGPOThemeIsDark {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -ne $script:PSGPOThemeDark) { return [bool]$script:PSGPOThemeDark }
    $saved = (Get-PSGPOUserSetting).Theme
    if ($saved -in 'Dark', 'Light') { return $saved -eq 'Dark' }
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
    # The theme another process chooses: its settings looked at while a window is open.
    if (-not $script:PSGPOThemeTimer) {
        $script:PSGPOThemeStamp = Get-PSGPOThemeSettingStamp
        $script:PSGPOThemeTimer = [Avalonia.Threading.DispatcherTimer]::new()
        $script:PSGPOThemeTimer.Interval = [TimeSpan]::FromSeconds(1)
        # Module functions only: the handler runs in the loop of whichever window is open.
        $script:PSGPOThemeTimer.Add_Tick({ Update-PSGPOThemeFromSetting })
    }
    $script:PSGPOThemeTimer.Start()
}

function Update-PSGPOThemeWindow {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$Entry, [Parameter(Mandatory)] [bool]$Dark)

    $Entry.Window.RequestedThemeVariant = if ($Dark) { [Avalonia.Styling.ThemeVariant]::Dark } else { [Avalonia.Styling.ThemeVariant]::Light }
    # The button offers the other theme.
    if ($Entry.Text) { $Entry.Text.Text = Get-PSGPOText $(if ($Dark) { 'Light mode' } else { 'Dark mode' }) }
    if ($Entry.Icon) { $Entry.Icon.Data = [Avalonia.Media.Geometry]::Parse((Get-PSGPOIconData -Name $(if ($Dark) { 'weather-sunny' } else { 'weather-moon' }))) }
}

# The other theme, for every window open, and kept in the settings of the user for the others.
function Switch-PSGPOTheme {
    [CmdletBinding()]
    param()

    Set-PSGPOThemeWindow -Dark (-not (Get-PSGPOThemeIsDark))
    Set-PSGPOUserSetting -Values @{ Theme = $(if ($script:PSGPOThemeDark) { 'Dark' } else { 'Light' }) } -Confirm:$false -WhatIf:$false
    # Its own change is not read again.
    $script:PSGPOThemeStamp = Get-PSGPOThemeSettingStamp
}

# A theme for every window open.
function Set-PSGPOThemeWindow {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [bool]$Dark)

    $script:PSGPOThemeDark = $Dark
    foreach ($entry in @($script:PSGPOThemeWindows)) {
        if ($entry.Closed) { [void]$script:PSGPOThemeWindows.Remove($entry); continue }
        Update-PSGPOThemeWindow -Entry $entry -Dark $Dark
    }
}

# When the settings of the user were written last (0 without them).
function Get-PSGPOThemeSettingStamp {
    [CmdletBinding()]
    [OutputType([long])]
    param()

    $path = Get-PSGPOUserSettingPath
    if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-Item -LiteralPath $path -Force).LastWriteTimeUtc.Ticks } else { 0 }
}

# The theme chosen in another process: the settings read again once they changed. The looking
# stops with the last window; it never stops a window (an error is left aside).
function Update-PSGPOThemeFromSetting {
    [CmdletBinding()]
    param()

    try {
        if (-not @($script:PSGPOThemeWindows | Where-Object { -not $_.Closed }).Count) {
            $script:PSGPOThemeTimer.Stop()
            return
        }
        $stamp = Get-PSGPOThemeSettingStamp
        if ($stamp -eq $script:PSGPOThemeStamp) { return }
        $script:PSGPOThemeStamp = $stamp
        # Applied again even when it is the same: Get-PSGPOThemeIsDark already reads the new one
        # when the session has no choice of its own.
        $saved = (Get-PSGPOUserSetting).Theme
        if ($saved -in 'Dark', 'Light') { Set-PSGPOThemeWindow -Dark ($saved -eq 'Dark') }
    } catch {
        Write-Verbose "The theme of the settings is not read: $($_.Exception.Message)"
    }
}
