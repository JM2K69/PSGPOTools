function Register-PSGPOEventSource {
    <#
    .SYNOPSIS
        Registers the event source HGPM in the Windows event log of this computer, once.
    .DESCRIPTION
        The consoles send each change of the audit log and each error of their technical log to the
        log of the system (Log.SystemLog of the configuration), for a SIEM: on Windows, the
        Application event log, source HGPM, an event ID per action. Only an administrator creates an
        event source: run Register-PSGPOEventSource once per computer, in PowerShell run as an
        administrator (a deployment script, a GPO startup script). Until then, the consoles of the
        computer write nothing to the event log, and say so in their technical log.

        On Linux there is nothing to register: the consoles send their events to syslog/journald
        with logger (tag hgpm), as any account may.
    .EXAMPLE
        Register-PSGPOEventSource
    .EXAMPLE
        # The events of HGPM, newest first
        Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'HGPM' } -MaxEvents 20
    .OUTPUTS
        PSGPOTools.EventSource
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/register-psgpoeventsource/
    .LINK
        Invoke-PSGPOAuditRetention
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.EventSource')]
    param()

    if (-not $IsWindows) { throw 'The event log is the one of Windows: on Linux the consoles send their events to syslog/journald (logger -t hgpm), nothing to register.' }
    $exists = $false
    try { $exists = [System.Diagnostics.EventLog]::SourceExists('HGPM') } catch { Write-Verbose "The event sources cannot be read: $($_.Exception.Message)" }
    if (-not $exists) {
        if (-not $PSCmdlet.ShouldProcess('Application', 'Register the event source HGPM')) { return }
        try {
            [System.Diagnostics.EventLog]::CreateEventSource('HGPM', 'Application')
        } catch {
            throw "The event source HGPM is not registered: $($_.Exception.GetBaseException().Message) Run PowerShell as an administrator."
        }
    }
    [pscustomobject]@{ PSTypeName = 'PSGPOTools.EventSource'; Source = 'HGPM'; Log = 'Application'; Created = -not $exists }
}
