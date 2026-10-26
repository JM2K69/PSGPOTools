#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Audit log: each change a domain accepted is a line of the log, read by Get-PSGPOAuditLog.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    Describe 'Audit log of the changes' {
        BeforeEach {
            $script:Log = Join-Path $TestDrive "audit-$([guid]::NewGuid())"
            Mock Get-PSGPOAuditPath { $script:Log }
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Directory.Account = 'CONTOSO\admin1'
            $Ou = $Directory.AddOrganizationalUnit($Directory.Domain, 'Servers')
            $Gpo = $Directory.AddGpo('C - Servers - Baseline', [guid]::Empty)
        }

        It 'Writes a change once the domain accepted it: when, who, from where, what, on what' {
            Mock Set-PSGPODomainBlockInheritance { $true }
            Mock Add-PSGPODomainGpLink { }
            $Directory.SetBlockInheritance($Ou, $true)
            $null = $Directory.NewLink($Ou, $Gpo)

            $Entries = @(Get-PSGPOAuditLog)
            $Entries.Count | Should -Be 2
            $Entries[0].Action | Should -Be 'NewLink' -Because 'the newest first'
            $Entries[0].GpoName | Should -Be 'C - Servers - Baseline'
            $Entries[0].GpoId | Should -Be $Gpo.Id
            $Entries[1].Action | Should -Be 'SetBlockInheritance'
            $Entries[1].Target | Should -Be 'OU=Servers,DC=contoso,DC=com'
            $Entries[1].Details.Blocked | Should -BeTrue
            $Entries[1].Account | Should -Be 'CONTOSO\admin1'
            $Entries[1].Server | Should -Be 'dc1.contoso.com'
            $Entries[1].Computer | Should -Be ([Environment]::MachineName)
            $Entries[1].Time | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-1))
            @(Get-ChildItem $script:Log).Name | Should -Be @("contoso.com-$([datetime]::UtcNow.ToString('yyyy-MM')).jsonl")
        }

        It 'Writes nothing when the domain refused the change' {
            Mock Set-PSGPODomainBlockInheritance { throw 'The account cannot block the inheritance of Servers.' }
            { $Directory.SetBlockInheritance($Ou, $true) } | Should -Throw
            @(Get-PSGPOAuditLog).Count | Should -Be 0
        }

        It 'Keeps the change when the log cannot be written, and says so' {
            Mock Set-PSGPODomainBlockInheritance { $true }
            # A file where the folder should be.
            Set-Content -LiteralPath $script:Log -Value 'not a folder'
            $Warnings = @($Directory.SetBlockInheritance($Ou, $true) 3>&1)
            "$Warnings" | Should -BeLike '*is done, but not written to the audit log*'
            $Ou.BlockInheritance | Should -BeTrue
        }

        It 'Filters on the GPO, the action, the account and the dates, and skips a damaged line' {
            Mock Set-PSGPODomainGpoStatus { }
            Mock Set-PSGPODomainBlockInheritance { $true }
            $Directory.SetGpoStatus($Gpo, 1)
            $Directory.SetBlockInheritance($Ou, $true)
            Add-Content -LiteralPath (Get-ChildItem $script:Log -File)[0].FullName -Value '{ damaged'

            @(Get-PSGPOAuditLog -Name 'C - Servers*' 3>$null).Action | Should -Be @('SetGpoStatus')
            @(Get-PSGPOAuditLog -Action 'Set*' 3>$null).Count | Should -Be 2
            @(Get-PSGPOAuditLog -Account 'CONTOSO\other' 3>$null).Count | Should -Be 0
            @(Get-PSGPOAuditLog -After (Get-Date).AddMinutes(1) 3>$null).Count | Should -Be 0
            @(Get-PSGPOAuditLog -Before (Get-Date).AddMinutes(1) 3>$null).Count | Should -Be 2
            "$(@(Get-PSGPOAuditLog 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }))" | Should -BeLike '*is not an entry of the audit log*'
        }

        It 'Logs a saved file with its hash and the new version' {
            Mock Save-PSGPODomainGpoFile { $Gpo.Version = 1 }
            $Directory.WritePolicyFile($Gpo, 'Machine', [byte[]](1, 2, 3))
            $Entry = Get-PSGPOAuditLog | Select-Object -First 1
            $Entry.Action | Should -Be 'SaveGpoFile'
            $Entry.Details.Path | Should -Be 'Machine\Registry.pol'
            $Entry.Details.Sha256 | Should -Be ([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([byte[]](1, 2, 3))))
            $Entry.Details.Version | Should -Be 1
        }

        It 'Is on by default, and writes nothing once Audit.Enabled is $false in the configuration of the domain' {
            (Get-PSGPOConfigurationData).Audit.Enabled | Should -BeTrue
            $Before = $script:PSGPOConfigurationState.Override
            try {
                $script:PSGPOConfigurationState.Override = @{ Audit = @{ Enabled = $false } }
                Mock Set-PSGPODomainBlockInheritance { $true }
                $Directory.SetBlockInheritance($Ou, $true)
                @(Get-PSGPOAuditLog).Count | Should -Be 0
                $Ou.BlockInheritance | Should -BeTrue -Because 'the change is made, only not logged'
                (Get-PSGPOConfigurationSetting | Where-Object Key -EQ 'Audit.Enabled').Kind | Should -Be 'Bool' -Because 'the Settings window offers it'
            } finally {
                $script:PSGPOConfigurationState.Override = $Before
            }
        }

        It 'Names the actions, shows the details and exports the changes to CSV' {
            Mock Save-PSGPODomainGpoFile { $Gpo.Version = 3 }
            $Directory.WritePolicyFile($Gpo, 'Machine', [byte[]](1, 2, 3))
            $Entry = Get-PSGPOAuditLog | Select-Object -First 1
            Get-PSGPOAuditActionText -Action 'SaveGpoFile' | Should -Be 'Settings of a GPO saved'
            Get-PSGPOAuditActionText -Action 'SomethingNew' | Should -Be 'SomethingNew'
            $Lines = (Format-PSGPOAuditDetail -Details $Entry.Details) -split [Environment]::NewLine
            $Lines | Should -Contain 'Path: Machine\Registry.pol'
            $Lines | Should -Contain 'Version: 3'
            # Every action the module writes has its name.
            $Written = @(Select-String -Path (Join-Path $PSScriptRoot '..' '..' 'Code' '*' '*.ps1'), (Join-Path $PSScriptRoot '..' '..' 'Code' '*' '*' '*.ps1') -Pattern "-Action '(\w+)'" -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
            $Written += 'SetGpoPermission', 'SetGpoSecurityFiltering'
            @($Written | Where-Object { -not $script:PSGPOAuditActionText.Contains($_) }) | Should -BeNullOrEmpty

            $Csv = Join-Path $TestDrive 'export\audit.csv'
            $File = Export-PSGPOAuditLogCsv -Entry @($Entry) -Path $Csv
            $File.FullName | Should -Be (Get-Item -LiteralPath $Csv).FullName
            $Read = @(Import-Csv -LiteralPath $Csv)
            $Read.Count | Should -Be 1
            $Read[0].Action | Should -Be 'SaveGpoFile'
            $Read[0].GpoName | Should -Be 'C - Servers - Baseline'
            $Read[0].Time | Should -Be $Entry.Time.ToUniversalTime().ToString('o')
            ($Read[0].Details | ConvertFrom-Json).Version | Should -Be 3
        }
    }

    Describe 'Audit.Path of the configuration' {
        It 'Refuses a relative path' {
            $Errors = @(Test-PSGPOConfiguration -Configuration (Merge-PSGPOConfiguration -Base (Import-PowerShellDataFile (Get-PSGPODefaultConfigurationPath)) -Override @{ Audit = @{ Path = 'audit' } }))
            "$Errors" | Should -BeLike '*Audit.Path must be a full path*'
        }
    }
}
