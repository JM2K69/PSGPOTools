<#
    The loop of a window of the consoles: Avalonia's SetupWithoutStarting() runs no message loop by
    itself, so each window drives one until it is closed, and the call blocks until then.

    The handler that stops the loop holds its own token (GetNewClosure). A handler that looked for
    $cts when it ran found the one of the window whose code was running then: closing the launcher
    stopped the loop of the GPO console opened from it, whose window stayed open without its code,
    and its next click failed ("The term 'Update-ApproveGpoGroupState' is not recognized").

    An error that no handler caught (Dispatcher.UnhandledException): with -KeepOpenOnError the
    window says it in a notification and goes on, and the technical log has it with where it
    happened; the window of the innermost loop running says it. Without it (the GUI tests, through
    -OnShown), a handler that fails stops the loop: the window is closed with it, rather than left
    open with buttons whose code is gone, and the error goes to the caller.
#>

function Invoke-PSGPOWindowLoop {
    [CmdletBinding()]
    param(
        # A window of Avalonia (untyped: the module loads before Avalonia).
        [Parameter(Mandatory)] $Window,

        # An error no handler caught is shown and logged, and the window stays open.
        [switch]$KeepOpenOnError
    )

    $cts = [System.Threading.CancellationTokenSource]::new()
    # Both made here: GetNewClosure keeps the variables of the scope it is called in, a closure made
    # inside another one would not have $cts. Posted: the other handlers of Closed run before the
    # loop stops.
    $cancel = [System.Action] { $cts.Cancel() }.GetNewClosure()
    $Window.add_Closed({ [Avalonia.Threading.Dispatcher]::UIThread.Post($cancel, [Avalonia.Threading.DispatcherPriority]::Background) }.GetNewClosure())

    if (-not $script:PSGPOWindowLoops) { $script:PSGPOWindowLoops = [System.Collections.Generic.List[hashtable]]::new() }
    if ($KeepOpenOnError -and -not $script:PSGPOUnhandledErrorHandler) {
        # Once for the process: a block of the module, so that it finds Receive-PSGPOWindowError.
        $script:PSGPOUnhandledErrorHandler = [Avalonia.Threading.DispatcherUnhandledExceptionEventHandler] {
            param($dispatcher, $unhandled)
            Receive-PSGPOWindowError -ErrorEvent $unhandled
        }
        [Avalonia.Threading.Dispatcher]::UIThread.add_UnhandledException($script:PSGPOUnhandledErrorHandler)
    }
    $loop = @{ Window = $Window; KeepOpen = [bool]$KeepOpenOnError; Notifications = $null; Last = $null; LastTime = [datetime]::MinValue }
    $script:PSGPOWindowLoops.Add($loop)
    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        Write-Verbose 'The window is closed.'
    } catch {
        if ($Window.IsVisible) {
            try { $Window.Close() } catch { Write-Verbose "The window is not closed: $($_.Exception.GetBaseException().Message)" }
        }
        throw
    } finally {
        $null = $script:PSGPOWindowLoops.Remove($loop)
    }
}

# An error no handler of a window caught (Dispatcher.UnhandledException): the window of the
# innermost loop running says it and stays open, when it keeps open on errors; else the error
# stops its loop. The same error again within a few seconds (a timer that fails) is said once.
function Receive-PSGPOWindowError {
    [CmdletBinding()]
    # DispatcherUnhandledExceptionEventArgs.
    param([Parameter(Mandatory)] $ErrorEvent)

    $loops = $script:PSGPOWindowLoops
    if (-not $loops -or -not $loops.Count) { return }
    $loop = $loops[$loops.Count - 1]
    if (-not $loop.KeepOpen) { return }
    $ErrorEvent.Handled = $true

    $exception = $ErrorEvent.Exception
    $message = $exception.GetBaseException().Message
    $now = [datetime]::UtcNow
    if ($loop.Last -eq $message -and ($now - $loop.LastTime).TotalSeconds -lt 5) { return }
    $loop.Last = $message
    $loop.LastTime = $now

    # Where it happened: the ErrorRecord of the PowerShell handler, when there is one.
    $record = $null
    for ($inner = $exception; $inner -and -not $record; $inner = $inner.InnerException) {
        if ($inner -is [System.Management.Automation.IContainsErrorRecord]) { $record = $inner.ErrorRecord }
    }
    $title = "$($loop.Window.Title)"
    try {
        Write-PSGPOLogEntry -Level Error -Source $(if ($title) { $title } else { 'Console' }) -Message (Get-PSGPOText 'An error was not handled: {0}' $message) -ErrorRecord $record -Detail ([ordered]@{ Exception = "$exception" })
    } catch {
        Write-Verbose "The error is not logged: $($_.Exception.Message)"
    }
    try {
        if (-not $loop.Notifications) {
            $notifications = [Avalonia.Controls.Notifications.WindowNotificationManager]::new($loop.Window)
            $notifications.Position = [Avalonia.Controls.Notifications.NotificationPosition]::TopRight
            $notifications.MaxItems = 3
            $loop.Notifications = $notifications
        }
        $text = Get-PSGPOText '{0} The window stays open; the technical log has the details.' $message
        $loop.Notifications.Show([Avalonia.Controls.Notifications.Notification]::new((Get-PSGPOText 'Error'), $text, [Avalonia.Controls.Notifications.NotificationType]::Error, [TimeSpan]::FromSeconds(30)))
    } catch {
        Write-Verbose "The error is not shown: $($_.Exception.Message)"
    }
}
