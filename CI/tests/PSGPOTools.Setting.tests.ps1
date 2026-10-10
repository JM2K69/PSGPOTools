#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Get-PSGPOPolicyRegistryChange: registry values written by a policy setting, i.e. the
# future content of Registry.pol, for a state and the values entered for its elements.
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
            param([string]$Id, [string]$Scope)
            [GPOToolsUtility]::Policies | Where-Object { $_.ID -eq $Id -and (-not $Scope -or "$($_.Scope)" -eq $Scope) } | Select-Object -First 1
        }
        function ConvertTo-Line {
            param($Changes)
            foreach ($Change in $Changes) { Format-PSGPORegistryValue $Change }
        }
    }

    Describe 'Not configured and disabled' {
        It 'Not configured writes nothing' {
            @(Get-PSGPOPolicyRegistryChange -Policy (Get-TestPolicy 'DisallowCpls') -State NotConfigured).Count | Should -Be 0
        }

        It 'Disabled writes the disabled values and clears the elements' {
            $Lines = ConvertTo-Line (Get-PSGPOPolicyRegistryChange -Policy (Get-TestPolicy 'DisallowCpls') -State Disabled)
            $Lines | Should -Be @(
                'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl: deleted [default]'
                'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl\*: all values deleted [default]'
            )
        }

        It 'Disabled uses an explicit disabledValue' {
            $Changes = @(Get-PSGPOPolicyRegistryChange -Policy (Get-TestPolicy 'DisableAntiSpywareDefender') -State Disabled)
            $Changes.Count | Should -Be 1
            $Changes[0].Value | Should -Be 0
            $Changes[0].Implicit | Should -BeFalse
        }
    }

    Describe 'List element (DisallowCpls, valuePrefix="")' {
        It 'Names the entries 1, 2, 3 after clearing the key' {
            $Lines = ConvertTo-Line (Get-PSGPOPolicyRegistryChange -Policy (Get-TestPolicy 'DisallowCpls') -State Enabled -Value @{
                    DisallowCplsList = @('Microsoft.Mouse', '', 'Microsoft.System')
                })
            $Lines | Should -Be @(
                'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl = 1 (DWord) [default]'
                'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl\*: all values deleted [default]'
                'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl\1 = Microsoft.Mouse (String)'
                'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowCpl\2 = Microsoft.System (String)'
            )
        }

        It 'Uses the entry as name and data without valuePrefix, and keeps the key when additive' {
            $Policy = [GPOToolsUtility]::Policies | Where-Object { $_.Elements | Where-Object { $_.Type -eq 'List' -and -not $_.HasValuePrefix -and -not $_.ExplicitValue -and $_.Additive } } | Select-Object -First 1
            $List = $Policy.Elements | Where-Object Type -EQ 'List' | Select-Object -First 1
            $Changes = @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $List.Id = @('contoso.com') } | Where-Object Key -EQ $List.Key)
            $Changes.Type | Should -Not -Contain 'DeleteAllValues'
            $Changes[-1].ValueName | Should -Be 'contoso.com'
            $Changes[-1].Value | Should -Be 'contoso.com'
        }

        It 'Writes the name/value pairs of an explicitValue list' {
            $Policy = Get-TestPolicy 'ApprovedActiveXInstallSites'
            $List = $Policy.Elements | Where-Object Type -EQ 'List'
            $List.ExplicitValue | Should -BeTrue
            $Changes = @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $List.Id = @(@{ Name = 'https://contoso.com'; Value = '2,1,0,0' }) } | Where-Object Key -EQ $List.Key)
            $Changes[-1].ValueName | Should -Be 'https://contoso.com'
            $Changes[-1].Value | Should -Be '2,1,0,0'
            { Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $List.Id = @(@{ Name = ''; Value = 'x' }) } } |
                Should -Throw '*needs a value name*'
        }
    }

    Describe 'Enum and boolean elements (AxISURLZonePolicies)' {
        BeforeAll {
            $Policy = Get-TestPolicy 'AxISURLZonePolicies'
            $Key = 'SOFTWARE\Policies\Microsoft\Windows\AxInstaller\AxISURLZonePolicies'
        }

        It 'Uses the ADML defaults when no value is entered' {
            $Changes = @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled)
            ($Changes | Where-Object ValueName -EQ 'InstallTrustedOCX').Value | Should -Be 2
            ($Changes | Where-Object ValueName -EQ 'InstallSignedOCX').Value | Should -Be 1
            ($Changes | Where-Object ValueName -EQ 'IgnoreUnknownCA').Value | Should -Be 0
        }

        It 'Writes the chosen enum item and the checked boxes' {
            $Changes = @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ InstallTrustedOCX = 0; IgnoreUnknownCA = $true })
            ($Changes | Where-Object ValueName -EQ 'InstallTrustedOCX').Value | Should -Be 0
            ($Changes | Where-Object ValueName -EQ 'IgnoreUnknownCA').Value | Should -Be 1
            $Changes.Key | Sort-Object -Unique | Should -Be $Key
        }

        It 'Rejects an enum choice that does not exist' {
            { Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ InstallTrustedOCX = 9 } } | Should -Throw '*choice 9 does not exist*'
        }
    }

    Describe 'Decimal, text and multiText elements' {
        It 'Checks the decimal bounds' {
            $Policy = [GPOToolsUtility]::Policies | Where-Object { @($_.Elements | Where-Object { $_.Type -eq 'Decimal' -and $_.MaxValue -lt 100000 }).Count -eq 1 -and $_.Elements.Count -eq 1 } | Select-Object -First 1
            $Element = $Policy.Elements[0]
            $Change = @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $Element.Id = $Element.MaxValue })[-1]
            $Change.Value | Should -Be $Element.MaxValue
            $Change.Type | Should -Be $Element.ValueType
            { Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $Element.Id = $Element.MaxValue + 1 } } | Should -Throw '*must be between*'
            { Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $Element.Id = 'abc' } } | Should -Throw '*positive whole number*'
        }

        It 'Requires a required text and limits its length' {
            $Policy = [GPOToolsUtility]::Policies | Where-Object { $_.Elements.Count -eq 1 -and $_.Elements[0].Type -eq 'Text' -and $_.Elements[0].Required } | Select-Object -First 1
            $Element = $Policy.Elements[0]
            { Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $Element.Id = '' } } | Should -Throw '*is required*'
            { Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $Element.Id = 'x' * ($Element.MaxLength + 1) } } | Should -Throw '*limited to*'
            @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $Element.Id = 'Contoso' })[-1].Value | Should -Be 'Contoso'
        }

        It 'Writes the non empty lines of a multiText as REG_MULTI_SZ' {
            $Policy = [GPOToolsUtility]::Policies | Where-Object { $_.Elements.Count -ge 1 -and $_.Elements[0].Type -eq 'MultiText' } | Select-Object -First 1
            $Element = $Policy.Elements[0]
            $Change = @(Get-PSGPOPolicyRegistryChange -Policy $Policy -State Enabled -Value @{ $Element.Id = @('a', '', 'b') } | Where-Object Type -EQ 'MultiString')[0]
            $Change.Type | Should -Be 'MultiString'
            $Change.Value | Should -Be @('a', 'b')
            Format-PSGPORegistryValue $Change | Should -BeLike '* = a | b (MultiString)'
        }
    }

    Describe 'Presentation layout' {
        It 'Keeps the ADML order, free texts included' {
            $Layout = (Get-TestPolicy 'AxISURLZonePolicies').Layout
            $Layout.Control | Should -Be @('dropdownList', 'dropdownList', 'dropdownList', 'text', 'checkBox', 'checkBox', 'checkBox', 'checkBox')
            $Layout[3].RefId | Should -BeNullOrEmpty
            $Layout[3].Label | Should -BeLike 'Permit connection to trusted sites*'
        }

        It 'Reads noSort on dropdown lists' {
            ((Get-TestPolicy 'AxISURLZonePolicies').Elements | Where-Object Id -EQ 'InstallTrustedOCX').NoSort | Should -BeTrue
        }
    }
}
