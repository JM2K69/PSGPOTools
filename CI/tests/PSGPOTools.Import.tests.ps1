#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Import of backed up GPOs with a migration table (PSGPOImport.ps1, Import-PSGPO): the backups and
# the migration table GPMC wrote on the Windows lab (Fixtures\GpmcBackup: Backup-GPO, and the
# Migration Table Editor with each kind of destination), and a backup of GPMC with settings that
# reference accounts and UNC paths, migrated into a domain in memory.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $Fixture = Join-Path $PSScriptRoot 'Fixtures' 'GpmcBackup'
        $Lab = 'S-1-5-21-204864384-581126797-2929775416'
        $Unicode = [System.Text.UnicodeEncoding]::new($false, $true)
        # The backup of the GPO TEST of the lab (no settings), given settings that reference
        # APPLY_TEST, DENY_TEST, Domain Admins, Backup Operators, an account by name and a UNC path.
        function New-RichBackup {
            $Root = Join-Path $TestDrive "backups-$([guid]::NewGuid())"
            $Folder = Join-Path $Root '{CDACBF0D-55B7-453B-B0E6-29AA70A61AAF}'
            $null = New-Item -ItemType Directory -Path $Folder -Force
            foreach ($Name in 'Backup.xml', 'bkupInfo.xml') { Copy-Item -LiteralPath (Join-Path $Fixture '{CDACBF0D-55B7-453B-B0E6-29AA70A61AAF}' $Name) -Destination $Folder }
            $Gpo = Join-Path $Folder 'DomainSysvol' 'GPO'
            $SecEdit = Join-Path $Gpo 'Machine' 'microsoft' 'windows nt' 'SecEdit'
            $null = New-Item -ItemType Directory -Path $SecEdit -Force
            [System.IO.File]::WriteAllText((Join-Path $SecEdit 'GptTmpl.inf'), (@(
                        '[Unicode]', 'Unicode=yes', '[Privilege Rights]'
                        "SeBackupPrivilege = *S-1-5-32-551,*$Lab-1108"
                        "SeServiceLogonRight = POWERSHELL\svc-app,*$Lab-1109"
                        '[Group Membership]'
                        "*S-1-5-32-544__Members = *$Lab-512,*$Lab-1108"
                        "*$Lab-1109__Memberof = *S-1-5-32-544"
                        '[File Security]'
                        """%SystemRoot%\Tools"",0,""D:AR(A;OICI;FA;;;$Lab-1108)(A;OICI;FA;;;$Lab-1109)(A;OICI;FA;;;SY)"""
                        '[Version]', 'signature="$CHICAGO$"', 'Revision=1', '') -join "`r`n"), $Unicode)
            $Groups = Join-Path $Gpo 'Machine' 'Preferences' 'Groups'
            $null = New-Item -ItemType Directory -Path $Groups -Force
            [System.IO.File]::WriteAllText((Join-Path $Groups 'Groups.xml'), (@(
                        '<?xml version="1.0" encoding="utf-8"?>'
                        '<Groups clsid="{3125E937-EB16-4b4c-9934-544FC6D24D26}"><Group clsid="{6D4A79E4-529C-4481-ABD0-F5BD7EA93BA7}" name="Administrators (built-in)" image="2" changed="2026-10-19 08:00:00" uid="{11111111-1111-1111-1111-111111111111}">'
                        '<Properties action="U" newName="" description="" deleteAllUsers="0" deleteAllGroups="0" removeAccounts="0" groupSid="S-1-5-32-544" groupName="Administrators (built-in)"><Members>'
                        "<Member name=""POWERSHELL\APPLY_TEST"" action=""ADD"" sid=""$Lab-1108""/><Member name=""POWERSHELL\DENY_TEST"" action=""ADD"" sid=""$Lab-1109""/>"
                        '</Members></Properties></Group></Groups>') -join "`r`n"), [System.Text.UTF8Encoding]::new($true))
            $Drives = Join-Path $Gpo 'User' 'Preferences' 'Drives'
            $null = New-Item -ItemType Directory -Path $Drives -Force
            [System.IO.File]::WriteAllText((Join-Path $Drives 'Drives.xml'), (@(
                        '<?xml version="1.0" encoding="utf-8"?>'
                        '<Drives clsid="{8FDDCC1A-0C3C-43cd-A6B4-71A6DF20DA8C}"><Drive clsid="{935D1B74-9CB8-4e3c-9914-7DD559B7A417}" name="P:" status="P:" image="2" changed="2026-10-19 08:00:00" uid="{22222222-2222-2222-2222-222222222222}">'
                        '<Properties action="U" thisDrive="NOCHANGE" allDrives="NOCHANGE" userName="" path="\\oldserver\pacakges\apps" label="Apps" persistent="0" useLetter="1" letter="P"/></Drive></Drives>') -join "`r`n"), [System.Text.UTF8Encoding]::new($true))
            $Scripts = Join-Path $Gpo 'Machine' 'Scripts'
            $null = New-Item -ItemType Directory -Path $Scripts -Force
            [System.IO.File]::WriteAllText((Join-Path $Scripts 'scripts.ini'), "`r`n[Startup]`r`n0CmdLine=\\OLDSERVER\pacakges\start.cmd`r`n0Parameters=`r`n", $Unicode)
            [System.IO.File]::WriteAllBytes((Join-Path $Gpo 'Machine' 'Registry.pol'), [byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0))
            $Root
        }
        # The table of the lab, without the entry for another domain (POWERSHELLK\Domain Computers).
        function Get-LabTable {
            @(Read-PSGPOMigrationTable -Path (Join-Path $Fixture 'test.migtable') | Where-Object { $_.Destination -notlike 'POWERSHELLK\*' })
        }
        # A domain of the import in memory, its accounts with SIDs of their own.
        function New-TargetDirectory {
            $Directory = [GPOToolsDirectory]::new('powershell.labo')
            $Directory.Account = 'POWERSHELL\admin1'
            $Directory
        }
        function Get-Text { param($Files, [string]$Path) (ConvertFrom-PSGPOFileByte -Bytes ([byte[]]$Files[$Path])).Text }
    }

    Describe 'Backups of GPMC' {
        It 'Reads the backups Backup-GPO wrote, newest first' {
            $Backups = @(Get-PSGPOGpmcBackup -Path $Fixture)
            $Backups.Count | Should -Be 4
            $Dc = $Backups | Where-Object DisplayName -EQ 'Default Domain Controllers Policy'
            $Dc.Id | Should -Be ([guid]'6AC1786C-016F-11D2-945F-00C04FB984F9')
            $Dc.Domain | Should -Be 'powershell.labo'
            $Dc.BackupId | Should -Be ([guid]'74781AA6-E994-4EF7-A5AC-EFB8AB9373CF')
            $Dc.BackedUp | Should -Be ([datetime]::new(2026, 10, 19, 7, 28, 31, [System.DateTimeKind]::Utc)) -Because 'GPMC writes the time in UTC'
            $Backups[-1].DisplayName | Should -Be 'Default Domain Controllers Policy'
            ($Backups | Where-Object DisplayName -EQ 'Default Domain Policy').MachineExtensionNames | Should -Be '[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]'
            $Test = $Backups | Where-Object DisplayName -EQ 'TEST'
            ($Test.SecurityGroups | Where-Object Name -EQ 'APPLY_TEST').Sid | Should -Be "$Lab-1108"
            ($Test.SecurityGroups | Where-Object Name -EQ 'APPLY_TEST').Type | Should -Be 'GlobalGroup'
            @(Get-PSGPOGpmcBackup -Path $Fixture -Name 'Default*').Count | Should -Be 2
            @(Get-PSGPOGpmcBackup -Path $Dc.Path).DisplayName | Should -Be 'Default Domain Controllers Policy' -Because 'a folder of one backup is a backup too'
        }

        It 'Reads the files of a backup by their path in the folder of a GPO' {
            $Dc = Get-PSGPOGpmcBackup -Path $Fixture -Name 'Default Domain Controllers Policy'
            $Files = Read-PSGPOImportFile -Source $Dc
            @($Files.Keys) | Should -Be @('Machine\microsoft\windows nt\SecEdit\GptTmpl.inf')
            $Files.Contains([GPOToolsDirectory]::SecurityTemplatePath) | Should -BeTrue -Because 'the paths of a GPO do not depend on the case'
        }

        It 'Lists the accounts and paths of the settings as the Migration Table Editor names them' {
            $Entries = @(Get-PSGPOMigrationEntry -Path $Fixture -Name 'Default Domain Controllers Policy')
            ($Entries | Where-Object Sid -EQ 'S-1-5-32-551').Source | Should -Be 'Backup Operators'
            ($Entries | Where-Object Sid -EQ 'S-1-5-32-551').Type | Should -Be 'Unknown'
            ($Entries | Where-Object Sid -EQ 'S-1-5-19').Source | Should -Be 'LOCAL SERVICE'
            ($Entries | Where-Object Sid -Like 'S-1-5-80-*').Source | Should -BeLike 'S-1-5-80-*' -Because 'a SID without a name stays a SID'
            $Entries.Source | Should -Not -Contain 'Domain Admins@powershell.labo' -Because 'the permissions only with -IncludePermission'
            $WithDacl = @(Get-PSGPOMigrationEntry -Path $Fixture -Name 'TEST' -IncludePermission)
            ($WithDacl | Where-Object Source -EQ 'APPLY_TEST@powershell.labo').Type | Should -Be 'GlobalGroup'
            ($WithDacl | Where-Object Source -EQ 'Enterprise Admins@powershell.labo').Type | Should -Be 'UniversalGroup'
        }
    }

    Describe 'Migration tables' {
        It 'Reads the table the Migration Table Editor wrote, with each kind of destination' {
            $Table = @(Get-PSGPOMigrationTable -Path (Join-Path $Fixture 'test.migtable'))
            $Table.Count | Should -Be 15
            ($Table | Where-Object Source -EQ 'Domain Admins@powershell.labo').Mode | Should -Be 'ByRelativeName'
            ($Table | Where-Object Source -EQ 'DENY_TEST@powershell.labo').Mode | Should -Be 'None'
            $Explicit = $Table | Where-Object Source -EQ 'APPLY_TEST@powershell.labo'
            "$($Explicit.Mode) $($Explicit.Destination)" | Should -Be 'Explicit Domain Users@powershell.labo'
            ($Table | Where-Object Type -EQ 'UNCPath').Destination | Should -Be '\\newserver\pacakges'
            ($Table | Where-Object Source -EQ 'Everyone').Mode | Should -Be 'SameAsSource'
        }

        It 'Writes a table GPMC reads, and reads it back' {
            $Path = Join-Path $TestDrive 'round.migtable'
            Save-PSGPOMigrationTable -Path $Path -Entry @(Read-PSGPOMigrationTable -Path (Join-Path $Fixture 'test.migtable'))
            $Bytes = [System.IO.File]::ReadAllBytes($Path)
            "$($Bytes[0]),$($Bytes[1])" | Should -Be '255,254' -Because 'the editor writes UTF-16 with its byte order mark'
            [System.Text.Encoding]::Unicode.GetString($Bytes) | Should -BeLike '*<MigrationTable *xmlns="http://www.microsoft.com/GroupPolicy/GPOOperations/MigrationTable"*<DestinationByRelativeName />*'
            $Again = @(Read-PSGPOMigrationTable -Path $Path)
            ($Again | ForEach-Object { "$($_.Type)|$($_.Source)|$($_.Mode)|$($_.Destination)" }) |
                Should -Be @(Read-PSGPOMigrationTable -Path (Join-Path $Fixture 'test.migtable') | ForEach-Object { "$($_.Type)|$($_.Source)|$($_.Mode)|$($_.Destination)" })
        }

        It 'Refuses what GPMC refuses: <Case>' -ForEach @(
            @{ Case = 'a UNC path removed'; Mapping = '<Type>UNCPath</Type><Source>\\a\b</Source><DestinationNone />'; Message = '*UNC path*' }
            @{ Case = 'free text by relative name'; Mapping = '<Type>Unknown</Type><Source>Admins</Source><DestinationByRelativeName />'; Message = '*free text or a SID*' }
            @{ Case = 'a SID as destination'; Mapping = '<Type>GlobalGroup</Type><Source>G@a.b</Source><Destination>S-1-5-21-1-2-3-1000</Destination>'; Message = '*names its destinations*' }
            @{ Case = 'an unknown type'; Mapping = '<Type>Printer</Type><Source>P</Source><DestinationSameAsSource />'; Message = '*unknown type*' }
        ) {
            $Path = Join-Path $TestDrive "$([guid]::NewGuid()).migtable"
            Set-Content -LiteralPath $Path -Value "<MigrationTable xmlns=""http://www.microsoft.com/GroupPolicy/GPOOperations/MigrationTable""><Mapping>$Mapping</Mapping></MigrationTable>"
            { Read-PSGPOMigrationTable -Path $Path } | Should -Throw -ExpectedMessage $Message
        }

        It 'Writes the table of the backups of a folder, by relative name with -MapByRelativeName' {
            $Path = Join-Path $TestDrive 'populate.migtable'
            $Written = @(New-PSGPOMigrationTable -Path $Path -BackupPath $Fixture -IncludePermission -MapByRelativeName)
            $Read = @(Read-PSGPOMigrationTable -Path $Path)
            $Read.Count | Should -Be $Written.Count
            ($Read | Where-Object Source -EQ 'APPLY_TEST@powershell.labo').Mode | Should -Be 'ByRelativeName'
            ($Read | Where-Object Source -EQ 'Backup Operators').Mode | Should -Be 'SameAsSource' -Because 'free text is not mapped by relative name'
            { New-PSGPOMigrationTable -Path $Path -BackupPath $Fixture } | Should -Throw -ExpectedMessage '*-Force*'
        }
    }

    Describe 'Migration of the settings' {
        BeforeEach {
            $Root = New-RichBackup
            $Source = Select-PSGPOImportSource -Path $Root
            $Files = Read-PSGPOImportFile -Source $Source
            $Directory = New-TargetDirectory
            Mock Resolve-PSGPOApplyTo { [pscustomobject]@{ Name = $Name; Sid = @{ 'Domain Users' = 'S-1-5-21-7-8-9-513'; 'Domain Admins' = 'S-1-5-21-7-8-9-512' }[$Name] } }
        }

        It 'Replaces, removes and keeps the accounts and paths of every kind of file' {
            $References = @(Get-PSGPOMigrationReference -Files $Files -SecurityGroups $Source.SecurityGroups)
            $Plan = @(Resolve-PSGPOMigrationPlan -Reference $References -Table (Get-LabTable) -Directory $Directory)
            ($Plan | Where-Object Source -EQ 'APPLY_TEST@powershell.labo').Destination.Sid | Should -Be 'S-1-5-21-7-8-9-513'
            ($Plan | Where-Object Source -EQ 'Domain Admins@powershell.labo').Destination.Sid | Should -Be 'S-1-5-21-7-8-9-512' -Because 'by relative name: Domain Admins of the domain of the import'
            ($Plan | Where-Object Source -EQ 'Backup Operators').Destination.Sid | Should -Be 'S-1-5-32-549'
            ($Plan | Where-Object Source -EQ 'POWERSHELL\svc-app').Mode | Should -Be 'NotInTable'
            $Migrated = Convert-PSGPOMigratedFile -Files $Files -Plan $Plan

            $Template = Get-Text $Migrated 'Machine\microsoft\windows nt\SecEdit\GptTmpl.inf'
            $Template | Should -BeLike '*SeBackupPrivilege = `*S-1-5-32-549,`*S-1-5-21-7-8-9-513*'
            $Template | Should -BeLike '*SeServiceLogonRight = POWERSHELL\svc-app*' -Because 'DENY_TEST is removed, an account the table does not name is kept'
            $Template | Should -Not -BeLike "*$Lab-1109*"
            $Template | Should -BeLike '*`*S-1-5-32-544__Members = `*S-1-5-21-7-8-9-512,`*S-1-5-21-7-8-9-513*'
            $Template | Should -Not -BeLike '*__Memberof*' -Because 'the restricted group of an account removed goes with it'
            $Template | Should -BeLike '*"D:AR(A;OICI;FA;;;S-1-5-21-7-8-9-513)(A;OICI;FA;;;SY)"*'
            $Files['Machine\microsoft\windows nt\SecEdit\GptTmpl.inf'][0..1] | Should -Be $Migrated['Machine\microsoft\windows nt\SecEdit\GptTmpl.inf'][0..1] -Because 'UTF-16, as it was'

            $Groups = [xml](Get-Text $Migrated 'Machine\Preferences\Groups\Groups.xml')
            @($Groups.Groups.Group.Properties.Members.Member).Count | Should -Be 1
            $Groups.Groups.Group.Properties.Members.Member.name | Should -Be 'POWERSHELL\Domain Users'
            $Groups.Groups.Group.Properties.Members.Member.sid | Should -Be 'S-1-5-21-7-8-9-513'
            $Groups.Groups.Group.Properties.groupSid | Should -Be 'S-1-5-32-544'

            ([xml](Get-Text $Migrated 'User\Preferences\Drives\Drives.xml')).Drives.Drive.Properties.path | Should -Be '\\newserver\pacakges\apps'
            Get-Text $Migrated 'Machine\Scripts\scripts.ini' | Should -BeLike '*0CmdLine=\\newserver\pacakges\start.cmd*' -Because 'a UNC path is matched whatever its case'
            $Migrated['Machine\Registry.pol'] | Should -Be $Files['Machine\Registry.pol'] -Because 'the administrative templates are copied as they are'
        }

        It 'Copies the references as they are without a table, and stops when the table does not name one with -Exclusive' {
            $References = @(Get-PSGPOMigrationReference -Files $Files -SecurityGroups $Source.SecurityGroups)
            $Plan = @(Resolve-PSGPOMigrationPlan -Reference $References -Directory $Directory)
            @($Plan | Where-Object Mode -NE 'NotInTable').Count | Should -Be 0
            $Migrated = Convert-PSGPOMigratedFile -Files $Files -Plan $Plan
            foreach ($Path in $Files.Keys) { $Migrated[$Path] | Should -Be $Files[$Path] }
            { Resolve-PSGPOMigrationPlan -Reference $References -Table (Get-LabTable) -Directory $Directory -Exclusive } | Should -Throw -ExpectedMessage '*does not name*svc-app*'
        }

        It 'Stops when a destination is not an account of the domain of the import' {
            $References = @(Get-PSGPOMigrationReference -Files $Files -SecurityGroups $Source.SecurityGroups)
            $Table = @([pscustomobject]@{ Type = 'GlobalGroup'; Source = 'APPLY_TEST@powershell.labo'; Destination = 'POWERSHELLK\Domain Computers'; Mode = 'Explicit' })
            { Resolve-PSGPOMigrationPlan -Reference $References -Table $Table -Directory $Directory } | Should -Throw -ExpectedMessage "*'APPLY_TEST@powershell.labo' cannot be found*not an account of powershell.labo*"
        }
    }

    Describe 'Import-PSGPO' {
        BeforeEach {
            $Root = New-RichBackup
            $Directory = New-TargetDirectory
            $Target = $Directory.AddGpo('C - Imported', [guid]::Empty)
            $Ou = $Directory.AddOrganizationalUnit($Directory.Domain, 'Servers')
            $null = $Directory.NewLink($Ou, $Target)
            $Table = Join-Path $TestDrive 'lab.migtable'
            Save-PSGPOMigrationTable -Path $Table -Entry (Get-LabTable)
            $BackupPath = Join-Path $TestDrive "before-$([guid]::NewGuid())"
            Mock Resolve-PSGPOApplyTo { [pscustomobject]@{ Name = $Name; Sid = @{ 'Domain Users' = 'S-1-5-21-7-8-9-513'; 'Domain Admins' = 'S-1-5-21-7-8-9-512' }[$Name] } }
        }

        It 'Imports the settings of a GPMC backup into a GPO, backed up first, its links kept' {
            $Version = $Target.Version
            $Result = Import-PSGPO -Path $Root -TargetName 'C - Imported' -MigrationTable $Table -Directory $Directory -BackupPath $BackupPath
            $Result.Source.DisplayName | Should -Be 'TEST'
            $Result.BackupBefore | Should -Not -BeNullOrEmpty
            @(Get-PSGPOBackup -Path $BackupPath).Comment | Should -BeLike "Before the import of the settings of 'TEST' (GPMC backup of 2026-10-19 07:28:33Z)."
            $Target.Version | Should -BeGreaterThan $Version
            [System.Text.Encoding]::Unicode.GetString($Directory.ReadSecurityTemplate($Target)) | Should -BeLike '*S-1-5-21-7-8-9-513*'
            $Directory.ReadPreferenceFile($Target, 'User', 'Drives\Drives.xml') | Should -Not -BeNullOrEmpty
            @($Directory.GetLinksOf($Target)).Count | Should -Be 1
            $Target.MachineExtensionNames | Should -BeLike '*827D319E-6EAC-11D2-A4EA-00C04F79F83A*' -Because 'the backup of TEST declares no extension: those of the files imported'
            ($Result.Migration | Where-Object Source -EQ 'DENY_TEST@powershell.labo').Mode | Should -Be 'None'
        }

        It 'Changes nothing with -WhatIf, refuses a GPO the domain does not have, creates it with -CreateIfNeeded' {
            $Version = $Target.Version
            Import-PSGPO -Path $Root -TargetName 'C - Imported' -Directory $Directory -BackupPath $BackupPath -WhatIf
            $Target.Version | Should -Be $Version
            { Import-PSGPO -Path $Root -TargetName 'C - New' -Directory $Directory -NoBackup } | Should -Throw -ExpectedMessage '*-CreateIfNeeded*'
            $Result = Import-PSGPO -Path $Root -TargetName 'C - New' -Directory $Directory -NoBackup -CreateIfNeeded
            $Result.Gpo.DisplayName | Should -Be 'C - New'
            $Directory.FindGpo('C - New') | Should -Not -BeNullOrEmpty
        }

        It 'Stops before any change when the migration table cannot be applied' {
            $Version = $Target.Version
            $Wrong = Join-Path $TestDrive 'wrong.migtable'
            Save-PSGPOMigrationTable -Path $Wrong -Entry @([pscustomobject]@{ Type = 'GlobalGroup'; Source = 'APPLY_TEST@powershell.labo'; Destination = 'OTHER\Group'; Mode = 'Explicit' })
            { Import-PSGPO -Path $Root -TargetName 'C - Imported' -MigrationTable $Wrong -Directory $Directory -BackupPath $BackupPath } | Should -Throw -ExpectedMessage '*cannot be found*'
            $Target.Version | Should -Be $Version
            Test-Path -LiteralPath $BackupPath | Should -BeFalse -Because 'the GPO is backed up once the migration is known to work'
        }

        It 'Asks which GPO when the folder holds backups of several' {
            { Import-PSGPO -Path $Fixture -TargetName 'C - Imported' -Directory $Directory -NoBackup } | Should -Throw -ExpectedMessage '*several GPOs*'
            (Import-PSGPO -Path $Fixture -SourceName 'Default Domain Controllers Policy' -TargetName 'C - Imported' -Directory $Directory -NoBackup).Source.DisplayName |
                Should -Be 'Default Domain Controllers Policy'
            (Import-PSGPO -Path $Fixture -BackupId '{80F43592-2458-436C-8E1A-2E8CBFC4C6AE}' -TargetName 'C - Imported' -Directory $Directory -NoBackup).Source.DisplayName |
                Should -Be 'Default Domain Policy'
        }

        It 'Imports a backup of PSGPOTools into another GPO' {
            $Sample = Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Samples' 'Directory.sample.json')
            $Gpo = $Sample.FindGpo('C - Servers - Security Baseline')
            $Sample.WriteSecurityTemplate($Gpo, $Unicode.GetPreamble() + $Unicode.GetBytes("[Unicode]`r`nUnicode=yes`r`n[System Access]`r`nMinimumPasswordLength = 14`r`n[Version]`r`nsignature=""`$CHICAGO`$""`r`nRevision=1`r`n"))
            $Own = Join-Path $TestDrive "own-$([guid]::NewGuid())"
            $null = New-Item -ItemType Directory -Path $Own
            $null = Save-PSGPOBackup -Directory $Sample -Gpo $Gpo -Path $Own
            $Result = Import-PSGPO -Path $Own -TargetName 'C - Imported' -Directory $Directory -NoBackup
            $Result.Source.Kind | Should -Be 'PSGPOTools'
            [System.Text.Encoding]::Unicode.GetString($Directory.ReadSecurityTemplate($Target)) | Should -BeLike '*MinimumPasswordLength = 14*'
        }
    }
}
