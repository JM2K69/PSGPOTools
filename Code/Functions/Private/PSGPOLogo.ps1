<#
    The logo of HGPM (Resources/hgpm.png, 256 x 256, transparent): the icon of every window of the
    module (title bar, task bar) and the image of the header of the console. A logo that cannot be
    read leaves the windows without it: it is never a reason not to open them.
#>

function Get-PSGPOLogoPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path $PSScriptRoot 'Resources' 'hgpm.png'
}

# The logo as the icon of a window.
function Set-PSGPOWindowIcon {
    [CmdletBinding()]
    # A window of Avalonia (untyped: the module loads before Avalonia).
    param([Parameter(Mandatory)] $Window)

    $path = Get-PSGPOLogoPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    try { $Window.Icon = [Avalonia.Controls.WindowIcon]::new($path) }
    catch { Write-Verbose "The logo is not the icon of the window: $($_.Exception.GetBaseException().Message)" }
}

# The logo as an image of a window; $null when it cannot be read.
function New-PSGPOLogoBitmap {
    [CmdletBinding()]
    param()

    $path = Get-PSGPOLogoPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    try { [Avalonia.Media.Imaging.Bitmap]::new($path) }
    catch { Write-Verbose "The logo cannot be read: $($_.Exception.GetBaseException().Message)" }
}
