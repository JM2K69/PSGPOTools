#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Backups of GPOs (Backup-PSGPO, Get-PSGPOBackup) and what changed between two of them
# (Compare-PSGPOBackup), on a directory in memory: the timeline of the History tab.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path
        Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Samples' 'Directory.sample.json'
        $Biometrics = [GPOToolsUtility]::Policies | Where-Object { $_.ID -eq 'Biometrics_EnableBio' } | Select-Object -First 1
        $MinimumLength = Get-PSGPOSecuritySetting | Where-Object Key -EQ 'MinimumPasswordLength'

        # Writes the biometrics policy and the minimum password length of a GPO.
        function Set-TestSetting {
            param($Directory, $Gpo, [string]$State, $Length)
            $Pol = [GPOToolsRegistryPol]::new()
            if ($State) { Set-PSGPOPolicyState -Policy $Biometrics -Pol $Pol -State $State }
            $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
            $Template = [GPOToolsSecurityTemplate]::new()
            Set-PSGPOSecurityValue -Template $Template -Setting $MinimumLength -Value $Length
            $Directory.WriteSecurityTemplate($Gpo, $Template.ToBytes())
        }
    }

    Describe 'Backup of a GPO' {
        BeforeEach {
            $Root = Join-Path $TestDrive "backups-$([guid]::NewGuid())"
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
        }

        It 'Keeps the files of the GPO and its properties, in a folder named after it and its last change' {
            Set-TestSetting $Directory $Gpo 'Enabled' 14
            $Backup = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $Backup.Result | Should -Be 'Created'
            Split-Path -Leaf (Split-Path -Parent $Backup.Path) | Should -Be 'C - Servers - Security Baseline {8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E20}'
            Split-Path -Leaf $Backup.Path | Should -Be ($Gpo.Modified.ToUniversalTime().ToString('yyyy-MM-dd_HH-mm-ss'))
            $Backup.Version | Should -Be $Gpo.Version
            $Backup.Status | Should -Be 'User configuration settings disabled'
            @($Backup.Links.Container) | Should -Be @('OU=Servers,DC=corp,DC=contoso,DC=com')
            @($Backup.Files.Path) | Should -Be @('Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf', 'Machine\Registry.pol')

            # The files as they are, and their hash in the manifest.
            $Pol = Join-Path $Backup.Path 'Files' 'Machine' 'Registry.pol'
            [Linq.Enumerable]::SequenceEqual([System.IO.File]::ReadAllBytes($Pol), [byte[]]$Directory.ReadPolicyFile($Gpo, 'Machine')) | Should -BeTrue
            ($Backup.Files | Where-Object Path -EQ 'Machine\Registry.pol').Sha256 | Should -Be (Get-FileHash -LiteralPath $Pol -Algorithm SHA256).Hash
        }

        It 'Does not back up a GPO again until it changes, unless -Force' {
            $First = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $Again = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $Again.Result | Should -Be 'Unchanged'
            $Again.Path | Should -Be $First.Path
            (Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName -Force).Result | Should -Be 'Created'

            Start-Sleep -Milliseconds 1100
            Set-TestSetting $Directory $Gpo 'Disabled' 12
            (Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName).Result | Should -Be 'Created'
            $Directory.SetGpoStatus($Gpo, 0)
            (Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName).Result | Should -Be 'Created' -Because 'its status changed'
            @(Get-PSGPOBackup -Path $Root).Count | Should -Be 4
        }

        It 'Keeps the history of a renamed GPO in its folder' {
            $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $Gpo.DisplayName = 'Servers baseline: renamed'
            $Backup = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            @(Get-ChildItem -LiteralPath $Root -Directory).Count | Should -Be 1
            @(Get-PSGPOBackup -Path $Root -Id $Gpo.Id).DisplayName | Should -Be @('Servers baseline: renamed', 'C - Servers - Security Baseline')
            $Backup.Result | Should -Be 'Created' -Because 'its name changed'
        }

        It 'Backs up every GPO, or those named, and says which are missing' {
            $All = @(Backup-PSGPO -Directory $Directory -Path $Root)
            $All.Count | Should -Be $Directory.Gpos.Count
            @(Backup-PSGPO -Directory $Directory -Path $Root -Name 'C - Servers - *').Result | Should -Not -Contain 'Created'
            Backup-PSGPO -Directory $Directory -Path $Root -Name 'Missing GPO' -ErrorVariable Problem -ErrorAction SilentlyContinue
            "$Problem" | Should -BeLike "*No GPO named 'Missing GPO'*"
        }

        It 'Lists the backups newest first, and ignores a folder it cannot read' {
            $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            Start-Sleep -Milliseconds 1100
            Set-TestSetting $Directory $Gpo 'Enabled' 14
            $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $null = New-Item -ItemType Directory -Path (Join-Path $Root 'Not a backup' 'x') -Force
            Set-Content -LiteralPath (Join-Path $Root 'Not a backup' 'x' 'manifest.json') -Value '{ broken'
            # The warnings of the module functions it calls: through the stream, not -WarningVariable.
            $Output = @(Get-PSGPOBackup -Path $Root 3>&1)
            $Backups = @($Output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
            $Backups.Count | Should -Be 2
            $Backups[0].BackedUp | Should -BeGreaterThan $Backups[1].BackedUp
            "$($Output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })" | Should -BeLike '*cannot be read*'
            @(Get-PSGPOBackup -Path $Root -Name 'Other*').Count | Should -Be 0
        }

        It 'Names the folder of a GPO without the characters a file name cannot hold' {
            $Gpo.DisplayName = 'Proxy: http/https <v2>?'
            Get-PSGPOBackupFolderName -Gpo $Gpo | Should -Be 'Proxy_ http_https _v2__ {8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E20}'
        }

        It 'Reads the last change of a GPO from the directory' {
            ConvertFrom-PSGPOGeneralizedTime '20261015093012.0Z' | Should -Be ([datetime]::new(2026, 10, 15, 9, 30, 12, [DateTimeKind]::Utc))
            (ConvertFrom-PSGPOGeneralizedTime '20261015093012.0Z').Kind | Should -Be 'Utc'
            ConvertFrom-PSGPOGeneralizedTime '' | Should -BeNullOrEmpty
        }
    }

    Describe 'Restore of a GPO from a backup' {
        BeforeEach {
            $Root = Join-Path $TestDrive "restore-$([guid]::NewGuid())"
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            Set-TestSetting $Directory $Gpo 'Enabled' 14
            $Old = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            Start-Sleep -Milliseconds 1100
            # Then: another setting, a user policy, another status.
            Set-TestSetting $Directory $Gpo 'Disabled' 8
            $UserPol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy ([GPOToolsUtility]::Policies | Where-Object { $_.ID -eq 'DisallowCpls' } | Select-Object -First 1) -Pol $UserPol -State Disabled
            $Directory.WritePolicyFile($Gpo, 'User', $UserPol.ToBytes())
            $Directory.SetGpoStatus($Gpo, 0)
        }

        It 'Puts back the files, status and extensions of the backup, increasing the version, after backing up the GPO' {
            $Before = $Gpo.Version
            $Result = Restore-PSGPO -Backup $Old -Directory $Directory -Confirm:$false
            [Linq.Enumerable]::SequenceEqual([byte[]]$Directory.ReadPolicyFile($Gpo, 'Machine'), [System.IO.File]::ReadAllBytes((Join-Path $Old.Path 'Files' 'Machine' 'Registry.pol'))) | Should -BeTrue
            $Directory.ReadPolicyFile($Gpo, 'User') | Should -BeNullOrEmpty -Because 'the backup has no user setting'
            $Gpo.GetStatus() | Should -Be 'User configuration settings disabled'
            "$($Gpo.UserExtensionNames)" | Should -Be "$($Old.UserExtensionNames)"
            $Gpo.GetComputerVersion() | Should -Be (($Before -band 0xFFFF) + 1)
            $Gpo.GetUserVersion() | Should -Be (($Before -shr 16) + 1)
            $Result.Version | Should -Be $Gpo.Version

            # The GPO before the restore is the newest backup; now it is as the restored one.
            $Result.BackupBefore | Should -Not -BeNullOrEmpty
            $Backups = @(Get-PSGPOBackup -Path $Root)
            $Backups[0].Path | Should -Be $Result.BackupBefore
            $Now = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            Compare-PSGPOBackup -ReferenceBackup $Old -DifferenceBackup $Now | Should -BeNullOrEmpty
        }

        It 'Restores nothing with -WhatIf, from a changed backup, or for a GPO not in the domain' {
            $Version = $Gpo.Version
            Restore-PSGPO -Backup $Old -Directory $Directory -WhatIf
            $Gpo.Version | Should -Be $Version

            [System.IO.File]::WriteAllBytes((Join-Path $Old.Path 'Files' 'Machine' 'Registry.pol'), [byte[]](1, 2, 3))
            { Restore-PSGPO -Backup $Old -Directory $Directory -Confirm:$false } | Should -Throw -ExpectedMessage '*was changed*Registry.pol*'
            $Gpo.Version | Should -Be $Version

            $Other = Import-PSGPODirectory -Path $SamplePath
            $Other.Gpos.Remove($Other.FindGpo('C - Servers - Security Baseline'))
            { Restore-PSGPO -Backup $Old -Directory $Other -Confirm:$false } | Should -Throw -ExpectedMessage '*is not in corp.contoso.com*'
        }

        It 'Finds the extensions of the files of a backup without them' {
            $Files = [ordered]@{ 'Machine\Registry.pol' = [byte[]]@(); 'Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf' = [byte[]]@() }
            Get-PSGPOFileExtensionName -Files $Files -Scope Machine |
                Should -Be '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}][{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]'
            Get-PSGPOFileExtensionName -Files $Files -Scope User | Should -Be ''
        }
    }

    Describe 'What changed between two backups' {
        BeforeAll {
            $Root = Join-Path $TestDrive 'timeline'
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            Start-Sleep -Milliseconds 1100
            Set-TestSetting $Directory $Gpo 'Enabled' 14
            $Directory.GpoFiles["$($Gpo.Id)\Machine\Scripts\scripts.ini"] = [System.Text.Encoding]::Unicode.GetBytes('[Startup]')
            $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            Start-Sleep -Milliseconds 1100
            Set-TestSetting $Directory $Gpo 'Disabled' $null
            $null = $Directory.NewFilteringGroups($Gpo, $null)
            $null = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $Backups = @(Get-PSGPOBackup -Path $Root)
        }

        It 'Lists the settings added at the first change, by category path' {
            $Changes = @(Compare-PSGPOBackup -ReferenceBackup $Backups[2] -DifferenceBackup $Backups[1])
            @($Changes | ForEach-Object { "$($_.Change) | $($_.Scope) | $($_.Name) | $($_.After)" }) | Should -Be @(
                'Added | Computer | Allow the use of biometrics | Enabled'
                'Added | Computer | Minimum password length | 14 characters'
                "Added | Files | Machine\Scripts\scripts.ini | 18 bytes, SHA-256 $((Get-PSGPOFileHash -Bytes $Directory.GpoFiles["$($Gpo.Id)\Machine\Scripts\scripts.ini"]).Substring(0, 12))")
            ($Changes | Where-Object Name -EQ 'Allow the use of biometrics').Path | Should -Be 'Policies > Administrative Templates > Windows Components > Biometrics'
        }

        It 'Shows a setting changed with its value before and after, a removed one, and the security filtering' {
            $Changes = @(Compare-PSGPOBackup -ReferenceBackup $Backups[1] -DifferenceBackup $Backups[0])
            $Bio = $Changes | Where-Object Name -EQ 'Allow the use of biometrics'
            $Bio.Change | Should -Be 'Changed'
            $Bio.Before | Should -Be 'Enabled'
            $Bio.After | Should -Be 'Disabled'
            ($Changes | Where-Object Name -EQ 'Minimum password length').Change | Should -Be 'Removed'
            $Filtering = $Changes | Where-Object Name -EQ 'Security filtering'
            $Filtering.Scope | Should -Be 'GPO'
            "$($Filtering.Before) -> $($Filtering.After)" | Should -Be 'Authenticated Users -> APPLY_C - Servers - Security Baseline'
            # The GPO properties first, then the computer settings.
            $Changes[0].Scope | Should -Be 'GPO'
        }

        It 'Finds nothing between a backup and itself' {
            Compare-PSGPOBackup -ReferenceBackup $Backups[0] -DifferenceBackup $Backups[0] | Should -BeNullOrEmpty
        }
    }
}
