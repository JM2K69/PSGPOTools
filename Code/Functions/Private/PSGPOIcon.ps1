<#
    Icons of Show-GPOManagerAvalonia: Microsoft Fluent UI System Icons (the Windows 11 icons,
    MIT license), shipped with the module in Resources/Icons as SVG files. Emoji were used
    before, but most Linux desktops have no font to draw them.

    Each SVG holds monochrome paths: their data, prefixed with F1 (non-zero fill rule, as in
    SVG), is a geometry Avalonia parses itself, in XAML or through a binding. Kept free of any
    Avalonia type so the trees can be built and tested without a UI.
#>

# Colour of the tree icons, close to the Windows ones and readable on the light and dark themes.
$script:PSGPOIconBrush = @{
    'folder'            = '#E8A93A'
    'folder-prohibited' = '#E8A93A'
    'globe'             = '#0F6CBD'
    'link'              = '#0F6CBD'
    'link-dismiss'      = '#8A8886'
    'lock-closed'       = '#CA5010'
    'library'           = '#8764B8'
    'document-settings' = '#0F6CBD'
    'document'          = '#3A96DD'
    'person'            = '#0F6CBD'
    'desktop'           = '#0F6CBD'
    'shield'            = '#107C10'
    # Restricted groups
    'people'            = '#107C10'
    # Deleted GPOs (their backups), templates of new GPOs
    'delete'            = '#8A8886'
    'document-copy'     = '#8764B8'
    # WMI filters
    'filter'            = '#5C2E91'
    # Preferences ([MS-GPPREF]): their own colour, apart from the policies
    'toolbox'           = '#038387'
    'wrench'            = '#038387'
    'folder-preference' = '#038387'
}

# Path data of an icon of Resources/Icons ('folder' for folder.svg).
function Get-PSGPOIconData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $script:PSGPOIconData) { $script:PSGPOIconData = @{} }
    $data = $script:PSGPOIconData[$Name]
    if (-not $data) {
        $file = Join-Path $PSScriptRoot 'Resources' 'Icons' "$Name.svg"
        if (-not (Test-Path -LiteralPath $file)) { throw "Icon not found: $file" }
        $svg = [xml](Get-Content -LiteralPath $file -Raw)
        $paths = @($svg.GetElementsByTagName('path') | ForEach-Object { $_.GetAttribute('d') })
        if (-not $paths) { throw "No path in the icon $file" }
        $data = 'F1 ' + ($paths -join ' ')
        $script:PSGPOIconData[$Name] = $data
    }
    $data
}

# Names of the icons shipped with the module.
function Get-PSGPOIconName {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Resources' 'Icons') -Filter '*.svg' | ForEach-Object BaseName | Sort-Object
}

# Gives a tree node an icon: its name, path data and colour.
function Set-PSGPOTreeNodeIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AvaloniaTreeNode]$Node,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $Node.Icon = $Name
    $Node.IconData = Get-PSGPOIconData -Name $Name
    $Node.IconBrush = $script:PSGPOIconBrush[$Name]
}
