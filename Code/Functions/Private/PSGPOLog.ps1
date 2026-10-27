<#
    The technical log of the console and the log of the system.

    - The technical log: what goes wrong where the console runs (LDAP, SYSVOL, samba-tool,
      smbclient, the commands with their output), to find the cause afterwards. One file per day in
      the data of the user (%LOCALAPPDATA%\PSGPOTools\Logs, ~/.local/share/PSGPOTools/Logs):
      hgpm-<yyyy-MM-dd>.log, an entry per line, its details indented below it. Log.Level of the
      configuration says what it keeps; the files older than Log.RetentionDays are deleted the first
      time the console writes there.
    - The log of the system (Log.SystemLog), for a SIEM: each change of the audit log and each error
      of the technical log, in the Windows event log (Application, source HGPM: an event ID per
      action, Register-PSGPOEventSource once per computer) or in syslog/journald (logger, tag hgpm).

    Writing a log never stops the console: a log that cannot be written is left aside.
#>

$script:PSGPOLogLevels = @{ Error = 1; Warning = 2; Information = 3; Verbose = 4 }
$script:PSGPOLogState = @{ Purged = $false; EventSourceMissing = $false; InSystemLog = $false }

# The event IDs of the system log: one per action of the audit log, 2000 the warnings, 3000 the
# errors of the technical log. Never changed once given: a SIEM filters on them.
$script:PSGPOAuditEventId = @{
    NewGpo = 1001; RenameGpo = 1002; SetGpoStatus = 1003; RemoveGpo = 1004; RemoveDeletedGpoBackup = 1005
    RestoreGpo = 1006; ImportGpo = 1007; SaveGpoFile = 1008; ImportPolicyRuleSet = 1009; PendingGpo = 1010; ApproveGpo = 1011
    NewLink = 1020; SetLink = 1021; RemoveLink = 1022; SetBlockInheritance = 1023
    SetGpoPermission = 1030; SetGpoSecurityFiltering = 1031; NewFilteringGroups = 1032
    SetWmiFilter = 1040; NewWmiFilter = 1041; EditWmiFilter = 1042; RemoveWmiFilter = 1043; SetWmiFilterPermission = 1044
    NewPasswordPolicy = 1050; SetPasswordPolicy = 1051; RemovePasswordPolicy = 1052
    SaveConfiguration = 1060; InstallAdmx = 1061; InitializeAuditShare = 1062; InitializeBackupShare = 1063; PurgeAuditLog = 1064
}

# The folder of the technical log: PSGPOTOOLS_LOG_PATH, else the data of the user.
function Get-PSGPOLogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:PSGPOTOOLS_LOG_PATH) { return $env:PSGPOTOOLS_LOG_PATH }
    $data = if ($IsWindows) { [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) } elseif ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local' 'share' }
    if (-not $data) { $data = $HOME }
    Join-Path $data 'PSGPOTools' 'Logs'
}

