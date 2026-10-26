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
        It 'Refuses a relative path, takes a share written as on Windows or on Linux' {
            $Base = Import-PowerShellDataFile (Get-PSGPODefaultConfigurationPath)
            $Errors = @(Test-PSGPOConfiguration -Configuration (Merge-PSGPOConfiguration -Base $Base -Override @{ Audit = @{ Path = 'audit' } }))
            "$Errors" | Should -BeLike '*Audit.Path must be a full path*'
            foreach ($Share in '\\files\gpo-audit', '//files/gpo-audit/logs') {
                @(Test-PSGPOConfiguration -Configuration (Merge-PSGPOConfiguration -Base $Base -Override @{ Audit = @{ Path = $Share } })) | Should -BeNullOrEmpty
            }
            Get-PSGPOAuditShare -Path '//files/gpo-audit/logs/2026' | Should -BeLike '*Server=files; Share=gpo-audit; Folder=logs\2026*'
            Get-PSGPOAuditShare -Path '\\files\gpo-audit' | Should -BeLike '*Folder=}'
            Get-PSGPOAuditShare -Path '/srv/gpo-audit' | Should -BeNullOrEmpty
        }
    }

    Describe 'Central audit log, a folder per tier' {
        BeforeEach {
            $script:Central = Join-Path $TestDrive "central-$([guid]::NewGuid())"
            $script:Before = $script:PSGPOConfigurationState.Override
            $script:PSGPOConfigurationState.Override = @{ Audit = @{ Path = $script:Central; Tiers = @{ Tier1 = 'GPO-Tier1-Admins'; Tier2 = 'GPO-Tier2-Admins' }; Readers = 'GPO-Auditors' } }
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Directory.Account = 'CONTOSO\tiers1'
            $Directory.IsDomainAdministrator = $false
            $Ou = $Directory.AddOrganizationalUnit($Directory.Domain, 'Servers')
        }
        AfterEach { $script:PSGPOConfigurationState.Override = $script:Before }

        It 'Finds the tier of the account in its groups: Tier 0 the administrators and the approvers, then Audit.Tiers' {
            Mock Get-PSGPOAccountGroupSid { , [string[]]@('S-1-5-21-1-2-3-1105', 'S-1-5-21-1-2-3-2001') }
            Mock Find-PSGPODomainAccount {
                switch ($Name) {
                    'Domain Admins' { [pscustomobject]@{ Name = $Name; Sid = 'S-1-5-21-1-2-3-512' } }
                    'GPO-Tier1-Admins' { [pscustomobject]@{ Name = $Name; Sid = 'S-1-5-21-1-2-3-2001' } }
                    'GPO-Tier2-Admins' { [pscustomobject]@{ Name = $Name; Sid = 'S-1-5-21-1-2-3-2002' } }
                    default { throw "No account named '$Name' in the domain." }
                }
            }
            $Connection = [pscustomobject]@{}
            Update-PSGPOAuditTier -Connection $Connection -Directory $Directory
            $Directory.AuditTier | Should -Be 'Tier1'
            $Directory.IsDomainAdministrator = $true
            Update-PSGPOAuditTier -Connection $Connection -Directory $Directory
            $Directory.AuditTier | Should -Be 'Tier0'
            $Directory.IsDomainAdministrator = $false
            Mock Get-PSGPOAccountGroupSid { , [string[]]@('S-1-5-21-1-2-3-1106') }
            $script:PSGPOConfigurationState.Override.Audit.Tiers.Tier2 = 'GPO-Missing, GPO-Tier2-Admins'
            $Warnings = @(Update-PSGPOAuditTier -Connection $Connection -Directory $Directory 3>&1)
            $Directory.AuditTier | Should -Be 'Unassigned' -Because 'an account in no tier'
            "$Warnings" | Should -BeLike "*No account named 'GPO-Missing'*"
        }

        It 'Writes each account in its own file of the folder of its tier, and reads every tier it can' {
            Mock Set-PSGPODomainBlockInheritance { $true }
            $Directory.AuditTier = 'Tier1'
            $Directory.SetBlockInheritance($Ou, $true)
            $Other = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Other.Account = 'CONTOSO\tiers2'
            $Other.AuditTier = 'Tier2'
            $OtherOu = $Other.AddOrganizationalUnit($Other.Domain, 'Workstations')
            $Other.SetBlockInheritance($OtherOu, $true)

            $Month = [datetime]::UtcNow.ToString('yyyy-MM')
            $Computer = [Environment]::MachineName -replace '[^\w.-]', '_'
            @(Get-ChildItem -LiteralPath $script:Central -Recurse -File | ForEach-Object { $_.FullName.Substring($script:Central.Length + 1) -replace '\\', '/' } | Sort-Object) |
                Should -Be @("Tier1/contoso.com-$Month-CONTOSO_tiers1-$Computer.jsonl", "Tier2/contoso.com-$Month-CONTOSO_tiers2-$Computer.jsonl")
            $Entries = @(Get-PSGPOAuditLog)
            @($Entries.Tier | Sort-Object) | Should -Be @('Tier1', 'Tier2')
            @(Get-PSGPOAuditLog -Domain 'contoso.com').Count | Should -Be 2
        }

        It 'Writes a share with smbclient on Linux: the file of the account read, the line added, the folder of its tier made' {
            $script:Commands = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-PSGPOSmbClient {
                $script:Commands.Add("$Server/$Share $Command")
                if ($Command -like 'get *') {
                    $Local = [regex]::Match($Command, 'get "[^"]+" "([^"]+)"').Groups[1].Value
                    [System.IO.File]::WriteAllText($Local, "{`"first`":1}`n")
                    , @('getting file')
                } elseif ($Command -like 'put *') {
                    $Local = [regex]::Match($Command, 'put "([^"]+)"').Groups[1].Value
                    $script:Written = [System.IO.File]::ReadAllText($Local)
                    , @('putting file')
                } else { , @() }
            }
            Add-PSGPOAuditShareLine -Share (Get-PSGPOAuditShare -Path '\\files\gpo-audit\logs') -Name 'Tier1\contoso.com-2026-10-CONTOSO_tiers1-PC1.jsonl' -Bytes ([System.Text.Encoding]::UTF8.GetBytes("{`"second`":2}`n"))
            $script:Commands[0] | Should -BeLike 'files/gpo-audit get "logs\Tier1\contoso.com-2026-10-CONTOSO_tiers1-PC1.jsonl" *'
            @($script:Commands | Where-Object { $_ -like '*mkdir*' }) | Should -Be @('files/gpo-audit mkdir "logs"', 'files/gpo-audit mkdir "logs\Tier1"')
            $script:Commands[-1] | Should -BeLike 'files/gpo-audit put * "logs\Tier1\contoso.com-2026-10-CONTOSO_tiers1-PC1.jsonl"'
            $script:Written | Should -Be "{`"first`":1}`n{`"second`":2}`n" -Because 'the lines already there are kept'
        }
    }

    Describe 'Import of the log of a console into the central log' {
        It 'Puts each change in the file of its account, computer and month, in the folder of its tier, once' {
            $Old = Join-Path $TestDrive "old-$([guid]::NewGuid())"
            $Central = Join-Path $TestDrive "central-$([guid]::NewGuid())"
            $null = New-Item -ItemType Directory -Path $Old
            $Line = {
                param($Time, $Account, $Action)
                [ordered]@{ Format = 'PSGPOTools.Audit/1'; Time = $Time; Domain = 'contoso.com'; Server = 'dc1.contoso.com'; Account = $Account; Computer = 'dc'; Action = $Action; Target = 'OU=Servers'; GpoId = $null; GpoName = $null; Details = @{ Blocked = $true } } | ConvertTo-Json -Compress
            }
            Set-Content -LiteralPath (Join-Path $Old 'contoso.com-2026-10.jsonl') -Encoding utf8 -Value @(
                (& $Line '2026-10-11T10:00:00.0000000Z' 'CONTOSO\Administrator' 'NewLink')
                (& $Line '2026-10-12T10:00:00.0000000Z' 'CONTOSO\tiers1' 'SetLink')
                (& $Line '2026-10-13T10:00:00.0000000Z' 'local-user' 'SetBlockInheritance')
            )
            Set-Content -LiteralPath (Join-Path $Old 'contoso.com-2026-09.jsonl') -Encoding utf8 -Value (& $Line '2026-09-30T10:00:00.0000000Z' 'CONTOSO\Administrator' 'NewGpo')
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            Mock Use-PSGPODomainConfiguration { }
            Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
            Mock Get-PSGPOAuditAccountTier { switch ($Account) { 'CONTOSO\Administrator' { 'Tier0' } 'CONTOSO\tiers1' { 'Tier1' } default { 'Unassigned' } } }

            $Result = @(Import-PSGPOAuditLog -Path $Old -Destination $Central -Directory $Directory -Confirm:$false)
            @($Result.File | Sort-Object) | Should -Be @('Tier0\contoso.com-2026-09-CONTOSO_Administrator-dc-imported.jsonl', 'Tier0\contoso.com-2026-10-CONTOSO_Administrator-dc-imported.jsonl', 'Tier1\contoso.com-2026-10-CONTOSO_tiers1-dc-imported.jsonl', 'Unassigned\contoso.com-2026-10-local-user-dc-imported.jsonl') -Because 'the files the importer owns, apart from those the accounts write'
            $Entries = @(Get-PSGPOAuditLog -Path $Central)
            $Entries.Count | Should -Be 4
            ($Entries | Where-Object Account -EQ 'CONTOSO\tiers1').Tier | Should -Be 'Tier1'
            # In UTC, as written: ConvertFrom-Json gives a date of the local time zone.
            $Time = ($Entries | Where-Object Account -EQ 'CONTOSO\tiers1').Time
            $Time.Kind | Should -Be 'Utc'
            $Time | Should -Be ([datetime]::new(2026, 10, 12, 10, 0, 0, [System.DateTimeKind]::Utc))
            ($Entries | Where-Object Account -EQ 'CONTOSO\tiers1').Details.Blocked | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $Old 'contoso.com-2026-10.jsonl') | Should -BeTrue -Because 'kept without -Remove'

            # Again: nothing twice; -Remove deletes what was read.
            @(Import-PSGPOAuditLog -Path $Old -Destination $Central -Directory $Directory -Remove -Confirm:$false) | Should -BeNullOrEmpty
            @(Get-PSGPOAuditLog -Path $Central).Count | Should -Be 4
            @(Get-ChildItem -LiteralPath $Old -File) | Should -BeNullOrEmpty
        }
    }

    Describe 'Share of the central audit log' {
        It 'Gives each tier its folder: its groups create their files and read their tier, Tier 0 and the readers read everything' {
            $Folders = @(Get-PSGPOAuditShareSddl -DomainAdminsSid 'S-1-5-21-1-2-3-512' -Tier0 'S-1-5-21-1-2-3-512', 'S-1-5-21-1-2-3-3000' -Tier1 'S-1-5-21-1-2-3-2001' -Tier2 'S-1-5-21-1-2-3-2002' -Readers 'S-1-5-21-1-2-3-4000')
            @($Folders.Folder) | Should -Be @('', 'Tier0', 'Tier1', 'Tier2', 'Unassigned')
            foreach ($Item in $Folders) {
                $Item.Sddl | Should -BeLike 'D:P(A;OICI;0x1f01ff;;;SY)(A;OICI;0x1f01ff;;;BA)(A;OICI;0x1f01ff;;;S-1-5-21-1-2-3-512)*' -Because 'protected, the administrators in full control'
                $Item.Sddl | Should -BeLike '*(A;OICI;0x1200a9;;;S-1-5-21-1-2-3-3000)*' -Because 'Tier 0 reads every folder'
                $Item.Sddl | Should -BeLike '*(A;OICI;0x1200a9;;;S-1-5-21-1-2-3-4000)*' -Because 'the readers too'
            }
            $Tier1 = $Folders | Where-Object Folder -EQ 'Tier1'
            $Tier1.Sddl | Should -BeLike '*(A;;0x1200ab;;;S-1-5-21-1-2-3-2001)(A;OIIO;0x1200a9;;;S-1-5-21-1-2-3-2001)*' -Because 'Tier 1 creates its files and reads those of its tier'
            $Tier1.Sddl | Should -Not -BeLike '*S-1-5-21-1-2-3-2002*' -Because 'Tier 2 has nothing in the folder of Tier 1'
            $Tier1.Sddl | Should -BeLike '*(A;OIIO;0x12019f;;;CO)(A;OIIO;0x12019f;;;S-1-3-4)' -Because 'the owner writes its file, without deleting it nor changing its permissions'
            ($Folders | Where-Object Folder -EQ 'Unassigned').Sddl | Should -BeLike '*(A;;0x1200ab;;;AU)*'
            $Root = ($Folders | Where-Object Folder -EQ '').Sddl
            $Root | Should -BeLike '*(A;;0x1200a9;;;S-1-5-21-1-2-3-2001)(A;;0x1200a9;;;S-1-5-21-1-2-3-2002)*' -Because 'the groups of the tiers list the share'
            $Root | Should -BeLike '*(A;;0x1000a0;;;AU)' -Because 'any other account only goes through it, to Unassigned'
            # A role the configuration leaves empty (no readers, no Tier 2): no ACE without a SID.
            $Empty = @(Get-PSGPOAuditShareSddl -DomainAdminsSid 'S-1-5-21-1-2-3-512' -Tier0 @($null) -Tier2 @($null) -Readers @($null))
            @($Empty.Sddl | Where-Object { $_ -like '*;;;)*' }) | Should -BeNullOrEmpty
        }

        It 'Writes the permissions of the folders on Windows' -Skip:(-not $IsWindows) {
            $Share = Join-Path $TestDrive 'share'
            # The account of the test as Domain Admins: it keeps its rights on the folders it makes.
            $Folders = @(Get-PSGPOAuditShareSddl -DomainAdminsSid ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -Tier1 'S-1-5-21-1-2-3-2001')
            Set-PSGPOAuditShareAcl -Path $Share -Folder $Folders -Confirm:$false
            $Acl = [System.IO.FileSystemAclExtensions]::GetAccessControl([System.IO.DirectoryInfo](Get-Item (Join-Path $Share 'Tier1')))
            $Acl.AreAccessRulesProtected | Should -BeTrue
            @($Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-21-1-2-3-2001' }).Count | Should -Be 2
        }

        It 'Reads the groups of the roles in the domain, then prepares the share' {
            $script:Before = $script:PSGPOConfigurationState.Override
            try {
                $script:PSGPOConfigurationState.Override = @{ Audit = @{ Path = '\\files\gpo-audit'; Tiers = @{ Tier1 = 'GPO-Tier1-Admins'; Tier2 = '' }; Readers = 'GPO-Auditors' } }
                $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
                Mock Use-PSGPODomainConfiguration { }
                Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
                Mock Invoke-PSGPOLdapBinarySearch { [pscustomobject]@{ Values = @{ objectSid = @(, [GPOToolsSecurityDescriptor]::ConvertSidToBytes('S-1-5-21-1-2-3')) } } }
                Mock Find-PSGPODomainAccount { foreach ($Item in $Name) { [pscustomobject]@{ Name = $Item; Sid = "S-1-5-21-1-2-3-$($Item.Length)" } } }
                Mock Set-PSGPOAuditShareAcl { $script:Prepared = @{ Path = $Path; Folder = $Folder } }
                Mock Write-PSGPOAuditEntry { }
                $Result = @(Initialize-PSGPOAuditShare -Directory $Directory -Confirm:$false)
                $script:Prepared.Path | Should -Be '\\files\gpo-audit'
                ($script:Prepared.Folder | Where-Object Folder -EQ 'Tier1').Sddl | Should -BeLike '*(A;;0x1200ab;;;S-1-5-21-1-2-3-16)*' -Because 'GPO-Tier1-Admins'
                $Result.Count | Should -Be 5
                ($Result | Where-Object Path -EQ '\\files\gpo-audit\Tier1').Writers | Should -Be @('GPO-Tier1-Admins')
                ($Result | Where-Object Path -EQ '\\files\gpo-audit\Tier2').Writers | Should -BeNullOrEmpty
                Should -Invoke Write-PSGPOAuditEntry -Times 1 -Exactly -ParameterFilter { $Action -eq 'InitializeAuditShare' }
            } finally {
                $script:PSGPOConfigurationState.Override = $script:Before
            }
        }
    }
}
