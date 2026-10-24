#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Rule sets of Policy Analyzer (.PolicyRules): the format, as GPO2PolicyRules.exe writes it (the
# fixture Fixtures/PolicyRules, made by New-PolicyRulesFixture.ps1), the sets made from GPOs,
# their comparison and its Excel workbook.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $Fixture = Join-Path $PSScriptRoot 'Fixtures' 'PolicyRules'
        $Expected = Join-Path $Fixture 'gpo2policyrules.PolicyRules'
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        # The paths of the files, from the folder of the GPOs, with \ on every platform.
        function Get-RelativeSourceText {
            param([GPOToolsPolicyRuleSet]$Set)
            foreach ($Rule in $Set.Rules) { $Rule.SourceFile = ($Rule.SourceFile -replace '/', '\') -replace '^.*?\\GPOs\\', 'GPOs\' }
            [System.Text.Encoding]::UTF8.GetString($Set.ToBytes())
        }
        # A set of some GPOs of another.
        function Select-RuleSet {
            param([GPOToolsPolicyRuleSet]$Set, [string]$Name, [string[]]$PolicyName)
            $Part = [GPOToolsPolicyRuleSet]::new($Name)
            foreach ($Rule in $Set.Rules) { if ($Rule.PolicyName -in $PolicyName) { $Part.Rules.Add($Rule) } }
            $Part
        }
    }

    Describe 'The .PolicyRules format' {
        It 'Reads every element GPO2PolicyRules writes, and writes the file back byte for byte' {
            $Bytes = [System.IO.File]::ReadAllBytes($Expected)
            $Set = [GPOToolsPolicyRuleSet]::Parse($Bytes, 'gpo2policyrules')
            @($Set.Rules | Group-Object Kind | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }) |
                Should -Be @('AuditOption=1', 'AuditSubcategory=2', 'GlobalAudit=1', 'Registry=21', 'SecurityTemplate=16')
            @($Set.Extensions | ForEach-Object { "$($_.Scope) $($_.Name)" }) | Should -Be @('Machine Registry Policy', 'Machine Security', 'Machine Audit Policy Configuration', 'User Registry Policy')
            @($Set.GetPolicyNames()) | Should -Be @('HGPM Test - Computer', 'HGPM Test - Second')
            $Text = $Set.Rules | Where-Object ValueName -EQ 'Text'
            $Text.RegData | Should -BeExactly "it's <a> & `"b`"`tc"
            ($Set.Rules | Where-Object ValueName -EQ '**del.Gone').RegData | Should -BeExactly ' ' -Because 'the data of a deletion is a space'
            ($Set.Rules | Where-Object Kind -EQ 'GlobalAudit').Sacl | Should -Be 'D:(AU;SA;KA;;;WD)'
            [System.Convert]::ToBase64String($Set.ToBytes()) | Should -Be ([System.Convert]::ToBase64String($Bytes))
        }

        It 'Reads the UTF-16 files of the first versions of Policy Analyzer, on one line' {
            $Text = [System.IO.File]::ReadAllText($Expected) -replace "`r`n", ''
            $Set = [GPOToolsPolicyRuleSet]::Parse(([byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($Text)), 'old')
            $Set.Rules.Count | Should -Be 41
            $Set.Extensions.Count | Should -Be 4
        }

        It 'Escapes the text as Policy Analyzer does' {
            [GPOToolsPolicyRuleSet]::Escape("a&b<c>`"d`"'e'`tf`r`n") | Should -BeExactly 'a&amp;b&lt;c&gt;&quot;d&quot;&apos;e&apos;&#x09;f&#x0D;&#x0A;'
        }

        It 'Refuses what is not a rule set' {
            { [GPOToolsPolicyRuleSet]::Parse([System.Text.Encoding]::UTF8.GetBytes('<Other/>'), 'x') } | Should -Throw -ExpectedMessage '*not <PolicyRules>*'
            { [GPOToolsPolicyRuleSet]::Parse([byte[]]::new(0), 'x') } | Should -Throw -ExpectedMessage '*empty*'
        }

        It 'Gives the same identity to a deletion and to the value it deletes, and compares lists in any order' {
            $Set = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($Expected), 'x')
            $Delete = $Set.Rules | Where-Object ValueName -EQ '**del.Gone'
            $Delete.GetIdentity() | Should -Be 'computer|registry|software\policies\hgpm test|gone'
            $Delete.GetComparable() | Should -Be '[[[delete]]]'
            $Rights = @($Set.Rules | Where-Object LineItem -Like 'SeBackupPrivilege=*')
            $Rights[0].GetComparable() | Should -Be $Rights[1].GetComparable()
            $Service = $Set.Rules | Where-Object LineItem -Like '"Spooler"*'
            $Service.GetLineKey() | Should -Be 'Spooler'
            $Service.GetLineValue() | Should -Be '4,"D:AR(A;;RPWPCCDCLCSWRCWDWOGA;;;BA)"'
        }
    }

    Describe 'Rule sets made from GPOs' {
        It 'Makes from GPMC backups the rule set GPO2PolicyRules makes' {
            $Set = Get-PSGPOPolicyRuleSet -GpmcBackupPath (Join-Path $Fixture 'GPOs')
            $Set.Name | Should -Be 'GPOs'
            $Reference = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($Expected), 'x')
            Get-RelativeSourceText -Set $Set | Should -BeExactly (Get-RelativeSourceText -Set $Reference)
        }

        It 'Reads a .PolicyRules file, and all those of a folder' {
            $Folder = Join-Path $TestDrive 'Rules'
            $null = New-Item -ItemType Directory -Path $Folder
            Copy-Item -LiteralPath $Expected -Destination (Join-Path $Folder 'One.PolicyRules')
            Copy-Item -LiteralPath $Expected -Destination (Join-Path $Folder 'Two.PolicyRules')
            Set-Content -LiteralPath (Join-Path $Folder 'Other.txt') -Value 'not a rule set'
            $Sets = @(Get-PSGPOPolicyRuleSet -Path $Folder)
            @($Sets.Name) | Should -Be @('One', 'Two')
            $Sets[0].Path | Should -Be (Join-Path $Folder 'One.PolicyRules')
            (Get-PSGPOPolicyRuleSet (Join-Path $Folder 'Two.PolicyRules')).Rules.Count | Should -Be 41
            Get-PSGPOPolicyRuleSet -Path (Join-Path $Folder 'None.PolicyRules') -ErrorVariable Problem -ErrorAction SilentlyContinue
            "$Problem" | Should -BeLike 'No .PolicyRules file or folder*'
        }

        It 'Makes a rule set from GPOs of the domain and from backups' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Pol = [GPOToolsRegistryPol]::new()
            $Pol.Entries.Add([GPOToolsPolEntry]::new('Software\Policies\HGPM', 'Value', [GPOToolsPolType]::DWord, [BitConverter]::GetBytes([uint32]7)))
            $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
            $Set = Get-PSGPOPolicyRuleSet -Directory $Directory -Name $Gpo.DisplayName
            $Set.Name | Should -Be $Gpo.DisplayName
            $Rule = $Set.Rules | Where-Object ValueName -EQ 'Value'
            $Rule.RegData | Should -Be '7'
            $Rule.PolicyName | Should -Be $Gpo.DisplayName
            $Rule.SourceFile | Should -BeLike "*\Policies\{$($Gpo.Id.ToString().ToUpperInvariant())}\Machine\Registry.pol"
            @($Set.Extensions | Where-Object Scope -EQ 'Machine').Guid | Should -Contain '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'

            $Backup = Backup-PSGPO -Directory $Directory -Path (Join-Path $TestDrive 'Backups') -Name $Gpo.DisplayName
            $FromBackup = $Backup | Get-PSGPOPolicyRuleSet -SetName 'Backup'
            $FromBackup.Name | Should -Be 'Backup'
            ($FromBackup.Rules | Where-Object ValueName -EQ 'Value').RegData | Should -Be '7'
            @(Compare-PSGPOPolicyRuleSet -RuleSet $Set, $FromBackup -DifferenceOnly).Count | Should -Be 0
            # The folder of the backups, the folder of the GPO, the backup, its Files folder.
            foreach ($Folder in (Join-Path $TestDrive 'Backups'), [System.IO.Path]::GetDirectoryName($Backup.Path), $Backup.Path, (Join-Path $Backup.Path 'Files')) {
                $FromFolder = Get-PSGPOPolicyRuleSet -BackupPath $Folder
                ($FromFolder.Rules | Where-Object ValueName -EQ 'Value').RegData | Should -Be '7' -Because $Folder
                $FromFolder.Name | Should -Be $Gpo.DisplayName
            }
            $Empty = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'NoBackup') -Force
            { Get-PSGPOPolicyRuleSet -BackupPath $Empty.FullName } | Should -Throw -ExpectedMessage 'No backup of GPMC nor of HGPM*'
        }

        It 'Saves a set as GPO2PolicyRules does, several sets merged in one file' {
            $Reference = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($Expected), 'x')
            $File = Export-PSGPOPolicyRuleSet -RuleSet $Reference -Path (Join-Path $TestDrive 'Out' 'Saved.PolicyRules')
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($File.FullName)) | Should -Be ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Expected)))
            { Export-PSGPOPolicyRuleSet -RuleSet $Reference -Path $File.FullName } | Should -Throw -ExpectedMessage '*exists*'

            $First = Select-RuleSet -Set $Reference -Name 'A' -PolicyName 'HGPM Test - Computer'
            $First.AddExtension('Machine', '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}', 'Registry Policy')
            $Second = Select-RuleSet -Set $Reference -Name 'B' -PolicyName 'HGPM Test - Second'
            $Second.AddExtension('Machine', '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}', 'Registry Policy')
            $Merged = $First, $Second | Export-PSGPOPolicyRuleSet -Path (Join-Path $TestDrive 'Merged.PolicyRules')
            $Read = Get-PSGPOPolicyRuleSet -Path $Merged.FullName
            $Read.Rules.Count | Should -Be 41
            $Read.Extensions.Count | Should -Be 1
        }

        It 'Writes the data of every registry type as GPO2PolicyRules, and reads it back' {
            $Reference = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($Expected), 'x')
            foreach ($Rule in @($Reference.Rules | Where-Object { $_.Kind -eq 'Registry' -and $_.RegType -ne 'REG_DWORD_BIG_ENDIAN' })) {
                $Value = ConvertFrom-PSGPOPolicyRuleData -Rule $Rule
                ConvertTo-PSGPOPolicyRuleData -Entry ([GPOToolsPolEntry]::new($Rule.Key, $Rule.ValueName, $Value.Type, [byte[]]$Value.Data)) | Should -BeExactly $Rule.RegData -Because "$($Rule.ValueName) ($($Rule.RegType))"
            }
            (ConvertFrom-PSGPOPolicyRuleData -Rule ($Reference.Rules | Where-Object ValueName -EQ 'BigEndian')).Data | Should -BeNullOrEmpty -Because 'Policy Analyzer does not keep it'
        }
    }

    Describe 'Comparison of rule sets' {
        BeforeAll {
            $Reference = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($Expected), 'Both')
            $First = Select-RuleSet -Set $Reference -Name 'Computer' -PolicyName 'HGPM Test - Computer'
            $Second = Select-RuleSet -Set $Reference -Name 'Second' -PolicyName 'HGPM Test - Second'
            $Rows = @(Compare-PSGPOPolicyRuleSet -RuleSet $First, $Second)
            $Row = { param($Setting) $Rows | Where-Object Setting -EQ $Setting | Select-Object -First 1 }
        }

        It 'Has a column per set, a row per setting' {
            $Rows.Count | Should -Be 36
            @($Rows[0].PSObject.Properties.Name)[0..6] | Should -Be @('Scope', 'Path', 'Name', 'Option', 'Computer', 'Second', 'Conflict')
            (& $Row 'Same').Computer | Should -Be '1'
            (& $Row 'Same').Conflict | Should -BeFalse
            (& $Row 'Same').Difference | Should -BeFalse
        }

        It 'Shows a conflict between two sets, and a setting only one set has' {
            (& $Row 'Differs').Conflict | Should -BeTrue
            (& $Row 'Differs').Second | Should -Be '2'
            $Only = & $Row 'OnlyB'
            $Only.Computer | Should -Be ''
            @($Only.Cells.State) | Should -Be @('Absent', 'Set')
            $Only.Conflict | Should -BeFalse
            $Only.Difference | Should -BeTrue
        }

        It 'Tells a REG_DWORD from a REG_SZ with the same data, and shows their types' {
            $Typed = & $Row 'TypeDiffers'
            $Typed.Conflict | Should -BeTrue
            $Typed.Computer | Should -Be '5 (REG_DWORD)'
            $Typed.Second | Should -Be '5 (REG_SZ)'
        }

        It 'Compares the accounts of a user right in any order, and shows them by name' {
            $Right = & $Row 'SeBackupPrivilege'
            $Right.Conflict | Should -BeFalse
            $Right.Name | Should -Be 'Back up files and directories'
            $Right.Path | Should -Be 'Policies > Windows Settings > Security Settings > Local Policies > User Rights Assignment'
            $Right.Computer | Should -Be 'BUILTIN\Backup Operators, BUILTIN\Administrators'
        }

        It 'Shows ***CONFLICT*** in a set whose GPOs give a setting different values, and duplicates' {
            $Alone = @(Compare-PSGPOPolicyRuleSet -RuleSet $Reference)
            $Differs = $Alone | Where-Object Setting -EQ 'Differs'
            $Differs.Both | Should -Be '***CONFLICT***'
            $Differs.Cells[0].State | Should -Be 'Conflict'
            @($Differs.Cells[0].Values | ForEach-Object { "$($_.PolicyName)=$($_.Value)" }) | Should -Be @('HGPM Test - Computer=1', 'HGPM Test - Second=2')
            $Differs.Conflict | Should -BeTrue
            $Same = $Alone | Where-Object Setting -EQ 'Same'
            $Same.Cells[0].State | Should -Be 'Duplicate'
            $Same.Conflict | Should -BeFalse
            ($Alone | Where-Object Setting -EQ 'SeBackupPrivilege').Cells[0].State | Should -Be 'Duplicate'
            ($Alone | Where-Object Setting -EQ 'MinimumPasswordAge').Both | Should -Be '***CONFLICT***'
            @(Compare-PSGPOPolicyRuleSet -RuleSet $Reference -ConflictOnly).Setting | Sort-Object | Should -Be @('Differs', 'MinimumPasswordAge', 'TypeDiffers')
            @(Compare-PSGPOPolicyRuleSet -RuleSet $First, $Second -DifferenceOnly | Where-Object { -not $_.Difference }).Count | Should -Be 0
        }

        It 'Shows deletions, services, file permissions, audit and restricted groups as the editor does' {
            (& $Row 'Gone').Computer | Should -Be '[[[delete]]]'
            (& $Row '*').Computer | Should -Be '[[[Delete all values]]]'
            (& $Row '').Computer | Should -Be '(REG_NONE)'
            (& $Row 'Multi').Computer | Should -Be 'one; two; three'
            (& $Row 'Spooler').Computer | Should -Be 'Disabled; D:AR(A;;RPWPCCDCLCSWRCWDWOGA;;;BA)'
            (& $Row 'Spooler').Path | Should -BeLike '*Security Settings > System Services'
            (& $Row 'XblGameSave').Computer | Should -Be 'Disabled'
            (& $Row '%SystemRoot%\HGPM').Computer | Should -Be 'Replace existing permissions; D:PAR(A;OICI;FA;;;BA)'
            $Audit = & $Row '{0cce923f-69ae-11d9-bed3-505054503030}'
            $Audit.Name | Should -Be 'Audit Credential Validation'
            $Audit.Computer | Should -Be 'Success and Failure'
            (& $Row 'Option:CrashOnAuditFail').Computer | Should -Be 'Enabled'
            $Members = & $Row '*S-1-5-32-544__Members'
            $Members.Name | Should -Be 'BUILTIN\Administrators (Members)'
            $Members.Computer | Should -Be 'Administrator'
            (& $Row 'UserValue').Scope | Should -Be 'User'
            (& $Row 'UserValue').PolicyType | Should -Be 'HKCU'
        }

        It 'Gives a unique column to sets of the same name' {
            $Columns = Get-PSGPOPolicyRuleColumnName -RuleSet @([GPOToolsPolicyRuleSet]::new('A'), [GPOToolsPolicyRuleSet]::new('A'), [GPOToolsPolicyRuleSet]::new('Name'))
            $Columns | Should -Be @('A', 'A (2)', 'Name (2)')
        }
    }

    Describe 'Rule sets written in a GPO' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Reference = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($Expected), 'Fixture')
            $Reference.AddExtension('Machine', '{2A8FDC61-2347-4C87-92F6-B05EB91A201A}', 'Group Policy Mitigation Options')
            # The GPO has settings of its own: a value, a list, a service and a security setting.
            $Pol = [GPOToolsRegistryPol]::new()
            $Pol.Entries.Add([GPOToolsPolEntry]::new('Software\Policies\Own', 'Kept', [GPOToolsPolType]::DWord, [BitConverter]::GetBytes([uint32]9)))
            $Pol.Entries.Add([GPOToolsPolEntry]::new('Software\Policies\HGPM Test\List', '9', [GPOToolsPolType]::String, [GPOToolsPolEntry]::EncodeString('old')))
            $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
            $Template = [GPOToolsSecurityTemplate]::new()
            $Template.SetValue('System Access', 'LockoutBadCount', '5')
            $Template.AddEntry('Service General Setting', '"Spooler",2,""', $null)
            $Directory.WriteSecurityTemplate($Gpo, $Template.ToBytes())
            $Backups = Join-Path $TestDrive "Backups-$([guid]::NewGuid())"
            $SetOfGpo = { Get-PSGPOPolicyRuleSet -Directory $Directory -Name $Gpo.DisplayName -SetName 'GPO' }
        }

        It 'Merges the settings of the set in the GPO: the GPO then has them, and keeps its own' {
            $Version = $Gpo.Version
            $Result = Import-PSGPOPolicyRuleSet -Directory $Directory -RuleSet $Reference -TargetName $Gpo.DisplayName -PolicyName 'HGPM Test - Computer' -BackupPath $Backups -Confirm:$false 3>$null
            $Result.Policies | Should -Be @('HGPM Test - Computer')
            $Result.Registry | Should -Be 16 -Because 'BigEndian has no data in a rule set'
            @($Result.Skipped) | Should -BeLike '*BigEndian*REG_DWORD_BIG_ENDIAN without its data*'
            $Result.SecurityTemplate | Should -Be 14
            $Result.Audit | Should -Be 4
            $Result.BackupBefore | Should -Not -BeNullOrEmpty
            $Gpo.Version | Should -Not -Be $Version

            $Written = & $SetOfGpo
            $Imported = Select-RuleSet -Set $Reference -Name 'Set' -PolicyName 'HGPM Test - Computer'
            $Rows = @(Compare-PSGPOPolicyRuleSet -RuleSet $Imported, $Written)
            @($Rows | Where-Object { $_.Cells[0].State -ne 'Absent' -and $_.Difference } | ForEach-Object Setting) | Should -Be @('BigEndian') -Because 'every setting of the set is in the GPO'
            ($Rows | Where-Object Setting -EQ 'Kept').GPO | Should -Be '9' -Because 'the GPO keeps its own settings'
            ($Rows | Where-Object Setting -EQ 'LockoutBadCount').GPO | Should -Not -BeNullOrEmpty
            # A **delvals. clears the values of the key; a service is replaced, not listed twice.
            @($Written.Rules | Where-Object { $_.Key -eq 'Software\Policies\HGPM Test\List' } | ForEach-Object ValueName) | Should -Be @('**delvals.', '1')
            @($Written.Rules | Where-Object LineItem -Like '"Spooler"*').Count | Should -Be 1
            ($Written.Rules | Where-Object LineItem -Like '"Spooler"*').LineItem | Should -Be '"Spooler",4,"D:AR(A;;RPWPCCDCLCSWRCWDWOGA;;;BA)"'
            # The extensions of the settings, and those of the set, with the tool of the administrative templates.
            $Gpo.MachineExtensionNames.Contains('[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}') | Should -BeTrue -Because $Gpo.MachineExtensionNames
            $Gpo.MachineExtensionNames.Contains('[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}') | Should -BeTrue -Because $Gpo.MachineExtensionNames
            $Gpo.MachineExtensionNames.Contains('[{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}]') | Should -BeTrue -Because $Gpo.MachineExtensionNames
            $Gpo.MachineExtensionNames.Contains('[{2A8FDC61-2347-4C87-92F6-B05EB91A201A}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]') | Should -BeTrue -Because $Gpo.MachineExtensionNames
            $Gpo.UserExtensionNames.Contains('[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F73-3407-48AE-BA88-E8213C6761F1}]') | Should -BeTrue -Because $Gpo.UserExtensionNames
        }

        It 'Replaces the settings of the GPO by those of the set with -Replace' {
            $null = Import-PSGPOPolicyRuleSet -Directory $Directory -RuleSet $Reference -TargetName $Gpo.DisplayName -PolicyName 'HGPM Test - Second' -Replace -NoBackup -Confirm:$false
            $Written = & $SetOfGpo
            @($Written.Rules | Where-Object ValueName -EQ 'Kept').Count | Should -Be 0
            @($Written.Rules | Where-Object LineItem -Like 'LockoutBadCount*').Count | Should -Be 0
            @($Written.Rules | Where-Object Kind -EQ 'Registry' | ForEach-Object ValueName) | Should -Be @('Same', 'Differs', 'TypeDiffers', 'OnlyB')
            @($Written.Rules | Where-Object Kind -EQ 'SecurityTemplate' | ForEach-Object LineItem) | Should -Be @('MinimumPasswordAge=2', 'SeBackupPrivilege=*S-1-5-32-544,*S-1-5-32-551')
        }

        It 'Warns of the settings the GPOs of the set give different values, and writes the value of the last one' {
            $null = Import-PSGPOPolicyRuleSet -Directory $Directory -RuleSet $Reference -TargetName $Gpo.DisplayName -NoBackup -Confirm:$false -WarningVariable Warned 3>$null
            "$Warned" | Should -BeLike '*3 setting(s) given different values by the GPOs of the rule set*'
            $Written = & $SetOfGpo
            ($Written.Rules | Where-Object ValueName -EQ 'Differs').RegData | Should -Be '2'
            ($Written.Rules | Where-Object LineItem -Like 'MinimumPasswordAge=*').LineItem | Should -Be 'MinimumPasswordAge=2'
        }

        It 'Changes nothing with -WhatIf, refuses a GPO the domain does not have, creates it with -CreateIfNeeded' {
            $Version = $Gpo.Version
            Import-PSGPOPolicyRuleSet -Directory $Directory -RuleSet $Reference -TargetName $Gpo.DisplayName -WhatIf 3>$null
            $Gpo.Version | Should -Be $Version
            { Import-PSGPOPolicyRuleSet -Directory $Directory -RuleSet $Reference -TargetName 'C - New Baseline' -Confirm:$false 3>$null } | Should -Throw -ExpectedMessage '*-CreateIfNeeded*'
            { Import-PSGPOPolicyRuleSet -Directory $Directory -RuleSet $Reference -TargetName $Gpo.DisplayName -PolicyName 'Nothing' -Confirm:$false } | Should -Throw -ExpectedMessage "No setting of the GPOs 'Nothing'*"
            $Result = Import-PSGPOPolicyRuleSet -Directory $Directory -RuleSet $Reference -TargetName 'C - New Baseline' -PolicyName 'HGPM Test - Second' -CreateIfNeeded -NoBackup -Confirm:$false
            $Directory.FindGpo('C - New Baseline') | Should -Not -BeNullOrEmpty
            $Result.Registry | Should -Be 4
        }
    }

    Describe 'GPOs that apply to a domain or an OU, by precedence' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Laptops = $Directory.FindSom('OU=Laptops,OU=Workstations,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com')
            # A value in two GPOs of the OU, a **delvals. of the one of higher precedence, and a part
            # of a GPO its status disables.
            $Write = {
                param($Name, [object[]]$Entries, [int]$Flags = -1)
                $Gpo = $Directory.FindGpo($Name)
                $Pol = [GPOToolsRegistryPol]::new()
                foreach ($Entry in $Entries) { $Pol.Entries.Add([GPOToolsPolEntry]::new($Entry[0], $Entry[1], [GPOToolsPolType]$Entry[2], [byte[]]$Entry[3])) }
                $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
                if ($Flags -ge 0) { $Gpo.Flags = $Flags }
            }
            $Dword = { param([uint32]$Value) [BitConverter]::GetBytes($Value) }
            & $Write 'C - Laptops - Power Management' @(@('Software\Policies\HGPM', 'Value', 'DWord', (& $Dword 1)), @('Software\Policies\HGPM\List', '**delvals.', 'String', [GPOToolsPolEntry]::EncodeString(' ')))
            & $Write 'C - Workstations - BitLocker' @(@('Software\Policies\HGPM', 'Value', 'DWord', (& $Dword 2)), @('Software\Policies\HGPM\List', '1', 'String', [GPOToolsPolEntry]::EncodeString('cleared')))
            & $Write 'C - All - Windows Firewall' @(, @('Software\Policies\HGPM', 'Off', 'DWord', (& $Dword 1))) -Flags 2
        }

        It 'Orders the GPOs as the Group Policy Inheritance tab of GPMC: enforced first from the domain, then from the OU up' {
            @(Get-PSGPOSomPrecedence -Som $Laptops | ForEach-Object { '{0} {1}' -f $_.Precedence, $_.Gpo.DisplayName }) | Should -Be @(
                '1 C - All - LAPS'
                '2 C - Workstations - Security Baseline Windows 11'
                '3 C - Laptops - Power Management'
                '4 C - Workstations - BitLocker'
                '5 C - Workstations - Windows Update Ring Broad'
                '6 Default Domain Policy'
                '7 C - All - Defender Antivirus'
                '8 C - All - Windows Firewall'
            ) -Because 'the disabled link of OLD - Windows 10 Baseline does not apply'
            # An OU that blocks the inheritance: the enforced links only, then its own.
            $Kiosks = $Directory.FindSom('OU=Kiosks,OU=Workstations,OU=Paris,OU=Sites,DC=corp,DC=contoso,DC=com')
            @(Get-PSGPOSomPrecedence -Som $Kiosks | ForEach-Object Gpo | ForEach-Object DisplayName) | Should -Be @('C - All - LAPS', 'C - Workstations - Security Baseline Windows 11', 'C - Kiosks - Assigned Access')
        }

        It 'Shows the value that wins, the values it overrides, and the values a **delvals. of higher precedence clears' {
            $Set = Get-PSGPOPolicyRuleSet -Directory $Directory -Container 'OU=Laptops,OU=Workstations,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com'
            $Set.Name | Should -Be 'Laptops (precedence)'
            ($Set.Rules | Where-Object ValueName -EQ 'Value' | Sort-Object Precedence | ForEach-Object { "$($_.PolicyName)=$($_.Precedence)" }) | Should -Be @('C - Laptops - Power Management=3', 'C - Workstations - BitLocker=4')
            @($Set.Rules | Where-Object ValueName -EQ 'Off').Count | Should -Be 0 -Because 'the status of the GPO disables its computer settings'

            $Rows = @(Compare-PSGPOPolicyRuleSet -RuleSet $Set)
            $Value = $Rows | Where-Object Setting -EQ 'Value'
            $Value.'Laptops (precedence)' | Should -Be '1'
            $Value.Cells[0].State | Should -Be 'Overridden'
            $Value.Conflict | Should -BeFalse -Because 'the precedence decides'
            @($Value.Cells[0].Values | ForEach-Object { '{0} {1} {2}' -f $_.PolicyName, $_.Precedence, $_.Applied }) | Should -Be @('C - Laptops - Power Management 3 True', 'C - Workstations - BitLocker 4 False')
            $Cleared = $Rows | Where-Object { $_.Group -eq 'Software\Policies\HGPM\List' -and $_.Setting -eq '1' }
            $Cleared.'Laptops (precedence)' | Should -Be '[[[Delete all values]]]'
            $Cleared.Cells[0].State | Should -Be 'Overridden'

            # Against a set without order: the value that wins is the one compared.
            $Baseline = [GPOToolsPolicyRuleSet]::new('Baseline')
            $Baseline.Rules.Add([GPOToolsPolicyRule]@{ Kind = 'Registry'; Scope = 'Computer'; Key = 'Software\Policies\HGPM'; ValueName = 'Value'; RegType = 'REG_DWORD'; RegData = '2'; PolicyName = 'Baseline' })
            $Against = @(Compare-PSGPOPolicyRuleSet -RuleSet $Baseline, $Set) | Where-Object Setting -EQ 'Value'
            $Against.Conflict | Should -BeTrue
            $Against.Baseline | Should -Be '2'
            $Against.'Laptops (precedence)' | Should -Be '1'
        }

        It 'Finds the OU by its name, and says when several OUs have it' {
            (Get-PSGPOPolicyRuleSet -Directory $Directory -Container 'Kiosks' -SetName 'Kiosks').Path | Should -Be 'OU=Kiosks,OU=Workstations,OU=Paris,OU=Sites,DC=corp,DC=contoso,DC=com'
            { Get-PSGPOPolicyRuleSet -Directory $Directory -Container 'Laptops' } | Should -Throw -ExpectedMessage "Several OUs are named 'Laptops'*"
        }
    }

    Describe 'Effective state of the computer' {
        BeforeAll {
            function New-TestRule {
                param([hashtable]$Values)
                $Rule = [GPOToolsPolicyRule]::new()
                $Rule.PolicyName = 'Baseline GPO'
                foreach ($Name in $Values.Keys) { $Rule.$Name = $Values[$Name] }
                $Rule
            }
            $Baseline = [GPOToolsPolicyRuleSet]::new('Baseline')
            foreach ($Values in @(
                    @{ Kind = 'Registry'; Scope = 'Computer'; Key = 'Software\Policies\Test'; ValueName = 'Enabled'; RegType = 'REG_DWORD'; RegData = '1' }
                    @{ Kind = 'Registry'; Scope = 'Computer'; Key = 'Software\Policies\Test'; ValueName = '**del.Old'; RegType = 'REG_SZ'; RegData = ' ' }
                    @{ Kind = 'Registry'; Scope = 'Computer'; Key = 'Software\Policies\Test'; ValueName = 'Missing'; RegType = 'REG_SZ'; RegData = 'x' }
                    @{ Kind = 'Registry'; Scope = 'User'; Key = 'Software\Policies\List'; ValueName = '**delvals.'; RegType = 'REG_SZ'; RegData = ' ' }
                    @{ Kind = 'Registry'; Scope = 'User'; Key = 'Software\Policies\List'; ValueName = '1'; RegType = 'REG_MULTI_SZ'; RegData = 'a\0b' }
                    @{ Kind = 'SecurityTemplate'; Section = 'Registry Values'; LineItem = 'MACHINE\System\Lsa\NoLMHash=4,1' }
                    @{ Kind = 'SecurityTemplate'; Section = 'Service General Setting'; LineItem = '"Spooler",4,""' }
                    @{ Kind = 'SecurityTemplate'; Section = 'Privilege Rights'; LineItem = 'SeBackupPrivilege=*S-1-5-32-544' }
                    @{ Kind = 'SecurityTemplate'; Section = 'Privilege Rights'; LineItem = 'SeTcbPrivilege=' }
                    @{ Kind = 'AuditSubcategory'; Guid = '{0cce923f-69ae-11d9-bed3-505054503030}'; Name = 'Audit Credential Validation'; Setting = '3' }
                )) { $Baseline.Rules.Add((New-TestRule $Values)) }
        }
        BeforeEach {
            Mock Test-PSGPOEffectiveStateSupported { $true }
            Mock Get-PSGPOEffectiveRegistryKey {
                $Values = [System.Collections.Generic.Dictionary[string, GPOToolsPolEntry]]::new([System.StringComparer]::OrdinalIgnoreCase)
                switch ("$Scope|$Key") {
                    'Computer|Software\Policies\Test' { $Values['Enabled'] = [GPOToolsPolEntry]::new($Key, 'Enabled', 'DWord', [BitConverter]::GetBytes([int]0)) }
                    'User|Software\Policies\List' { $Values['1'] = [GPOToolsPolEntry]::new($Key, '1', 'MultiString', [System.Text.Encoding]::Unicode.GetBytes("b`0a`0`0")) }
                    'Computer|System\Lsa' { $Values['NoLMHash'] = [GPOToolsPolEntry]::new($Key, 'NoLMHash', 'DWord', [BitConverter]::GetBytes([int]1)) }
                    'Computer|SYSTEM\CurrentControlSet\Services\Spooler' { $Values['Start'] = [GPOToolsPolEntry]::new($Key, 'Start', 'DWord', [BitConverter]::GetBytes([int]2)) }
                    default { return }
                }
                $Values
            }
            Mock Get-PSGPOEffectiveSecurityTemplate { , [System.Text.Encoding]::Unicode.GetBytes("`u{FEFF}[Unicode]`r`nUnicode=yes`r`n[Privilege Rights]`r`nSeBackupPrivilege = *S-1-5-32-551,*S-1-5-32-544`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1`r`n") }
            Mock Get-PSGPOEffectiveAuditPolicy { , [System.Text.Encoding]::UTF8.GetBytes("Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value`r`nCLI,System,Audit Credential Validation,{0CCE923F-69AE-11D9-BED3-505054503030},Success,,1`r`n") }
        }

        It 'Reads, for each setting of the sets, the value the computer and its user have now' {
            Mock Test-PSGPOIsAdministrator { $true }
            $State = New-PSGPOPolicyRuleSetFromEffectiveState -RuleSet $Baseline -SetName 'Here'
            $State.Skipped | Should -Be 0
            $Set = $State.RuleSet
            $Set.Name | Should -Be 'Here'
            $Lines = @($Set.Rules | ForEach-Object { '{0}|{1}' -f $_.GetIdentity(), $_.GetComparable() })
            $Lines | Should -Be @(
                'computer|registry|software\policies\test|enabled|REG_DWORD|0'
                'computer|registry|software\policies\test|old|[[[delete]]]'
                'user|registry|software\policies\list|**delvals.|[[[Delete all values]]]'
                'user|registry|software\policies\list|1|REG_MULTI_SZ|a,b'
                'computer|securitytemplate|registry values|machine\system\lsa\nolmhash|4,1'
                'computer|securitytemplate|service general setting|spooler|2,""'
                'computer|securitytemplate|privilege rights|sebackupprivilege|*S-1-5-32-544,*S-1-5-32-551'
                'computer|securitytemplate|privilege rights|setcbprivilege|'
                'computer|auditsubcategory|{0cce923f-69ae-11d9-bed3-505054503030}|1'
            ) -Because 'a value the computer does not have is not in the set, a value deleted is, and a right nobody has is empty'
            @($Set.Rules.PolicyName | Select-Object -Unique) | Should -Be 'Effective state'
            ($Set.Rules | Where-Object ValueName -EQ 'Enabled').SourceFile | Should -Be 'HKLM\Software\Policies\Test'
            # Saved and read again as Policy Analyzer does.
            $Read = [GPOToolsPolicyRuleSet]::Parse($Set.ToBytes(), 'Here')
            @($Read.Rules | ForEach-Object { '{0}|{1}' -f $_.GetIdentity(), $_.GetComparable() }) | Should -Be $Lines
            $Rows = @(Compare-PSGPOPolicyRuleSet -RuleSet $Baseline, $Set -DifferenceOnly)
            @($Rows | ForEach-Object { $_.Cells[1].State }) | Should -Contain 'Absent' -Because 'the value the computer does not have'
            $Rows.Count | Should -Be 5 -Because 'Enabled, Missing, the startup of Spooler, the accounts of SeBackupPrivilege and the audit differ'
        }

        It 'Without an administrator, reads the registry and counts the settings secedit and auditpol give' {
            Mock Test-PSGPOIsAdministrator { $false }
            $State = New-PSGPOPolicyRuleSetFromEffectiveState -RuleSet $Baseline
            $State.Skipped | Should -Be 3
            $State.RuleSet.Name | Should -Match '^EffectiveState_.+_\d{8}-\d{6}$'
            @($State.RuleSet.Rules | Where-Object { $_.Section -eq 'Privilege Rights' -or $_.Kind -like 'Audit*' }) | Should -BeNullOrEmpty
            @($State.RuleSet.Rules).Count | Should -Be 6
            Should -Invoke Get-PSGPOEffectiveSecurityTemplate -Times 0 -Exactly
            Should -Invoke Get-PSGPOEffectiveAuditPolicy -Times 0 -Exactly
            $Output = Get-PSGPOPolicyRuleSet -EffectiveState -RuleSet $Baseline -SetName 'Mine' 3>&1
            @($Output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Message | Should -Be '3 security and audit settings are not read: secedit and auditpol need PowerShell run as an administrator.'
            @($Output | Where-Object { $_ -is [GPOToolsPolicyRuleSet] }).Name | Should -Be 'Mine'
        }

        It 'Is the one of a Windows computer' {
            Mock Test-PSGPOEffectiveStateSupported { $false }
            { New-PSGPOPolicyRuleSetFromEffectiveState -RuleSet $Baseline } | Should -Throw '*Windows*'
        }
    }

    Describe 'Names of the policies of the ADMX' {
        BeforeAll {
            Initialize-PSGPOAdmx -Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions') -UICulture 'en-US' 3>$null
        }
        AfterAll {
            [GPOToolsUtility]::RemoveAll()
        }

        It 'Shows a registry value as the policy and option of the ADMX that write it' {
            $Set = [GPOToolsPolicyRuleSet]::new('Admx')
            $Set.Rules.Add([GPOToolsPolicyRule]@{ Kind = 'Registry'; Scope = 'Computer'; Key = 'Software\Policies\Microsoft\Windows\Personalization'; ValueName = 'NoLockScreen'; RegType = 'REG_DWORD'; RegData = '1'; PolicyName = 'GPO' })
            $Set.Rules.Add([GPOToolsPolicyRule]@{ Kind = 'Registry'; Scope = 'User'; Key = 'Software\Policies\Microsoft\Windows\Control Panel\Desktop'; ValueName = 'ScreenSaveTimeOut'; RegType = 'REG_SZ'; RegData = '900'; PolicyName = 'GPO' })
            $Set.Rules.Add([GPOToolsPolicyRule]@{ Kind = 'Registry'; Scope = 'Computer'; Key = 'Software\Policies\HGPM'; ValueName = 'Unknown'; RegType = 'REG_DWORD'; RegData = '1'; PolicyName = 'GPO' })
            $Rows = @(Compare-PSGPOPolicyRuleSet -RuleSet $Set)
            $Lock = $Rows | Where-Object Setting -EQ 'NoLockScreen'
            $Lock.Name | Should -Be 'Do not display the lock screen'
            $Lock.Path | Should -Be 'Policies > Administrative Templates > Control Panel > Personalization'
            $Lock.Explain | Should -BeLike 'This policy setting controls whether the lock screen appears*'
            $Saver = $Rows | Where-Object Setting -EQ 'ScreenSaveTimeOut'
            $Saver.Name | Should -Be 'Screen saver timeout'
            $Saver.Option | Should -Be 'Seconds'
            ($Rows | Where-Object Setting -EQ 'Unknown').Name | Should -Be 'HKLM\Software\Policies\HGPM\Unknown'
            ($Rows | Where-Object Setting -EQ 'Unknown').Path | Should -Be 'Extra Registry Settings'
        }
    }

    Describe 'Excel workbook of a comparison' {
        It 'Writes a workbook Excel opens: the colours of Policy Analyzer, the GPOs of each set' {
            $Reference = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($Expected), 'Both')
            $First = Select-RuleSet -Set $Reference -Name 'Computer' -PolicyName 'HGPM Test - Computer'
            $Second = Select-RuleSet -Set $Reference -Name 'Second' -PolicyName 'HGPM Test - Second'
            $File = Compare-PSGPOPolicyRuleSet -RuleSet $First, $Second | Export-PSGPOPolicyRuleComparison -Path (Join-Path $TestDrive 'Comparison.xlsx') -All
            Add-Type -AssemblyName System.IO.Compression
            $Zip = [System.IO.Compression.ZipArchive]::new([System.IO.File]::OpenRead($File.FullName))
            try {
                @($Zip.Entries.FullName) | Should -Contain 'xl/workbook.xml'
                $Read = { param($Name) $Stream = $Zip.GetEntry($Name).Open(); try { [System.IO.StreamReader]::new($Stream).ReadToEnd() } finally { $Stream.Dispose() } }
                $Workbook = [xml](& $Read 'xl/workbook.xml')
                @($Workbook.workbook.sheets.sheet.name) | Should -Be @('Comparison', 'GPOs')
                $Sheet = [xml](& $Read 'xl/worksheets/sheet1.xml')
                $Ns = [System.Xml.XmlNamespaceManager]::new($Sheet.NameTable)
                $Ns.AddNamespace('s', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
                $Header = @($Sheet.SelectNodes('//s:row[@r="1"]/s:c', $Ns) | ForEach-Object InnerText)
                $Header[0..5] | Should -Be @('Scope', 'Path', 'Name', 'Option', 'Computer', 'Second')
                $Header | Should -Contain 'Computer - GPOs'
                $Sheet.SelectSingleNode('//s:autoFilter', $Ns).GetAttribute('ref') | Should -Be "A1:M$($Sheet.SelectNodes('//s:row', $Ns).Count)"
                # The row of Differs: yellow (style 2); of OnlyB: grey where absent (style 3).
                $RowOf = { param($Setting) $Sheet.SelectNodes('//s:row', $Ns) | Where-Object { @($_.SelectNodes('s:c', $Ns))[8].InnerText -eq $Setting } }
                @((& $RowOf 'Differs').SelectNodes('s:c', $Ns))[4].GetAttribute('s') | Should -Be '2'
                @((& $RowOf 'OnlyB').SelectNodes('s:c', $Ns))[4].GetAttribute('s') | Should -Be '3'
                @((& $RowOf 'OnlyB').SelectNodes('s:c', $Ns))[5].GetAttribute('s') | Should -Be '0'
                $Gpos = [xml](& $Read 'xl/worksheets/sheet2.xml')
                $Gpos.DocumentElement.InnerText | Should -BeLike '*HGPM Test - Second*'
            } finally { $Zip.Dispose() }
        }

        It 'Names the columns A to Z, then AA' {
            Get-PSGPOXlsxColumnName 0 | Should -Be 'A'
            Get-PSGPOXlsxColumnName 25 | Should -Be 'Z'
            Get-PSGPOXlsxColumnName 26 | Should -Be 'AA'
            Get-PSGPOXlsxColumnName 701 | Should -Be 'ZZ'
            Get-PSGPOXlsxColumnName 702 | Should -Be 'AAA'
        }
    }
}
