<#
    Private helpers backing Show-GPOManagerAvalonia. Not exported by the module.
#>

function Get-PSGPOAvaloniaRid {
    [CmdletBinding()]
    param()

    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    if ($null -eq $IsWindows -or $IsWindows) {
        if ($arch -eq 'Arm64') { 'win-arm64' } else { 'win-x64' }
    } elseif ($IsLinux) {
        if ($arch -eq 'Arm64') { 'linux-arm64' } else { 'linux-x64' }
    } else {
        'osx'
    }
}

function Initialize-PSGPOAvaloniaRuntime {
    [CmdletBinding()]
    param()

    if ($script:PSGPOAvaloniaInitialized) { return }

    # Avalonia can only be set up once per process. Re-importing the module (Import-Module -Force,
    # rebuild) resets $script:PSGPOAvaloniaInitialized but not Avalonia: reuse the running application.
    $applicationType = 'Avalonia.Application' -as [type]
    if ($null -ne $applicationType -and $null -ne $applicationType::Current) {
        Write-Verbose 'Avalonia is already set up in this process: reusing the current application.'
        $script:PSGPOAvaloniaInitialized = $true
        return
    }

    $rid = Get-PSGPOAvaloniaRid
    # The module or the data folder of the user; installed from nuget.org on first use.
    $avaloniaPath = Get-PSGPOAvaloniaPath -Rid $rid
    if (-not $avaloniaPath) {
        Write-Information -InformationAction Continue "PSGPOTools: the Avalonia runtime of the window ($rid) is not installed; installing it once from nuget.org (checked packages)..."
        $avaloniaPath = Install-PSGPOAvaloniaRuntime -Rid $rid
        Write-Information -InformationAction Continue "PSGPOTools: Avalonia runtime installed in $avaloniaPath."
    }

    # Common managed assemblies, plus the platform-specific windowing backend.
    $assemblies = @(
        'Avalonia.Base.dll', 'Avalonia.dll', 'Avalonia.Controls.dll', 'Avalonia.Desktop.dll',
        'Avalonia.Dialogs.dll', 'Avalonia.Markup.dll', 'Avalonia.Markup.Xaml.dll',
        'Avalonia.Markup.Xaml.Loader.dll', 'Avalonia.Metal.dll', 'Avalonia.MicroCom.dll',
        'Avalonia.OpenGL.dll', 'Avalonia.Remote.Protocol.dll', 'Avalonia.Skia.dll',
        'Avalonia.Themes.Fluent.dll', 'Avalonia.Controls.DataGrid.dll', 'HarfBuzzSharp.dll', 'SkiaSharp.dll'
    )
    switch -Wildcard ($rid) {
        'win-*' { $assemblies += 'Avalonia.Win32.dll' }
        'linux-*' { $assemblies += 'Tmds.DBus.Protocol.dll', 'Avalonia.X11.dll', 'Avalonia.FreeDesktop.dll' }
        'osx' { $assemblies += 'Avalonia.Native.dll' }
    }

    foreach ($dll in $assemblies) {
        $full = Join-Path -Path $avaloniaPath -ChildPath $dll
        if (Test-Path -Path $full) {
            [System.Reflection.Assembly]::LoadFrom($full) | Out-Null
        } else {
            Write-Warning "Avalonia assembly not found: $full"
        }
    }

    # The X server is usually running in a Linux desktop session, but DISPLAY may not be
    # inherited by every process. Default it rather than fail platform initialization.
    if (-not $IsWindows -and [string]::IsNullOrWhiteSpace($env:DISPLAY)) {
        $env:DISPLAY = ':0'
    }

    $builder = [Avalonia.AppBuilder]::Configure[Avalonia.Application]()
    $builder = [Avalonia.AppBuilderDesktopExtensions]::UsePlatformDetect($builder)
    $builder.SetupWithoutStarting() | Out-Null
    [Avalonia.Application]::Current.Styles.Add([Avalonia.Themes.Fluent.FluentTheme]::new())

    # The DataGrid control ships its Fluent theme resources separately from Avalonia.Themes.Fluent;
    # without this StyleInclude, DataGrid/DataGridTextColumn cannot be resolved from XAML.
    $dataGridStyle = [Avalonia.Markup.Xaml.Styling.StyleInclude]::new([Uri]::new('resm:Styles?assembly=Avalonia.Controls.DataGrid'))
    $dataGridStyle.Source = [Uri]::new('avares://Avalonia.Controls.DataGrid/Themes/Fluent.xaml')
    [Avalonia.Application]::Current.Styles.Add($dataGridStyle)

    $script:PSGPOAvaloniaInitialized = $true
}

function Get-PSGPOAvaloniaControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [string]$Name
    )

    # Avalonia has no FindName(); resolve through the parsed document's name scope instead.
    $nameScope = [Avalonia.Controls.NameScope]::GetNameScope($Root)
    if ($null -eq $nameScope) { throw "No name scope on the root element." }
    $control = $nameScope.Find($Name)
    if ($null -eq $control) { throw "Control not found: $Name" }
    return $control
}
