#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Configuration of HGPM (Get-PSGPOConfiguration): the defaults of the module, the
# configuration of the domain over them (SYSVOL\<domain>\PSGPOTools\Configuration.psd1, here in a
# directory in memory), and what they set for a new GPO.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        # A domain in memory with the configuration $Content (none when empty), in use.
        function Set-DomainConfiguration {
            param([string]$Content)
            $script:Domain = Import-PSGPODirectory -Path $SamplePath
            if ($Content) { $script:Domain.WriteConfigurationFile([System.Text.Encoding]::UTF8.GetBytes($Content)) }
            Use-PSGPODomainConfiguration -Directory $script:Domain -Force
            $script:Domain
        }
    }
    AfterAll { Use-PSGPODomainConfiguration -Directory $null }

    Describe 'Configuration of PSGPOTools' {
        It 'Has the defaults of the module when the domain has no configuration, or without a domain' {
            Use-PSGPODomainConfiguration -Directory $null
            (Get-PSGPOConfiguration).Domain | Should -BeNullOrEmpty
            $Domain = Set-DomainConfiguration $null
            $Read = Get-PSGPOConfiguration
            $Read.Domain | Should -Be 'corp.contoso.com'
            $Read.DomainFileExists | Should -BeFalse
            $Read.DefaultPath | Should -BeLike '*Resources*Configuration.psd1'
            $Groups = $Read.Configuration.NewGpo.SecurityFilteringGroups
            $Groups.Create | Should -BeFalse
            $Groups.ApplyPrefix | Should -Be 'APPLY_'
            $Groups.DenyPrefix | Should -Be 'DENY_'
            $Groups.Scope | Should -Be 'Global'
            $Read.Configuration.NewGpo.Status | Should -Be 'Enabled'
        }

        It 'Takes the keys of the configuration of the domain, the others keeping their default' {
            $Domain = Set-DomainConfiguration "@{ NewGpo = @{ Status = 'ComputerOnly'; SecurityFilteringGroups = @{ Create = `$true; ApplyPrefix = 'GPO-A-'; Scope = 'DomainLocal' } } }"
            $Read = Get-PSGPOConfiguration
            $Read.DomainFileExists | Should -BeTrue
            $Read.DomainPath | Should -BeLike 'SYSVOL\corp.contoso.com\PSGPOTools\Configuration.psd1*'

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
            @{ Case = 'shows what is not managed with a text'; Content = "@{ View = @{ ShowUnmanaged = 'no' } }"; Message = '*View.ShowUnmanaged must be $true or $false*' }
            @{ Case = 'runs code'; Content = "@{ NewGpo = @{ DefaultName = (Get-Date) } }"; Message = ' it is not PowerShell data: Cannot generate a PowerShell object for a ScriptBlock evaluating dynamic expressions*' }
            @{ Case = 'is not PowerShell data'; Content = "@{ NewGpo = "; Message = " it is not PowerShell data: The file 'Configuration.psd1' could not be parsed*" }
        ) {
            $Output = @(Set-DomainConfiguration $Content 3>&1)
            "$($Output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })" | Should -BeLike "The configuration of the domain SYSVOL\corp.contoso.com\PSGPOTools\Configuration.psd1*is not used:$Message"
            (Get-PSGPOConfiguration).Problem | Should -Not -BeNullOrEmpty
            (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups.Scope | Should -Be 'Global' -Because 'the defaults apply'
        }

        It 'Saves the configuration of the domain, checked first, and reads it again' {
            $Domain = Set-DomainConfiguration $null
            { Save-PSGPODomainConfiguration -Directory $Domain -Values @{ 'NewGpo.Status' = 'Sometimes' } } | Should -Throw '*Status must be Enabled*'
            $Domain.ReadConfigurationFile() | Should -BeNullOrEmpty -Because 'nothing is written when a value is wrong'
            Save-PSGPODomainConfiguration -Directory $Domain -Values @{ 'NewGpo.Status' = 'UserOnly'; 'Backup.TemplateLabel' = 'Model' }
            $Text = [System.Text.Encoding]::UTF8.GetString($Domain.ReadConfigurationFile())
            $Text | Should -BeLike '# Configuration of HGPM for the domain corp.contoso.com, for every console of the domain*'
            (Get-PSGPOConfigurationData).NewGpo.Status | Should -Be 'UserOnly'
            Get-PSGPOTemplateLabel | Should -Be 'Model'
            Save-PSGPODomainConfiguration -Directory $Domain -Values @{}
            $Text = [System.Text.Encoding]::UTF8.GetString($Domain.ReadConfigurationFile())
            $Text | Should -BeLike '# Configuration of HGPM*@{*}*' -Because 'no value: an empty configuration, the file stays'
            (ConvertFrom-PSGPOConfigurationByte -Bytes $Domain.ReadConfigurationFile()).Count | Should -Be 0
            (Get-PSGPOConfigurationData).NewGpo.Status | Should -Be 'Enabled'
        }

        It 'Creates the configuration of the domain at the first start, for an administrator of the domain only' {
            $Domain = Set-DomainConfiguration $null
            $Domain.IsDomainAdministrator = $false
            Initialize-PSGPODomainConfiguration -Directory $Domain | Should -BeFalse
            $Domain.ReadConfigurationFile() | Should -BeNullOrEmpty -Because 'only an administrator of the domain writes it'
            $Domain.IsDomainAdministrator = $true
            $Domain.IsReadOnly = $true
            Initialize-PSGPODomainConfiguration -Directory $Domain | Should -BeFalse
            $Domain.ReadConfigurationFile() | Should -BeNullOrEmpty
            $Domain.IsReadOnly = $false

            Initialize-PSGPODomainConfiguration -Directory $Domain | Should -BeTrue
            (ConvertFrom-PSGPOConfigurationByte -Bytes $Domain.ReadConfigurationFile()).Count | Should -Be 0 -Because 'every setting has its default'
            (Get-PSGPOConfiguration).DomainFileExists | Should -BeTrue

            # Created once: the settings saved later are kept.
            Save-PSGPODomainConfiguration -Directory $Domain -Values @{ 'NewGpo.Status' = 'UserOnly' }
            Initialize-PSGPODomainConfiguration -Directory $Domain | Should -BeFalse
            (Get-PSGPOConfigurationData).NewGpo.Status | Should -Be 'UserOnly'
        }

        It 'Leaves a configuration that cannot be read as it is' {
            $Domain = Set-DomainConfiguration 'not data ('
            Initialize-PSGPODomainConfiguration -Directory $Domain 3>$null | Should -BeFalse
            [System.Text.Encoding]::UTF8.GetString($Domain.ReadConfigurationFile()) | Should -Be 'not data ('
        }

        It 'Knows an administrator of the domain by the SIDs of Domain Admins, Enterprise Admins or Administrators' -ForEach @(
            @{ Sids = @('S-1-5-21-1-2-3-1105', 'S-1-5-21-1-2-3-512'); Expected = $true }
            @{ Sids = @('S-1-5-21-1-2-3-1105', 'S-1-5-21-9-8-7-519'); Expected = $true }
            @{ Sids = @('S-1-5-21-1-2-3-1105', 'S-1-5-32-544'); Expected = $true }
            @{ Sids = @('S-1-5-21-1-2-3-1105', 'S-1-5-21-1-2-3-513', 'S-1-5-21-1-2-3-5120'); Expected = $false }
        ) {
            Mock Get-PSGPOAccountGroupSid { , [string[]]$Sids }
            Test-PSGPODomainAdministrator -Connection 'ldap' -DomainDistinguishedName 'DC=contoso,DC=com' -Account 'CONTOSO\user1' | Should -Be $Expected
        }

        It 'Is not an administrator when its groups cannot be read, or without an account' {
            Mock Get-PSGPOAccountGroupSid { throw 'no access' }
            Test-PSGPODomainAdministrator -Connection 'ldap' -DomainDistinguishedName 'DC=contoso,DC=com' -Account 'CONTOSO\user1' | Should -BeFalse
            Test-PSGPODomainAdministrator -Connection 'ldap' -DomainDistinguishedName 'DC=contoso,DC=com' -Account 'Anonymous' | Should -BeFalse
        }

        It 'Reads the configuration of the domain of the directory used, not of another' {
            $First = Set-DomainConfiguration "@{ NewGpo = @{ DefaultName = 'First' } }"
            $Second = Import-PSGPODirectory -Path $SamplePath
            (Get-PSGPOConfigurationData).NewGpo.DefaultName | Should -Be 'New Group Policy Object' -Because 'the directory read last has no configuration'
            Use-PSGPODomainConfiguration -Directory $First
            (Get-PSGPOConfigurationData).NewGpo.DefaultName | Should -Be 'First'
        }

        It 'Reads and writes the configuration in the SYSVOL share of the domain controller' {
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Directory.GetConfigurationPath() | Should -Be '\\dc1.contoso.com\SYSVOL\contoso.com\PSGPOTools\Configuration.psd1'
            Mock Read-PSGPOSysvolItem { , [byte[]](64, 123, 125) }
            Mock Write-PSGPOSysvolItem { }
            Mock Remove-PSGPOSysvolItem { }
            [System.Text.Encoding]::ASCII.GetString($Directory.ReadConfigurationFile()) | Should -Be '@{}'
            Should -Invoke Read-PSGPOSysvolItem -Times 1 -Exactly -ParameterFilter { $Share -eq 'SYSVOL' -and $Path -eq 'contoso.com\PSGPOTools\Configuration.psd1' }
            $Directory.WriteConfigurationFile([byte[]](1, 2))
            Should -Invoke Write-PSGPOSysvolItem -Times 1 -Exactly -ParameterFilter { $Share -eq 'SYSVOL' -and $Base -eq 'contoso.com' -and $Path -eq 'PSGPOTools\Configuration.psd1' }
            $Directory.WriteConfigurationFile($null)
            Should -Invoke Remove-PSGPOSysvolItem -Times 1 -Exactly -ParameterFilter { $Path -eq 'contoso.com\PSGPOTools\Configuration.psd1' }

            Mock Write-PSGPOSysvolItem { throw 'smbclient //dc1/SYSVOL failed: NT_STATUS_ACCESS_DENIED' }
            $Directory.Account = 'CONTOSO\tech1'
            { Save-PSGPODomainConfiguration -Directory $Directory -Values @{ 'NewGpo.Status' = 'UserOnly' } } |
                Should -Throw -ExpectedMessage 'The account CONTOSO\tech1 cannot write the configuration of the domain*only the administrators of the domain can*'
        }

        It 'Makes the container of the groups a distinguished name of the domain' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            Resolve-PSGPOGroupContainer -Directory $Directory -Container '' | Should -Be 'CN=Users,DC=corp,DC=contoso,DC=com'
            Resolve-PSGPOGroupContainer -Directory $Directory -Container 'OU=GPO,OU=Groups' | Should -Be 'OU=GPO,OU=Groups,DC=corp,DC=contoso,DC=com'
            Resolve-PSGPOGroupContainer -Directory $Directory -Container 'OU=GPO,DC=other,DC=com' | Should -Be 'OU=GPO,DC=other,DC=com'
        }

        It 'Creates the groups of a new GPO with the prefixes and in the container of the configuration' {
            $Directory = Set-DomainConfiguration "@{ NewGpo = @{ SecurityFilteringGroups = @{ Container = 'OU=Servers'; ApplyPrefix = 'GPO-A-'; DenyPrefix = 'GPO-D-' } } }"
            $Groups = $Directory.NewFilteringGroups($Directory.FindGpo('C - Servers - Security Baseline'), $null)
            @($Groups.DistinguishedName) | Should -Be @(
                'CN=GPO-A-C - Servers - Security Baseline,OU=Servers,DC=corp,DC=contoso,DC=com'
                'CN=GPO-D-C - Servers - Security Baseline,OU=Servers,DC=corp,DC=contoso,DC=com')
        }

        It 'Creates a security group of the scope of the configuration, with its description' {
            $null = Set-DomainConfiguration "@{ NewGpo = @{ SecurityFilteringGroups = @{ Scope = 'DomainLocal'; ApplyDescription = 'Apply {0} (Tier 1)' } } }"
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
