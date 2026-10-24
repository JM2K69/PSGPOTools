<#
    Shows a main window of the console in front of the others. On Windows, a process started from a
    terminal does not own the window in front (it belongs to the terminal), so the system opens its
    windows behind that one: the window is made topmost for a moment, which puts it on top, then
    activated. Linux window managers already open a new window in front.
#>

function Show-PSGPOWindow {
    [CmdletBinding()]
    # A window of Avalonia (untyped: the module loads before Avalonia).
    param([Parameter(Mandatory)] $Window)

    $Window.Show()
    if (-not $IsWindows) { return }
    try {
        $Window.Topmost = $true
        $Window.Activate()
        $Window.Topmost = $false
    } catch {
        Write-Verbose "The window is not brought to the front: $($_.Exception.GetBaseException().Message)"
    }
}
