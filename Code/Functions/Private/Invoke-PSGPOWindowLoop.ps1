<#
    The loop of a window of the consoles: Avalonia's SetupWithoutStarting() runs no message loop by
    itself, so each window drives one until it is closed, and the call blocks until then.

    The handler that stops the loop holds its own token (GetNewClosure). A handler that looked for
    $cts when it ran found the one of the window whose code was running then: closing the launcher
    stopped the loop of the GPO console opened from it, whose window stayed open without its code,
    and its next click failed ("The term 'Update-ApproveGpoGroupState' is not recognized").

    A handler that fails stops the loop: the window is closed with it, rather than left open with
    buttons whose code is gone, and the error goes to the caller.
#>

function Invoke-PSGPOWindowLoop {
    [CmdletBinding()]
    # A window of Avalonia (untyped: the module loads before Avalonia).
    param([Parameter(Mandatory)] $Window)

    $cts = [System.Threading.CancellationTokenSource]::new()
    # Both made here: GetNewClosure keeps the variables of the scope it is called in, a closure made
    # inside another one would not have $cts. Posted: the other handlers of Closed run before the
    # loop stops.
    $cancel = [System.Action] { $cts.Cancel() }.GetNewClosure()
    $Window.add_Closed({ [Avalonia.Threading.Dispatcher]::UIThread.Post($cancel, [Avalonia.Threading.DispatcherPriority]::Background) }.GetNewClosure())
    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        Write-Verbose 'The window is closed.'
    } catch {
        if ($Window.IsVisible) {
            try { $Window.Close() } catch { Write-Verbose "The window is not closed: $($_.Exception.GetBaseException().Message)" }
        }
        throw
    }
}
