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
    }

    Describe 'Audit.Path of the configuration' {
        It 'Refuses a relative path' {
            $Errors = @(Test-PSGPOConfiguration -Configuration (Merge-PSGPOConfiguration -Base (Import-PowerShellDataFile (Get-PSGPODefaultConfigurationPath)) -Override @{ Audit = @{ Path = 'audit' } }))
            "$Errors" | Should -BeLike '*Audit.Path must be a full path*'
        }
    }
}
