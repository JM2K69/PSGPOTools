#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Configuration of PSGPOTools (Get-PSGPOConfiguration): the defaults of the module, the
# Configuration.psd1 of the user over them, and what they set for a new GPO.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $Before = $env:PSGPOTOOLS_CONFIGURATION_PATH
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Samples' 'Directory.sample.json'
        function Set-UserConfiguration {
            param([string]$Content)
            $env:PSGPOTOOLS_CONFIGURATION_PATH = Join-Path $TestDrive "Configuration-$([guid]::NewGuid()).psd1"
            if ($Content) { Set-Content -LiteralPath $env:PSGPOTOOLS_CONFIGURATION_PATH -Value $Content }
        }
    }
    AfterAll { $env:PSGPOTOOLS_CONFIGURATION_PATH = $Before }

    Describe 'Configuration of PSGPOTools' {
        It 'Has the defaults of the module when the user has no configuration' {
            Set-UserConfiguration $null
            $Read = Get-PSGPOConfiguration
            $Read.UserFileExists | Should -BeFalse
            $Read.DefaultPath | Should -BeLike '*Resources*Configuration.psd1'
            $Groups = $Read.Configuration.NewGpo.SecurityFilteringGroups
            $Groups.Create | Should -BeFalse
            $Groups.ApplyPrefix | Should -Be 'APPLY_'
            $Groups.DenyPrefix | Should -Be 'DENY_'
            $Groups.Scope | Should -Be 'Global'
            $Read.Configuration.NewGpo.Status | Should -Be 'Enabled'
        }

        It 'Takes the keys of the configuration of the user, the others keeping their default' {
            Set-UserConfiguration "@{ NewGpo = @{ Status = 'ComputerOnly'; SecurityFilteringGroups = @{ Create = `$true; ApplyPrefix = 'GPO-A-'; Scope = 'DomainLocal' } } }"
            $Read = Get-PSGPOConfiguration
            $Read.UserFileExists | Should -BeTrue
            $Read.Configuration.NewGpo.Status | Should -Be 'ComputerOnly'
            $Read.Configuration.NewGpo.DefaultName | Should -Be 'New Group Policy Object'
            $Groups = $Read.Configuration.NewGpo.SecurityFilteringGroups
            "$($Groups.Create) $($Groups.ApplyPrefix) $($Groups.DenyPrefix) $($Groups.Scope)" | Should -Be 'True GPO-A- DENY_ DomainLocal'
            Get-PSGPOFilteringGroupName -Role Apply -GpoName 'Proxy' | Should -Be 'GPO-A-Proxy'
        }

        It 'Leaves out a configuration that <Case>, and says why' -ForEach @(
            @{ Case = 'has an unknown setting'; Content = "@{ NewGpo = @{ Colour = 'blue' } }"; Message = '*Unknown setting NewGpo.Colour*' }
            @{ Case = 'has a wrong scope'; Content = "@{ NewGpo = @{ SecurityFilteringGroups = @{ Scope = 'Forest' } } }"; Message = "*Scope must be Global, DomainLocal or Universal, not 'Forest'*" }
            @{ Case = 'has a prefix a group name cannot hold'; Content = "@{ NewGpo = @{ SecurityFilteringGroups = @{ DenyPrefix = 'DENY:' } } }"; Message = '*DenyPrefix must not be empty, nor hold*' }
            @{ Case = 'runs code'; Content = "@{ NewGpo = @{ DefaultName = (Get-Date) } }"; Message = '*is not used*' }
            @{ Case = 'is not PowerShell data'; Content = "@{ NewGpo = "; Message = '*is not used*' }
        ) {
            Set-UserConfiguration $Content
            $Output = @(Get-PSGPOConfigurationData 3>&1)
            "$($Output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })" | Should -BeLike $Message
            ($Output | Where-Object { $_ -is [hashtable] }).NewGpo.SecurityFilteringGroups.Scope | Should -Be 'Global' -Because 'the defaults apply'
        }

        It 'Makes the container of the groups a distinguished name of the domain' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            Resolve-PSGPOGroupContainer -Directory $Directory -Container '' | Should -Be 'CN=Users,DC=corp,DC=contoso,DC=com'
            Resolve-PSGPOGroupContainer -Directory $Directory -Container 'OU=GPO,OU=Groups' | Should -Be 'OU=GPO,OU=Groups,DC=corp,DC=contoso,DC=com'
            Resolve-PSGPOGroupContainer -Directory $Directory -Container 'OU=GPO,DC=other,DC=com' | Should -Be 'OU=GPO,DC=other,DC=com'
        }

        It 'Creates the groups of a new GPO with the prefixes and in the container of the configuration' {
            Set-UserConfiguration "@{ NewGpo = @{ SecurityFilteringGroups = @{ Container = 'OU=Servers'; ApplyPrefix = 'GPO-A-'; DenyPrefix = 'GPO-D-' } } }"
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Groups = $Directory.NewFilteringGroups($Directory.FindGpo('C - Servers - Security Baseline'), $null)
            @($Groups.DistinguishedName) | Should -Be @(
                'CN=GPO-A-C - Servers - Security Baseline,OU=Servers,DC=corp,DC=contoso,DC=com'
                'CN=GPO-D-C - Servers - Security Baseline,OU=Servers,DC=corp,DC=contoso,DC=com')
        }

        It 'Creates a security group of the scope of the configuration, with its description' {
            Set-UserConfiguration "@{ NewGpo = @{ SecurityFilteringGroups = @{ Scope = 'DomainLocal'; ApplyDescription = 'Apply {0} (Tier 1)' } } }"
            $script:Requests = [System.Collections.Generic.List[object]]::new()
            Mock New-PSGPODirectoryConnection {
                $Connection = [pscustomobject]@{}
                $Connection | Add-Member -MemberType ScriptMethod -Name SendRequest -Value { param($Request) $script:Requests.Add($Request); throw 'stop after the request' }
                $Connection | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
                $Connection
            }
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Gpo = [GPOToolsGpo]@{ DisplayName = 'Proxy' }
            { New-PSGPODomainFilteringGroup -Directory $Directory -Gpo $Gpo -Container 'CN=Users,DC=contoso,DC=com' } | Should -Throw
            $Add = $script:Requests[0]
            $Add.DistinguishedName | Should -Be 'CN=APPLY_Proxy,CN=Users,DC=contoso,DC=com'
            ($Add.Attributes | Where-Object Name -EQ 'groupType').GetValues([string]) | Should -Be '-2147483644'
            ($Add.Attributes | Where-Object Name -EQ 'description').GetValues([string]) | Should -Be 'Apply Proxy (Tier 1)'
        }
    }
}
