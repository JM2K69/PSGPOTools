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
    lists are assigned inside the branches. `Select-Object` wraps its objects too: a list made
    from it takes `.PSObject.BaseObject` of each item.

!!! note "The button of the view shown"
    The class `accent` of the Fluent theme does not color a button here: the windows share the
    style `Button.active` (`Get-PSGPOWindowResourceXaml`, with the brushes of both themes).

## The code of a window

Each named control of a window (`Name='...'` in its XAML) is in a variable of its name
(`$treeView`, `$applySettingButton`...), made from the XAML in one loop
(`Get-PSGPOAvaloniaNamedControl`), not one line per control. The GPO console is split by view:
`Start-PSGPOManagerWindow` builds the window, then dot-sources each view
(`Initialize-PSGPOManagerSettingView`, `...HistoryView`, `...WmiFilterView`...), a file each, whose
state, functions and handlers live in the scope of the window while it is open.

A variable misspelt would only be `$null` when the window runs: `PSGPOTools.WindowCode.tests.ps1`
reads the code of the console (its syntax tree) and fails on a variable read that is neither
assigned nor a control of its XAML.

## An error no handler caught

An error that escapes a handler (a click, a timer, an action posted) does not close the window: the
loop of each window (`Invoke-PSGPOWindowLoop -KeepOpenOnError`) takes it from
`Dispatcher.UIThread.UnhandledException`, shows it in a notification of the window (at the top
right, for 30 seconds), and writes it to the technical log (`ERROR`, with the script and the line
where it happened). The same error again within 5 seconds is said once. The GUI tests open the
windows without it: an error there stops the loop and fails the test.

## Long operations in the background { #long-operations-in-the-background }

The GPO console reads and writes some things that take seconds or minutes: Refresh (F5) and
Change Domain Controller..., Detect Now (Status tab), Back up and Back up all (History tab), Save
report.... They run in a worker of the console: a runspace of its own, opened as the console
starts, with HGPM imported in it once (some seconds on Windows, where the module is scanned; the
first operation waits for it). The window stays drawn and answers: a banner says what runs, the
tree and the details of the domain wait (no other change starts meanwhile), and **Cancel** stops
a read (not a backup, which writes and is not left half-way).

The block of an operation runs in the scope of the module in the worker: it finds the functions of
HGPM, and what it needs from the window is given as arguments. The objects of HGPM go to the
worker and back as they are, as its classes are the same types in both runspaces; the worker gets
the language and the configuration of the domain of the window when the operation starts, and the
ADMX files loaded are static members, shared already (`PSGPOWindowOperation.ps1`,
`Initialize-PSGPOManagerOperationView`). The GUI tests run the operations on the thread of the
window instead, where their mocks are; the worker has tests of its own (a result, an error, a
cancellation, a second operation refused).

!!! note "Classes and runspaces"
    A method of a class of HGPM that calls the module runs in the runspace that defined the class,
    the one of the window, even when the worker calls it (reading the files of a GPO for a
    report). That runspace takes such a call between two commands of its pipeline, never while it
    runs the loop of the window: the worker waited forever. While an operation runs, its timer
    runs `Start-Sleep -Milliseconds 0` every 5 ms, which lets the window take them. The classes
    keep their affinity: with `[NoRunspaceAffinity()]` their methods would look for the functions
    of the module in the session of the caller, where a closure or a script of the user does not
    have them. Checked against the Samba lab and the Windows lab: Refresh, Detect Now and a report
    in the worker, the window answering meanwhile.

## Tests of the window

`Start-PSGPOManagerWindow -OnShown { param($Ui) ... }` (and `Start-PSGPOPasswordPolicyWindow` for
the PSO console, its window of a PSO in `$Ui.Editor`) opens the real window and runs the block
once it is shown, with its controls by name: the GUI tests click, type and check what the window
shows, then the window closes. They run on Windows and in the X session of a Linux computer.
