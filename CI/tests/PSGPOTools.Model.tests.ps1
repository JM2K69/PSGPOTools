#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Registry model of the policies: values written when enabled/disabled, elements
# (boolean, decimal, text, multiText, enum, list) and their ADML presentation.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path
        $Target = [AdmxNamespace]::new([pscustomobject]@{ prefix = 'test'; namespace = 'Test.Policies' })

        # Parses an XML fragment in the PolicyDefinitions namespace and returns its root element.
        function ConvertTo-AdmxNode {
            param([string]$Xml)
            $Document = [xml]"<root xmlns='http://schemas.microsoft.com/GroupPolicy/2006/07/PolicyDefinitions'>$Xml</root>"
            $Document.DocumentElement.FirstChild
        }

        function New-TestElement {
            param([string]$Xml)
            [GPOToolsPolicyElement]::new((ConvertTo-AdmxNode $Xml), 'Software\Policies\Test')
        }
    }

    Describe 'GPOToolsRegistryValue' {
        It 'Reads a <Child> value as <Type>' -ForEach @(
            @{ Child = 'decimal'; Xml = '<decimal value="4294967295"/>'; Type = 'DWord'; Expected = [uint32]::MaxValue }
            @{ Child = 'longDecimal'; Xml = '<longDecimal value="18446744073709551615"/>'; Type = 'QWord'; Expected = [uint64]::MaxValue }
            @{ Child = 'string'; Xml = '<string>%ProgramFiles%\App</string>'; Type = 'String'; Expected = '%ProgramFiles%\App' }
            @{ Child = 'delete'; Xml = '<delete/>'; Type = 'Delete'; Expected = $null }
        ) {
            $Value = [GPOToolsRegistryValue]::FromValueNode((ConvertTo-AdmxNode "<value>$Xml</value>"), 'Software\Test', 'Name')
            $Value.Type | Should -Be $Type
            $Value.Value | Should -Be $Expected
            $Value.Key | Should -Be 'Software\Test'
            $Value.ValueName | Should -Be 'Name'
            $Value.Implicit | Should -BeFalse
        }

        It 'Returns $null for a missing node' {
            [GPOToolsRegistryValue]::FromValueNode($null, 'Software\Test', 'Name') | Should -BeNullOrEmpty
        }

        It 'Resolves the key of list items: item key, then defaultKey, then the default key' {
            $List = ConvertTo-AdmxNode @'
<enabledList defaultKey="Software\ListDefault">
  <item key="Software\ItemKey" valueName="A"><value><decimal value="1"/></value></item>
  <item valueName="B"><value><string>b</string></value></item>
</enabledList>
'@
            $Values = [GPOToolsRegistryValue]::FromListNode($List, 'Software\Policy')
            $Values.Count | Should -Be 2
            $Values[0].Key | Should -Be 'Software\ItemKey'
            $Values[1].Key | Should -Be 'Software\ListDefault'

            $NoDefault = ConvertTo-AdmxNode '<disabledList><item valueName="C"><value><delete/></value></item></disabledList>'
            ([GPOToolsRegistryValue]::FromListNode($NoDefault, 'Software\Policy'))[0].Key | Should -Be 'Software\Policy'
            [GPOToolsRegistryValue]::FromListNode($null, 'Software\Policy').Count | Should -Be 0
        }
    }

    Describe 'GPOToolsPolicyElement' {
        It 'boolean without trueValue/falseValue writes 1 / 0 (implicit)' {
            $Element = New-TestElement '<boolean id="B" valueName="Flag"/>'
            $Element.Type | Should -Be 'Boolean'
            $Element.Key | Should -Be 'Software\Policies\Test'
            $Element.TrueValue.Value | Should -Be 1
            $Element.FalseValue.Value | Should -Be 0
            $Element.TrueValue.Implicit | Should -BeTrue
            $Element.FalseValue.Implicit | Should -BeTrue
        }

        It 'boolean reads explicit values and lists' {
            $Element = New-TestElement @'
<boolean id="B" key="Software\Other" valueName="Flag">
  <trueValue><string>yes</string></trueValue>
  <falseValue><delete/></falseValue>
  <trueList><item valueName="Extra"><value><decimal value="7"/></value></item></trueList>
</boolean>
'@
            $Element.Key | Should -Be 'Software\Other'
            $Element.TrueValue.Value | Should -Be 'yes'
            $Element.TrueValue.Implicit | Should -BeFalse
            $Element.FalseValue.Type | Should -Be 'Delete'
            $Element.TrueList[0].Key | Should -Be 'Software\Other'
            $Element.TrueList[0].Value | Should -Be 7
        }

        It 'decimal uses the schema defaults (0..9999, DWORD)' {
            $Element = New-TestElement '<decimal id="D" valueName="Count"/>'
            $Element.MinValue | Should -Be 0
            $Element.MaxValue | Should -Be 9999
            $Element.ValueType | Should -Be 'DWord'
            $Element.Required | Should -BeFalse
        }

        It 'decimal reads bounds, storeAsText and tolerates a lowercase maxvalue' {
            $Element = New-TestElement '<decimal id="D" valueName="Count" required="true" minValue="5" maxvalue="70000" storeAsText="true"/>'
            $Element.Required | Should -BeTrue
            $Element.MinValue | Should -Be 5
            $Element.MaxValue | Should -Be 70000
            $Element.ValueType | Should -Be 'String'
        }

        It 'longDecimal is stored as QWORD' {
            (New-TestElement '<longDecimal id="L" valueName="Big"/>').ValueType | Should -Be 'QWord'
        }

        It 'text defaults to 1023 characters, expandable gives REG_EXPAND_SZ' {
            $Text = New-TestElement '<text id="T" valueName="Path"/>'
            $Text.MaxLength | Should -Be 1023
            $Text.ValueType | Should -Be 'String'
            (New-TestElement '<text id="T" valueName="Path" expandable="true" maxLength="260"/>').ValueType | Should -Be 'ExpandString'
        }

        It 'multiText is a REG_MULTI_SZ with default limits' {
            $Element = New-TestElement '<multiText id="M" valueName="Lines"/>'
            $Element.ValueType | Should -Be 'MultiString'
            $Element.MaxLength | Should -Be 1023
            $Element.MaxStrings | Should -Be 0
        }

        It 'enum reads each item value and its valueList' {
            $Element = New-TestElement @'
<enum id="E" valueName="Mode">
  <item displayName="$(string.Off)"><value><decimal value="0"/></value></item>
  <item displayName="$(string.On)">
    <value><decimal value="1"/></value>
    <valueList><item valueName="Other"><value><delete/></value></item></valueList>
  </item>
</enum>
'@
            $Element.Type | Should -Be 'Enum'
            $Element.ValueType | Should -Be 'DWord'
            $Element.Items.Count | Should -Be 2
            $Element.Items.DisplayNameRef | Should -Be @('Off', 'On')
            $Element.Items[1].Value.Value | Should -Be 1
            $Element.Items[1].ValueList[0].ValueName | Should -Be 'Other'
            $Element.Items[1].ValueList[0].Type | Should -Be 'Delete'
        }

        It 'list reads its encoding attributes' {
            $Element = New-TestElement '<list id="L" key="Software\Policies\Test\List" valuePrefix="Item" additive="true" explicitValue="true" expandable="true"/>'
            $Element.Type | Should -Be 'List'
            $Element.Key | Should -Be 'Software\Policies\Test\List'
            $Element.ValuePrefix | Should -Be 'Item'
            $Element.Additive | Should -BeTrue
            $Element.ExplicitValue | Should -BeTrue
            $Element.ValueType | Should -Be 'ExpandString'
        }

        It 'Throws on an unknown element type' {
            { New-TestElement '<color id="C"/>' } | Should -Throw '*Unknown element type color*'
        }
    }

    Describe 'AdmxPolicy enabled and disabled values' {
        It 'valueName without enabledValue/disabledValue: DWORD 1 when enabled, deleted when disabled (implicit)' {
            $Policy = [AdmxPolicy]::new((ConvertTo-AdmxNode '<policy name="P" class="Machine" displayName="$(string.P)" key="Software\Policies\Test" valueName="Enabled"/>'), $Target)
            $Policy.EnabledValues.Count | Should -Be 1
            $Policy.EnabledValues[0].Type | Should -Be 'DWord'
            $Policy.EnabledValues[0].Value | Should -Be 1
            $Policy.EnabledValues[0].Implicit | Should -BeTrue
            $Policy.DisabledValues[0].Type | Should -Be 'Delete'
            $Policy.DisabledValues[0].Implicit | Should -BeTrue
        }

        It 'Explicit values and lists are combined' {
            $Xml = @'
<policy name="P" class="User" displayName="$(string.P)" key="Software\Policies\Test" valueName="Mode" presentation="$(presentation.P)">
  <enabledValue><decimal value="2"/></enabledValue>
  <disabledValue><decimal value="0"/></disabledValue>
  <enabledList defaultKey="Software\Policies\Test\Sub"><item valueName="Extra"><value><string>x</string></value></item></enabledList>
  <elements><boolean id="B" valueName="Flag"/><text id="T" valueName="Name"/></elements>
</policy>
'@
            $Policy = [AdmxPolicy]::new((ConvertTo-AdmxNode $Xml), $Target)
            $Policy.Presentation | Should -Be 'P'
            $Policy.EnabledValues.Value | Should -Be @(2, 'x')
            $Policy.EnabledValues[1].Key | Should -Be 'Software\Policies\Test\Sub'
            $Policy.EnabledValues.Implicit | Should -Not -Contain $true
            $Policy.DisabledValues.Value | Should -Be @(0)
            $Policy.Elements.Id | Should -Be @('B', 'T')
        }

        It 'A policy with only elements has no enabled/disabled value' {
            $Policy = [AdmxPolicy]::new((ConvertTo-AdmxNode '<policy name="P" class="User" displayName="$(string.P)" key="K"><elements><text id="T" valueName="N"/></elements></policy>'), $Target)
            $Policy.EnabledValues.Count | Should -Be 0
            $Policy.DisabledValues.Count | Should -Be 0
            $Policy.Elements.Count | Should -Be 1
        }
    }

    Describe 'ADML presentations' {
        BeforeAll {
            $AdmlPath = Join-Path $TestDrive 'Test.adml'
            Set-Content -Path $AdmlPath -Encoding utf8 -Value @'
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitionResources revision="1.0" schemaVersion="1.0" xmlns="http://schemas.microsoft.com/GroupPolicy/2006/07/PolicyDefinitions">
  <resources>
    <stringTable><string id="Off">Disabled mode</string></stringTable>
    <presentationTable>
      <presentation id="P">
        <text>Free text without refId</text>
        <checkBox refId="B" defaultChecked="true">Enable the flag</checkBox>
        <decimalTextBox refId="D" defaultValue="42" spin="true">Count:</decimalTextBox>
        <textBox refId="T"><label>Name:</label><defaultValue>Contoso</defaultValue></textBox>
        <dropdownList refId="E" defaultItem="1">Mode:</dropdownList>
        <multiTextBox refId="M">Lines:</multiTextBox>
      </presentation>
    </presentationTable>
  </resources>
</policyDefinitionResources>
'@
            $Adml = [GpoToolsAdml]::new($AdmlPath)
        }

        It 'Reads the <Control> control of <RefId>' -ForEach @(
            @{ RefId = 'B'; Control = 'checkBox'; Label = 'Enable the flag'; Default = $true }
            @{ RefId = 'D'; Control = 'decimalTextBox'; Label = 'Count:'; Default = '42' }
            @{ RefId = 'T'; Control = 'textBox'; Label = 'Name:'; Default = 'Contoso' }
            @{ RefId = 'E'; Control = 'dropdownList'; Label = 'Mode:'; Default = '1' }
            @{ RefId = 'M'; Control = 'multiTextBox'; Label = 'Lines:'; Default = $null }
        ) {
            $Presented = $Adml.GetPresentation('P')[$RefId]
            $Presented.Control | Should -Be $Control
            $Presented.Label | Should -Be $Label
            $Presented.DefaultValue | Should -Be $Default
        }

        It 'Ignores controls without refId and unknown presentations' {
            $Adml.GetPresentation('P').Count | Should -Be 5
            $Adml.GetPresentation('Unknown') | Should -BeNullOrEmpty
            $Adml.GetPresentation($null) | Should -BeNullOrEmpty
        }

        It 'Localize fills the label, default value and enum display names' {
            $Element = New-TestElement '<enum id="E" valueName="Mode"><item displayName="$(string.Off)"><value><decimal value="0"/></value></item></enum>'
            $Element.Localize($Adml, $Adml.GetPresentation('P'))
            $Element.Control | Should -Be 'dropdownList'
            $Element.Label | Should -Be 'Mode:'
            $Element.DefaultValue | Should -Be '1'
            $Element.Items[0].DisplayName | Should -Be 'Disabled mode'
        }
    }

    Describe 'Model loaded from the Windows ADMX files' {
        BeforeAll {
            Initialize-PSGPOAdmx -Path $PolicyDefinitions -UICulture 'en-US' 3>$null
            $Policies = [GPOToolsUtility]::Policies
        }

        It 'Every policy writes at least one registry value' {
            @($Policies | Where-Object { $_.EnabledValues.Count -eq 0 -and $_.DisabledValues.Count -eq 0 -and $_.Elements.Count -eq 0 }).Count | Should -Be 0
        }

        It 'A Both policy exists once per scope, with the matching hive' {
            $Both = @($Policies | Where-Object ID -EQ 'AppxRuntimeBlockFileElevation')
            $Both.Scope | Sort-Object | Should -Be @('User', 'Machine')
            ($Both | Where-Object Scope -EQ 'Machine').Registry.Path | Should -BeLike 'HKLM:\*'
            ($Both | Where-Object Scope -EQ 'User').Registry.Path | Should -BeLike 'HKCU:\*'
            $Both.Class | Sort-Object -Unique | Should -Be 'Both'
        }

        It 'Each Both policy gives exactly two objects' {
            $Both = $Policies | Where-Object Class -EQ 'Both'
            @($Both | Group-Object FileName, ID | Where-Object Count -NE 2).Count | Should -Be 0
        }

        It 'Localizes the elements of AxISURLZonePolicies' {
            $Policy = $Policies | Where-Object ID -EQ 'AxISURLZonePolicies'
            $Policy.RegistryKey | Should -Be 'SOFTWARE\Policies\Microsoft\Windows\AxInstaller\AxISURLZonePolicies'
            $Policy.Elements.Id | Should -Contain 'InstallTrustedOCX'

            $Enum = $Policy.Elements | Where-Object Id -EQ 'InstallTrustedOCX'
            $Enum.Control | Should -Be 'dropdownList'
            $Enum.Label | Should -Be 'Installation Policy for ActiveX control signed by trusted publisher'
            $Enum.DefaultValue | Should -Be '2'
            $Enum.Items.DisplayName | Should -Be @("Don't install", 'Prompt the user', 'Silently install')
            $Enum.Items.Value.Value | Should -Be @(0, 1, 2)

            $Check = $Policy.Elements | Where-Object Id -EQ 'IgnoreUnknownCA'
            $Check.Control | Should -Be 'checkBox'
            $Check.DefaultValue | Should -BeFalse
            $Check.TrueValue.Value | Should -Be 1
        }

        It 'Every element has a presentation control' {
            @($Policies.Elements | Where-Object { -not $_.Control }).Count | Should -Be 0
        }

        It 'GUI registry rows list the enabled, disabled and element values' {
            $Rows = @(Get-PSGPOPolicyRegistryRow -Policy ($Policies | Where-Object ID -EQ 'AxISURLZonePolicies'))
            $Rows.Count | Should -Be 7
            $Rows[0].Key | Should -Be 'Installation Policy for ActiveX control signed by trusted publisher'
            $Rows[0].Value | Should -Be 'Enum, 3 choices: SOFTWARE\Policies\Microsoft\Windows\AxInstaller\AxISURLZonePolicies\InstallTrustedOCX (DWord)'
            ($Rows | Where-Object Key -EQ 'Unknown certifcation authority (CA)').Value | Should -BeLike 'Boolean: *\IgnoreUnknownCA (DWord)'
        }

        It 'GUI registry rows flag the implicit default values' {
            $Policy = $Policies | Where-Object { $_.EnabledValues.Count -eq 1 -and $_.EnabledValues[0].Implicit -and $_.Elements.Count -eq 0 } | Select-Object -First 1
            $Rows = @(Get-PSGPOPolicyRegistryRow -Policy $Policy)
            $Rows.Key | Should -Be @('Enabled', 'Disabled')
            $Rows[0].Value | Should -Be ('{0}\{1} = 1 (DWord) [default]' -f $Policy.RegistryKey, $Policy.EnabledValues[0].ValueName)
            $Rows[1].Value | Should -Be ('{0}\{1}: deleted [default]' -f $Policy.RegistryKey, $Policy.EnabledValues[0].ValueName)
        }
    }
}
