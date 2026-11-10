<#
    The logo of HGPM (Resources/hgpm.png, 256 x 256, transparent): the icon of every window of the
    module (title bar, task bar) and the image of the header of the console; or those an add-on
    gives (its hook WindowLogo). A logo that cannot be read leaves the windows without it: it is
    never a reason not to open them.
#>

# The icon of the windows, or the image of their header (-Kind Header).
function Get-PSGPOLogoPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([ValidateSet('Icon', 'Header')] [string]$Kind = 'Icon')

    $given = try { Get-PSGPOAddOnWindowLogo -Kind $Kind } catch { $null }
    if ($given) { return $given }
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

# The logo as the image of the header of a window; $null when it cannot be read.
function New-PSGPOLogoBitmap {
    [CmdletBinding()]
    param()

    $path = Get-PSGPOLogoPath -Kind Header
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    try { [Avalonia.Media.Imaging.Bitmap]::new($path) }
    catch { Write-Verbose "The logo cannot be read: $($_.Exception.GetBaseException().Message)" }
}
