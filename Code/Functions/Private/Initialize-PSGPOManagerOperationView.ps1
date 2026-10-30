<#
    The long operations of the console, in the background (PSGPOWindowOperation.ps1): Refresh and
    Change Domain Controller, Detect Now, a backup, a report. While one runs, the banner says what
    and offers Cancel (not to an operation that writes), and the tree and the details of the domain
    wait, so that no other change starts meanwhile; the window stays drawn and answers.

    The worker of the console starts with it (HGPM imported in its runspace takes some seconds on
    Windows; the first operation waits for it). The GUI tests (-OnShown) have none: the operations
    run on the thread of the window, where their mocks are.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerOperationView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerOperationView {
    # Running: an operation in progress; Done, Failed, Cancelled: what it does next, on the thread
    # of the window; Enabled: the buttons of the toolbar as they were before it.
    $consoleOperation = @{ Worker = $null; Running = $false; Text = $null; Done = $null; Failed = $null; Cancelled = $null; Enabled = @{} }
    if (-not $OnShown) { $consoleOperation.Worker = New-PSGPOWindowWorker }
    $window.add_Closed({ Remove-PSGPOWindowWorker -Worker $consoleOperation.Worker })

    # Runs $ScriptBlock in the background, with what it needs in -ArgumentList (not the variables
    # of the window); $Text in the banner meanwhile. -Done gets what it returned, -Failed its error;
    # -NoCancel: an operation that writes, which is not stopped half-way. $false when an operation
    # runs already.
    function Start-ConsoleOperation {
        param(
            [Parameter(Mandatory)] [string]$Text,
            [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
            [object[]]$ArgumentList = @(),
            [Parameter(Mandatory)] [scriptblock]$Done,
            [Parameter(Mandatory)] [scriptblock]$Failed,
            [scriptblock]$Cancelled = { Show-DirectoryResult -Text (Get-PSGPOText 'Cancelled: {0}' $consoleOperation.Text) -Problem },
            [switch]$NoCancel
        )
        if ($consoleOperation.Running) { return $false }
        $consoleOperation.Running = $true
        $consoleOperation.Text = $Text
        $consoleOperation.Done = $Done
        $consoleOperation.Failed = $Failed
        $consoleOperation.Cancelled = $Cancelled
        $operationTextBlock.Text = $Text
        $operationCancelButton.IsVisible = -not $NoCancel -and [bool]$consoleOperation.Worker
        $operationCancelButton.IsEnabled = $true
        $operationBanner.IsVisible = $true
        $domainTreeBorder.IsEnabled = $false
        $directoryDetailsBorder.IsEnabled = $false
        foreach ($button in $refreshButton, $browseAdmxButton, $configurationButton) {
            $consoleOperation.Enabled[$button.Name] = $button.IsEnabled
            $button.IsEnabled = $false
        }
        # Callbacks of the window, found through $consoleOperation when they run.
        Start-PSGPOWindowOperation -Worker $consoleOperation.Worker -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Language $script:PSGPOLanguage `
            -Done { param($Result) Complete-ConsoleOperation; & $consoleOperation.Done $Result } `
            -Failed { param($ErrorRecord) Complete-ConsoleOperation; & $consoleOperation.Failed $ErrorRecord } `
            -Cancelled { Complete-ConsoleOperation; & $consoleOperation.Cancelled }
        $true
    }

    function Complete-ConsoleOperation {
        $consoleOperation.Running = $false
        $operationBanner.IsVisible = $false
        $domainTreeBorder.IsEnabled = $true
        $directoryDetailsBorder.IsEnabled = $true
        foreach ($button in $refreshButton, $browseAdmxButton, $configurationButton) {
            if ($consoleOperation.Enabled.ContainsKey($button.Name)) { $button.IsEnabled = $consoleOperation.Enabled[$button.Name] }
        }
    }

    $operationCancelButton.Add_Click({
            $operationCancelButton.IsEnabled = $false
            $operationTextBlock.Text = Get-PSGPOText 'Cancelling: {0}' $consoleOperation.Text
            Stop-PSGPOWindowOperation -Worker $consoleOperation.Worker
        })
}
