#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Platform detection and reading of the directory over LDAP (Get-PSGPODirectory). The model is
# built from LDAP search entries without a server; the tests against a real domain controller
# run only when PSGPOTOOLS_TEST_LDAP_SERVER names one (with a Kerberos ticket on Linux):
#   PSGPOTOOLS_TEST_LDAP_SERVER=dc.hardenbox.labo pwsh -File CI/Invoke-Tests.ps1
# The tests that write to that domain (an OU and a GPO of their own, deleted at the end) also
# need PSGPOTOOLS_TEST_LDAP_WRITE=1, samba-tool and an account allowed to create GPOs.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    # Evaluated during discovery, in the module scope (see PSGPOTools.Gui.tests.ps1).
    $LdapServer = $env:PSGPOTOOLS_TEST_LDAP_SERVER
    $LdapWrite = $LdapServer -and $env:PSGPOTOOLS_TEST_LDAP_WRITE -eq '1'

    BeforeAll {
        . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')

        function Write-TestFile {
            param([string]$Name, [string]$Content)
            $File = Join-Path $TestDrive $Name
            Set-Content -LiteralPath $File -Value $Content -Encoding utf8
            $File
        }
    }

    Describe 'Samba and Kerberos configuration' {
        It 'Reads the [global] parameters of smb.conf with normalized names' {
            $File = Write-TestFile 'smb.conf' @'
# Global parameters
[global]
	netbios name = DC
	Server Role = active directory domain controller
	realm = hardenbox.labo
	; a comment
	dns forwarder = 1.1.1.1 \
	    1.0.0.1
	idmap_ldb:use rfc2307 = yes

[sysvol]
	path = /var/lib/samba/sysvol
	realm = not.global
'@
            $Config = Read-PSGPOSambaConfig -Path $File
            $Config['serverrole'] | Should -Be 'active directory domain controller'
            $Config['realm'] | Should -Be 'hardenbox.labo'
            $Config['dnsforwarder'] | Should -Be '1.1.1.1 1.0.0.1'
            $Config['netbiosname'] | Should -Be 'DC'
            $Config.ContainsKey('path') | Should -BeFalse
        }

        It 'Returns nothing for a missing smb.conf' {
            (Read-PSGPOSambaConfig -Path (Join-Path $TestDrive 'none.conf')).Count | Should -Be 0
        }

        It 'Reads the default realm of krb5.conf' {
            $File = Write-TestFile 'krb5.conf' @'
[realms]
    default_realm = NOT.THIS
[libdefaults]
    default_realm = HARDENBOX.LABO
    dns_lookup_kdc = true
'@
            Get-PSGPOKerberosDefaultRealm -Path $File | Should -Be 'HARDENBOX.LABO'
            Get-PSGPOKerberosDefaultRealm -Path (Join-Path $TestDrive 'none.conf') | Should -BeNullOrEmpty
        }

        It 'Detects a Samba domain controller (<Role>)' -ForEach @(
            @{ Role = 'active directory domain controller' }
            @{ Role = 'Active Directory Domain Controller' }
            @{ Role = 'dc' }
        ) {
            $Smb = Write-TestFile 'smb-dc.conf' "[global]`n server role = $Role`n realm = HARDENBOX.LABO"
            $Result = Resolve-PSGPOUnixPlatform -SmbConfPath $Smb -Krb5ConfPath (Join-Path $TestDrive 'none.conf')
            $Result.IsDomainController | Should -BeTrue
            $Result.DomainControllerType | Should -Be 'Samba'
            $Result.Realm | Should -Be 'HARDENBOX.LABO'
            $Result.DomainName | Should -Be 'hardenbox.labo'
        }

        It 'Detects a domain member, its realm from smb.conf or else from krb5.conf' {
            $Member = Write-TestFile 'smb-member.conf' "[global]`n security = ads`n realm = corp.contoso.com"
            $Krb5 = Write-TestFile 'krb5-other.conf' "[libdefaults]`n default_realm = OTHER.LAN"
            $Result = Resolve-PSGPOUnixPlatform -SmbConfPath $Member -Krb5ConfPath $Krb5
            $Result.IsDomainController | Should -BeFalse
            $Result.DomainName | Should -Be 'corp.contoso.com'

            $Result = Resolve-PSGPOUnixPlatform -SmbConfPath (Join-Path $TestDrive 'none.conf') -Krb5ConfPath $Krb5
            $Result.Realm | Should -Be 'OTHER.LAN'
            $Result.DomainName | Should -Be 'other.lan'

            $Result = Resolve-PSGPOUnixPlatform -SmbConfPath (Join-Path $TestDrive 'none.conf') -Krb5ConfPath (Join-Path $TestDrive 'none.conf')
            $Result.DomainName | Should -BeNullOrEmpty
        }
    }

    Describe 'Get-PSGPOPlatform' {
        AfterAll { $script:PSGPOPlatform = $null }

        It 'Detects the operating system of this computer and keeps the result in the module scope' {
            $Platform = Get-PSGPOPlatform -Force
            $Platform | Should -BeOfType ([GPOToolsPlatform])
            $Platform.OperatingSystem | Should -Be $(if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' })
            $Platform.ComputerName | Should -Be ([Environment]::MachineName)
            $script:PSGPOPlatform | Should -Be $Platform
            Get-PSGPOPlatform | Should -Be $Platform -Because 'the platform is detected once'
            Get-PSGPOPlatform -Force | Should -Not -Be $Platform
        }

        It 'Finds the LDAP library, or says what to install' {
            $Platform = Get-PSGPOPlatform -Force
            if ($Platform.LdapAvailable) { $Platform.LdapUnavailableReason | Should -BeNullOrEmpty }
            else { $Platform.LdapUnavailableReason | Should -BeLike '*libldap*' }
            if ($IsWindows) { $Platform.LdapAvailable | Should -BeTrue }
        }

        It 'Reads the system description and the addresses of this computer' {
            $Platform = Get-PSGPOPlatform -Force
            $Platform.OperatingSystemDescription | Should -Be ([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)
            foreach ($Address in $Platform.IPAddresses) {
                [System.Net.IPAddress]::Parse($Address) | Should -Not -BeNullOrEmpty
                [System.Net.IPAddress]::IsLoopback([System.Net.IPAddress]::Parse($Address)) | Should -BeFalse
                $Address | Should -Not -BeLike 'fe80:*'
            }
        }

        It 'Describes the platform in one line' {
            $Platform = [GPOToolsPlatform]@{ ComputerName = 'dc'; OperatingSystem = 'Linux'; DomainName = 'hardenbox.labo'; IsDomainController = $true; DomainControllerType = 'Samba' }
            "$Platform" | Should -Be 'dc (Linux, Samba domain controller of hardenbox.labo)'
            "$([GPOToolsPlatform]@{ ComputerName = 'pc'; OperatingSystem = 'Windows' })" | Should -Be 'pc (Windows, not in a domain)'
        }
    }

    Describe 'gPLink' {
        It 'Reads the links by link order: the last entry is link order 1' {
            $Links = [GPOToolsGpoLink]::Parse('[LDAP://cn={A},cn=policies,cn=system,DC=x;0][LDAP://cn={B},cn=policies,cn=system,DC=x;2][ldap://cn={C},cn=policies,cn=system,DC=x;1]')
            @($Links.Order) | Should -Be @(1, 2, 3)
            @($Links.GpoDistinguishedName) | Should -Be @('cn={C},cn=policies,cn=system,DC=x', 'cn={B},cn=policies,cn=system,DC=x', 'cn={A},cn=policies,cn=system,DC=x')
            $Links[0].Enabled | Should -BeFalse
            $Links[1].Enforced | Should -BeTrue
            $Links[1].Enabled | Should -BeTrue
            $Links[2].Enabled | Should -BeTrue
            $Links[2].Enforced | Should -BeFalse
        }

        It 'Reads a disabled and enforced link (options 3) as disabled and enforced' {
            $Link = [GPOToolsGpoLink]::Parse('[LDAP://cn={A},DC=x;3]')[0]
            $Link.Enabled | Should -BeFalse
            $Link.Enforced | Should -BeTrue
        }

        It 'Reads no link from an empty or blank gPLink, and ignores what is not a link' {
            [GPOToolsGpoLink]::Parse('').Count | Should -Be 0
            [GPOToolsGpoLink]::Parse(' ').Count | Should -Be 0
            [GPOToolsGpoLink]::Parse($null).Count | Should -Be 0
            [GPOToolsGpoLink]::Parse('[LDAP://cn={A},DC=x;0] garbage [cn={B};1]').Count | Should -Be 1
        }
    }

    Describe 'Directory read over LDAP' {
        BeforeAll {
            $Directory = New-TestLdapDirectory
            $Lyon = $Directory.FindSom("OU=Lyon,$TestLdapDomainDN")
            $Workstations = $Directory.FindSom("OU=Workstations,OU=Lyon,$TestLdapDomainDN")
        }

        It 'Reads the domain' {
            $Directory | Should -BeOfType ([GPOToolsLdapDirectory])
            $Directory.DomainName | Should -Be 'hardenbox.labo'
            $Directory.Domain.DistinguishedName | Should -Be $TestLdapDomainDN
            $Directory.Server | Should -Be 'dc.hardenbox.labo'
            $Directory.IsReadOnly | Should -BeFalse
            $Directory.Source | Should -Be 'read over LDAP from dc.hardenbox.labo (Samba AD)'
            $Directory.ServerType | Should -Be 'Samba AD'
        }

        It 'Reads the GPOs, their versions, status and SYSVOL path' {
            $Directory.Gpos.Count | Should -Be 5
            $Default = $Directory.Gpos | Where-Object Id -EQ ([guid]$TestLdapDefaultDomainPolicy)
            $Default.DisplayName | Should -Be 'Default Domain Policy'
            $Default.FileSysPath | Should -Be "\\hardenbox.labo\sysvol\hardenbox.labo\Policies\$TestLdapDefaultDomainPolicy"
            $Default.GetComputerVersion() | Should -Be 3
            $Workstation = $Directory.Gpos | Where-Object Id -EQ ([guid]$TestLdapWorkstationsPolicy)
            $Workstation.GetUserVersion() | Should -Be 2
            $Workstation.GetComputerVersion() | Should -Be 2
            $Workstation.GetStatus() | Should -Be 'User configuration settings disabled'
        }

        It 'Keeps GPOs with the same name, and names a GPO without display name after its GUID' {
            @($Directory.Gpos | Where-Object DisplayName -EQ 'Workstations').Count | Should -Be 2
            ($Directory.Gpos | Where-Object Id -EQ ([guid]'8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E32')).DisplayName | Should -Be '{8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E32}'
        }

        It 'Warns about the containers that are not GPOs and the OUs outside the domain tree' {
            $Set = Get-TestLdapEntrySet
            $null = ConvertTo-PSGPOLdapDirectory -Server 'dc' -DomainEntry $Set.Domain -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos -WarningVariable Warnings 3>$null
            $Warnings.Count | Should -Be 2
            $Warnings[0] | Should -BeLike '*not a GUID: CN=NotAGuid,*'
            $Warnings[1] | Should -BeLike '*parent is not the domain or an OU: OU=Orphan,CN=Users,*'
        }

        It 'Builds the OU tree whatever the order of the entries, sorted by name' {
            @($Directory.Domain.Children.Name) | Should -Be @('Domain Controllers', 'Lyon', 'Sales, Paris')
            @($Lyon.Children.Name) | Should -Be @('Workstations')
            $Workstations.Children[0].Name | Should -Be 'Laptops'
            $Workstations.Children[0].Parent | Should -Be $Workstations
            $Directory.FindSom("OU=Sales\, Paris,$TestLdapDomainDN").Name | Should -Be 'Sales, Paris'
            $Workstations.BlockInheritance | Should -BeTrue
            $Lyon.BlockInheritance | Should -BeFalse
        }

        It 'Resolves the links whatever the case of their DN, and keeps a link to a missing GPO' {
            $Directory.Domain.Links.Count | Should -Be 1
            $Directory.Domain.Links[0].Gpo.DisplayName | Should -Be 'Default Domain Policy'

            @($Workstations.Links.Order) | Should -Be @(1, 2)
            $Workstations.Links[0].Gpo.Id | Should -Be ([guid]$TestLdapWorkstationsPolicy)
            $Workstations.Links[0].Enforced | Should -BeTrue
            $Missing = $Workstations.Links[1]
            $Missing.Gpo | Should -BeNullOrEmpty
            $Missing.Enabled | Should -BeFalse
            $Missing.GetDisplayName() | Should -Be "GPO not found ($(Get-TestLdapGpoDN $TestLdapMissingPolicy))"
            $Missing.GetStatus() | Should -Be 'GPO not found'
        }

        It 'Shows a link to a missing GPO in the tree and the details, without GPO to edit' {
            $Roots = New-PSGPODirectoryTree -Directory $Directory
            $Node = $Roots[0].Children | Where-Object Header -EQ 'Lyon' | ForEach-Object Children | Where-Object Header -Like 'Workstations*' |
                ForEach-Object Children | Where-Object { $_.Tag -is [GPOToolsGpoLink] -and -not $_.Tag.Gpo }
            $Node.Header | Should -Be "GPO not found ($(Get-TestLdapGpoDN $TestLdapMissingPolicy)) (link disabled)"
            $Node.Icon | Should -Be 'link-dismiss'

            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Node.Tag
            $Detail.Gpo | Should -BeNullOrEmpty
            $Detail.Title | Should -BeLike 'GPO not found*'
            ($Detail.Properties | Where-Object Key -EQ 'Link order').Value | Should -Be '2'

            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Workstations
            @($Detail.Links.Status) | Should -Be @('User configuration settings disabled', 'GPO not found')
        }

    }

    Describe 'Directory service of the domain controller' {
        It 'Is <Expected> for the vendor name "<Vendor>"' -ForEach @(
            @{ Vendor = 'Samba Team (https://www.samba.org)'; Expected = 'Samba AD' }
            @{ Vendor = ''; Expected = 'Active Directory' }
            @{ Vendor = $null; Expected = 'Active Directory' }
        ) {
            [GPOToolsLdapDirectory]::GetServerType($Vendor) | Should -Be $Expected
        }

        It 'Shows the domain controller and its directory service in the details of the domain' {
            $Directory = New-TestLdapDirectory
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Directory.Domain
            ($Detail.Properties | Where-Object Key -EQ 'Domain controller').Value | Should -Be 'dc.hardenbox.labo'
            ($Detail.Properties | Where-Object Key -EQ 'Directory service').Value | Should -Be 'Samba AD'
        }
    }

    Describe 'Status bar' {
        BeforeAll {
            $SambaDc = [GPOToolsPlatform]@{
                ComputerName = 'dc'; OperatingSystem = 'Linux'; OperatingSystemDescription = 'Debian GNU/Linux 13 (trixie)'
                IPAddresses = @('10.0.0.51', '2001:db8::51'); DomainName = 'hardenbox.labo'; IsDomainController = $true; DomainControllerType = 'Samba'
            }
            $Workstation = [GPOToolsPlatform]@{ ComputerName = 'pc'; OperatingSystem = 'Windows'; OperatingSystemDescription = 'Microsoft Windows 10.0.26300' }
        }

        It 'Shows a Samba domain controller reading its own domain' {
            $Items = @(Get-PSGPOStatusBarItem -Platform $SambaDc -Directory (New-TestLdapDirectory))
            @($Items.Text) | Should -Be @(
                'dc - Debian GNU/Linux 13 (trixie) (Samba domain controller)'
                'IP 10.0.0.51, 2001:db8::51'
                'Domain hardenbox.labo'
                'DC dc.hardenbox.labo (Samba AD)')
            $Items[0].ToolTip | Should -Be 'This computer: dc (Linux, Samba domain controller of hardenbox.labo)'
            $Items[3].ToolTip | Should -Be 'Directory read over LDAP from dc.hardenbox.labo (Samba AD)'
            $Items | ForEach-Object { $_.IconData | Should -Match '^F1 M' }
        }

        It 'Shows <Case>' -ForEach @(
            @{ Case = 'the demonstration directory'; Demo = $true; Error = $null; Expected = 'No domain controller: demonstration directory' }
            @{ Case = 'an offline directory'; Demo = $false; Error = $null; Expected = 'No domain controller: corp.contoso.com offline' }
            @{ Case = 'a domain that could not be read'; Demo = $null; Error = 'LDAP connection failed'; Expected = 'Domain controller not reached' }
            @{ Case = 'no directory'; Demo = $null; Error = $null; Expected = 'No directory read' }
        ) {
            $Directory = if ($null -ne $Demo) { Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Samples' 'Directory.sample.json') }
            if ($Demo) { $Directory.IsDemonstration = $true }
            $Items = @(Get-PSGPOStatusBarItem -Platform $Workstation -Directory $Directory -DirectoryError $Error)
            $Items[3].Text | Should -Be $Expected
            if ($Error) { $Items[3].ToolTip | Should -Be $Error }
        }

        It 'Shows a computer outside a domain without network address' {
            $Items = @(Get-PSGPOStatusBarItem -Platform $Workstation)
            @($Items.Text) | Should -Be @('pc - Microsoft Windows 10.0.26300', 'No network address', 'Not in a domain', 'No directory read')
        }
    }

    Describe 'Show-GPOManagerAvalonia at launch' {
        BeforeEach {
            $script:Opened = $null
            Mock Start-PSGPOManagerWindow { $script:Opened = @{ Directory = $Directory; DirectoryError = $DirectoryError; StartView = $StartView } }
            Mock Get-PSGPODirectory { New-TestLdapDirectory }
        }
        AfterAll { $script:PSGPOPlatform = $null }

        It 'Reads the domain of the computer and opens on it' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Linux'; DomainName = 'hardenbox.labo' } }
            Show-GPOManagerAvalonia
            Should -Invoke Get-PSGPODirectory -Times 1 -Exactly -ParameterFilter { -not $Server -and -not $Credential -and -not $UseSsl }
            $script:Opened.Directory.DomainName | Should -Be 'hardenbox.labo'
            $script:Opened.StartView | Should -Be 'Management'
            $script:Opened.DirectoryError | Should -BeNullOrEmpty
        }

        It 'Shows the sample directory as a demonstration when no domain is discovered' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Windows' } }
            Show-GPOManagerAvalonia
            Should -Invoke Get-PSGPODirectory -Times 0 -Exactly
            $script:Opened.Directory.DomainName | Should -Be 'corp.contoso.com'
            $script:Opened.Directory.IsDemonstration | Should -BeTrue
            $script:Opened.DirectoryError | Should -BeNullOrEmpty
        }

        It 'Opens without directory, and warns, when the sample directory cannot be read' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Linux' } }
            Mock Import-PSGPODirectory { throw 'file not found' }
            Show-GPOManagerAvalonia -WarningVariable Warnings 3>$null
            $Warnings | Should -BeLike '*demonstration directory cannot be read: file not found'
            $script:Opened.Directory | Should -BeNullOrEmpty
        }

        It 'Reads the domain of -Server with -Credential and -UseSsl, even outside a domain' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Windows' } }
            $Credential = [pscredential]::new('administrator', (ConvertTo-SecureString 'not-used' -AsPlainText -Force))
            Show-GPOManagerAvalonia -Server 'dc.hardenbox.labo' -Credential $Credential -UseSsl
            Should -Invoke Get-PSGPODirectory -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'dc.hardenbox.labo' -and $Credential.UserName -eq 'administrator' -and $UseSsl
            }
            $script:Opened.Directory | Should -Not -BeNullOrEmpty
        }

        It 'Opens with the reason, not the demonstration, when the domain cannot be read, and warns' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Linux'; DomainName = 'hardenbox.labo' } }
            Mock Get-PSGPODirectory { throw 'LDAP connection to dc.hardenbox.labo:389 failed: no ticket' }
            Show-GPOManagerAvalonia -WarningVariable Warnings 3>$null
            $Warnings | Should -BeLike '*could not be read: LDAP connection to dc.hardenbox.labo:389 failed: no ticket'
            # Sample data next to a domain that exists would mislead.
            $script:Opened.Directory | Should -BeNullOrEmpty
            $script:Opened.DirectoryError | Should -Be 'LDAP connection to dc.hardenbox.labo:389 failed: no ticket'
        }

        It 'Shows the given directory without detecting anything' {
            Mock Get-PSGPOPlatform { throw 'not expected' }
            $Given = [GPOToolsDirectory]::new('offline.test')
            Show-GPOManagerAvalonia -Directory $Given
            Should -Invoke Get-PSGPOPlatform -Times 0 -Exactly
            Should -Invoke Get-PSGPODirectory -Times 0 -Exactly
            $script:Opened.Directory | Should -Be $Given
        }

        It 'Reads nothing with -NoDirectory' {
            Mock Get-PSGPOPlatform { throw 'not expected' }
            Show-GPOManagerAvalonia -NoDirectory
            Should -Invoke Get-PSGPOPlatform -Times 0 -Exactly
            $script:Opened.Directory | Should -BeNullOrEmpty
            $script:Opened.StartView | Should -Be 'Editor'
        }
    }

    Describe 'gPLink formatting' {
        It 'Writes the links with the highest link order first, with their options' {
            $Links = [GPOToolsGpoLink]::Parse('[LDAP://cn={A},DC=x;0][LDAP://cn={B},DC=x;2][LDAP://cn={C},DC=x;1]')
            [GPOToolsGpoLink]::Format($Links) | Should -Be '[LDAP://cn={A},DC=x;0][LDAP://cn={B},DC=x;2][LDAP://cn={C},DC=x;1]'
            [GPOToolsGpoLink]::Format(@()) | Should -Be ''
        }

        It 'Adds a new link with the lowest precedence, first in the value' {
            $Link = [GPOToolsGpoLink]@{ GpoDistinguishedName = 'cn={N},DC=x'; Order = 3 }
            Get-PSGPONewGpLink -Current '[LDAP://cn={A},DC=x;0][LDAP://cn={B},DC=x;2]' -Link $Link | Should -Be '[LDAP://cn={N},DC=x;0][LDAP://cn={A},DC=x;0][LDAP://cn={B},DC=x;2]'
            Get-PSGPONewGpLink -Current $null -Link $Link | Should -Be '[LDAP://cn={N},DC=x;0]'
            Get-PSGPONewGpLink -Current ' ' -Link $Link | Should -Be '[LDAP://cn={N},DC=x;0]'
            $Enforced = [GPOToolsGpoLink]@{ GpoDistinguishedName = 'cn={N},DC=x'; Enforced = $true }
            Get-PSGPONewGpLink -Current '' -Link $Enforced | Should -Be '[LDAP://cn={N},DC=x;2]'
        }

        It 'Refuses a link that the domain already has, whatever the case of its DN' {
            $Link = [GPOToolsGpoLink]@{ GpoDistinguishedName = 'CN={A},DC=X' }
            { Get-PSGPONewGpLink -Current '[LDAP://cn={a},dc=x;0]' -Link $Link } | Should -Throw -ExpectedMessage '*already linked*'
        }
    }

    Describe 'samba-tool' {
        It 'Reads the GUID of the new GPO in the output of gpo create' {
            ConvertFrom-PSGPOSambaToolGpoCreate -Output @('Using temporary directory /tmp/x', "GPO 'Test' created as {8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99}") |
                Should -Be ([guid]'8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99')
            { ConvertFrom-PSGPOSambaToolGpoCreate -Output @('ERROR: something') } | Should -Throw -ExpectedMessage '*did not give the GUID*'
        }

        It 'Says what to install when samba-tool is missing' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Linux' } }
            { Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'listall' } | Should -Throw -ExpectedMessage $(if ($IsWindows) { '*runs on Linux*' } else { '*apt install python3-samba*' })
        }

        It 'Refuses to give a password to samba-tool: the changes use Kerberos' {
            $Directory = New-TestLdapDirectory
            $Directory.Credential = [pscredential]::new('administrator', (ConvertTo-SecureString 'not-used' -AsPlainText -Force))
            { New-PSGPODomainGpo -Directory $Directory -Gpo ([GPOToolsGpo]@{ DisplayName = 'X' }) } | Should -Throw -ExpectedMessage '*uses Kerberos: run kinit administrator*'
        }
    }

    Describe 'Commands of the system' {
        BeforeAll {
            $Pwsh = (Get-Process -Id $PID).Path
        }

        It 'Gives a prompt the end of input instead of waiting for the keyboard' {
            $Watch = [System.Diagnostics.Stopwatch]::StartNew()
            $Result = Invoke-PSGPONativeCommand -FilePath $Pwsh -ArgumentList '-NoProfile', '-Command', '$Line = [Console]::In.ReadLine(); "read: [$Line]"' -TimeoutSeconds 60
            $Result.ExitCode | Should -Be 0
            $Result.Output | Should -Be 'read: []'
            $Watch.Elapsed.TotalSeconds | Should -BeLessThan 30
        }

        It 'Stops a command that does not end in time' {
            $Watch = [System.Diagnostics.Stopwatch]::StartNew()
            { Invoke-PSGPONativeCommand -FilePath $Pwsh -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 60' -TimeoutSeconds 3 } |
                Should -Throw -ExpectedMessage '*did not end within 3 seconds: stopped.'
            $Watch.Elapsed.TotalSeconds | Should -BeLessThan 30
        }

        It 'Returns the exit code, the output and the errors, the arguments passed as they are' {
            $Result = Invoke-PSGPONativeCommand -FilePath $Pwsh -ArgumentList '-NoProfile', '-Command', '"one"; "two words"; [Console]::Error.WriteLine("bad thing"); exit 3'
            $Result.ExitCode | Should -Be 3
            $Result.Output | Should -Be @('one', 'two words')
            $Result.Error.Trim() | Should -Be 'bad thing'
        }

        It 'Never lets samba-tool and smbclient ask for a password' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Linux'; SambaToolPath = '/usr/bin/samba-tool' } }
            Mock Get-Command { [pscustomobject]@{ Source = '/usr/bin/smbclient' } } -ParameterFilter { $Name -eq 'smbclient' }
            Mock Invoke-PSGPONativeCommand { [pscustomobject]@{ ExitCode = 0; Output = @("GPO 'X' created as {8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99}"); Error = '' } }
            $null = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'create', 'X', '-H', 'ldap://dc', '--use-kerberos=required'
            Should -Invoke Invoke-PSGPONativeCommand -Times 1 -Exactly -ParameterFilter { $FilePath -eq '/usr/bin/samba-tool' -and $ArgumentList -contains '--no-pass' -and $ArgumentList[2] -eq 'X' }
            $null = Invoke-PSGPOSmbClient -Server 'dc' -Share 'sysvol' -Command 'ls'
            # smbclient: Kerberos, and no --no-pass, with which it does not use the ticket.
            Should -Invoke Invoke-PSGPONativeCommand -Times 1 -Exactly -ParameterFilter { $FilePath -eq '/usr/bin/smbclient' -and $ArgumentList -notcontains '--no-pass' -and $ArgumentList -contains '--use-kerberos=required' }
        }
    }

    Describe 'Changes of a directory read over LDAP' {
        BeforeEach {
            $Directory = New-TestLdapDirectory
            $Lyon = $Directory.FindSom("OU=Lyon,$TestLdapDomainDN")
            $Workstations = $Directory.FindSom("OU=Workstations,OU=Lyon,$TestLdapDomainDN")
        }

        It 'Creates the GPO in the domain, with the identity the domain gave it' {
            Mock New-PSGPODomainGpo {
                $Gpo.Id = [guid]'8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99'
                $Gpo.DistinguishedName = "CN={8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99},CN=Policies,CN=System,$TestLdapDomainDN"
                $Gpo.FileSysPath = '\\hardenbox.labo\sysvol\hardenbox.labo\Policies\{8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99}'
            }
            $Gpo = $Directory.NewGpo('C - Lyon - Proxy')
            Should -Invoke New-PSGPODomainGpo -Times 1 -Exactly -ParameterFilter { $Gpo.DisplayName -eq 'C - Lyon - Proxy' }
            $Gpo.Id | Should -Be ([guid]'8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99')
            $Directory.Gpos | Should -Contain $Gpo
        }

        It 'Keeps the directory unchanged when the domain refuses the GPO' {
            Mock New-PSGPODomainGpo { throw 'samba-tool gpo create failed (255): access denied' }
            { $Directory.NewGpo('Refused') } | Should -Throw -ExpectedMessage '*access denied*'
            $Directory.Gpos.Count | Should -Be 5
        }

        It 'Links the GPO in the domain, then shows the links the domain has' {
            $Gpo = $Directory.Gpos | Where-Object Id -EQ ([guid]$TestLdapDefaultDcPolicy)
            # Someone else linked the Workstations GPO meanwhile: the domain has two links.
            Mock Add-PSGPODomainGpLink {
                $New = "[LDAP://$($Link.GpoDistinguishedName);0][LDAP://$(Get-TestLdapGpoDN $TestLdapWorkstationsPolicy);0]"
                $Directory.SetLinks($Som, $New)
                for ($i = 0; $i -lt $Som.Links.Count; $i++) {
                    if ($Som.Links[$i].GpoDistinguishedName -eq $Link.GpoDistinguishedName) { $Link.Order = $Som.Links[$i].Order; $Som.Links[$i] = $Link }
                }
            }
            $Link = $Directory.NewLink($Lyon, $Gpo)
            Should -Invoke Add-PSGPODomainGpLink -Times 1 -Exactly
            $Lyon.Links.Count | Should -Be 2
            $Lyon.Links[1] | Should -Be $Link
            $Link.Order | Should -Be 2
            $Lyon.Links[0].Gpo.Id | Should -Be ([guid]$TestLdapWorkstationsPolicy)
        }

        It 'Keeps the links unchanged when the domain refuses the link' {
            Mock Add-PSGPODomainGpLink { throw 'The links of Lyon changed in the domain meanwhile' }
            { $Directory.NewLink($Lyon, $Directory.Gpos[0]) } | Should -Throw -ExpectedMessage '*changed in the domain meanwhile*'
            $Lyon.Links.Count | Should -Be 0
        }
    }

    Describe 'LDAP errors' {
        It 'Explains <Case>' -ForEach @(
            @{ Case = 'wrong credentials'; Code = 49; Expected = '*user name or the password is wrong*' }
            @{ Case = 'an unreachable server'; Code = 81; Expected = '*cannot be reached*dc.test*port 389*' }
            @{ Case = 'a refused weak authentication'; Code = 8; Expected = '*stronger authentication*-UseSsl*' }
        ) {
            Add-Type -AssemblyName System.DirectoryServices.Protocols
            $Exception = [System.DirectoryServices.Protocols.LdapException]::new($Code, 'server message')
            Get-PSGPOLdapErrorMessage -Exception $Exception -Server 'dc.test' -Port 389 | Should -BeLike "LDAP connection to dc.test:389 failed: server message $Expected"
        }

        It 'Refuses to send a password over plain LDAP outside Windows' -Skip:$IsWindows {
            $Credential = [pscredential]::new('administrator', (ConvertTo-SecureString 'not-used' -AsPlainText -Force))
            { New-PSGPOLdapConnection -Server 'dc.test' -Credential $Credential } | Should -Throw -ExpectedMessage '*only sent over LDAPS*-UseSsl*kinit administrator*'
        }
    }

    Describe 'Get-PSGPODirectory against a domain controller' -Skip:(-not $LdapServer) {
        BeforeAll {
            $Directory = Get-PSGPODirectory -Server $env:PSGPOTOOLS_TEST_LDAP_SERVER
        }

        It 'Reads the domain of the domain controller' {
            $Directory | Should -BeOfType ([GPOToolsLdapDirectory])
            $Directory.Domain.DistinguishedName | Should -Match '^DC='
            $Directory.IsReadOnly | Should -BeFalse
        }

        It 'Names the directory service of the domain controller' {
            $Directory.ServerType | Should -BeIn 'Samba AD', 'Active Directory'
            $Directory.Source | Should -BeLike "read over LDAP from * ($($Directory.ServerType))"
        }

        It 'Is read by Show-GPOManagerAvalonia at launch' {
            Mock Start-PSGPOManagerWindow { $script:Launched = $Directory }
            Show-GPOManagerAvalonia -Server $env:PSGPOTOOLS_TEST_LDAP_SERVER
            $script:Launched | Should -BeOfType ([GPOToolsLdapDirectory])
            $script:Launched.Domain.DistinguishedName | Should -Be $Directory.Domain.DistinguishedName
        }

        It 'Finds the default GPOs and their links' {
            $DefaultDomain = $Directory.Gpos | Where-Object Id -EQ ([guid]'31B2F340-016D-11D2-945F-00C04FB984F9')
            $DefaultDc = $Directory.Gpos | Where-Object Id -EQ ([guid]'6AC1786C-016F-11D2-945F-00C04FB984F9')
            $DefaultDomain | Should -Not -BeNullOrEmpty
            $DefaultDc | Should -Not -BeNullOrEmpty
            $DefaultDomain.FileSysPath | Should -BeLike '\\*\sysvol\*\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}'
            $Directory.Domain.Links.Gpo | Should -Contain $DefaultDomain
            $Directory.FindSom("OU=Domain Controllers,$($Directory.Domain.DistinguishedName)").Links.Gpo | Should -Contain $DefaultDc
        }
    }

    Describe 'Changes written to a domain controller' -Skip:(-not $LdapWrite) {
        BeforeAll {
            $Server = $env:PSGPOTOOLS_TEST_LDAP_SERVER
            $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $Directory = Get-PSGPODirectory -Server $Server
            $OuName = "PSGPOTools test $Stamp"
            $OuDN = "OU=$OuName,$($Directory.Domain.DistinguishedName)"
            $GpoName = "PSGPOTools test GPO $Stamp"
            $SecondName = "PSGPOTools test GPO 2 $Stamp"
            $TerminalName = "PSGPOTools test GPO terminal $Stamp"
            # An OU of the test, then the directory read again to have it.
            $null = Invoke-PSGPOSambaTool -ArgumentList 'ou', 'add', $OuDN, '-H', "ldap://$Server", '--use-kerberos=required'
            $Directory = Get-PSGPODirectory -Server $Server
            $Ou = $Directory.FindSom($OuDN)
        }

        AfterAll {
            # Everything the tests created, whatever failed.
            foreach ($Name in $GpoName, $SecondName, $TerminalName) {
                $Gpo = (Get-PSGPODirectory -Server $Server).FindGpo($Name)
                if (-not $Gpo) { continue }
                $Id = '{' + $Gpo.Id.ToString().ToUpperInvariant() + '}'
                try { $null = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'dellink', $OuDN, $Id, '-H', "ldap://$Server", '--use-kerberos=required' } catch { }
                try { $null = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'del', $Id, '-H', "ldap://$Server", '--use-kerberos=required' } catch { Write-Warning $_ }
            }
            try { $null = Invoke-PSGPOSambaTool -ArgumentList 'ou', 'delete', $OuDN, '-H', "ldap://$Server", '--use-kerberos=required', '--force-subtree-delete' } catch { Write-Warning $_ }
        }

        It 'Creates a GPO in the domain, with its folder in SYSVOL' {
            $Ou | Should -Not -BeNullOrEmpty -Because 'the OU of the test was created'
            $Gpo = $Directory.NewGpo($GpoName)
            $Gpo.Id | Should -Not -Be ([guid]::Empty)
            $Gpo.FileSysPath | Should -BeLike "*\Policies\{$($Gpo.Id.ToString())}"

            $Read = Get-PSGPODirectory -Server $Server
            $Again = $Read.FindGpo($GpoName)
            $Again.Id | Should -Be $Gpo.Id
            $Again.Version | Should -Be 0
            $Again.GetStatus() | Should -Be 'Enabled'
        }

        It 'Links the GPO to the OU with the lowest precedence' {
            $Gpo = $Directory.FindGpo($GpoName)
            $Link = $Directory.NewLink($Ou, $Gpo)
            $Link.Order | Should -Be 1
            $Ou.Links.Count | Should -Be 1

            $Second = $Directory.NewGpo($SecondName)
            $SecondLink = $Directory.NewLink($Ou, $Second)
            $SecondLink.Order | Should -Be 2 -Because 'a new link has the lowest precedence'

            $ReadOu = (Get-PSGPODirectory -Server $Server).FindSom($OuDN)
            @($ReadOu.Links.Gpo.DisplayName) | Should -Be @($GpoName, $SecondName)
            @($ReadOu.Links.Enabled) | Should -Be @($true, $true)
        }

        It 'Refuses to link the same GPO twice, and changes nothing' {
            $Gpo = $Directory.FindGpo($GpoName)
            { $Directory.NewLink($Ou, $Gpo) } | Should -Throw -ExpectedMessage '*already linked*'
            (Get-PSGPODirectory -Server $Server).FindSom($OuDN).Links.Count | Should -Be 2
        }

        It 'Writes the Registry.pol of the GPO in SYSVOL and increases its version' {
            Initialize-PSGPOAdmx -Path (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path -UICulture 'en-US' 3>$null
            $Policy = [GPOToolsUtility]::Policies | Where-Object { $_.ID -eq 'AxISURLZonePolicies' } | Select-Object -First 1
            $Gpo = $Directory.FindGpo($GpoName)
            $Directory.ReadPolicyFile($Gpo, 'Machine') | Should -BeNullOrEmpty -Because 'a new GPO has no setting'

            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $Policy -Pol $Pol -State Enabled -Value @{ InstallTrustedOCX = 0; IgnoreUnknownCA = $true }
            $Directory.WritePolicyFile($Gpo, 'Machine', $Pol.ToBytes())
            $Gpo.GetComputerVersion() | Should -Be 1

            # Read again from the domain: the file, its setting, the version and the extension.
            $Read = Get-PSGPODirectory -Server $Server
            $Again = $Read.FindGpo($GpoName)
            $Again.Version | Should -Be 1
            $Bytes = $Read.ReadPolicyFile($Again, 'Machine')
            [Linq.Enumerable]::SequenceEqual([byte[]]$Bytes, [byte[]]$Pol.ToBytes()) | Should -BeTrue
            $State = Get-PSGPOPolicyState -Policy $Policy -Pol ([GPOToolsRegistryPol]::Parse($Bytes))
            $State.State | Should -Be 'Enabled'
            $State.Value['IgnoreUnknownCA'] | Should -BeTrue
            $GptIni = [System.Text.Encoding]::ASCII.GetString((Read-PSGPOSysvolFile -Directory $Read -Gpo $Again -Path 'GPT.INI'))
            $GptIni | Should -Match '(?m)^Version=1\r?$'
            $Connection = New-PSGPODirectoryConnection -Directory $Read
            try { $Entry = Invoke-PSGPOLdapSearch -Connection $Connection -SearchBase $Again.DistinguishedName -Scope Base -Attribute 'gPCMachineExtensionNames' }
            finally { $Connection.Dispose() }
            Get-PSGPOLdapValue $Entry 'gPCMachineExtensionNames' | Should -Be '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'

            # A user setting increases the user version only.
            $UserPolicy = [GPOToolsUtility]::Policies | Where-Object { $_.ID -eq 'DisallowCpls' } | Select-Object -First 1
            $UserPol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy $UserPolicy -Pol $UserPol -State Enabled -Value @{ DisallowCplsList = [string[]]@('Microsoft.Mouse') }
            $Read.WritePolicyFile($Again, 'User', $UserPol.ToBytes())
            (Get-PSGPODirectory -Server $Server).FindGpo($GpoName).Version | Should -Be 0x00010001
        }

        It 'Writes the security settings of the GPO in GptTmpl.inf, which Samba reads back' {
            $Gpo = $Directory.FindGpo($GpoName)
            $Before = (Get-PSGPODirectory -Server $Server).FindGpo($GpoName).Version
            $Template = [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($Gpo))
            $Template.IsEmpty() | Should -BeTrue -Because 'a new GPO has no security setting'
            $Catalog = Get-PSGPOSecuritySetting
            Set-PSGPOSecurityValue -Template $Template -Setting ($Catalog | Where-Object Key -EQ 'MinimumPasswordLength') -Value 14
            Set-PSGPOSecurityValue -Template $Template -Setting ($Catalog | Where-Object Key -EQ 'MaxTicketAge') -Value 8
            Set-PSGPOSecurityValue -Template $Template -Setting ($Catalog | Where-Object Key -EQ 'AuditLogonEvents') -Value 3
            Set-PSGPOSecurityValue -Template $Template -Setting ($Catalog | Where-Object Key -EQ 'SeBackupPrivilege') -Value @('*S-1-5-32-544')
            $Directory.WriteSecurityTemplate($Gpo, $Template.ToBytes())

            $Read = Get-PSGPODirectory -Server $Server
            $Again = $Read.FindGpo($GpoName)
            $Again.Version | Should -Be ($Before + 1) -Because 'the computer version increases'
            [Linq.Enumerable]::SequenceEqual([byte[]]$Read.ReadSecurityTemplate($Again), [byte[]]$Template.ToBytes()) | Should -BeTrue
            $Connection = New-PSGPODirectoryConnection -Directory $Read
            try { $Entry = Invoke-PSGPOLdapSearch -Connection $Connection -SearchBase $Again.DistinguishedName -Scope Base -Attribute 'gPCMachineExtensionNames' }
            finally { $Connection.Dispose() }
            # Contains, not -BeLike: the brackets are wildcards for -like.
            (Get-PSGPOLdapValue $Entry 'gPCMachineExtensionNames').Contains('[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]') | Should -BeTrue

            # Samba reads the file the module wrote.
            $Listed = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'manage', 'security', 'list', ('{' + $Again.Id.ToString().ToUpperInvariant() + '}'), '-H', "ldap://$Server", '--use-kerberos=required'
            ($Listed -join "`n") | Should -Match 'MinimumPasswordLength\s*=\s*14'
            ($Listed -join "`n") | Should -Match 'MaxTicketAge\s*=\s*8'
        }

        It 'Sets the GPO status and the security filtering groups, consistent in SYSVOL' {
            $Gpo = $Directory.FindGpo($SecondName)
            $Directory.SetGpoStatus($Gpo, 1)
            (Get-PSGPODirectory -Server $Server).FindGpo($SecondName).GetStatus() | Should -Be 'User configuration settings disabled'

            # In the OU of the test, deleted with it.
            $Groups = $Directory.NewFilteringGroups($Gpo, $OuDN)
            @($Groups.Name) | Should -Be @("APPLY_$SecondName", "DENY_$SecondName")
            @($Groups.DistinguishedName) | Should -Be @("CN=APPLY_$SecondName,$OuDN", "CN=DENY_$SecondName,$OuDN")
            $Groups.Sid | ForEach-Object { $_ | Should -Match '^S-1-5-21-\d+-\d+-\d+-\d+$' }

            $Connection = New-PSGPODirectoryConnection -Directory $Directory
            try { $Sddl = (Get-PSGPODomainSecurityDescriptor -Connection $Connection -DistinguishedName $Gpo.DistinguishedName).ToSddl() }
            finally { $Connection.Dispose() }
            $Sddl | Should -Match ([regex]::Escape("(OD;CI;0x00000100;edacfd8f-ffb3-11d1-b41d-00a0c968f939;;$($Groups[1].Sid))"))
            $Sddl | Should -Match ([regex]::Escape("(OA;CI;0x00000100;edacfd8f-ffb3-11d1-b41d-00a0c968f939;;$($Groups[0].Sid))"))
            $Sddl | Should -Match ([regex]::Escape("(A;CI;0x00020094;;;$($Groups[0].Sid))"))
            $Sddl | Should -Not -Match 'edacfd8f-ffb3-11d1-b41d-00a0c968f939;;S-1-5-11\)' -Because 'Authenticated Users no longer apply it'
            $Sddl | Should -Match ([regex]::Escape('(A;CI;0x00020094;;;S-1-5-11)')) -Because 'the computers still read it'

            # Samba finds the ACL of the SYSVOL folder consistent with the directory one.
            $Check = Invoke-PSGPONativeCommand -FilePath (Get-PSGPOPlatform).SambaToolPath -ArgumentList 'gpo', 'aclcheck', '-H', "ldap://$Server", '--use-kerberos=required', '--no-pass'
            "$($Check.Output -join "`n")`n$($Check.Error)" | Should -Not -Match 'ERROR'
            { $Directory.NewFilteringGroups($Gpo, $OuDN) } | Should -Throw -ExpectedMessage '*already exists*'
        }

        It 'Creates a GPO from a terminal without waiting for a password (the window froze)' -Skip:(-not (Get-Command script -ErrorAction SilentlyContinue)) {
            # samba-tool gpo create asks for a password on the terminal, even with Kerberos.
            $Script = Join-Path $TestDrive 'create-from-terminal.ps1'
            $Module = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
            Set-Content -LiteralPath $Script -Value @"
Import-Module '$Module'
& (Get-Module PSGPOTools) { Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'create', '$TerminalName', '-H', 'ldap://$Server', '--use-kerberos=required' }
"@
            $Pwsh = (Get-Process -Id $PID).Path
            # A pseudo-terminal as standard input, as when the window is started from a shell.
            $Output = & timeout 90 script -qec "$Pwsh -NoProfile -File $Script" /dev/null 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "the command ended: $($Output -join ' ')"
            ($Output -join "`n") | Should -Match 'created as \{'
            (Get-PSGPODirectory -Server $Server).FindGpo($TerminalName) | Should -Not -BeNullOrEmpty
        }

        It 'Adds a link to the links the domain has now, not to a stale copy' {
            # A stale copy of the OU: someone removes a link after it was read.
            $Stale = Get-PSGPODirectory -Server $Server
            $StaleOu = $Stale.FindSom($OuDN)
            $StaleOu.Links.Count | Should -Be 2
            $Id = '{' + $Directory.FindGpo($SecondName).Id.ToString().ToUpperInvariant() + '}'
            $null = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'dellink', $OuDN, $Id, '-H', "ldap://$Server", '--use-kerberos=required'

            $DefaultDomain = $Stale.Gpos | Where-Object Id -EQ ([guid]'31B2F340-016D-11D2-945F-00C04FB984F9')
            $Link = $Stale.NewLink($StaleOu, $DefaultDomain)
            # The removed link does not come back, and the copy now has the links of the domain.
            $Expected = @($GpoName, 'Default Domain Policy')
            @($StaleOu.Links.Gpo.DisplayName) | Should -Be $Expected
            $Link.Order | Should -Be 2
            @((Get-PSGPODirectory -Server $Server).FindSom($OuDN).Links.Gpo.DisplayName) | Should -Be $Expected
        }
    }
}
