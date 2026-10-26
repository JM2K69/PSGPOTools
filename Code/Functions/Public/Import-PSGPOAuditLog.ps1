function Import-PSGPOAuditLog {
    <#
    .SYNOPSIS
        Moves the changes of an audit log of a console into the central audit log of the domain.
    .DESCRIPTION
        Before the central log (Audit.Path), each console wrote its changes in the folder Audit of
        the backups of its account. Import-PSGPOAuditLog adds them to the central log as the
        consoles write it now: each change in a file of its account, of its computer and of its
        month, in the folder of the tier of the account (read in its groups, as for a change made
        now; an account the domain does not know goes to Unassigned). The file is named
        ...-imported.jsonl: the account that runs the import owns it, and each account writes only
        the files it made. Only the changes of the domain of the directory are imported: those of
        other domains are left out, with a warning, and -Remove keeps the files that hold them.

        It can run again: a change already in the central log (same time, account, action and
        target) is not written twice. With -Remove, the files read are deleted once their changes
        are written. Run it with an account that writes every tier (an administrator of the
        domain), as the files go in the folders of the accounts that made the changes.
    .PARAMETER Path
        The folder of the log to import (the folder Audit of the backups of an account).
    .PARAMETER Destination
        The central log: Audit.Path of the configuration of the domain by default.
    .PARAMETER Remove
        Deletes the files read, once their changes are in the central log.
    .PARAMETER Directory
        The domain (Get-PSGPODirectory), already read: its configuration gives the central log and
        the tiers.
    .PARAMETER Server
        Domain controller to read the domain from. By default, the domain of the computer.
    .PARAMETER Credential
        Account to read the domain with, instead of the current identity.
    .EXAMPLE
        Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -WhatIf
    .EXAMPLE
        Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -Server dc.hardenbox.labo -Remove
    .OUTPUTS
        PSGPOTools.AuditImport
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/import-psgpoauditlog/
    .LINK
        Initialize-PSGPOAuditShare
    .LINK
        Get-PSGPOAuditLog
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Domain')]
    [OutputType('PSGPOTools.AuditImport')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Destination,

        [switch]$Remove,

        [Parameter(Mandatory, ParameterSetName = 'Directory')]
        [GPOToolsLdapDirectory]$Directory,

        [Parameter(ParameterSetName = 'Domain')]
        [string]$Server,

        [Parameter(ParameterSetName = 'Domain')]
        [pscredential]$Credential
    )

    $source = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "No folder $source." }
    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        if ($Credential) { $read.Credential = $Credential }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    if (-not $Destination) { $Destination = "$((Get-PSGPOConfigurationData).Audit.Path)".Trim() }
    if (-not $Destination) { throw 'No central audit log: give -Destination, or set Audit.Path in the configuration of the domain.' }

    $files = @(Get-ChildItem -LiteralPath $source -File -Recurse -Filter '*.jsonl')
    # The changes of this domain only: the log of a console may hold those of other domains (its
    # file kept by -Remove, for the import of its domain).
    $entries = [System.Collections.Generic.List[object]]::new()
    $kept = [System.Collections.Generic.HashSet[string]]::new()
    $others = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        foreach ($entry in @(Read-PSGPOAuditFile -File @($file))) {
            if ("$($entry.Domain)" -eq $Directory.DomainName) { $entries.Add($entry) }
            else { $others.Add($entry); $null = $kept.Add($file.FullName) }
        }
    }
    $entries = @($entries)
    if ($others.Count) { Write-Warning "$($others.Count) change(s) of other domains left out ($(@($others.Domain | Sort-Object -Unique) -join ', ')): import them with the directory of their domain." }
    # What the central log has already: the same change is not written twice.
    $key = { param($Entry) '{0}|{1}|{2}|{3}' -f $Entry.Time.ToUniversalTime().ToString('o'), $Entry.Account, $Entry.Action, $Entry.Target }
    $known = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($entry in @(Read-PSGPOAuditEntry -Path $Destination 3>$null)) { $null = $known.Add((& $key $entry)) }

    # The tier of each account, read once.
    $tiers = @{}
    $cache = @{}
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        foreach ($account in @($entries | ForEach-Object Account | Sort-Object -Unique)) {
            try {
                $tiers["$account"] = Get-PSGPOAuditAccountTier -Connection $connection -Directory $Directory -Account "$account" -Cache $cache
            } catch {
                Write-Warning "The tier of $account cannot be read, its changes go to Unassigned: $($_.Exception.GetBaseException().Message)"
                $tiers["$account"] = 'Unassigned'
            }
        }
    } finally {
        $connection.Dispose()
    }

    # The changes by file of the central log, oldest first, as they were written.
    $byFile = [ordered]@{}
    $skipped = 0
    foreach ($entry in @($entries | Sort-Object Time)) {
        if ($known.Contains((& $key $entry))) { $skipped++; continue }
        $tier = $tiers["$($entry.Account)"]
        $name = Get-PSGPOAuditCentralFileName -Tier $tier -Domain $entry.Domain -Time $entry.Time -Account "$($entry.Account)" -Computer "$($entry.Computer)" -Suffix 'imported'
        if (-not $byFile.Contains($name)) { $byFile[$name] = [pscustomobject]@{ Tier = $tier; Account = $entry.Account; Computer = $entry.Computer; Lines = [System.Collections.Generic.List[string]]::new() } }
        $line = [ordered]@{
            Format = $script:PSGPOAuditFormat
            Time = $entry.Time.ToUniversalTime().ToString('o')
            Domain = $entry.Domain
            Server = $entry.Server
            Account = $entry.Account
            Computer = $entry.Computer
            Action = $entry.Action
            Target = $entry.Target
            GpoId = if ($entry.GpoId) { $entry.GpoId.ToString() }
            GpoName = $entry.GpoName
            Tier = $tier
            Details = if ($entry.Details) { $entry.Details } else { @{} }
        }
        $byFile[$name].Lines.Add((ConvertTo-Json -InputObject $line -Depth 5 -Compress))
    }
    if ($skipped) { Write-Verbose "$skipped change(s) already in $Destination." }

    $share = if (-not $IsWindows) { Get-PSGPOAuditShare -Path $Destination }
    foreach ($name in $byFile.Keys) {
        $item = $byFile[$name]
        if (-not $PSCmdlet.ShouldProcess("$Destination\$name", "Add $($item.Lines.Count) change(s)")) { continue }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((($item.Lines -join "`n") + "`n"))
        if ($share) {
            Add-PSGPOAuditShareLine -Share $share -Name $name -Bytes $bytes
        } else {
            $file = [System.IO.Path]::Combine([string[]](@($Destination) + @($name -split '\\')))
            $null = New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($file)) -Force -ErrorAction Stop
            $stream = [System.IO.FileStream]::new($file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        }
        [pscustomobject]@{ PSTypeName = 'PSGPOTools.AuditImport'; File = $name; Tier = $item.Tier; Account = $item.Account; Computer = $item.Computer; Changes = $item.Lines.Count }
    }
    if ($Remove -and -not $WhatIfPreference) {
        foreach ($file in $files) {
            if ($kept.Contains($file.FullName)) { continue }
            if ($PSCmdlet.ShouldProcess($file.FullName, 'Delete the file, its changes are in the central log')) { Remove-Item -LiteralPath $file.FullName -Force }
        }
    }
}
