#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The Starter GPOs of a domain (PSGPOStarterGpo.ps1), as GPMC keeps them in SYSVOL\<domain>\
# StarterGPOs: the files GPMC wrote on the Windows lab (System and Custom), those HGPM writes, the
# commands on the sample directory in memory, and a GPO started from a Starter GPO. The folder of a
# real domain is tested in PSGPOTools.Ldap.tests.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        $Utf8Bom = [System.Text.UTF8Encoding]::new($true)
        function Get-Utf8Byte { param([string]$Text, [switch]$Bom) if ($Bom) { [byte[]]($Utf8Bom.GetPreamble() + $Utf8Bom.GetBytes($Text)) } else { [byte[]][System.Text.Encoding]::UTF8.GetBytes($Text) } }
        # As GPMC wrote them on powershell.labo (Windows Server, 2026-11-01).
        $SystemTemplate = @'
<?xml version='1.0' encoding='utf-8'?>
<policyTemplate xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" revision="1.0" schemaVersion="1.0" xmlns="http://www.microsoft.com/GroupPolicy/TemplateDefinitions">
  <template minRequiredRevision="1.0" uniqueID="{0CC42745-34A0-4C7E-ACFA-37CE56B13706}" templateType="System" templateVersion="0" product="$(resource.product)" author="$(resource.author)" displayName="$(resource.displayName)" description="$(resource.description)"></template>
  <computerExtensions>
    <guidPair guidExtension="{35378EAC-683F-11D2-A89A-00C04FBBCFA2}" guidSnapin="{B05566AC-FE9C-4368-BE01-7A4CBB6CBA11}"></guidPair>
  </computerExtensions>
  <resources minRequiredRevision="1.0">
  </resources>
</policyTemplate>
'@
        $SystemResource = @'
<?xml version="1.0" encoding="utf-8"?>
<templateDefinitionResources xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" revision="1.0" schemaVersion="1.0" xmlns="http://www.microsoft.com/GroupPolicy/TemplateDefinitions">
  <resources>
    <stringTable>
      <string id="displayName">Group Policy Reporting Firewall Ports</string>
      <string id="product"></string>
      <string id="author">Microsoft</string>
      <string id="description">This Starter GPO contains the computer Group Policy settings required for remote access to Resultant Set of Policy (RSoP) reports.</string>
    </stringTable>
  </resources>
</templateDefinitionResources>
'@
        $CustomTemplate = @'
<?xml version='1.0' encoding='utf-8'?>
<policyTemplate xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" revision="1.0" schemaVersion="1.0" xmlns="http://www.microsoft.com/GroupPolicy/TemplateDefinitions">
  <template minRequiredRevision="1.0" uniqueID="{66749208-6A4D-42E6-A40A-90DB3841E25E}" templateType="Custom" computerVersion="0" userVersion="0" displayName="$(resource.displayName)" description="$(resource.description)"></template>
  <resources minRequiredRevision="1.0">
    <stringTable>
      <string id="displayName">HGPM probe starter</string>
      <string id="description">Probe of HGPM
second line</string>
    </stringTable>
  </resources>
