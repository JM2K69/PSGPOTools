<#
    The long operations of a console in the background: a worker (a runspace of its own, HGPM
    imported in it once) runs them one at a time, while the window stays drawn and answers; the
    window says what runs and can cancel it. What an operation returns comes back to the window on
    its thread (-Done), or its error (-Failed), or its cancellation (-Cancelled).

    The block of an operation runs in the worker, in the scope of the module there: it finds the
    functions of HGPM, not the variables of the window; what it needs is given with -ArgumentList.
    The objects of the module go to the worker and back as they are (the classes of HGPM are the
    same types in both runspaces), and the worker gets the state of the module the window has when
    the operation starts: the language and the configuration of the domain. The ADMX files loaded
    are static members of GPOToolsUtility, shared already.

    A method of a class of HGPM that calls the module runs in the runspace that defined the class,
    the one of the window, even when the worker calls it (reading the files of a GPO for a report):
    the worker waits until that runspace takes the call, which it does between two commands of its
    pipeline, not while it runs the loop of the window. The timer of an operation runs
    Start-Sleep -Milliseconds 0 every 5 ms, which lets it take them. (NoRunspaceAffinity on the
    classes is not the way: their methods would then look for the functions of the module in the
    session of the caller, where a closure or a script of the user does not have them.)

    Without a worker (-Inline: the GUI tests, whose mocks are in the runspace of the window), the
    block runs on the thread of the window, posted, as before.
#>

# A worker: its runspace opened and HGPM imported in it, started at once (some seconds on Windows,
# where the module is scanned); the first operation waits for the import.
function New-PSGPOWindowWorker {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $modulePath = $MyInvocation.MyCommand.Module.Path -replace '\.psm1$', '.psd1'
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript('param($Path) $env:PSGPOTOOLS_SKIP_UPDATE_CHECK = ''1''; Import-Module $Path -WarningAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null').AddArgument($modulePath)
    @{ PowerShell = $powershell; Runspace = $runspace; Handle = $powershell.BeginInvoke(); Ready = $false; Operation = $null }
}

# Stops what the worker runs and closes its runspace (the window is closed).
function Remove-PSGPOWindowWorker {
    [CmdletBinding()]
    param([AllowNull()] [hashtable]$Worker)

    if (-not $Worker) { return }
    if ($Worker.Operation -and $Worker.Operation.Timer) { $Worker.Operation.Timer.Stop() }
    try { [void]$Worker.PowerShell.BeginStop($null, $null) } catch { Write-Verbose "The worker is not stopped: $($_.Exception.Message)" }
    $Worker.PowerShell.Dispose()
    $Worker.Runspace.Dispose()
}

# Runs $ScriptBlock in the worker; -Done gets what it returned, -Failed its error (an ErrorRecord),
# -Cancelled is called once Stop-PSGPOWindowOperation stopped it. All three on the thread of the
# window. Throws when an operation runs already.
function Start-PSGPOWindowOperation {
    [CmdletBinding()]
    param(
        # $null: the block runs on the thread of the window (-Inline).
        [AllowNull()] [hashtable]$Worker,
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [Parameter(Mandatory)] [scriptblock]$Done,
        [Parameter(Mandatory)] [scriptblock]$Failed,
        [scriptblock]$Cancelled = {},
        # The language of the interface, given to the worker.
        [string]$Language
    )

    if (-not $Worker) {
        # Posted: what the window shows first (the banner) is drawn before the block runs.
        $inline = @{ ScriptBlock = $ScriptBlock; ArgumentList = $ArgumentList; Done = $Done; Failed = $Failed }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                $result = $null
                $arguments = @($inline.ArgumentList)
                try { $result = @(& $inline.ScriptBlock @arguments) } catch { & $inline.Failed $_; return }
                & $inline.Done $result
            }.GetNewClosure(), [Avalonia.Threading.DispatcherPriority]::Background)
        return
    }
    if ($Worker.Operation) { throw 'An operation of the console runs already: wait for it, or cancel it.' }

    $operation = @{ Done = $Done; Failed = $Failed; Cancelled = $Cancelled; Stopped = $false; Handle = $null; Timer = $null; Started = $false }
    $Worker.Operation = $operation
    $state = @{
        Configuration = (Get-PSGPOConfigurationState).Clone()
        Language      = $(if ($Language) { $Language } else { $script:PSGPOLanguage })
    }
    $start = {
        $Worker.PowerShell.Commands.Clear()
        [void]$Worker.PowerShell.AddScript({
                param($Body, $Arguments, $State)
                $module = Get-Module HGPM
                & $module { param($State) Set-PSGPOConfigurationState -State $State.Configuration; $null = Set-PSGPOLanguage -Language $State.Language } $State
                & $module ([scriptblock]::Create($Body)) @Arguments
            }.ToString()).AddArgument($ScriptBlock.ToString()).AddArgument(@($ArgumentList)).AddArgument($state)
        $operation.Handle = $Worker.PowerShell.BeginInvoke()
        $operation.Started = $true
    }.GetNewClosure()

    # The timer of the window: the import first, then the operation, then what it gives.
    $operation.Timer = [Avalonia.Threading.DispatcherTimer]::new()
    $operation.Timer.Interval = [TimeSpan]::FromMilliseconds(5)
    $operation.Timer.Add_Tick({
            # The calls of the worker to the methods of the classes, taken here (see above).
            Start-Sleep -Milliseconds 0
            if (-not $Worker.Ready) {
                if (-not $Worker.Handle.IsCompleted) { return }
                $Worker.Ready = $true
                try { [void]$Worker.PowerShell.EndInvoke($Worker.Handle) } catch { Write-Verbose "Import of the worker: $($_.Exception.Message)" }
                $Worker.PowerShell.Streams.ClearStreams()
            }
            if ($operation.Stopped -and -not $operation.Started) {
                $operation.Timer.Stop(); $Worker.Operation = $null
                & $operation.Cancelled
                return
            }
            if (-not $operation.Started) { & $start; return }
            if (-not $operation.Handle.IsCompleted) { return }
            $operation.Timer.Stop()
            $Worker.Operation = $null
            $result = $null
            $failure = $null
            try {
                $result = @($Worker.PowerShell.EndInvoke($operation.Handle))
                if ($Worker.PowerShell.HadErrors -and $Worker.PowerShell.Streams.Error.Count) { $failure = $Worker.PowerShell.Streams.Error[0] }
            } catch {
                $failure = $_
            }
            $Worker.PowerShell.Streams.ClearStreams()
            if ($operation.Stopped) { & $operation.Cancelled; return }
            if ($failure) {
                # The error of the block, not the one of EndInvoke that carries it.
                $record = $failure
                $inner = $failure.Exception
                while ($inner) {
                    if ($inner -is [System.Management.Automation.IContainsErrorRecord] -and $inner.ErrorRecord -and $inner -isnot [System.Management.Automation.MethodInvocationException]) { $record = $inner.ErrorRecord; break }
                    $inner = $inner.InnerException
                }
                & $operation.Failed $record
                return
            }
            & $operation.Done $result
        }.GetNewClosure())
    $operation.Timer.Start()
}

# Cancels the operation the worker runs: the pipeline is stopped (between two commands: a call to
# a domain controller ends first), then -Cancelled is called.
function Stop-PSGPOWindowOperation {
    [CmdletBinding()]
    param([AllowNull()] [hashtable]$Worker)

    if (-not $Worker -or -not $Worker.Operation -or $Worker.Operation.Stopped) { return }
    $Worker.Operation.Stopped = $true
    if ($Worker.Operation.Started) { [void]$Worker.PowerShell.BeginStop($null, $null) }
}
