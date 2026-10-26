function Invoke-PSGPOAuditRetention {
    <#
    .SYNOPSIS
        Archives the months of the audit log older than its retention, then deletes their files.
    .DESCRIPTION
        The audit log keeps Audit.RetentionMonths months (13 by default; 0 keeps everything): this
        month and the ones before it. The files of an older month, in every folder of the log (the
        tiers of the central log), go to a .zip of the folder Archive of the log,
        Archive\audit-<yyyy-MM>.zip, with their folder in it; once the archive holds them, they are
        deleted. A month already archived gets the files written since added to its archive. The
        archives are kept: delete them, or copy them away, as the policy of the company says.

        Run it as an account that deletes files of the log (an administrator of the domain: the
        accounts of the tiers do not delete), by hand or planned (a scheduled task on Windows, a
        systemd timer or cron on Linux). The folder Archive gets the permissions of the share: Tier
        0 and the readers read it. On Linux a share is reached with smbclient (Kerberos). The
        retention is written to the audit log itself (PurgeAuditLog).
    .PARAMETER Path
        The folder of the log: Audit.Path of the configuration of the domain by default, else the
        folder Audit of the backups of the account.
    .PARAMETER RetentionMonths
        Months kept; Audit.RetentionMonths of the configuration by default.
    .PARAMETER Directory
        The domain (Get-PSGPODirectory), already read: its configuration gives the log and its
        retention.
    .PARAMETER Server
        Domain controller to read the domain from. Without -Directory nor -Server, the domain of the
        computer when there is one.
    .EXAMPLE
        Invoke-PSGPOAuditRetention -WhatIf
    .EXAMPLE
        Invoke-PSGPOAuditRetention -Path \\files\gpo-audit -RetentionMonths 24
    .OUTPUTS
        PSGPOTools.AuditRetention
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/invoke-psgpoauditretention/
    .LINK
        Get-PSGPOAuditLog
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Domain')]
    [OutputType('PSGPOTools.AuditRetention')]
    param(
        [string]$Path,

        [ValidateRange(0, 1200)]
        [int]$RetentionMonths = -1,

        [Parameter(Mandatory, ParameterSetName = 'Directory')]
        [GPOToolsDirectory]$Directory,

        [Parameter(ParameterSetName = 'Domain')]
        [string]$Server
    )

    if (-not $Directory -and ($Server -or (Get-PSGPOPlatform).DomainName)) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop -WarningAction SilentlyContinue
    }
    if ($Directory) { Use-PSGPODomainConfiguration -Directory $Directory }
    if (-not $Path) { $Path = Get-PSGPOAuditPath }
    if (-not $PSBoundParameters.ContainsKey('RetentionMonths')) { $RetentionMonths = [int]"$((Get-PSGPOConfigurationData).Audit.RetentionMonths)" }
    if ($RetentionMonths -le 0) { Write-Verbose 'Audit.RetentionMonths is 0: everything is kept.'; return }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.ZipFile

    # The first month kept: this one and the ones before it, $RetentionMonths in all.
    $now = [datetime]::UtcNow
    $first = [datetime]::new($now.Year, $now.Month, 1, 0, 0, 0, [System.DateTimeKind]::Utc).AddMonths( - ($RetentionMonths - 1))
    $kept = $first.ToString('yyyy-MM', [cultureinfo]::InvariantCulture)

    $share = if (-not $IsWindows) { Get-PSGPOAuditShare -Path $Path }
    $local = $Path
    if ($share) {
        # Linux: the files of the share copied first, the old ones deleted on the share.
        $local = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-retention-$([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $local
        $command = 'prompt OFF; recurse ON; lcd "{0}"; {1}mget *' -f $local, $(if ($share.Folder) { 'cd "{0}"; ' -f $share.Folder })
        $null = Invoke-PSGPOSmbClient -Server $share.Server -Share $share.Share -TimeoutSeconds 600 -AllowMissing -IgnoreExitCode -IgnoreStatus 'NT_STATUS_ACCESS_DENIED', 'NT_STATUS_NO_SUCH_FILE' -Command $command
    }
    try {
        if (-not (Test-Path -LiteralPath $local -PathType Container)) { return }
        $archiveFolder = Join-Path $local 'Archive'
        $files = @(Get-ChildItem -LiteralPath $local -File -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue | Where-Object { -not $_.FullName.StartsWith($archiveFolder, [System.StringComparison]::OrdinalIgnoreCase) })
        $old = [ordered]@{}
        foreach ($file in $files) {
            $match = [regex]::Match($file.Name, '-(\d{4}-\d{2})(?:-[^\\/]*)?\.jsonl$')
            if (-not $match.Success -or [string]::CompareOrdinal($match.Groups[1].Value, $kept) -ge 0) { continue }
            $month = $match.Groups[1].Value
            if (-not $old.Contains($month)) { $old[$month] = [System.Collections.Generic.List[System.IO.FileInfo]]::new() }
            $old[$month].Add($file)
        }
        $done = [System.Collections.Generic.List[object]]::new()
        foreach ($month in @($old.Keys | Sort-Object)) {
            $monthFiles = $old[$month]
            $zipName = "audit-$month.zip"
            if (-not $PSCmdlet.ShouldProcess((Join-Path $Path $monthFiles[0].Name), "Archive $($monthFiles.Count) file(s) of $month in Archive\$zipName, then delete them")) { continue }
            $null = New-Item -ItemType Directory -Path $archiveFolder -Force
            $zip = Join-Path $archiveFolder $zipName
            # The archive of the month as it is on the share, to add to it.
            if ($share) {
                $remoteZip = (@($share.Folder, 'Archive', $zipName) | Where-Object { $_ }) -join '\'
                $null = Invoke-PSGPOSmbClient -Server $share.Server -Share $share.Share -AllowMissing -Command ('get "{0}" "{1}"' -f $remoteZip, $zip)
            }
            $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Update)
            try {
                foreach ($file in $monthFiles) {
                    $entryName = $file.FullName.Substring($local.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
                    $existing = $archive.GetEntry($entryName)
                    if ($existing) { $existing.Delete() }
                    $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
                }
            } finally {
                $archive.Dispose()
            }
            # Checked before anything is deleted: every file in the archive.
            $check = [System.IO.Compression.ZipFile]::OpenRead($zip)
            try { $names = @($check.Entries.FullName) } finally { $check.Dispose() }
            $relative = @($monthFiles | ForEach-Object { $_.FullName.Substring($local.TrimEnd('\', '/').Length + 1) -replace '\\', '/' })
            if (@($relative | Where-Object { $_ -notin $names }).Count) { throw "The archive $zip does not hold every file of ${month}: nothing deleted." }
            if ($share) {
                $null = Invoke-PSGPOSmbClient -Server $share.Server -Share $share.Share -IgnoreStatus 'NT_STATUS_OBJECT_NAME_COLLISION' -Command ('mkdir "{0}"' -f ((@($share.Folder, 'Archive') | Where-Object { $_ }) -join '\'))
                $null = Invoke-PSGPOSmbClient -Server $share.Server -Share $share.Share -Command ('put "{0}" "{1}"' -f $zip, $remoteZip)
                foreach ($name in $relative) {
                    $null = Invoke-PSGPOSmbClient -Server $share.Server -Share $share.Share -Command ('del "{0}"' -f ((@($share.Folder, ($name -replace '/', '\')) | Where-Object { $_ }) -join '\'))
                }
            } else {
                foreach ($file in $monthFiles) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop }
            }
            $done.Add([pscustomobject]@{
                    PSTypeName = 'PSGPOTools.AuditRetention'
                    Month = $month
                    Files = $monthFiles.Count
                    Archive = if ($share) { "$($Path.TrimEnd('\', '/'))\Archive\$zipName" } else { $zip }
                })
        }
        $done
        if ($done.Count -and $Directory) {
            Write-PSGPOAuditEntry -Directory $Directory -Action 'PurgeAuditLog' -Target $Path -Details ([ordered]@{ RetentionMonths = $RetentionMonths; Months = @($done.Month); Files = ($done | Measure-Object Files -Sum).Sum })
        }
    } finally {
        if ($share) { Remove-Item -LiteralPath $local -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
