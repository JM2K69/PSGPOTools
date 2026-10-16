# The user interface

## Avalonia from PowerShell

The window is [Avalonia 11](https://avaloniaui.net/), hosted by PowerShell 7:

- the **XAML** of each window is a string, parsed at runtime
  (`AvaloniaRuntimeXamlLoader.Parse`): no compiled assembly of the module;
- the application is started once per session, and the window runs its own dispatcher loop
  (`Dispatcher.UIThread.MainLoop`) until it is closed: the call blocks, as a modal console;
- the data of the lists and trees are small PowerShell classes (`AvaloniaTreeNode`,
  `AvaloniaHistoryNode`, `AvaloniaConfigurationRow`...): Avalonia binds to their properties.

## The runtime

`Resources/AvaloniaPackages.json` pins the 21 NuGet packages of the window (Avalonia, Skia,
HarfBuzz, their native assets per runtime) with the SHA-512 of the nuget.org catalog. On the first
opening of a window, the console downloads the packages of the runtime of the computer, checks
each hash before extracting anything, stages them, and moves them into place at once: the module
folder when it can be written to, else the data folder of the user.

## Trees and details without a window

`New-PSGPODirectoryTree`, `New-PSGPOPolicyTree` and `Get-PSGPODirectoryDetail` build what the
window shows (nodes, icons, headers, details) without any Avalonia type: they are tested without a
UI.

## Icons

[Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons) (MIT), size 20,
regular, in `Resources/Icons`: the window reads the path of each SVG as an Avalonia geometry,
available in XAML as `{StaticResource Icon.<name>}`. Emoji were used before, but most Linux
desktops have no font to draw them.

## Pitfalls met

!!! note "Closures"
    A handler made with `GetNewClosure()` runs in a new dynamic module: it no longer sees the
    private functions of the module, nor its classes. The handlers capture what they call first
    (`$Save = ${function:Save-PSGPODomainConfiguration}`, `$RowType = [AvaloniaConfigurationRow]`).

!!! note "The pipeline"
    The output of the pipeline wraps objects in `PSObject`, which Avalonia cannot bind: the lists
    are built with `List[T]` and `foreach`. `if (...) { @(...) }` unrolls a list of one item: the
    lists are assigned inside the branches.

## Tests of the window

`Start-PSGPOManagerWindow -OnShown { param($Ui) ... }` opens the real window and runs the block
once it is shown, with its controls by name: the GUI tests click, type and check what the window
shows, then the window closes. They run on Windows and in the X session of a Linux computer.