# Adds an entry to the technical log when Log.Level keeps it, and an error or a warning to the log
# of the system. $Detail: what explains it (the command, its output, the server...), one line each.
function Write-PSGPOLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Error', 'Warning', 'Information', 'Verbose')] [string]$Level,
        # What wrote it: LDAP, SYSVOL, smbclient, samba-tool, the GPO console...
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Message,
        [System.Collections.IDictionary]$Detail,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    try {
        $setting = (Get-PSGPOConfigurationData).Log
        $kept = $script:PSGPOLogLevels["$($setting.Level)"]
        if (-not $kept) { $kept = $script:PSGPOLogLevels.Warning }
        $now = [datetime]::UtcNow
        if ($script:PSGPOLogLevels[$Level] -le $kept) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add(('{0} {1,-11} {2,-12} {3}' -f $now.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [cultureinfo]::InvariantCulture), $Level.ToUpperInvariant(), $Source, $Message))
            if ($Detail) { foreach ($name in $Detail.Keys) { foreach ($text in @("$($Detail[$name])" -split '\r?\n' | Where-Object { $_ })) { $lines.Add("    ${name}: $text") } } }
            if ($ErrorRecord) {
                $lines.Add("    Exception: $($ErrorRecord.Exception.GetType().FullName): $($ErrorRecord.Exception.GetBaseException().Message)")
                foreach ($text in @("$($ErrorRecord.ScriptStackTrace)" -split '\r?\n' | Where-Object { $_ })) { $lines.Add("    at $text") }
            }
            $folder = Get-PSGPOLogPath
            $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop -WhatIf:$false
            if (-not $script:PSGPOLogState.Purged) {
                $script:PSGPOLogState.Purged = $true
                $days = 30
                if ([int]::TryParse("$($setting.RetentionDays)", [ref]$days) -and $days -gt 0) {
                    Get-ChildItem -LiteralPath $folder -File -Filter 'hgpm-*.log' -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTimeUtc -lt $now.AddDays(-$days) } | Remove-Item -Force -ErrorAction SilentlyContinue
                }
            }
            $file = Join-Path $folder ('hgpm-{0}.log' -f $now.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture))
            $bytes = [System.Text.Encoding]::UTF8.GetBytes((($lines -join "`n") + "`n"))
            $stream = [System.IO.FileStream]::new($file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        }
    } catch {
        Write-Verbose "The technical log is not written: $($_.Exception.Message)"
    }
    if ($Level -in 'Error', 'Warning') {
        $id = if ($Level -eq 'Error') { 3000 } else { 2000 }
        $text = "HGPM $($Level.ToLowerInvariant()) ($Source): $Message"
        if ($ErrorRecord) { $text += " - $($ErrorRecord.Exception.GetBaseException().Message)" }
        Write-PSGPOSystemLog -Level $Level -EventId $id -Message $text
    }
}

# Sends an event to the log of the system when Log.SystemLog is on: the Windows event log (source
# HGPM, Application), else syslog/journald (logger -t hgpm).
function Write-PSGPOSystemLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Error', 'Warning', 'Information')] [string]$Level,
        [Parameter(Mandatory)] [int]$EventId,
        [Parameter(Mandatory)] [string]$Message
    )

    # The tests (CI/Invoke-Tests.ps1) write nothing there.
    if ($script:PSGPOLogState.InSystemLog -or $env:PSGPOTOOLS_SKIP_SYSTEM_LOG) { return }
    try {
        if ((Get-PSGPOConfigurationData).Log.SystemLog -eq $false) { return }
    } catch { return }
    $script:PSGPOLogState.InSystemLog = $true
    try {
        if ($IsWindows) {
            if ($script:PSGPOLogState.EventSourceMissing) { return }
            try {
                $type = [System.Diagnostics.EventLogEntryType]$Level
                # 32766 characters at most in an event.
                [System.Diagnostics.EventLog]::WriteEntry('HGPM', $Message.Substring(0, [Math]::Min($Message.Length, 31000)), $type, $EventId)
            } catch {
                # Not registered: only an administrator creates the source.
                $script:PSGPOLogState.EventSourceMissing = $true
                Write-PSGPOLogEntry -Level Information -Source 'Event log' -Message 'The event source HGPM is not registered on this computer: nothing goes to the event log until an administrator runs Register-PSGPOEventSource.' -Detail @{ Error = $_.Exception.GetBaseException().Message }
            }
            return
        }
        $logger = Get-Command -Name 'logger' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $logger) { return }
        $priority = switch ($Level) { 'Error' { 'user.err' } 'Warning' { 'user.warning' } default { 'user.notice' } }
        $null = Invoke-PSGPONativeCommand -FilePath $logger.Source -TimeoutSeconds 10 -ArgumentList '-t', 'hgpm', '-p', $priority, '--', "[$EventId] $Message"
    } catch {
        Write-Verbose "The log of the system is not written: $($_.Exception.Message)"
    } finally {
        $script:PSGPOLogState.InSystemLog = $false
    }
}
