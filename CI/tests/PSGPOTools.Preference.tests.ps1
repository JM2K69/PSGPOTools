#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Group Policy Preferences ([MS-GPPREF]): the catalog of the preference types, the XML files and
# their items as GPMC writes them, and the preferences in the settings report of a GPO.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Samples' 'Directory.sample.json'
        $Registry = Get-PSGPOPreferenceExtension -Id Registry
        $RegistryItem = $Registry.Items | Where-Object Element -EQ 'Registry'
        $Groups = Get-PSGPOPreferenceExtension -Id Groups
        # A file written by GPMC: a collection, item-level targeting, an attribute of another version.
        $GpmcRegistry = @'
<?xml version="1.0" encoding="utf-8"?>
<RegistrySettings clsid="{A3CCFC41-DFDB-43a5-8D26-0FE8B954DA51}"><Registry clsid="{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}" name="Mode" status="Mode" image="7" changed="2020-04-20 14:12:33" uid="{D5F1A6A4-2A9C-4D3F-9C3C-6A1E2B3C4D5E}" bypassErrors="1"><Properties action="U" displayDecimal="1" default="0" hive="HKEY_LOCAL_MACHINE" key="SOFTWARE\Contoso" name="Mode" type="REG_DWORD" value="00000001" futureAttribute="kept"/><Filters><FilterGroup bool="AND" not="0" name="CONTOSO\Servers" sid="S-1-5-21-1-2-3-1104" userContext="0" primaryGroup="0" localGroup="0"/></Filters></Registry><Collection clsid="{53B533F5-224C-47e3-B01B-CA3B3F3FF4BF}" name="Proxy"><Registry clsid="{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}" name="ProxyServer" status="ProxyServer" image="7" changed="2020-04-20 14:12:33" uid="{0A1B2C3D-4E5F-4061-8273-9485A6B7C8D9}"><Properties action="U" hive="HKEY_CURRENT_USER" key="Software\Proxy" name="ProxyServer" type="REG_SZ" value="proxy:8080"/></Registry></Collection>
</RegistrySettings>
'@
    }

    Describe 'Catalog of the preference types' {
        It 'Has the 21 preference types of [MS-GPPREF] with their client-side extension and tool' {
            $Catalog = @(Get-PSGPOPreferenceCatalog)
            $Catalog.Count | Should -Be 21
            # [MS-GPPREF] 1.9 Standards Assignments
            (Get-PSGPOPreferenceExtension -Id Registry).Cse | Should -Be '{B087BE9D-ED37-454f-AF9C-04291E351182}'
            (Get-PSGPOPreferenceExtension -Id Registry).Tool | Should -Be '{BEE07A6A-EC9F-4659-B8C9-0B1937907C83}'
            (Get-PSGPOPreferenceExtension -Id Drives).Cse | Should -Be '{5794DAFD-BE60-433f-88A2-1A31939AC01F}'
            (Get-PSGPOPreferenceExtension -Id Groups).Tool | Should -Be '{79F92669-4224-476c-9C5C-6EFB4D87DF4A}'
            (Get-PSGPOPreferenceExtension -Id NetworkShares).Tool | Should -Be '{BFCBBEB0-9DF4-4c0c-A728-434EA66A0373}'
            foreach ($Extension in $Catalog) {
                $Extension.Cse | Should -Match '^\{[0-9A-Fa-f-]{36}\}$'
                $Extension.Tool | Should -Match '^\{[0-9A-Fa-f-]{36}\}$'
                $Extension.RootClsid | Should -Match '^\{[0-9A-Fa-f-]{36}\}$'
                $Extension.Path | Should -Match '^\w+\\\w+\.xml$'
                foreach ($Type in $Extension.Items) {
                    $Type.Clsid | Should -Match '^\{[0-9A-Fa-f-]{36}\}$'
                    @($Type.Properties.Name | Group-Object | Where-Object Count -GT 1) | Should -BeNullOrEmpty -Because "$($Type.Element) defines each attribute once"
                }
            }
            @($Catalog.Cse | Select-Object -Unique).Count | Should -Be 21
        }

        It 'Gives each scope its preference types, as the Group Policy editor' {
            @(Get-PSGPOPreferenceExtension -Scope Machine).Name | Should -Not -Contain 'Drive Maps'
            @(Get-PSGPOPreferenceExtension -Scope Machine).Name | Should -Contain 'Services'
            @(Get-PSGPOPreferenceExtension -Scope Machine).Name | Should -Contain 'Network Shares'
            @(Get-PSGPOPreferenceExtension -Scope User).Name | Should -Contain 'Drive Maps'
            @(Get-PSGPOPreferenceExtension -Scope User).Name | Should -Not -Contain 'Services'
            @(Get-PSGPOPreferenceExtension -Scope Machine).Count | Should -Be 16
            @(Get-PSGPOPreferenceExtension -Scope User).Count | Should -Be 19
        }
    }

    Describe 'Preference files' {
        It 'Reads the items of a GPMC file, those of collections included, and keeps what it does not edit' {
            $File = [GPOToolsPreferenceFile]::Parse([System.Text.Encoding]::UTF8.GetBytes($GpmcRegistry))
            $Items = @(Get-PSGPOPreferenceItem -File $File -Extension $Registry)
            @($Items.Name) | Should -Be @('Mode', 'ProxyServer')
            $Items[0].FilterCount | Should -Be 1
            $Items[0].BypassErrors | Should -BeTrue
            $Items[0].Properties['futureAttribute'] | Should -Be 'kept'
            $Items[1].Collection | Should -Be 'Proxy'

            # A change keeps the targeting and the attributes it does not know.
            Set-PSGPOPreferenceElement -Element $Items[0].Element -Type $RegistryItem -Values @{ value = '00000002' }
            $Again = [GPOToolsPreferenceFile]::Parse($File.ToBytes())
            $Item = @(Get-PSGPOPreferenceItem -File $Again -Extension $Registry)[0]
            $Item.Properties['value'] | Should -Be '00000002'
            $Item.Properties['futureAttribute'] | Should -Be 'kept'
            $Item.FilterCount | Should -Be 1
            $Again.Document.SelectSingleNode('//FilterGroup').GetAttribute('name') | Should -Be 'CONTOSO\Servers'
            $Item.Changed | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }

        It 'Writes UTF-8 with the XML declaration, keeping a byte order mark when the file had one' {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($GpmcRegistry)
            [GPOToolsPreferenceFile]::Parse($Bytes).ToBytes()[0..4] | Should -Be ([byte[]][char[]]'<?xml')
            $WithBom = [byte[]](0xEF, 0xBB, 0xBF) + $Bytes
            [GPOToolsPreferenceFile]::Parse($WithBom).ToBytes()[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        }

        It 'Creates an item as GPMC does: clsid, uid, name and status, icon of the action, date of the change' {
            $File = [GPOToolsPreferenceFile]::Create($Registry.Root, $Registry.RootClsid)
            $Element = New-PSGPOPreferenceItem -File $File -Type $RegistryItem -Values @{ action = 'C'; key = 'SOFTWARE\Contoso'; name = 'Mode'; type = 'REG_DWORD'; value = '00000001' } -Common @{ desc = 'Mode of the agent'; bypassErrors = '1'; removePolicy = '0' }
            $Element.GetAttribute('clsid') | Should -Be '{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}'
            $Element.GetAttribute('uid') | Should -Match '^\{[0-9A-F-]{36}\}$'
            $Element.GetAttribute('name') | Should -Be 'Mode'
            $Element.GetAttribute('status') | Should -Be 'Mode'
            $Element.GetAttribute('image') | Should -Be '0'
            $Element.GetAttribute('desc') | Should -Be 'Mode of the agent'
            $Element.HasAttribute('removePolicy') | Should -BeFalse
            $Properties = $Element.SelectSingleNode('Properties')
            $Properties.GetAttribute('hive') | Should -Be 'HKEY_LOCAL_MACHINE' -Because 'the default of the type'
            $Properties.GetAttribute('displayDecimal') | Should -Be '0'
            $File.GetRoot().GetAttribute('clsid') | Should -Be '{A3CCFC41-DFDB-43a5-8D26-0FE8B954DA51}'

            # A key without value: named after the key.
            (New-PSGPOPreferenceItem -File $File -Type $RegistryItem -Values @{ key = 'SOFTWARE\Contoso\Agent'; name = ''; type = '' }).GetAttribute('name') | Should -Be 'Agent'
        }

        It 'Names a drive map by its letter and a file by the file it writes' {
            $Drive = (Get-PSGPOPreferenceExtension -Id Drives).Items[0]
            $File = [GPOToolsPreferenceFile]::Create('Drives', '{8FDDCC1A-0C3C-43cd-A6B4-71A6DF20DA8C}')
            (New-PSGPOPreferenceItem -File $File -Type $Drive -Values @{ path = '\\srv\home'; letter = 'P' }).GetAttribute('name') | Should -Be 'P:'
            Format-PSGPOPreferenceName -Format '{targetPath|leaf}' -Values @{ targetPath = 'C:\Tools\agent.ini' } | Should -Be 'agent.ini'
            Format-PSGPOPreferenceName -Format '{localName|ipAddress}' -Values @{ localName = ''; ipAddress = '10.0.0.9' } | Should -Be '10.0.0.9'
        }

        It 'Writes the members of a local group' {
            $Group = $Groups.Items | Where-Object Element -EQ 'Group'
            $File = [GPOToolsPreferenceFile]::Create($Groups.Root, $Groups.RootClsid)
            $Members = @([pscustomobject]@{ Action = 'ADD'; Name = 'CONTOSO\GPO-Tier1-Admins'; Sid = 'S-1-5-21-1-2-3-1123' }, [pscustomobject]@{ Action = 'remove'; Name = 'CONTOSO\Old'; Sid = '' })
            $Element = New-PSGPOPreferenceItem -File $File -Type $Group -Values @{ groupName = 'Administrators (built-in)'; groupSid = 'S-1-5-32-544'; Members = $Members }
            $Nodes = @($Element.SelectNodes('Properties/Members/Member'))
            $Nodes.Count | Should -Be 2
            "$($Nodes[0].GetAttribute('action')) $($Nodes[0].GetAttribute('name')) $($Nodes[0].GetAttribute('sid'))" | Should -Be 'ADD CONTOSO\GPO-Tier1-Admins S-1-5-21-1-2-3-1123'
            $Nodes[1].GetAttribute('action') | Should -Be 'REMOVE'
            $Item = @(Get-PSGPOPreferenceItem -File $File -Extension $Groups)[0]
            Get-PSGPOPreferenceSummary -Item $Item | Should -BeLike 'Update - Group name: Administrators (built-in)*2 member(s): ADD CONTOSO\GPO-Tier1-Admins, REMOVE CONTOSO\Old'
        }

        It 'Never writes a password, and keeps the one an item already stores' {
            $User = $Groups.Items | Where-Object Element -EQ 'User'
            $File = [GPOToolsPreferenceFile]::Create($Groups.Root, $Groups.RootClsid)
            { New-PSGPOPreferenceItem -File $File -Type $User -Values @{ userName = 'svc'; cpassword = 'P@ss' } } | Should -Throw -ExpectedMessage '*MS14-025*'
            $Element = New-PSGPOPreferenceItem -File $File -Type $User -Values @{ userName = 'svc' }
            $Element.SelectSingleNode('Properties').HasAttribute('cpassword') | Should -BeFalse
            # A password written by an old GPMC: reported, kept, never overwritten.
            $Element.SelectSingleNode('Properties').SetAttribute('cpassword', 'j1Uyj3Vx8TY9LtLZil2uAuZkFQA/4latT76ZwgdHdhw')
            $Item = @(Get-PSGPOPreferenceItem -File $File -Extension $Groups)[0]
            $Item.HasPassword | Should -BeTrue
            Set-PSGPOPreferenceElement -Element $Element -Type $User -Values @{ fullName = 'Service' }
            $Element.SelectSingleNode('Properties').GetAttribute('cpassword') | Should -Be 'j1Uyj3Vx8TY9LtLZil2uAuZkFQA/4latT76ZwgdHdhw'
            { Set-PSGPOPreferenceElement -Element $Element -Type $User -Values @{ cpassword = 'new' } } | Should -Throw -ExpectedMessage '*MS14-025*'
        }

        It 'Checks the values of an item against its type' {
            $File = [GPOToolsPreferenceFile]::Create($Registry.Root, $Registry.RootClsid)
            { New-PSGPOPreferenceItem -File $File -Type $RegistryItem -Values @{ key = '' } } | Should -Throw -ExpectedMessage '*Key path is required*'
            { New-PSGPOPreferenceItem -File $File -Type $RegistryItem -Values @{ key = 'K'; hive = 'HKEY_NOWHERE' } } | Should -Throw -ExpectedMessage "*'HKEY_NOWHERE' is not one of*"
            { New-PSGPOPreferenceItem -File $File -Type $RegistryItem -Values @{ key = 'K'; action = 'X' } } | Should -Throw -ExpectedMessage '*C, R, U or D*'
            $Service = (Get-PSGPOPreferenceExtension -Id Services).Items[0]
            { New-PSGPOPreferenceItem -File $File -Type $Service -Values @{ serviceName = 'Spooler'; timeout = 'soon' } } | Should -Throw -ExpectedMessage '*must be a number*'
            $Task = (Get-PSGPOPreferenceExtension -Id ScheduledTasks).Items[0]
            { New-PSGPOPreferenceItem -File $File -Type $Task -Values @{} } | Should -Throw -ExpectedMessage '*created with GPMC*'
            @(Get-PSGPOPreferenceItem -File $File -Extension $Registry).Count | Should -Be 0 -Because 'nothing was added'
        }

        It 'Moves and deletes items: they apply in their order' {
            $File = [GPOToolsPreferenceFile]::Create($Registry.Root, $Registry.RootClsid)
            foreach ($Name in 'A', 'B', 'C') { $null = New-PSGPOPreferenceItem -File $File -Type $RegistryItem -Values @{ key = 'SOFTWARE\Test'; name = $Name; value = $Name } }
            $B = @(Get-PSGPOPreferenceItem -File $File -Extension $Registry)[1].Element
            Move-PSGPOPreferenceElement -Element $B -Direction Up
            @(Get-PSGPOPreferenceItem -File $File -Extension $Registry).Name | Should -Be @('B', 'A', 'C')
            Move-PSGPOPreferenceElement -Element $B -Direction Up
            @(Get-PSGPOPreferenceItem -File $File -Extension $Registry).Name | Should -Be @('B', 'A', 'C') -Because 'it is first already'
            Move-PSGPOPreferenceElement -Element $B -Direction Down
            Remove-PSGPOPreferenceElement -Element @(Get-PSGPOPreferenceItem -File $File -Extension $Registry)[2].Element
            @(Get-PSGPOPreferenceItem -File $File -Extension $Registry).Name | Should -Be @('A', 'B')
        }
    }

    Describe 'Preferences of a GPO' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
        }

        It 'Writes the file in Preferences, increases the version and declares the extension as GPMC does' {
            $Version = $Gpo.GetComputerVersion()
            $File = [GPOToolsPreferenceFile]::Create($Registry.Root, $Registry.RootClsid)
            $null = New-PSGPOPreferenceItem -File $File -Type $RegistryItem -Values @{ key = 'SOFTWARE\Contoso'; name = 'Mode'; type = 'REG_SZ'; value = 'on' }
            $Directory.WritePreferenceFile($Gpo, 'Machine', $Registry.Path, $File.ToBytes(), $Registry.Cse, $Registry.Tool)
            $Directory.ReadPreferenceFile($Gpo, 'Machine', $Registry.Path) | Should -Not -BeNullOrEmpty
            @($Directory.ReadGpoFolder($Gpo).Keys) | Should -Contain 'Machine\Preferences\Registry\Registry.xml'
            $Gpo.GetComputerVersion() | Should -Be ($Version + 1)
            $Gpo.MachineExtensionNames | Should -Be '[{00000000-0000-0000-0000-000000000000}{BEE07A6A-EC9F-4659-B8C9-0B1937907C83}][{B087BE9D-ED37-454F-AF9C-04291E351182}{BEE07A6A-EC9F-4659-B8C9-0B1937907C83}]'
        }

        It 'Lists the preference items in the settings report, and shows a change of one in the history' {
            $Before = [ordered]@{ 'Machine\Preferences\Registry\Registry.xml' = [System.Text.Encoding]::UTF8.GetBytes($GpmcRegistry) }
            $Rows = @(Get-PSGPOConfiguredPreference -Files $Before -Scope Machine)
            $Rows.Count | Should -Be 2
            $Rows[0].Row.Path | Should -Be 'Policies > Preferences > Windows Settings > Registry'
            $Rows[0].Row.State | Should -Be 'Update'
            $Rows[0].Row.Options | Should -Match 'key = SOFTWARE\\Contoso'
            $Rows[0].Row.Options | Should -Match '1 item-level targeting filter'
            $Rows[1].Row.Path | Should -Be 'Policies > Preferences > Windows Settings > Registry > Proxy'

            $File = [GPOToolsPreferenceFile]::Parse($Before['Machine\Preferences\Registry\Registry.xml'])
            Set-PSGPOPreferenceElement -Element @(Get-PSGPOPreferenceItem -File $File -Extension $Registry)[0].Element -Type $RegistryItem -Values @{ value = '00000002'; name = 'Level' }
            $After = [ordered]@{ 'Machine\Preferences\Registry\Registry.xml' = $File.ToBytes() }
            $Property = @{ DisplayName = 'G'; Status = 'Enabled'; SecurityFiltering = @('Authenticated Users'); DeniedTo = @(); Links = @() }
            $Changes = @(Compare-PSGPOSettingReport -Reference @(Get-PSGPOSettingReport -Files $Before -Property $Property) -Difference @(Get-PSGPOSettingReport -Files $After -Property $Property))
            $Changes.Count | Should -Be 1 -Because 'the item keeps its uid when renamed'
            $Changes[0].Change | Should -Be 'Changed'
            $Changes[0].Name | Should -Be 'Level'
            $Changes[0].Before | Should -Match 'value = 00000001'
            $Changes[0].After | Should -Match 'value = 00000002'
        }
    }
}
