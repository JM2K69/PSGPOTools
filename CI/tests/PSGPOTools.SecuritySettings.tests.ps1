#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Security settings of a GPO: GptTmpl.inf ([MS-GPSB] 2.2, GPOToolsSecurityTemplate), the catalog
# of the settings (Get-PSGPOSecuritySetting), their values and the Settings report. The fixtures
# are the GptTmpl.inf of the default GPOs of a Samba 4.22 domain.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $Fixtures = Join-Path $PSScriptRoot 'Fixtures'
        $DefaultDomain = Join-Path $Fixtures 'GptTmpl.DefaultDomainPolicy.samba.inf'
        $DefaultDc = Join-Path $Fixtures 'GptTmpl.DefaultDomainControllersPolicy.samba.inf'

        function Get-Text {
            param([byte[]]$Bytes)
            $Bytes[0..1] | Should -Be @(0xFF, 0xFE) -Because 'GptTmpl.inf is written in UTF-16LE with a byte order mark'
            [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
        }
        function Get-Setting {
            param([string]$Section, [string]$Key)
            Get-PSGPOSecuritySetting | Where-Object { $_.Section -eq $Section -and $_.Key -eq $Key }
        }
    }

    Describe 'GptTmpl.inf format' {
        It 'Rewrites the files of Samba byte for byte' {
            foreach ($File in $DefaultDomain, $DefaultDc) {
                $Bytes = [System.IO.File]::ReadAllBytes($File)
                [Linq.Enumerable]::SequenceEqual([byte[]][GPOToolsSecurityTemplate]::Parse($Bytes).ToBytes(), $Bytes) | Should -BeTrue -Because $File
            }
        }

        It 'Reads the sections and values, whatever the case of their names' {
            $Template = [GPOToolsSecurityTemplate]::Parse([System.IO.File]::ReadAllBytes($DefaultDomain))
            $Template.GetSectionNames() | Should -Be @('Unicode', 'System Access', 'Kerberos Policy', 'Registry Values', 'Version')
            $Template.GetValue('system access', 'MINIMUMPASSWORDLENGTH') | Should -Be '12'
            $Template.GetValue('Registry Values', 'MACHINE\System\CurrentControlSet\Control\Lsa\NoLMHash') | Should -Be '4,1'
            $Template.GetValue('System Access', 'Missing') | Should -BeNullOrEmpty
            $Template.HasValue('Kerberos Policy', 'MaxClockSkew') | Should -BeTrue
        }

        It 'Changes a value in place, keeping the other lines as they were' {
            $Template = [GPOToolsSecurityTemplate]::Parse([System.IO.File]::ReadAllBytes($DefaultDomain))
            $Template.SetValue('System Access', 'MinimumPasswordLength', '14')
            $Template.SetValue('Registry Values', 'MACHINE\Software\Contoso\Value', '4,1')
            $Template.SetValue('Privilege Rights', 'SeBackupPrivilege', '*S-1-5-32-544')
            $Lines = (Get-Text $Template.ToBytes()) -split "`r`n"
            $Lines[3] | Should -Be 'MinimumPasswordAge = 0'
            $Lines | Should -Contain 'MinimumPasswordLength = 14'
            # As secedit writes them: no spaces in [Registry Values], spaces elsewhere.
            $Lines | Should -Contain 'MACHINE\Software\Contoso\Value=4,1'
            $Lines | Should -Contain 'SeBackupPrivilege = *S-1-5-32-544'
            $Lines[-1] | Should -Be '' -Because 'the last line ends with CRLF'
        }

        It 'Removes a setting, and the section it empties' {
            $Template = [GPOToolsSecurityTemplate]::Parse([System.IO.File]::ReadAllBytes($DefaultDomain))
            $Template.SetValue('Registry Values', 'MACHINE\System\CurrentControlSet\Control\Lsa\NoLMHash', $null)
            $Template.GetSectionNames() | Should -Not -Contain 'Registry Values'
            $Template.SetValue('System Access', 'Missing', $null)
            $Template.IsEmpty() | Should -BeFalse
        }

        It 'Reads a file written by samba-tool: UTF-8, no [Unicode] nor [Version], and adds them when writing a setting' {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes("[System Access]`nMinimumPasswordLength = 10`n")
            $Template = [GPOToolsSecurityTemplate]::Parse($Bytes)
            $Template.GetValue('System Access', 'MinimumPasswordLength') | Should -Be '10'
            Set-PSGPOSecurityValue -Template $Template -Setting (Get-Setting 'System Access' 'PasswordComplexity') -Value $true
            $Template.GetSectionNames() | Should -Be @('Unicode', 'Version', 'System Access')
            ((Get-Text $Template.ToBytes()) -split "`r`n")[0..3] | Should -Be @('[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"')
        }

        It 'Keeps the comments and blank lines it reads' {
            $Text = "[Unicode]`r`nUnicode=yes`r`n; a comment`r`n`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1`r`n"
            $Bytes = [byte[]]([byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($Text))
            [Linq.Enumerable]::SequenceEqual([byte[]][GPOToolsSecurityTemplate]::Parse($Bytes).ToBytes(), $Bytes) | Should -BeTrue
        }

        It 'Writes a new template with its preamble' {
            $Template = [GPOToolsSecurityTemplate]::new()
            $Template.IsEmpty() | Should -BeTrue
            Get-Text $Template.ToBytes() | Should -Be "[Unicode]`r`nUnicode=yes`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1`r`n"
            [GPOToolsSecurityTemplate]::Parse(@()).IsEmpty() | Should -BeTrue
        }

        It 'Refuses a file that is not a security template' {
            { [GPOToolsSecurityTemplate]::Parse([System.Text.Encoding]::UTF8.GetBytes('MinimumPasswordLength = 1')) } | Should -Throw -ExpectedMessage '*setting before any*'
            { [GPOToolsSecurityTemplate]::Parse([System.Text.Encoding]::UTF8.GetBytes('; only a comment')) } | Should -Throw -ExpectedMessage '*no `[section`]*'
        }
    }

    Describe 'Catalog of the security settings' {
        BeforeAll { $Catalog = @(Get-PSGPOSecuritySetting) }

        It 'Has every setting once, under the nodes of the Group Policy editor' {
            $Catalog.Count | Should -BeGreaterThan 180
            @($Catalog | Group-Object Id | Where-Object Count -GT 1).Count | Should -Be 0
            $Paths = @($Catalog | ForEach-Object { $_.Path -join ' > ' } | Select-Object -Unique)
            foreach ($Path in 'Account Policies > Password Policy', 'Account Policies > Account Lockout Policy', 'Account Policies > Kerberos Policy',
                'Local Policies > Audit Policy', 'Local Policies > User Rights Assignment', 'Local Policies > Security Options', 'Event Log') {
                $Paths | Should -Contain $Path
            }
        }

        It 'Gives every setting a name, a known kind and, for registry values, a type and a display' {
            foreach ($Setting in $Catalog) {
                $Setting.Name | Should -Not -Match '^(@|%)' -Because $Setting.Key
                $Setting.Kind | Should -BeIn 'Number', 'Boolean', 'Text', 'Choice', 'Audit', 'Accounts', 'RegistryValue'
                if ($Setting.Kind -eq 'RegistryValue') {
                    $Setting.RegistryType | Should -BeIn 1, 2, 3, 4, 7 -Because $Setting.Name
                    $Setting.Display | Should -BeIn 'Boolean', 'Number', 'Text', 'Choice', 'MultiText', 'Bitmask' -Because $Setting.Name
                }
                if ($Setting.Kind -eq 'Choice' -or $Setting.Display -in 'Choice', 'Bitmask') { $Setting.Choices.Count | Should -BeGreaterThan 0 -Because $Setting.Name }
            }
        }

        It 'Shows the registry values of the password policy with it, not with the security options' {
            (Get-Setting 'Registry Values' 'MACHINE\System\CurrentControlSet\Control\SAM\RelaxMinimumPasswordLengthLimits').Path | Should -Be @('Account Policies', 'Password Policy')
        }
    }

    Describe 'Values of the security settings' {
        It 'Reads and writes <Kind> values' -ForEach @(
            @{ Kind = 'number'; Section = 'System Access'; Key = 'MinimumPasswordLength'; Raw = '12'; Value = 12; Text = '12 characters' }
            @{ Kind = 'boolean'; Section = 'System Access'; Key = 'PasswordComplexity'; Raw = '1'; Value = $true; Text = 'Enabled' }
            @{ Kind = 'text'; Section = 'System Access'; Key = 'NewAdministratorName'; Raw = '"Admin ""Root"""'; Value = 'Admin "Root"'; Text = 'Admin "Root"' }
            @{ Kind = 'choice'; Section = 'Security Log'; Key = 'AuditLogRetentionPeriod'; Raw = '2'; Value = 2; Text = 'Do not overwrite events (clear log manually)' }
            @{ Kind = 'audit'; Section = 'Event Audit'; Key = 'AuditLogonEvents'; Raw = '3'; Value = 3; Text = 'Success, Failure' }
            @{ Kind = 'user right'; Section = 'Privilege Rights'; Key = 'SeBackupPrivilege'; Raw = '*S-1-5-32-551,CONTOSO\Backup'; Value = [string[]]@('*S-1-5-32-551', 'CONTOSO\Backup'); Text = 'BUILTIN\Backup Operators, CONTOSO\Backup' }
            @{ Kind = 'registry boolean'; Section = 'Registry Values'; Key = 'MACHINE\System\CurrentControlSet\Control\Lsa\NoLMHash'; Raw = '4,1'; Value = $true; Text = 'Enabled' }
            @{ Kind = 'registry choice'; Section = 'Registry Values'; Key = 'MACHINE\System\CurrentControlSet\Control\Lsa\LmCompatibilityLevel'; Raw = '4,5'; Value = 5; Text = 'Send NTLMv2 response only. Refuse LM & NTLM' }
            @{ Kind = 'registry multi-line text'; Section = 'Registry Values'; Key = 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\NullSessionShares'; Raw = '7,share1,share2'; Value = [string[]]@('share1', 'share2'); Text = 'share1; share2' }
            @{ Kind = 'registry bitmask'; Section = 'Registry Values'; Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters\SupportedEncryptionTypes'; Raw = '4,24'; Value = 24; Text = 'AES128_HMAC_SHA1, AES256_HMAC_SHA1' }
        ) {
            $Setting = Get-Setting $Section $Key
            $Setting | Should -Not -BeNullOrEmpty
            $Read = $Setting.ConvertFromRaw($Raw)
            $Read | Should -Be $Value
            $Setting.ConvertToRaw($Read) | Should -Be $Raw
            $Setting.FormatValue($Read) | Should -Be $Text
        }

        It 'Shows the special values with their meaning' {
            (Get-Setting 'System Access' 'MaximumPasswordAge').FormatValue(-1) | Should -Be 'Password will not expire'
            (Get-Setting 'System Access' 'LockoutBadCount').FormatValue(0) | Should -Be 'Account will not lock out'
            (Get-Setting 'Event Audit' 'AuditSystemEvents').FormatValue(0) | Should -Be 'No auditing'
            (Get-Setting 'System Access' 'MaximumPasswordAge').FormatValue($null) | Should -Be 'Not Defined'
        }

        It 'Refuses a value out of its range, and changes nothing' {
            $Template = [GPOToolsSecurityTemplate]::Parse([System.IO.File]::ReadAllBytes($DefaultDomain))
            { Set-PSGPOSecurityValue -Template $Template -Setting (Get-Setting 'System Access' 'MinimumPasswordLength') -Value 200 } | Should -Throw -ExpectedMessage '*at most 128 characters*'
            { Set-PSGPOSecurityValue -Template $Template -Setting (Get-Setting 'Security Log' 'AuditLogRetentionPeriod') -Value 7 } | Should -Throw -ExpectedMessage '*not one of its choices*'
            $Template.GetValue('System Access', 'MinimumPasswordLength') | Should -Be '12'
        }

        It 'Reads, writes and removes the value of a setting in a template' {
            $Template = [GPOToolsSecurityTemplate]::Parse([System.IO.File]::ReadAllBytes($DefaultDomain))
            $Setting = Get-Setting 'Event Audit' 'AuditLogonEvents'
            (Get-PSGPOSecurityValue -Template $Template -Setting $Setting).Defined | Should -BeFalse
            Set-PSGPOSecurityValue -Template $Template -Setting $Setting -Value 2
            $Read = Get-PSGPOSecurityValue -Template $Template -Setting $Setting
            $Read.Defined | Should -BeTrue
            $Read.Value | Should -Be 2
            $Read.Raw | Should -Be '2'
            Set-PSGPOSecurityValue -Template $Template -Setting $Setting -Value $null
            (Get-PSGPOSecurityValue -Template $Template -Setting $Setting).Defined | Should -BeFalse
            $Template.GetSectionNames() | Should -Not -Contain 'Event Audit'
        }

        It 'Says when a value cannot be read' {
            $Template = [GPOToolsSecurityTemplate]::Parse([System.Text.Encoding]::UTF8.GetBytes("[System Access]`nMinimumPasswordLength = twelve`n"))
            $Read = Get-PSGPOSecurityValue -Template $Template -Setting (Get-Setting 'System Access' 'MinimumPasswordLength')
            $Read.Defined | Should -BeTrue
            $Read.Problem | Should -BeLike "*'twelve' cannot be read*"
        }
    }

    Describe 'Settings report of the security settings' {
        It 'Lists the defined settings of the Default Domain Policy of Samba, as GPMC' {
            $Rows = @(Get-PSGPOConfiguredSecuritySetting -Template ([GPOToolsSecurityTemplate]::Parse([System.IO.File]::ReadAllBytes($DefaultDomain))))
            $Length = $Rows | Where-Object Name -EQ 'Minimum password length'
            $Length.Path | Should -Be 'Policies > Windows Settings > Security Settings > Account Policies > Password Policy'
            $Length.State | Should -Be '12 characters'
            ($Rows | Where-Object Name -EQ 'Maximum lifetime for user ticket').State | Should -Be '10 hours'
            ($Rows | Where-Object Name -EQ 'Account lockout threshold').State | Should -Be 'Account will not lock out'
            ($Rows | Where-Object Name -Like 'Network security: Do not store LAN Manager hash*').State | Should -Be 'Enabled'
            # A key Windows ignores: shown as it is.
            $Extra = $Rows | Where-Object Name -EQ 'RequireLogonToChangePassword'
            $Extra.IsExtra | Should -BeTrue
            $Extra.Path | Should -Be 'Policies > Windows Settings > Security Settings > [System Access]'
            $Rows | ForEach-Object { $_.GetType().Name | Should -Be 'AvaloniaSettingRow' }
        }

        It 'Names the accounts of the user rights' {
            $Rows = @(Get-PSGPOConfiguredSecuritySetting -Template ([GPOToolsSecurityTemplate]::Parse([System.IO.File]::ReadAllBytes($DefaultDc))))
            ($Rows | Where-Object Name -EQ 'Back up files and directories').State | Should -Be 'BUILTIN\Server Operators, BUILTIN\Backup Operators, BUILTIN\Administrators'
            [GPOToolsSecuritySetting]::FormatAccount('*S-1-5-21-1-2-3-512') | Should -Be 'Domain Admins'
            [GPOToolsSecuritySetting]::FormatAccount('*S-1-5-21-1-2-3-1105') | Should -Be 'S-1-5-21-1-2-3-1105'
        }

        It 'Keeps the GptTmpl.inf of an offline directory in memory, its computer version increased' {
            $Directory = [GPOToolsDirectory]::new('offline.test')
            $Gpo = $Directory.NewGpo('Test')
            $Directory.ReadSecurityTemplate($Gpo) | Should -BeNullOrEmpty
            $Bytes = [System.IO.File]::ReadAllBytes($DefaultDomain)
            $Directory.WriteSecurityTemplate($Gpo, $Bytes)
            $Directory.ReadSecurityTemplate($Gpo) | Should -Be $Bytes
            $Gpo.GetComputerVersion() | Should -Be 1
            $Gpo.GetUserVersion() | Should -Be 0
        }
    }

    Describe 'Restricted groups ([Group Membership])' {
        It 'Reads the groups, their members and the groups they are a member of' {
            $Template = [GPOToolsSecurityTemplate]::new()
            $Template.SetValue('Group Membership', '*S-1-5-32-544__Memberof', '')
            $Template.SetValue('Group Membership', '*S-1-5-32-544__Members', '*S-1-5-21-1-2-3-512,CONTOSO\Helpdesk')
            $Template.SetValue('Group Membership', 'CONTOSO\Helpdesk__Memberof', '*S-1-5-32-555')
            $Groups = @(Get-PSGPORestrictedGroup -Template $Template)
            $Groups.Group | Should -Be @('*S-1-5-32-544', 'CONTOSO\Helpdesk')
            $Groups[0].Members | Should -Be @('*S-1-5-21-1-2-3-512', 'CONTOSO\Helpdesk')
            $Groups[0].MemberOf.Count | Should -Be 0
            $null -eq $Groups[1].Members | Should -BeTrue -Because 'no __Members key: its members do not change'
            $Groups[1].MemberOf | Should -Be @('*S-1-5-32-555')
        }

        It 'Writes a group as the Group Policy editor, an empty list of members kept, and removes it' {
            $Template = [GPOToolsSecurityTemplate]::new()
            Set-PSGPORestrictedGroup -Template $Template -Group '*S-1-5-32-544' -Members @('CONTOSO\Admins', ' CONTOSO\Admins ', '') -MemberOf @()
            $Template.GetValue('Group Membership', '*S-1-5-32-544__Members') | Should -Be 'CONTOSO\Admins'
            $Template.HasValue('Group Membership', '*S-1-5-32-544__Memberof') | Should -BeTrue
            Set-PSGPORestrictedGroup -Template $Template -Group 'CONTOSO\Kiosk' -Members @() -MemberOf $null
            $Template.HasValue('Group Membership', 'CONTOSO\Kiosk__Members') | Should -BeTrue -Because 'defined and empty: no member'
            $Template.GetValue('Group Membership', 'CONTOSO\Kiosk__Members') | Should -Be ''
            Set-PSGPORestrictedGroup -Template $Template -Group 'contoso\kiosk' -Members $null -MemberOf @('*S-1-5-32-545')
            @(Get-PSGPORestrictedGroup -Template $Template).Count | Should -Be 2 -Because 'the same group, another case of its name'
            $Template.HasValue('Group Membership', 'contoso\kiosk__Members') | Should -BeFalse
            Remove-PSGPORestrictedGroup -Template $Template -Group '*S-1-5-32-544'
            Remove-PSGPORestrictedGroup -Template $Template -Group 'CONTOSO\KIOSK'
            $Template.GetSectionNames() | Should -Not -Contain 'Group Membership'
            { Set-PSGPORestrictedGroup -Template $Template -Group ' ' -Members @() } | Should -Throw
        }

        It 'Lists them in the Settings tab, not as unknown keys' {
            $Template = [GPOToolsSecurityTemplate]::new()
            Set-PSGPORestrictedGroup -Template $Template -Group '*S-1-5-32-544' -Members @('CONTOSO\Admins') -MemberOf @()
            Set-PSGPORestrictedGroup -Template $Template -Group 'CONTOSO\Kiosk' -Members @() -MemberOf @('*S-1-5-32-545')
            $Rows = @(Get-PSGPOConfiguredSecuritySetting -Template $Template)
            $Rows.Count | Should -Be 2
            $Rows[0].Path | Should -Be 'Policies > Windows Settings > Security Settings > Restricted Groups'
            $Rows[0].Name | Should -Be 'BUILTIN\Administrators (*S-1-5-32-544)'
            $Rows[0].State | Should -Be 'Members: CONTOSO\Admins'
            $Rows[1].State | Should -Be 'Members: none (the computers remove every member)'
            $Rows[1].Options | Should -Be 'Member of: BUILTIN\Users (*S-1-5-32-545)'
        }
    }

    Describe 'Advanced audit policy (audit.csv)' {
        BeforeAll {
            $Credential = Get-PSGPOSecuritySetting | Where-Object Name -EQ 'Audit Credential Validation'
            $Logon = Get-PSGPOSecuritySetting | Where-Object Name -EQ 'Audit Logon'
        }

        It 'Has the subcategories of Windows under Advanced Audit Policy Configuration > Audit Policies' {
            $Audit = @(Get-PSGPOSecuritySetting | Where-Object Section -EQ 'AdvancedAudit')
            $Audit.Count | Should -Be 60
            @($Audit.Path | Where-Object { $_ -notin 'Advanced Audit Policy Configuration', 'Audit Policies' } | Sort-Object -Unique) | Should -Be @(
                'Account Logon', 'Account Management', 'Detailed Tracking', 'DS Access', 'Logon/Logoff', 'Object Access', 'Policy Change', 'Privilege Use', 'System')
            $Credential.Key | Should -Be '{0cce923f-69ae-11d9-bed3-505054503030}'
            $Credential.Path | Should -Be @('Advanced Audit Policy Configuration', 'Audit Policies', 'Account Logon')
            $Credential.Kind | Should -Be 'Audit'
        }

        It 'Writes audit.csv as the Group Policy editor, and reads it back' {
            $File = [GPOToolsAuditPolicyFile]::new()
            Set-PSGPOSecurityValue -Template $File -Setting $Credential -Value 3
            Set-PSGPOSecurityValue -Template $File -Setting $Logon -Value 0
            $Text = [System.Text.Encoding]::UTF8.GetString($File.ToBytes())
            $Text | Should -Be ("Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value`r`n" +
                ",System,Audit Credential Validation,{0cce923f-69ae-11d9-bed3-505054503030},Success and Failure,,3`r`n" +
                ",System,Audit Logon,{0cce9215-69ae-11d9-bed3-505054503030},No Auditing,,0`r`n")
            $Read = [GPOToolsAuditPolicyFile]::Parse($File.ToBytes())
            (Get-PSGPOSecurityValue -Template $Read -Setting $Credential).Value | Should -Be 3
            (Get-PSGPOSecurityValue -Template $Read -Setting $Logon).Defined | Should -BeTrue -Because 'No auditing is a setting'
            Set-PSGPOSecurityValue -Template $Read -Setting $Logon -Value $null
            $Read.HasValue('AdvancedAudit', $Logon.Key) | Should -BeFalse
            { Set-PSGPOSecurityValue -Template $Read -Setting $Logon -Value 4 } | Should -Throw
        }

        It 'Keeps the lines it does not know, and reads a file in UTF-16 or with upper-case GUIDs' {
            $Text = "Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value`r`n" +
                ",System,Audit Credential Validation,{0CCE923F-69AE-11D9-BED3-505054503030},Success,,1`r`n" +
                ",,Option:CrashOnAuditFail,,Enabled,,1`r`n"
            $Bytes = [byte[]](@(0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($Text))
            $File = [GPOToolsAuditPolicyFile]::Parse($Bytes)
            $File.GetValue('AdvancedAudit', $Credential.Key) | Should -Be '1'
            [System.Text.Encoding]::UTF8.GetString($File.ToBytes()) | Should -BeLike '*,,Option:CrashOnAuditFail,,Enabled,,1*'
        }

        It 'Lists the subcategories configured as the Settings tab of GPMC' {
            $File = [GPOToolsAuditPolicyFile]::new()
            Set-PSGPOSecurityValue -Template $File -Setting $Credential -Value 3
            $Row = @(Get-PSGPOConfiguredAuditSetting -AuditFile $File)
            $Row.Count | Should -Be 1
            $Row[0].Path | Should -Be 'Policies > Windows Settings > Security Settings > Advanced Audit Policy Configuration > Audit Policies > Account Logon'
            $Row[0].Name | Should -Be 'Audit Credential Validation'
            $Row[0].State | Should -Be 'Success and Failure'
        }

        It 'Saves audit.csv in the GPO with the extension of the advanced audit policy' {
            $Directory = Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json')
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Version = $Gpo.GetComputerVersion()
            $File = [GPOToolsAuditPolicyFile]::new()
            Set-PSGPOSecurityValue -Template $File -Setting $Credential -Value 2
            $Directory.WriteAuditPolicyFile($Gpo, $File.ToBytes())
            [GPOToolsAuditPolicyFile]::Parse($Directory.ReadAuditPolicyFile($Gpo)).GetValue('AdvancedAudit', $Credential.Key) | Should -Be '2'
            $Gpo.GetComputerVersion() | Should -Be ($Version + 1)
            $Gpo.MachineExtensionNames | Should -Match ([regex]::Escape('{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}'))
            # A backup reports it, as the History tab compares it.
            $Report = @(Get-PSGPOSettingReport -Files $Directory.ReadGpoFolder($Gpo) -Property @{ DisplayName = $Gpo.DisplayName })
            ($Report | Where-Object Name -EQ 'Audit Credential Validation').State | Should -Be 'Failure'
        }
    }
}
