#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Registry.pol: the file format (GPOToolsRegistryPol), and the setting of a policy read from and
# written to its entries (Get-PSGPOPolicyState / Set-PSGPOPolicyState).
# Every policy of the ADMX set is checked with PSGPOTOOLS_TEST_ALL_POLICIES=1, one in eight otherwise.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path
        Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null

        function Get-TestPolicy {
            param([string]$Id, [string]$File)
            [GPOToolsUtility]::Policies | Where-Object { $_.ID -eq $Id -and (-not $File -or $_.FileName -eq $File) } | Select-Object -First 1
        }
        function Get-Line {
            param([GPOToolsRegistryPol]$Pol)
            @($Pol.Entries | ForEach-Object { "$_" })
        }
        # Bytes of a Registry.pol written by hand: header, then each entry.
        function New-PolBytes {
            param([object[]]$Entry)
            $Bytes = [System.Collections.Generic.List[byte]]::new()
            $Bytes.AddRange([byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0))
            $U = [System.Text.Encoding]::Unicode
            foreach ($E in $Entry) {
                $Bytes.AddRange($U.GetBytes("[$($E.Key)`0;$($E.Name)`0;"))
                $Bytes.AddRange([BitConverter]::GetBytes([uint32]$E.Type))
                $Bytes.AddRange($U.GetBytes(';'))
                $Bytes.AddRange([BitConverter]::GetBytes([uint32]$E.Data.Length))
                $Bytes.AddRange($U.GetBytes(';'))
                $Bytes.AddRange([byte[]]$E.Data)
                $Bytes.AddRange($U.GetBytes(']'))
            }
            , $Bytes.ToArray()
        }
    }

    Describe 'Registry.pol format' {
        It 'Reads an empty file and a file with the header only' {
            [GPOToolsRegistryPol]::Parse([byte[]]@()).Entries.Count | Should -Be 0
            [GPOToolsRegistryPol]::Parse($null).Entries.Count | Should -Be 0
            [GPOToolsRegistryPol]::Parse((New-PolBytes @())).Entries.Count | Should -Be 0
            [GPOToolsRegistryPol]::new().ToBytes() | Should -Be ([byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0))
        }

        It 'Reads every kind of value' {
            $U = [System.Text.Encoding]::Unicode
            $Bytes = New-PolBytes @(
                @{ Key = 'Software\Policies\A'; Name = 'Text'; Type = 1; Data = $U.GetBytes("hello`0") }
                @{ Key = 'Software\Policies\A'; Name = 'Path'; Type = 2; Data = $U.GetBytes("%windir%\x`0") }
                @{ Key = 'Software\Policies\A'; Name = 'Number'; Type = 4; Data = [BitConverter]::GetBytes([uint32]42) }
                @{ Key = 'Software\Policies\A'; Name = 'Big'; Type = 11; Data = [BitConverter]::GetBytes([uint64]5000000000) }
                @{ Key = 'Software\Policies\A'; Name = 'Lines'; Type = 7; Data = $U.GetBytes("one`0two`0`0") }
                @{ Key = 'Software\Policies\A'; Name = 'Raw'; Type = 3; Data = [byte[]](1, 2, 3) }
                @{ Key = 'Software\Policies\A'; Name = '**del.Old'; Type = 1; Data = $U.GetBytes(" `0") }
                @{ Key = 'Software\Policies\B'; Name = '**delvals.'; Type = 1; Data = $U.GetBytes(" `0") }
                @{ Key = 'Software\Policies\C'; Name = ''; Type = 0; Data = [byte[]]@() }
            )
            $Pol = [GPOToolsRegistryPol]::Parse($Bytes)
            $Pol.Entries.Count | Should -Be 9
            $Pol.Entries[0].GetValue() | Should -Be 'hello'
            $Pol.Entries[1].Type | Should -Be ([GPOToolsPolType]::ExpandString)
            $Pol.Entries[2].GetValue() | Should -Be 42
            $Pol.Entries[3].GetValue() | Should -Be 5000000000
            $Pol.Entries[4].GetValue() | Should -Be @('one', 'two')
            $Pol.Entries[5].GetValue() | Should -Be ([byte[]](1, 2, 3))
            $Pol.Entries[6].IsDelete() | Should -BeTrue
            $Pol.Entries[6].GetTargetValueName() | Should -Be 'Old'
            $Pol.Entries[7].IsDeleteAllValues() | Should -BeTrue
            $Pol.Entries[8].Key | Should -Be 'Software\Policies\C'

            # Written back byte for byte.
            [Linq.Enumerable]::SequenceEqual([byte[]]$Pol.ToBytes(), [byte[]]$Bytes) | Should -BeTrue
        }

        It 'Rewrites the local policy of Windows byte for byte' -Skip:(-not ($IsWindows -and (Test-Path 'C:\Windows\System32\GroupPolicy\Machine\Registry.pol'))) {
            $Bytes = [System.IO.File]::ReadAllBytes('C:\Windows\System32\GroupPolicy\Machine\Registry.pol')
            [Linq.Enumerable]::SequenceEqual([byte[]][GPOToolsRegistryPol]::Parse($Bytes).ToBytes(), $Bytes) | Should -BeTrue
        }

        It 'Refuses <Case>' -ForEach @(
            @{ Case = 'a file that is not a Registry.pol'; Bytes = [byte[]](1, 2, 3, 4, 5, 6, 7, 8); Message = '*PReg signature*' }
            @{ Case = 'another version'; Bytes = [byte[]](0x50, 0x52, 0x65, 0x67, 2, 0, 0, 0); Message = '*version 2*' }
            @{ Case = 'a missing bracket'; Bytes = [byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0, 0x41, 0); Message = "*'``[' expected*" }
        ) {
            { [GPOToolsRegistryPol]::Parse($Bytes) } | Should -Throw -ExpectedMessage $Message
        }

        It 'Refuses a truncated entry' {
            $Bytes = New-PolBytes @(@{ Key = 'K'; Name = 'V'; Type = 4; Data = [BitConverter]::GetBytes([uint32]1) })
            { [GPOToolsRegistryPol]::Parse($Bytes[0..($Bytes.Length - 5)]) } | Should -Throw -ExpectedMessage '*truncated*'
        }

        It 'Writes the registry values of a setting as the Group Policy editor does' {
            $Pol = [GPOToolsRegistryPol]::new()
            foreach ($Value in @(
                    [GPOToolsRegistryValue]::new('K', 'S', 'String', 'text')
                    [GPOToolsRegistryValue]::new('K', 'E', 'ExpandString', '%windir%')
                    [GPOToolsRegistryValue]::new('K', 'M', 'MultiString', [string[]]@('a', 'b'))
                    [GPOToolsRegistryValue]::new('K', 'D', 'DWord', [uint32]7)
                    [GPOToolsRegistryValue]::new('K', 'Q', 'QWord', [uint64]8)
                    [GPOToolsRegistryValue]::new('K', 'Old', 'Delete', $null)
                    [GPOToolsRegistryValue]::new('L', '', 'DeleteAllValues', $null))) {
                $Pol.Entries.Add([GPOToolsPolEntry]::FromRegistryValue($Value))
            }
            Get-Line $Pol | Should -Be @('[K;S;String;text]', '[K;E;ExpandString;%windir%]', '[K;M;MultiString;a|b]', '[K;D;DWord;7]', '[K;Q;QWord;8]', '[K;**del.Old;String; ]', '[L;**delvals.;String; ]')
            # REG_MULTI_SZ ends with two null characters; a deletion holds a space and its null.
            $Pol.Entries[2].Data.Length | Should -Be 10
            $Pol.Entries[5].Data | Should -Be ([byte[]](0x20, 0, 0, 0))
        }

        It 'Finds a value and its deletion whatever the case of the key' {
            $Pol = [GPOToolsRegistryPol]::new()
            $Pol.Entries.Add([GPOToolsPolEntry]::FromRegistryValue([GPOToolsRegistryValue]::new('Software\Policies\X', 'Old', 'Delete', $null)))
            $Pol.FindValue('SOFTWARE\POLICIES\X', 'old').IsDelete() | Should -BeTrue
            $Pol.FindValue('Software\Policies\X', 'Other') | Should -BeNullOrEmpty
        }
    }

    Describe 'Setting of a policy in Registry.pol' {
        It 'Reads and writes the options of AxISURLZonePolicies' {
            $Policy = Get-TestPolicy 'AxISURLZonePolicies'
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled -Value @{ InstallTrustedOCX = 0; IgnoreUnknownCA = $true }
            $Read = Get-PSGPOPolicyState -Policy $Policy -Pol ([GPOToolsRegistryPol]::Parse($Pol.ToBytes()))
            $Read.State | Should -Be 'Enabled'
            $Read.Value['InstallTrustedOCX'] | Should -Be 0
            $Read.Value['IgnoreUnknownCA'] | Should -BeTrue
            $Read.Value['IgnoreInvalidCN'] | Should -BeFalse

            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Disabled
            (Get-PSGPOPolicyState -Policy $Policy -Pol $Pol).State | Should -Be 'Disabled'
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State NotConfigured
            $Pol.Entries.Count | Should -Be 0
            (Get-PSGPOPolicyState -Policy $Policy -Pol $Pol).State | Should -Be 'NotConfigured'
        }

        It 'Reads the entries of a list in the order of their number' {
            $Policy = Get-TestPolicy 'DisallowCpls'
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled -Value @{ DisallowCplsList = [string[]]@('Microsoft.Mouse', 'Microsoft.Sound') }
            Get-Line $Pol | Should -Be @(
                '[Software\Microsoft\Windows\CurrentVersion\Policies\Explorer;DisallowCpl;DWord;1]'
                '[Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl;**delvals.;String; ]'
                '[Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl;1;String;Microsoft.Mouse]'
                '[Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl;2;String;Microsoft.Sound]')
            # Written by another tool in another order.
            $Pol.Entries.Reverse()
            (Get-PSGPOPolicyState -Policy $Policy -Pol $Pol).Value['DisallowCplsList'] | Should -Be @('Microsoft.Mouse', 'Microsoft.Sound')
        }

        It 'Replaces only the entries of the policy' {
            $Pol = [GPOToolsRegistryPol]::new()
            $Other = [GPOToolsPolEntry]::FromRegistryValue([GPOToolsRegistryValue]::new('Software\Policies\Other', 'Kept', 'DWord', [uint32]1))
            $Pol.Entries.Add($Other)
            $Policy = Get-TestPolicy 'Biometrics_EnableBio'
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Disabled
            Get-Line $Pol | Should -Be @('[Software\Policies\Other;Kept;DWord;1]', '[SOFTWARE\Policies\Microsoft\Biometrics;Enabled;DWord;0]')
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State NotConfigured
            $Pol.Entries | Should -Be @($Other)
        }

        It 'Checks the setting before changing anything' {
            $Policy = [GPOToolsUtility]::Policies | Where-Object { $_.Elements.Count -eq 1 -and $_.Elements[0].Type -eq 'Text' -and $_.Elements[0].Required -and -not $_.Elements[0].DefaultValue } | Select-Object -First 1
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Disabled
            $Before = Get-Line $Pol
            { Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled -Value @{} } | Should -Throw -ExpectedMessage '*is required.'
            Get-Line $Pol | Should -Be $Before
        }

        It 'Writes a value once when an element writes the value of the policy itself' {
            # valueName on the policy without enabledValue, and an enum on the same value.
            $Policy = Get-TestPolicy 'ExploitGuard_ControlledFolderAccess_EnableControlledFolderAccess'
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled -Value @{ ExploitGuard_ControlledFolderAccess_EnableControlledFolderAccess = 0 }
            Get-Line $Pol | Should -Be '[Software\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access;EnableControlledFolderAccess;DWord;0]'
            (Get-PSGPOPolicyState -Policy $Policy -Pol $Pol).State | Should -Be 'Enabled'
        }

        It 'Tells DWORD 0 from the string "0" (Windows Firewall logging)' {
            $Policy = Get-TestPolicy 'WF_Logging_Name_2'
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled
            (Get-PSGPOPolicyState -Policy $Policy -Pol $Pol).State | Should -Be 'Enabled'
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Disabled
            (Get-PSGPOPolicyState -Policy $Policy -Pol $Pol).State | Should -Be 'Disabled'
        }

        It 'Reads a disabled policy whose ADMX declares a value twice (fthsvc)' {
            $Policy = Get-TestPolicy 'WdiScenarioExecutionPolicy' 'fthsvc.admx'
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Disabled
            (Get-PSGPOPolicyState -Policy $Policy -Pol $Pol).State | Should -Be 'Disabled'
        }

        It 'Writes the default value of a key (empty value name), and clears it' {
            $Policy = Get-TestPolicy 'CSE_LocalUsersAndGroups'
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled
            (Get-Line $Pol)[0] | Should -Be '[Software\Policies\Microsoft\Windows\Group Policy\{17D89FEC-5C44-4972-B12D-241CAEF74509};;String;Local Users and Groups Policy Processing]'
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State NotConfigured
            $Pol.Entries.Count | Should -Be 0
        }
    }

    Describe 'Version of a GPO' {
        It 'Increases the computer version in the low word, the user version in the high word' {
            [GPOToolsDirectory]::GetNextVersion(0, 'Machine') | Should -Be 1
            [GPOToolsDirectory]::GetNextVersion(0, 'User') | Should -Be 65536
            [GPOToolsDirectory]::GetNextVersion(0x00030005, 'Machine') | Should -Be 0x00030006
            [GPOToolsDirectory]::GetNextVersion(0x00030005, 'User') | Should -Be 0x00040005
            # Each half wraps on its own.
            [GPOToolsDirectory]::GetNextVersion(0x0001FFFF, 'Machine') | Should -Be 0x00010000
        }

        It 'Sets Version= in GPT.INI, keeping its other lines and its encoding' {
            $Ascii = [System.Text.Encoding]::ASCII.GetBytes("[General]`r`nVersion=0`r`ndisplayName=New Group Policy Object`r`n")
            [System.Text.Encoding]::ASCII.GetString((Set-PSGPOGptIniVersion -Bytes $Ascii -Version 65537)) |
                Should -Be "[General]`r`nVersion=65537`r`ndisplayName=New Group Policy Object`r`n"

            $Unicode = [byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes("[General]`r`nVersion=3`r`n")
            $Result = Set-PSGPOGptIniVersion -Bytes $Unicode -Version 4
            $Result[0..1] | Should -Be @(0xFF, 0xFE)
            [System.Text.Encoding]::Unicode.GetString($Result, 2, $Result.Length - 2) | Should -Be "[General]`r`nVersion=4`r`n"

            [System.Text.Encoding]::ASCII.GetString((Set-PSGPOGptIniVersion -Bytes $null -Version 1)) | Should -Be "[General]`r`nVersion=1`r`n"
            [System.Text.Encoding]::ASCII.GetString((Set-PSGPOGptIniVersion -Bytes ([System.Text.Encoding]::ASCII.GetBytes("[General]`r`n")) -Version 2)) | Should -Be "[General]`r`nVersion=2`r`n"
        }

        It 'Declares the Registry extension and its tool once, sorted by GUID' {
            $Registry = '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'
            $Machine = '{D02B1F72-3407-48AE-BA88-E8213C6761F1}'
            Add-PSGPOExtensionName -Current $null -Extension $Registry -Tool $Machine | Should -Be "[$Registry$Machine]"
            $Security = '[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]'
            Add-PSGPOExtensionName -Current $Security -Extension $Registry -Tool $Machine | Should -Be "[$Registry$Machine]$Security"
            # Already declared, in lower case: unchanged but normalized.
            Add-PSGPOExtensionName -Current "[$($Registry.ToLower())$Machine]" -Extension $Registry -Tool $Machine | Should -Be "[$Registry$Machine]"
        }

        It 'Finds the GPO folder from its SYSVOL path' {
            $Directory = [GPOToolsDirectory]::new('hardenbox.labo')
            $Gpo = [GPOToolsGpo]@{ Id = [guid]'31B2F340-016D-11D2-945F-00C04FB984F9'; FileSysPath = '\\hardenbox.labo\sysvol\hardenbox.labo\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}' }
            $Location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
            $Location.Share | Should -Be 'sysvol'
            $Location.Path | Should -Be 'hardenbox.labo\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}'
            $Gpo.FileSysPath = $null
            (Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo).Path | Should -Be 'hardenbox.labo\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}'
        }

        It 'Keeps the Registry.pol of an offline directory in memory, its version increased' {
            $Directory = [GPOToolsDirectory]::new('offline.test')
            $Gpo = $Directory.NewGpo('Test')
            $Directory.ReadPolicyFile($Gpo, 'Machine') | Should -BeNullOrEmpty
            $Bytes = [GPOToolsRegistryPol]::new().ToBytes()
            $Directory.WritePolicyFile($Gpo, 'Machine', $Bytes)
            $Directory.WritePolicyFile($Gpo, 'User', $Bytes)
            $Directory.ReadPolicyFile($Gpo, 'Machine') | Should -Be $Bytes
            $Gpo.GetComputerVersion() | Should -Be 1
            $Gpo.GetUserVersion() | Should -Be 1
            { $Directory.ReadPolicyFile($Gpo, 'Both') } | Should -Throw -ExpectedMessage '*Unknown policy scope*'
        }
    }

    Describe 'Settings report of a GPO' {
        It 'Lists the configured policies with their category path, state and options' {
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy (Get-TestPolicy 'AxISURLZonePolicies') -Pol $Pol -State Enabled -Value @{ InstallTrustedOCX = 0; IgnoreUnknownCA = $true }
            Set-PSGPOPolicyState -Policy (Get-TestPolicy 'Biometrics_EnableBio') -Pol $Pol -State Disabled
            $Rows = @(Get-PSGPOConfiguredSetting -Pol $Pol -Scope Machine)
            $Rows.Count | Should -Be 2
            $Rows[0].Path | Should -Be 'Policies > Administrative Templates > Windows Components > ActiveX Installer Service'
            $Rows[0].Name | Should -Be 'Establish ActiveX installation policy for sites in Trusted zones'
            $Rows[0].State | Should -Be 'Enabled'
            $Options = $Rows[0].Options -split '\r?\n'
            $Options | Should -Contain "Installation Policy for ActiveX control signed by trusted publisher: Don't install"
            $Options | Should -Contain 'Unknown certifcation authority (CA): Enabled'
            $Options | Should -Contain 'Invalid certificate name (CN): Disabled'
            $Rows[1].Path | Should -Be 'Policies > Administrative Templates > Windows Components > Biometrics'
            $Rows[1].State | Should -Be 'Disabled'
            $Rows[1].Options | Should -BeNullOrEmpty
        }

        It 'Shows the entries of a list' {
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy (Get-TestPolicy 'DisallowCpls') -Pol $Pol -State Enabled -Value @{ DisallowCplsList = [string[]]@('Microsoft.Mouse', 'Microsoft.Sound') }
            $Row = Get-PSGPOConfiguredSetting -Pol $Pol -Scope User
            $Row.Options | Should -BeLike '*: Microsoft.Mouse; Microsoft.Sound'
        }

        It 'Lists the values no policy explains as Extra Registry Settings, with the hive of the scope' {
            $Pol = [GPOToolsRegistryPol]::new()
            foreach ($Value in @(
                    [GPOToolsRegistryValue]::new('Software\Contoso\App', 'Mode', 'DWord', [uint32]3)
                    [GPOToolsRegistryValue]::new('Software\Contoso\App', 'Old', 'Delete', $null)
                    [GPOToolsRegistryValue]::new('Software\Contoso\App', '', 'String', 'default'))) {
                $Pol.Entries.Add([GPOToolsPolEntry]::FromRegistryValue($Value))
            }
            $Rows = @(Get-PSGPOConfiguredSetting -Pol $Pol -Scope User)
            @($Rows.Path | Select-Object -Unique) | Should -Be 'Extra Registry Settings'
            @($Rows.Name | Select-Object -Unique) | Should -Be 'HKCU\Software\Contoso\App'
            @($Rows.Options) | Should -Be @('Mode = 3', 'Old', '(Default) = default')
            @($Rows.State) | Should -Be @('DWord', 'Delete value', 'String')
            $Rows | ForEach-Object { $_.IsExtra | Should -BeTrue }
        }

        It 'Lists nothing for an empty Registry.pol' {
            @(Get-PSGPOConfiguredSetting -Pol ([GPOToolsRegistryPol]::new()) -Scope Machine).Count | Should -Be 0
        }
    }

    Describe 'Every policy of the ADMX set' {
        It 'Reads back what it writes, enabled and disabled, then clears it' {
            $All = $env:PSGPOTOOLS_TEST_ALL_POLICIES -eq '1'
            $Failures = [System.Collections.Generic.List[string]]::new()
            $Checked = 0
            $Index = 0
            foreach ($Policy in [GPOToolsUtility]::Policies) {
                $Index++
                if (-not $All -and $Index % 8) { continue }
                foreach ($State in 'Enabled', 'Disabled') {
                    $Pol = [GPOToolsRegistryPol]::new()
                    # Policies with a required value have no default setting to write.
                    try { Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State $State } catch { continue }
                    if (-not $Pol.Entries.Count) { continue }
                    $Lines = (Get-Line $Pol) -join '|'
                    if ($State -eq 'Enabled') {
                        # Enabled without value and disabled can write the same file: nothing tells them apart.
                        $Off = [GPOToolsRegistryPol]::new()
                        try { Set-PSGPOPolicyState -Policy $Policy -Pol $Off -State Disabled } catch { }
                        if (((Get-Line $Off) -join '|') -eq $Lines) { continue }
                    }
                    $Checked++
                    $Read = Get-PSGPOPolicyState -Policy $Policy -Pol ([GPOToolsRegistryPol]::Parse($Pol.ToBytes()))
                    $Name = "$($Policy.ID) ($($Policy.Scope), $($Policy.FileName)) $State"
                    if ($Read.State -ne $State) { $Failures.Add("$Name read $($Read.State)"); continue }
                    if ($State -eq 'Enabled') {
                        $Again = [GPOToolsRegistryPol]::new()
                        try { Set-PSGPOPolicyState -Policy $Policy -Pol $Again -State Enabled -Value $Read.Value } catch { $Failures.Add("$Name rewrite: $($_.Exception.Message)"); continue }
                        if (((Get-Line $Again) -join '|') -ne $Lines) { $Failures.Add("$Name values read differ") }
                    }
                    Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State NotConfigured
                    if ($Pol.Entries.Count) { $Failures.Add("$Name not cleared") }
                }
            }
            $Checked | Should -BeGreaterThan $(if ($All) { 4000 } else { 500 })
            $Failures | Should -BeNullOrEmpty
        }
    }
}
