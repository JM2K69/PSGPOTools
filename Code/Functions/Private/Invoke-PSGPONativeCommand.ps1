<#
    Runs a command of the system (samba-tool, smbclient) so that it can never wait for the user:
    its standard input is closed at once, so a prompt (a password, a confirmation) reads the end
    of input instead of the keyboard of the terminal the window was started from; and it is
    stopped after a time limit. A prompt waiting on the terminal froze the window before
    (samba-tool gpo create asks for a password even with --use-kerberos=required).
#>

function Invoke-PSGPONativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        # Stopped (and its child processes) after this time.
        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 120
    )

    $start = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($argument in $ArgumentList) { $start.ArgumentList.Add($argument) }
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($start)
    try {
        # Nothing to read: a prompt gets the end of input.
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch { Write-Verbose "Stopping $FilePath failed: $($_.Exception.Message)" }
            throw "$([System.IO.Path]::GetFileName($FilePath)) $($ArgumentList[0..1] -join ' ') did not end within $TimeoutSeconds seconds: stopped."
        }
        # Ends the reading of the redirected streams.
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = @($output.GetAwaiter().GetResult() -split '\r?\n' | Where-Object { $_ -ne '' })
            Error = $errors.GetAwaiter().GetResult()
        }
    } finally {
        $process.Dispose()
    }
}
