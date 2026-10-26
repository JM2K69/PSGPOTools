#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The technical log of the console, the log of the system (event log, syslog), and the retention of
# the audit log.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $LogBefore = $env:PSGPOTOOLS_LOG_PATH
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
    }
    AfterAll { $env:PSGPOTOOLS_LOG_PATH = $LogBefore }

    Describe 'Technical log of the console' {
        BeforeEach {
            $env:PSGPOTOOLS_LOG_PATH = Join-Path $TestDrive "log-$([guid]::NewGuid())"
            $script:PSGPOLogState.Purged = $false
            $script:Before = $script:PSGPOConfigurationState.Override
            Mock Write-PSGPOSystemLog { }
        }
        AfterEach { $script:PSGPOConfigurationState.Override = $script:Before }

        It 'Keeps what Log.Level says, an entry per line and its details below it, in a file per day' {
            Write-PSGPOLogEntry -Level Information -Source 'smbclient' -Message 'Exit code 1.'
            Test-Path -LiteralPath $env:PSGPOTOOLS_LOG_PATH | Should -BeFalse -Because 'Warning by default: no Information'
            try { throw 'Cannot contact dc1' } catch { $Record = $_ }
            Write-PSGPOLogEntry -Level Error -Source 'LDAP' -Message 'The domain cannot be read.' -Detail ([ordered]@{ Server = 'dc1.contoso.com'; Output = "line 1`nline 2" }) -ErrorRecord $Record
            $File = Join-Path $env:PSGPOTOOLS_LOG_PATH "hgpm-$([datetime]::UtcNow.ToString('yyyy-MM-dd')).log"
            $Lines = @(Get-Content -LiteralPath $File)
            $Lines[0] | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z ERROR\s+LDAP\s+The domain cannot be read\.$'
            $Lines | Should -Contain '    Server: dc1.contoso.com'
            $Lines | Should -Contain '    Output: line 2'
            $Lines | Should -Contain '    Exception: System.Management.Automation.RuntimeException: Cannot contact dc1'
            Should -Invoke Write-PSGPOSystemLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' -and $EventId -eq 3000 -and $Message -like 'HGPM error (LDAP): The domain cannot be read. - Cannot contact dc1' }

            $script:PSGPOConfigurationState.Override = @{ Log = @{ Level = 'Information' } }
            Write-PSGPOLogEntry -Level Information -Source 'smbclient' -Message 'Exit code 1.'
            @(Get-Content -LiteralPath $File)[-1] | Should -BeLike '*INFORMATION smbclient*Exit code 1.'
            Should -Invoke Write-PSGPOSystemLog -Times 1 -Exactly -Because 'only the errors and the warnings go to the log of the system'
        }

        It 'Deletes the files older than Log.RetentionDays, the first time it writes' {
            $null = New-Item -ItemType Directory -Path $env:PSGPOTOOLS_LOG_PATH
            $Old = Join-Path $env:PSGPOTOOLS_LOG_PATH 'hgpm-2026-01-01.log'
            $Recent = Join-Path $env:PSGPOTOOLS_LOG_PATH 'hgpm-2026-10-01.log'
            foreach ($Item in $Old, $Recent) { Set-Content -LiteralPath $Item -Value 'x' }
            (Get-Item $Old).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-31)
            (Get-Item $Recent).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-29)
            Write-PSGPOLogEntry -Level Warning -Source 'SYSVOL' -Message 'Slow.'
            Test-Path -LiteralPath $Old | Should -BeFalse
            Test-Path -LiteralPath $Recent | Should -BeTrue
        }

        It 'Keeps a command that fails, with its exit code, its error output and the command' {
            $script:PSGPOConfigurationState.Override = @{ Log = @{ Level = 'Information' } }
            $Pwsh = (Get-Process -Id $PID).Path
            $Result = Invoke-PSGPONativeCommand -FilePath $Pwsh -ArgumentList '-NoProfile', '-Command', '[Console]::Error.WriteLine(''no ticket''); exit 3'
            $Result.ExitCode | Should -Be 3
            $Text = Get-Content -LiteralPath (Join-Path $env:PSGPOTOOLS_LOG_PATH "hgpm-$([datetime]::UtcNow.ToString('yyyy-MM-dd')).log") -Raw
            $Text | Should -BeLike "*INFORMATION*Exit code 3.*Command: $([System.IO.Path]::GetFileName($Pwsh)) -NoProfile -Command '*exit 3'*Error: no ticket*"
        }

        It 'Refuses a Log.Level it does not know, and a retention that is not a number' {
            $Base = Import-PowerShellDataFile (Get-PSGPODefaultConfigurationPath)
            "$(@(Test-PSGPOConfiguration -Configuration (Merge-PSGPOConfiguration -Base $Base -Override @{ Log = @{ Level = 'Debug' } })))" | Should -BeLike '*Log.Level must be Error, Warning, Information or Verbose*'
            "$(@(Test-PSGPOConfiguration -Configuration (Merge-PSGPOConfiguration -Base $Base -Override @{ Audit = @{ RetentionMonths = 'many' } })))" | Should -BeLike '*Audit.RetentionMonths must be a number*'
        }
    }

    Describe 'Log of the system, for a SIEM' {
        It 'Sends each change of the audit log with the event ID of its action, and the entry as JSON' {
            Mock Write-PSGPOSystemLog { }
            Write-PSGPOAuditSystemLog -Entry ([ordered]@{ Action = 'ApproveGpo'; Account = 'CONTOSO\admin'; Computer = 'PC1'; Domain = 'contoso.com'; GpoName = 'T1 - Proxy'; Target = 'CN={1}' })
            Should -Invoke Write-PSGPOSystemLog -Times 1 -Exactly -ParameterFilter {
                $EventId -eq 1011 -and $Level -eq 'Information' -and $Message -like 'HGPM audit: ApproveGpo by CONTOSO\admin from PC1 on contoso.com: T1 - Proxy - CN={1}*"Action":"ApproveGpo"*'
            }
            # Every action has an event ID of its own.
            @($script:PSGPOAuditActionText.Keys | Where-Object { -not $script:PSGPOAuditEventId.ContainsKey($_) }) | Should -BeNullOrEmpty
            @($script:PSGPOAuditEventId.Values | Group-Object | Where-Object Count -GT 1) | Should -BeNullOrEmpty
        }

        It 'Uses logger on Linux, with the priority of the level and the tag hgpm' -Skip:$IsWindows {
            $SkipBefore = $env:PSGPOTOOLS_SKIP_SYSTEM_LOG
            try {
                $env:PSGPOTOOLS_SKIP_SYSTEM_LOG = $null
                Mock Get-Command { [pscustomobject]@{ Source = '/usr/bin/logger' } } -ParameterFilter { $Name -eq 'logger' }
                Mock Invoke-PSGPONativeCommand { [pscustomobject]@{ ExitCode = 0; Output = @(); Error = '' } }
                Write-PSGPOSystemLog -Level Warning -EventId 2000 -Message 'HGPM warning (SYSVOL): slow.'
                Should -Invoke Invoke-PSGPONativeCommand -Times 1 -Exactly -ParameterFilter { $FilePath -eq '/usr/bin/logger' -and ($ArgumentList -join ' ') -eq '-t hgpm -p user.warning -- [2000] HGPM warning (SYSVOL): slow.' }
                { Register-PSGPOEventSource } | Should -Throw '*syslog/journald*nothing to register*'
            } finally {
                $env:PSGPOTOOLS_SKIP_SYSTEM_LOG = $SkipBefore
            }
        }

        It 'Sends nothing when Log.SystemLog is off' {
            $SkipBefore = $env:PSGPOTOOLS_SKIP_SYSTEM_LOG
            $Before = $script:PSGPOConfigurationState.Override
            try {
                $env:PSGPOTOOLS_SKIP_SYSTEM_LOG = $null
                $script:PSGPOConfigurationState.Override = @{ Log = @{ SystemLog = $false } }
                Mock Invoke-PSGPONativeCommand { }
                Write-PSGPOSystemLog -Level Error -EventId 3000 -Message 'x'
                Should -Invoke Invoke-PSGPONativeCommand -Times 0 -Exactly
            } finally {
                $env:PSGPOTOOLS_SKIP_SYSTEM_LOG = $SkipBefore
                $script:PSGPOConfigurationState.Override = $Before
            }
        }
    }

    Describe 'Retention of the audit log' {
        It 'Archives the months older than the retention in Archive, their folders in it, then deletes their files' {
            $Log = Join-Path $TestDrive "audit-$([guid]::NewGuid())"
            $Now = [datetime]::UtcNow
            $Month = { param([int]$Ago) $Now.AddMonths(-$Ago).ToString('yyyy-MM') }
            $Files = [ordered]@{
                "Tier1\contoso.com-$(& $Month 0)-CONTOSO_tiers1-PC1.jsonl" = 'kept: this month'
                "Tier1\contoso.com-$(& $Month 12)-CONTOSO_tiers1-PC1.jsonl" = 'kept: the 13th month'
                "Tier1\contoso.com-$(& $Month 13)-CONTOSO_tiers1-PC1.jsonl" = 'archived'
                "Tier0\contoso.com-$(& $Month 13)-CONTOSO_admin-PC2-imported.jsonl" = 'archived'
                "contoso.com-$(& $Month 20).jsonl" = 'archived: the log of an account'
            }
            foreach ($Name in $Files.Keys) {
                $Full = [System.IO.Path]::Combine([string[]](@($Log) + @($Name -split '\\')))
                $null = New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($Full)) -Force
                Set-Content -LiteralPath $Full -Value $Files[$Name]
            }
            $Directory = Import-PSGPODirectory -Path $SamplePath
            Mock Write-PSGPOAuditEntry { }

            $Result = @(Invoke-PSGPOAuditRetention -Path $Log -RetentionMonths 13 -Directory $Directory -Confirm:$false)
            @($Result.Month) | Should -Be @((& $Month 20), (& $Month 13))
            ($Result | Where-Object Month -EQ (& $Month 13)).Files | Should -Be 2
            $Zip = Join-Path $Log 'Archive' "audit-$(& $Month 13).zip"
            $Archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
            try { @($Archive.Entries.FullName | Sort-Object) | Should -Be @("Tier0/contoso.com-$(& $Month 13)-CONTOSO_admin-PC2-imported.jsonl", "Tier1/contoso.com-$(& $Month 13)-CONTOSO_tiers1-PC1.jsonl") } finally { $Archive.Dispose() }
            @(Get-ChildItem -LiteralPath $Log -Recurse -File -Filter '*.jsonl' | ForEach-Object Name | Sort-Object) |
                Should -Be @("contoso.com-$(& $Month 12)-CONTOSO_tiers1-PC1.jsonl", "contoso.com-$(& $Month 0)-CONTOSO_tiers1-PC1.jsonl")
            Should -Invoke Write-PSGPOAuditEntry -Times 1 -Exactly -ParameterFilter { $Action -eq 'PurgeAuditLog' -and $Details.Files -eq 3 }

            # Written since in a month archived: added to its archive.
            Set-Content -LiteralPath (Join-Path $Log 'Tier1' "contoso.com-$(& $Month 13)-CONTOSO_tiers2-PC3.jsonl") -Value 'late'
            $Again = @(Invoke-PSGPOAuditRetention -Path $Log -RetentionMonths 13 -Directory $Directory -Confirm:$false)
            $Again.Files | Should -Be 1
            $Archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
            try { @($Archive.Entries).Count | Should -Be 3 } finally { $Archive.Dispose() }
        }

        It 'Keeps everything with a retention of 0' {
            $Log = Join-Path $TestDrive "audit-$([guid]::NewGuid())"
            $null = New-Item -ItemType Directory -Path $Log
            Set-Content -LiteralPath (Join-Path $Log 'contoso.com-2001-01.jsonl') -Value 'old'
            @(Invoke-PSGPOAuditRetention -Path $Log -RetentionMonths 0 -Directory (Import-PSGPODirectory -Path $SamplePath) -Confirm:$false) | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $Log 'contoso.com-2001-01.jsonl') | Should -BeTrue
        }
    }
}