</policyTemplate>
'@
        # A Registry.pol with one value, for the Machine or User part.
        function New-TestPol {
            param([string]$Value)
            $Pol = [GPOToolsRegistryPol]::new()
            $Pol.Entries.Add([GPOToolsPolEntry]::new('Software\Policies\Contoso\Starter', $Value, [GPOToolsPolType]::DWord, [BitConverter]::GetBytes([uint32]1)))
            , $Pol.ToBytes()
        }
    }

    Describe 'StarterGPO.tmplx' {
        It 'Reads a System Starter GPO of GPMC, its texts from its .tmpll' {
            $Read = ConvertFrom-PSGPOStarterTemplate -Template (Get-Utf8Byte $SystemTemplate -Bom) -Resource (Get-Utf8Byte $SystemResource)
            $Read.Id | Should -Be ([guid]'0CC42745-34A0-4C7E-ACFA-37CE56B13706')
            $Read.Type | Should -Be 'System'
            $Read.DisplayName | Should -Be 'Group Policy Reporting Firewall Ports'
            $Read.Author | Should -Be 'Microsoft'
            $Read.Description | Should -BeLike 'This Starter GPO contains*'
            $Read.ComputerVersion | Should -BeNullOrEmpty
            $Read.ComputerExtensions | Should -Be @('{35378EAC-683F-11D2-A89A-00C04FBBCFA2}')
            @($Read.UserExtensions) | Should -BeNullOrEmpty
        }

        It 'Reads a Custom Starter GPO of GPMC, its texts in the file' {
            $Read = ConvertFrom-PSGPOStarterTemplate -Template (Get-Utf8Byte $CustomTemplate -Bom)
            $Read.Type | Should -Be 'Custom'
            $Read.DisplayName | Should -Be 'HGPM probe starter'
            $Read.Description -split '\r?\n' | Should -Be @('Probe of HGPM', 'second line')
            $Read.ComputerVersion | Should -Be 0
            $Read.UserVersion | Should -Be 0
        }

        It 'Writes a Custom Starter GPO as GPMC: UTF-8 with its mark, its texts escaped, an extension for each part with settings' {
            $Id = [guid]::NewGuid()
            $Bytes = ConvertTo-PSGPOStarterTemplate -Id $Id -DisplayName 'Kiosks <halls> & "lobby"' -Description "First`nsecond" -ComputerVersion 1 -ComputerSettings
            $Bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
            $Text = [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
            $Text | Should -BeLike "*uniqueID=`"{$($Id.ToString().ToUpperInvariant())}`" templateType=`"Custom`" computerVersion=`"1`" userVersion=`"0`"*"
            $Text | Should -BeLike '*&lt;halls&gt; &amp; &quot;lobby&quot;*'
            $Read = ConvertFrom-PSGPOStarterTemplate -Template $Bytes
            $Read.Id | Should -Be $Id
            $Read.DisplayName | Should -Be 'Kiosks <halls> & "lobby"'
            $Read.Description | Should -Be "First`nsecond" -Because 'XML reads a line break as LF'
            $Read.ComputerExtensions | Should -Be @('{35378EAC-683F-11D2-A89A-00C04FBBCFA2}')
            @($Read.UserExtensions) | Should -BeNullOrEmpty
        }

        It 'Refuses a file that is not a Starter GPO, and one with a DTD' {
            { ConvertFrom-PSGPOStarterTemplate -Template (Get-Utf8Byte '<policyTemplate xmlns="http://www.microsoft.com/GroupPolicy/TemplateDefinitions"/>') } | Should -Throw '*no <template> element*'
            { ConvertFrom-PSGPOStarterTemplate -Template (Get-Utf8Byte '<!DOCTYPE x [<!ENTITY a "aaaa">]><policyTemplate/>') } | Should -Throw '*DTD*'
        }
    }

    Describe 'Starter GPOs of a directory' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.IsReadOnly = $false
            $Source = $Directory.FindGpo('C - Kiosks - Assigned Access')
            $Directory.WritePolicyFile($Source, 'Machine', (New-TestPol 'ShowClock'))
            $Directory.WritePolicyFile($Source, 'User', (New-TestPol 'NoRun'))
        }

        It 'Has none at first, then the one created from a GPO, with its Administrative Templates only' {
            @(Get-PSGPOStarterGpo -Directory $Directory) | Should -BeNullOrEmpty
            $Directory.WriteGpoComment($Source, 'not a setting')
            $Starter = New-PSGPOStarterGpo -Directory $Directory -Name 'Kiosks - Baseline' -Description "Kiosks`nhalls" -FromGpo $Source.DisplayName -Confirm:$false
            $Starter.PSObject.TypeNames | Should -Contain 'PSGPOTools.StarterGpo'
            $Starter.Type | Should -Be 'Custom'
            $Starter.ComputerVersion | Should -Be 1
            $Starter.UserVersion | Should -Be 1
            $Starter.Description | Should -Be "Kiosks`nhalls"
            @($Starter.Files.Keys | Sort-Object) | Should -Be @('Machine\Registry.pol', 'StarterGPO.tmplx', 'User\Registry.pol')
            $Starter.Files['Machine\Registry.pol'] | Should -Be $Directory.ReadGpoFile($Source, 'Machine\Registry.pol')
            @($Directory.ReadStarterGpoFiles().Keys) | Should -Contain "{$($Starter.Id.ToString().ToUpperInvariant())}\StarterGPO.tmplx"
            @(Get-PSGPOStarterGpo -Directory $Directory -Name 'kiosks*').DisplayName | Should -Be @('Kiosks - Baseline')
        }

        It 'Refuses a name taken or empty, and changes nothing with -WhatIf' {
            $null = New-PSGPOStarterGpo -Directory $Directory -Name 'Kiosks - Baseline' -Confirm:$false
            { New-PSGPOStarterGpo -Directory $Directory -Name 'kiosks - baseline' -Confirm:$false } | Should -Throw "*A Starter GPO named 'kiosks - baseline' already exists*"
            { New-PSGPOStarterGpo -Directory $Directory -Name ' ' -Confirm:$false } | Should -Throw '*name of the Starter GPO is required*'
            New-PSGPOStarterGpo -Directory $Directory -Name 'Never' -WhatIf 6>$null | Should -BeNullOrEmpty
            @(Get-PSGPOStarterGpo -Directory $Directory).Count | Should -Be 1
            { Get-PSGPOStarterGpo -Directory $Directory -Name 'Nothing like it' } | Should -Throw "*No Starter GPO named 'Nothing like it'*"
        }

        It 'Starts a new GPO from a Starter GPO: its Administrative Templates, declared, its version increased' {
            $null = New-PSGPOStarterGpo -Directory $Directory -Name 'Kiosks - Baseline' -FromGpo $Source.DisplayName -Confirm:$false
            $Gpo = New-PSGPO -Directory $Directory -Name 'C - Kiosks - Lyon' -StarterGpo 'Kiosks - Baseline' -Confirm:$false
            $Directory.ReadGpoFile($Gpo, 'Machine\Registry.pol') | Should -Be $Directory.ReadGpoFile($Source, 'Machine\Registry.pol')
            $Directory.ReadGpoFile($Gpo, 'User\Registry.pol') | Should -Be $Directory.ReadGpoFile($Source, 'User\Registry.pol')
            $Gpo.MachineExtensionNames | Should -Be '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{0F6B957D-509E-11D1-A7CC-0000F87571E3}]' -Because 'the tool GPMC declares, seen on the Windows lab'
            $Gpo.UserExtensionNames | Should -Be '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{0F6B957E-509E-11D1-A7CC-0000F87571E3}]'
            $Gpo.GetComputerVersion() | Should -BeGreaterThan 0
            $Gpo.GetUserVersion() | Should -BeGreaterThan 0
            { New-PSGPO -Directory $Directory -Name 'C - Other' -StarterGpo 'No such starter' -Confirm:$false } | Should -Throw "*No Starter GPO named 'No such starter'*"
            $Directory.FindGpo('C - Other') | Should -BeNullOrEmpty -Because 'nothing is created when the Starter GPO is not found'
            $Template = [pscustomobject]@{ PSTypeName = 'PSGPOTools.Backup'; DisplayName = 'T' }
            { New-PSGPO -Directory $Directory -Name 'C - Other' -Template $Template -StarterGpo 'Kiosks - Baseline' -Confirm:$false } | Should -Throw '*Give -Template or -StarterGpo*'
        }

        It 'Deletes a Custom Starter GPO, never a System one' {
            $Starter = New-PSGPOStarterGpo -Directory $Directory -Name 'Kiosks - Baseline' -Confirm:$false
            $Directory.WriteStarterGpo([guid]'0CC42745-34A0-4C7E-ACFA-37CE56B13706', 'System', @{ 'StarterGPO.tmplx' = (Get-Utf8Byte $SystemTemplate -Bom); 'en-US\StarterGPO.tmpll' = (Get-Utf8Byte $SystemResource) })
            Remove-PSGPOStarterGpo -Directory $Directory -Name 'Group Policy Reporting Firewall Ports' -Confirm:$false -ErrorVariable Problems -ErrorAction SilentlyContinue
            "$Problems" | Should -BeLike '*System Starter GPO of Microsoft: it is not deleted*'
            Remove-PSGPOStarterGpo -Directory $Directory -Name 'Kiosks - Baseline' -Confirm:$false
            @(Get-PSGPOStarterGpo -Directory $Directory).DisplayName | Should -Be @('Group Policy Reporting Firewall Ports')
            @($Directory.ReadStarterGpoFiles().Keys) | Should -Not -Contain "{$($Starter.Id.ToString().ToUpperInvariant())}\StarterGPO.tmplx"
        }

        It 'Shows the Starter GPOs under the domain once read, and their details' {
            $Node = (New-PSGPODirectoryTree -Directory $Directory)[0].Children | Where-Object Tag -EQ 'StarterGpos'
            $Node.Header | Should -Be 'Starter GPOs'
            $Node.Children.Count | Should -Be 0 -Because 'they are read when the node is selected'
            (Get-PSGPODirectoryDetail -Directory $Directory -Item 'StarterGpos').Properties[0].Value | Should -Be 'Reading the Starter GPOs of corp.contoso.com...'
            (Get-PSGPODirectoryDetail -Directory $Directory -Item 'StarterGpos' -StarterGpo @()).Properties[0].Key | Should -Be 'None'
            (Get-PSGPODirectoryDetail -Directory $Directory -Item 'StarterGpos' -StarterGpo @() -StarterGpoProblem 'access denied').Properties[0].Value | Should -Be 'The Starter GPOs cannot be read: access denied'

            $Directory.WritePolicyFile($Source, 'User', ([GPOToolsRegistryPol]::new().ToBytes()))
            $Starter = New-PSGPOStarterGpo -Directory $Directory -Name 'Kiosks - Baseline' -Description 'Kiosks' -FromGpo $Source.DisplayName -Confirm:$false
            $List = @(Get-PSGPOStarterGpoData -Directory $Directory)
            $Node = (New-PSGPODirectoryTree -Directory $Directory -StarterGpo $List)[0].Children | Where-Object Tag -EQ 'StarterGpos'
            @($Node.Children.Header) | Should -Be @('Kiosks - Baseline')
            $Node.Children[0].Tag.Id | Should -Be $Starter.Id
            $All = Get-PSGPODirectoryDetail -Directory $Directory -Item 'StarterGpos' -StarterGpo $List
            $All.Title | Should -Be 'Starter GPOs in corp.contoso.com'
            $All.Properties[0].Key | Should -Be 'Kiosks - Baseline'
            $All.Properties[0].Value | Should -Be 'Custom'
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $List[0]
            $Detail.Title | Should -Be 'Kiosks - Baseline'
            ($Detail.Properties | Where-Object Key -EQ 'Type').Value | Should -Be 'Custom'
            ($Detail.Properties | Where-Object Key -EQ 'Description').Value | Should -Be 'Kiosks'
            ($Detail.Properties | Where-Object Key -EQ 'Computer settings').Value | Should -Be '1 registry value(s)'
            ($Detail.Properties | Where-Object Key -EQ 'User settings').Value | Should -Be '0 registry value(s)'
            ($Detail.Properties | Where-Object Key -EQ 'Folder').Value | Should -Be "\\corp.contoso.com\SYSVOL\corp.contoso.com\StarterGPOs\{$($Starter.Id.ToString().ToUpperInvariant())}"
        }

        It 'Lists a folder it cannot read with its problem, and takes the texts of a System Starter GPO in the language of the interface' {
            $Directory.WriteStarterGpo([guid]::NewGuid(), 'Broken', @{ 'StarterGPO.tmplx' = (Get-Utf8Byte 'not xml') })
            $French = $SystemResource.Replace('Group Policy Reporting Firewall Ports', 'Ports du pare-feu pour les rapports')
            $Directory.WriteStarterGpo([guid]'0CC42745-34A0-4C7E-ACFA-37CE56B13706', 'System', @{
                    'StarterGPO.tmplx' = (Get-Utf8Byte $SystemTemplate -Bom); 'en-US\StarterGPO.tmpll' = (Get-Utf8Byte $SystemResource); 'fr-FR\StarterGPO.tmpll' = (Get-Utf8Byte $French) })
            $Starters = @(Get-PSGPOStarterGpo -Directory $Directory)
            $Starters.Count | Should -Be 2
            @($Starters | Where-Object Problem).Problem | Should -BeLike '*cannot be read*'
            ($Starters | Where-Object Type -EQ 'System').DisplayName | Should -Be 'Group Policy Reporting Firewall Ports'
            try {
                $null = Set-PSGPOLanguage -Language 'fr-FR'
                (@(Get-PSGPOStarterGpo -Directory $Directory) | Where-Object Type -EQ 'System').DisplayName | Should -Be 'Ports du pare-feu pour les rapports'
            } finally {
                $null = Set-PSGPOLanguage -Language 'en-US'
            }
        }
    }
}
