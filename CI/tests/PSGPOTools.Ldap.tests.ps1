#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Platform detection and reading of the directory over LDAP (Get-PSGPODirectory). The model is
# built from LDAP search entries without a server; the tests against a real domain controller
# run only when PSGPOTOOLS_TEST_LDAP_SERVER names one (with a Kerberos ticket on Linux):
#   PSGPOTOOLS_TEST_LDAP_SERVER=dc.hardenbox.labo pwsh -File CI/Invoke-Tests.ps1
# The tests that write to that domain (an OU and a GPO of their own, deleted at the end) also
# need PSGPOTOOLS_TEST_LDAP_WRITE=1, samba-tool and an account allowed to create GPOs.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    # Evaluated during discovery, in the module scope (see PSGPOTools.Gui.tests.ps1).
    $LdapServer = $env:PSGPOTOOLS_TEST_LDAP_SERVER
    $LdapWrite = $LdapServer -and $env:PSGPOTOOLS_TEST_LDAP_WRITE -eq '1'
    # The scripts of the lab (docs/assets/scripts) create OUs, groups and accounts, and change
    # the configuration of the domain (its workflow, for a moment): only on the throwaway domain of the CI.
    $LabScripts = $LdapWrite -and -not $IsWindows -and $env:PSGPOTOOLS_TEST_LAB_SCRIPTS -eq '1'
    # The approval with two accounts: after the scripts of the lab (tiers1 gets a ticket with the
    # password of the lab), or on a lab whose ticket of tiers1 is given (PSGPOTOOLS_TEST_TIER1_CCACHE).
    $ApprovalTest = $LabScripts -or ($LdapWrite -and -not $IsWindows -and $env:PSGPOTOOLS_TEST_TIER1_CCACHE)

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

        It 'Shows the versions of the directory and of SYSVOL of a GPO, as GPMC, and when they differ' {
            $Gpo = $Directory.Gpos | Where-Object Id -EQ ([guid]$TestLdapWorkstationsPolicy)
            $Row = { param($Detail, $Key) ($Detail.Properties | Where-Object Key -EQ $Key).Value }
            # GPT.INI of the same version (user 2, computer 2), then of another one.
            $script:GptIni = [System.Text.Encoding]::ASCII.GetBytes("[General]`r`nVersion=131074`r`n")
            Mock Read-PSGPOSysvolFile { $script:GptIni } -ParameterFilter { $Path -eq 'GPT.INI' }
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo
            & $Row $Detail 'User version' | Should -Be '2 (AD), 2 (SYSVOL)'
            & $Row $Detail 'Computer version' | Should -Be '2 (AD), 2 (SYSVOL)'
            & $Row $Detail 'Versions' | Should -BeNullOrEmpty

            $Gpo.Version = (3 -shl 16) -bor 2
            $script:GptIni = [byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes("[General]`r`nVersion=131074`r`n")
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo
            & $Row $Detail 'User version' | Should -Be '3 (AD), 2 (SYSVOL)'
            & $Row $Detail 'Versions' | Should -BeLike 'The directory and SYSVOL of dc.hardenbox.labo do not have the same version*'

            # Read once for a version of the GPO in the directory; a folder that cannot be read is said.
            Should -Invoke Read-PSGPOSysvolFile -Times 2 -Exactly
            $null = Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo
            Should -Invoke Read-PSGPOSysvolFile -Times 2 -Exactly
            $Gpo.Version = (4 -shl 16) -bor 2
            Mock Read-PSGPOSysvolFile { throw 'smbclient failed: NT_STATUS_ACCESS_DENIED' } -ParameterFilter { $Path -eq 'GPT.INI' }
            & $Row (Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo) 'Computer version' | Should -Be '2 (AD), SYSVOL not read: smbclient failed: NT_STATUS_ACCESS_DENIED'
        }

    }

    Describe 'PDC emulator' {
        BeforeEach {
            $Set = Get-TestLdapEntrySet
            $PdcDN = 'CN=DC1,CN=Servers,CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=hardenbox,DC=labo'
            $Set.Domain.Attributes['fsmoroleowner'] = [string[]]@("CN=NTDS Settings,$PdcDN")
            $script:Down = $null
            $script:Connected = [System.Collections.Generic.List[string]]::new()
            Mock Resolve-PSGPODomainServer { if ($Server) { $Server } else { 'hardenbox.labo' } }
            Mock New-PSGPOLdapConnection {
                if ($Server -eq $script:Down) { throw "The LDAP server $Server is unavailable." }
                $script:Connected.Add($Server)
                [pscustomobject]@{ Server = $Server } | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru
            }
            Mock Invoke-PSGPOLdapSearch {
                # The name of the domain reaches dc2.
                if ($SearchBase -eq '') {
                    $Name = if ($Connection.Server -eq 'hardenbox.labo') { 'dc2.hardenbox.labo' } else { $Connection.Server }
                    return New-TestLdapEntry '' @{ defaultNamingContext = $TestLdapDomainDN; dnsHostName = $Name; vendorName = 'Samba Team (https://www.samba.org)' }
                }
                if ($SearchBase -eq $TestLdapDomainDN -and $Scope -eq 'Base') { return $Set.Domain }
                if ($SearchBase -eq $PdcDN) { return New-TestLdapEntry $PdcDN @{ dNSHostName = 'dc1.hardenbox.labo' } }
                if ($Filter -like '*organizationalUnit*') { return $Set.Ous }
                if ($Filter -like '*groupPolicyContainer*') { return $Set.Gpos }
            }
            Mock Get-PSGPOLdapAccount { 'HARDENBOX\Administrator' }
            Mock Test-PSGPODomainAdministrator { $true }
            Mock Read-PSGPODomainSecurityFiltering { }
            Mock Read-PSGPODomainWmiFilter { }
            Mock Use-PSGPODomainConfiguration { }
            Mock Get-PSGPOWorkflowSetting { @{ Enabled = $false } }
            Mock Get-PSGPOConfigurationData { @{ Audit = @{}; Backup = @{} } }
        }

        It 'Reads the domain from its PDC emulator, found by the domain controller the name of the domain reaches' {
            $Read = Get-PSGPODirectory -WarningVariable Warnings 3>$null
            $Read.Server | Should -Be 'dc1.hardenbox.labo'
            $Read.PdcEmulator | Should -Be 'dc1.hardenbox.labo'
            $Read.IsPdcEmulator() | Should -BeTrue
            @($script:Connected) | Should -Be @('hardenbox.labo', 'dc1.hardenbox.labo')
            @($Warnings | Where-Object { "$_" -like '*PDC emulator*' }) | Should -BeNullOrEmpty
        }

        It 'Warns when -Server is another domain controller, and reads from it' {
            $Read = Get-PSGPODirectory -Server 'dc2.hardenbox.labo' -WarningVariable Warnings 3>$null
            $Read.Server | Should -Be 'dc2.hardenbox.labo'
            $Read.PdcEmulator | Should -Be 'dc1.hardenbox.labo'
            $Read.IsPdcEmulator() | Should -BeFalse
            @($Warnings | Where-Object { "$_" -like '*PDC emulator*' }) | Should -BeLike 'dc2.hardenbox.labo is not the PDC emulator of hardenbox.labo (dc1.hardenbox.labo)*Give -Server dc1.hardenbox.labo, or no -Server.'
        }

        It 'Reads from the domain controller found when the PDC emulator cannot be reached' {
            $script:Down = 'dc1.hardenbox.labo'
            $Read = Get-PSGPODirectory -WarningVariable Warnings 3>$null
            $Read.Server | Should -Be 'dc2.hardenbox.labo'
            @($Warnings | Where-Object { "$_" -like 'The PDC emulator*' }) | Should -BeLike 'The PDC emulator of the domain, dc1.hardenbox.labo, cannot be read (*unavailable*): the domain is read from dc2.hardenbox.labo.'
        }

        It 'Reads a domain whose PDC emulator is not known from the domain controller found' {
            $Set.Domain.Attributes.Remove('fsmoroleowner')
            $Read = Get-PSGPODirectory 3>$null
            $Read.Server | Should -Be 'dc2.hardenbox.labo'
            $Read.PdcEmulator | Should -BeNullOrEmpty
            $Read.IsPdcEmulator() | Should -BeTrue -Because 'nothing says another one is'
        }

        It 'Lists the domain controllers of the domain, the PDC emulator first' {
            Mock Invoke-PSGPOLdapSearch { New-TestLdapEntry 'CN=DC2' @{ dNSHostName = 'dc2.hardenbox.labo' }; New-TestLdapEntry 'CN=DC1' @{ dNSHostName = 'dc1.hardenbox.labo' } }
            $Directory = New-TestLdapDirectory
            $Directory.PdcEmulator = 'dc1.hardenbox.labo'
            @(Get-PSGPODomainController -Directory $Directory) | Should -Be @('dc1.hardenbox.labo', 'dc2.hardenbox.labo')
            Should -Invoke Invoke-PSGPOLdapSearch -Times 1 -Exactly -ParameterFilter { $Filter -eq '(&(objectCategory=computer)(userAccountControl:1.2.840.113556.1.4.803:=8192))' }
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
            $Directory = if ($null -ne $Demo) { Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json') }
            if ($Demo) { $Directory.IsDemonstration = $true }
            $Items = @(Get-PSGPOStatusBarItem -Platform $Workstation -Directory $Directory -DirectoryError $Error)
            $Items[3].Text | Should -Be $Expected
            if ($Error) { $Items[3].ToolTip | Should -Be $Error }
        }

        It 'Says whether the domain controller is the PDC emulator, where GPMC changes the GPOs' {
            $Directory = New-TestLdapDirectory
            $Directory.PdcEmulator = 'dc.hardenbox.labo'
            @(Get-PSGPOStatusBarItem -Platform $SambaDc -Directory $Directory)[3].Text | Should -Be 'DC dc.hardenbox.labo (Samba AD, PDC emulator)'
            $Directory.PdcEmulator = 'dc1.hardenbox.labo'
            $Item = @(Get-PSGPOStatusBarItem -Platform $SambaDc -Directory $Directory)[3]
            $Item.Text | Should -Be 'DC dc.hardenbox.labo (Samba AD, not the PDC emulator (dc1.hardenbox.labo))'
            $Item.ToolTip | Should -BeLike '*GPMC changes the GPOs on the PDC emulator, dc1.hardenbox.labo: Change Domain Controller... in the context menu of the domain.'
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
            # The ADMX files as loaded: no window asking for them, no central store looked for.
            Mock Show-PSGPOAdmxWindow { $true }
            Mock Get-PSGPOAdmxStartSource { @{ Path = $null; UICulture = $null; CentralStore = @() } }
            Mock Initialize-PSGPODomainConfiguration { $true }
        }
        AfterAll { $script:PSGPOPlatform = $null }

        It 'Reads the domain of the computer and opens on it' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Linux'; DomainName = 'hardenbox.labo' } }
            Show-GPOManagerAvalonia
            Should -Invoke Get-PSGPODirectory -Times 1 -Exactly -ParameterFilter { -not $Server -and -not $Credential -and -not $UseSsl }
            $script:Opened.Directory.DomainName | Should -Be 'hardenbox.labo'
            $script:Opened.StartView | Should -Be 'Management'
            $script:Opened.DirectoryError | Should -BeNullOrEmpty
            Should -Invoke Initialize-PSGPODomainConfiguration -Times 1 -Exactly -ParameterFilter { $Directory.DomainName -eq 'hardenbox.labo' } -Because 'the first start creates the configuration of the domain'
        }

        It 'Shows the sample directory as a demonstration when no domain is discovered' {
            Mock Get-PSGPOPlatform { [GPOToolsPlatform]@{ OperatingSystem = 'Windows' } }
            Show-GPOManagerAvalonia
            Should -Invoke Get-PSGPODirectory -Times 0 -Exactly
            $script:Opened.Directory.DomainName | Should -Be 'corp.contoso.com'
            $script:Opened.Directory.IsDemonstration | Should -BeTrue
            $script:Opened.DirectoryError | Should -BeNullOrEmpty
            Should -Invoke Initialize-PSGPODomainConfiguration -Times 0 -Exactly
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

    Describe 'GPO creation from Windows (RSAT)' {
        BeforeAll {
            # New-GPO exists only where RSAT is installed: a stand-in to mock.
            if (-not (Get-Command New-GPO -ErrorAction SilentlyContinue)) { function script:New-GPO { param($Name, $Domain, $Server) } }
            if (-not (Get-Command Remove-GPO -ErrorAction SilentlyContinue)) { function script:Remove-GPO { param($Guid, $Domain, $Server, [switch]$Confirm) } }
            $Directory = [GPOToolsLdapDirectory]::new('powershell.labo', 'DC=powershell,DC=labo', 'ADDS.powershell.labo', 'Active Directory')
        }

        It 'Creates the GPO with New-GPO on the domain controller of the directory' {
            Mock Get-Module -ParameterFilter { $ListAvailable -and $SkipEditionCheck -and $Name -eq 'GroupPolicy' } { [pscustomobject]@{ Name = 'GroupPolicy' } }
            Mock Import-Module -ParameterFilter { $Name -eq 'GroupPolicy' } { }
            Mock New-GPO { [pscustomobject]@{ Id = [guid]'11111111-2222-3333-4444-555555555555'; DisplayName = $Name } }
            New-PSGPOWindowsGpo -Directory $Directory -Name 'Test' | Should -Be ([guid]'11111111-2222-3333-4444-555555555555')
            Should -Invoke New-GPO -Times 1 -Exactly -ParameterFilter { $Name -eq 'Test' -and $Domain -eq 'powershell.labo' -and $Server -eq 'ADDS.powershell.labo' }
        }

        It 'Says how to install the Group Policy Management tools when they are missing' {
            Mock Get-Module -ParameterFilter { $ListAvailable -and $SkipEditionCheck -and $Name -eq 'GroupPolicy' } { }
            { New-PSGPOWindowsGpo -Directory $Directory -Name 'Test' } | Should -Throw -ExpectedMessage "*Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0*Install-WindowsFeature GPMC*"
        }

        It 'Says why New-GPO failed' {
            Mock Get-Module -ParameterFilter { $ListAvailable -and $SkipEditionCheck -and $Name -eq 'GroupPolicy' } { [pscustomobject]@{ Name = 'GroupPolicy' } }
            Mock Import-Module -ParameterFilter { $Name -eq 'GroupPolicy' } { }
            Mock New-GPO { throw 'Access is denied.' }
            { New-PSGPOWindowsGpo -Directory $Directory -Name 'Test' } | Should -Throw -ExpectedMessage 'New-GPO failed on ADDS.powershell.labo: Access is denied.'
        }

        It 'Deletes the GPO with Remove-GPO on the domain controller of the directory, then checks it is gone' {
            Mock Get-Module -ParameterFilter { $ListAvailable -and $SkipEditionCheck -and $Name -eq 'GroupPolicy' } { [pscustomobject]@{ Name = 'GroupPolicy' } }
            Mock Import-Module -ParameterFilter { $Name -eq 'GroupPolicy' } { }
            Mock Remove-GPO { }
            $Gpo = [GPOToolsGpo]@{ Id = [guid]'11111111-2222-3333-4444-555555555555'; DisplayName = 'Test'; DistinguishedName = 'CN={11111111-2222-3333-4444-555555555555},CN=Policies,CN=System,DC=powershell,DC=labo' }
            Remove-PSGPOWindowsGpo -Directory $Directory -Gpo $Gpo
            Should -Invoke Remove-GPO -Times 1 -Exactly -ParameterFilter { $Guid -eq $Gpo.Id -and $Domain -eq 'powershell.labo' -and $Server -eq 'ADDS.powershell.labo' }

            Mock Remove-GPO { throw 'Access is denied.' }
            { Remove-PSGPOWindowsGpo -Directory $Directory -Gpo $Gpo } | Should -Throw -ExpectedMessage 'Remove-GPO failed on ADDS.powershell.labo: Access is denied.'
            Mock Get-Module -ParameterFilter { $ListAvailable -and $SkipEditionCheck -and $Name -eq 'GroupPolicy' } { }
            { Remove-PSGPOWindowsGpo -Directory $Directory -Gpo $Gpo } | Should -Throw -ExpectedMessage 'Deleting a GPO from Windows needs the Group Policy Management tools of RSAT*'
        }

        It 'Gives Windows the ACL of the SYSVOL folder without the ACEs of the extended rights' -Skip:(-not $IsWindows) {
            $Descriptor = [GPOToolsSecurityDescriptor]::new()
            $Descriptor.Control = [GPOToolsSecurityDescriptor]::DaclProtected
            $Descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            $Descriptor.SetSecurityFiltering('S-1-5-21-1-2-3-1103', 'S-1-5-21-1-2-3-1104')
            $Files = [GPOToolsSecurityDescriptor]::Parse($Descriptor.ConvertToFileSystem().ToBytes())
            $Files.Dacl.RemoveAll([Predicate[GPOToolsAce]] { param($Ace) $Ace.IsObjectAce() }) | Out-Null
            $Security = [System.Security.AccessControl.DirectorySecurity]::new()
            $Security.SetSecurityDescriptorSddlForm($Files.ToSddl(), [System.Security.AccessControl.AccessControlSections]::Access)
            $Security.AreAccessRulesProtected | Should -BeTrue
            @($Security.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]).IdentityReference.Value) | Should -Be @('S-1-5-21-1-2-3-1103')
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
            { New-PSGPODomainGpo -Directory $Directory -Gpo ([GPOToolsGpo]@{ DisplayName = 'X' }) } | Should -Throw -ExpectedMessage '*uses the identity of the session (Kerberos)*without -Credential*'
            { Remove-PSGPODomainGpo -Directory $Directory -Gpo ([GPOToolsGpo]@{ DisplayName = 'X' }) } | Should -Throw -ExpectedMessage 'Deleting a GPO uses the identity of the session (Kerberos)*without -Credential*'
        }

        It 'Deletes a GPO with samba-tool gpo del and Kerberos, then checks it is gone' -Skip:$IsWindows {
            $Directory = New-TestLdapDirectory
            $Gpo = [GPOToolsGpo]@{ Id = [guid]'8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99'; DisplayName = 'X'; DistinguishedName = 'CN={8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99},CN=Policies,CN=System,DC=corp,DC=contoso,DC=com' }
            Mock Invoke-PSGPOSambaTool { }
            Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
            Mock Invoke-PSGPOLdapSearch { }
            Remove-PSGPODomainGpo -Directory $Directory -Gpo $Gpo
            Should -Invoke Invoke-PSGPOSambaTool -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq "gpo del {8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E99} -H ldap://$($Directory.Server) --use-kerberos=required"
            }
            # Its folder read first (gPCFileSysPath, not redirected), then the GPO still there.
            Mock Invoke-PSGPOLdapSearch { [pscustomobject]@{ DistinguishedName = $Gpo.DistinguishedName; Attributes = @{} } }
            { Remove-PSGPODomainGpo -Directory $Directory -Gpo $Gpo } | Should -Throw -ExpectedMessage "*'X' is still in the domain after its deletion*"
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
            Mock Show-PSGPOAdmxWindow { $true }
            Mock Get-PSGPOAdmxStartSource { @{ Path = $null; UICulture = $null; CentralStore = @() } }
            # Not the configuration of the domain of the lab.
            Mock Initialize-PSGPODomainConfiguration { $false }
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

        It 'Names the account it is read with, and its rights' {
            $Directory.Account | Should -Match '^[^\\]+\\[^\\]+$|^CN='
            # The tests run as a domain administrator: every right, nothing hidden.
            $Directory.IsLimited() | Should -BeFalse -Because "$($Directory.Account) manages every OU and GPO"
            $Directory.CanCreateGpo | Should -BeTrue
            $Directory.IsDomainAdministrator | Should -BeTrue -Because 'it changes the configuration of the domain'
        }
    }

    Describe 'Scripts of the lab' -Skip:(-not $LabScripts) {
        BeforeAll {
            $Server = $env:PSGPOTOOLS_TEST_LDAP_SERVER
            $Scripts = Join-Path $PSScriptRoot '..' '..' 'docs' 'assets' 'scripts' 'linux'
            $Module = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
            $Directory = Get-PSGPODirectory -Server $Server
            $DomainDN = $Directory.Domain.DistinguishedName
            function Invoke-LabScript {
                param([string]$Name, [string[]]$Argument)
                $Output = pwsh -NoProfile -NonInteractive -Command "Import-Module '$Module'; & '$(Join-Path $Scripts $Name)' -Server '$Server' $($Argument -join ' ')" 2>&1
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($Output | ForEach-Object { "$_" }) -join "`n" }
            }
        }

        It 'Creates the OUs of the tiers, their groups and the accounts of the technicians, then keeps them' {
            $Run = Invoke-LabScript 'New-PSGPOTierLab.ps1'
            $Run.ExitCode | Should -Be 0 -Because $Run.Output
            $Read = Get-PSGPODirectory -Server $Server
            foreach ($Ou in 'OU=Servers,OU=Tier 1', 'OU=Groups,OU=Tier 1', 'OU=Workstations,OU=Tier 2', 'OU=Users,OU=Tier 2', 'OU=Groups,OU=Tier 2') {
                $Read.FindSom("$Ou,$DomainDN") | Should -Not -BeNullOrEmpty -Because "$Ou was created"
            }
            (Invoke-PSGPOSambaTool -ArgumentList 'group', 'listmembers', 'GPO-Tier1-Admins', '-H', "ldap://$Server", '--use-kerberos=required') -join "`n" | Should -Match 'tiers1'
            (Invoke-PSGPOSambaTool -ArgumentList 'group', 'listmembers', 'GPO-Tier2-Admins', '-H', "ldap://$Server", '--use-kerberos=required') -join "`n" | Should -Match 'tiers2'

            # The password of the lab: tiers1 gets a ticket, in a cache of its own.
            $Cache = $env:KRB5CCNAME
            try {
                $env:KRB5CCNAME = "FILE:$(Join-Path $TestDrive 'tiers1.ccache')"
                $null = 'H@rdenB0x!' | kinit "tiers1@$($Directory.DomainName.ToUpperInvariant())" 2>&1
                $LASTEXITCODE | Should -Be 0 -Because 'tiers1 has the password of the lab'
            } finally { $env:KRB5CCNAME = $Cache }

            $Again = Invoke-LabScript 'New-PSGPOTierLab.ps1'
            $Again.ExitCode | Should -Be 0 -Because $Again.Output
            $Again.Output | Should -Not -Match 'created|added' -Because 'what is there is kept'
        }

        It 'Delegates finely the links of the tier OUs and the creation of GPOs, never Group Policy Creator Owners, then keeps them' {
            $Sid = "$((Invoke-PSGPOSambaTool -ArgumentList 'group', 'show', 'GPO-Tier1-Admins', '--attributes=objectSid', '-H', "ldap://$Server", '--use-kerberos=required') -match '^objectSid: ' | Select-Object -First 1)" -replace '^objectSid: '
            $LinkAce = "(OA;CI;RPWP;f30e3bbe-9ff0-11d1-b603-0000f80367c1;;$Sid)"
            $ReadAcl = { (Invoke-PSGPOSambaTool -ArgumentList 'dsacl', 'get', "--objectdn=OU=Tier 1,$DomainDN", '-H', "ldap://$Server", '--use-kerberos=required') -join "`n" }

            # Without the workflow of the creators, it stops before any change.
            $Refused = Invoke-LabScript 'Grant-PSGPOTierDelegation.ps1'
            $Refused.ExitCode | Should -Not -Be 0
            $Refused.Output | Should -Match 'approval workflow of the domain must be enabled'
            (& $ReadAcl) | Should -Not -BeLike "*$LinkAce*" -Because 'nothing is changed without the workflow'

            # The workflow of the lab, for the test only.
            Save-PSGPODomainConfiguration -Directory $Directory -Values @{ 'Workflow.Enabled' = $true; 'Workflow.Creators' = 'GPO-Tier1-Admins, GPO-Tier2-Admins' } -Confirm:$false
            try {
                $Run = Invoke-LabScript 'Grant-PSGPOTierDelegation.ps1'
                $Run.ExitCode | Should -Be 0 -Because $Run.Output
                $Acl = & $ReadAcl
                $Acl | Should -BeLike "*$LinkAce*"
                $Acl | Should -BeLike "*(OA;CI;RPWP;f30e3bbf-9ff0-11d1-b603-0000f80367c1;;$Sid)*"
                # The rights of the creation of GPOs, all there.
                $Rights = @(Initialize-PSGPOWorkflow -Server $Server)
                $Rights.Count | Should -BeGreaterThan 0
                @($Rights | Where-Object State -NE 'Present') | Should -BeNullOrEmpty -Because 'the script gave every right of the creation of GPOs'
                # Never Group Policy Creator Owners.
                (Invoke-PSGPOSambaTool -ArgumentList 'group', 'listmembers', 'Group Policy Creator Owners', '-H', "ldap://$Server", '--use-kerberos=required') -join "`n" | Should -Not -Match 'GPO-Tier'

                $Again = Invoke-LabScript 'Grant-PSGPOTierDelegation.ps1'
                $Again.ExitCode | Should -Be 0 -Because $Again.Output
                $Again.Output | Should -Not -Match 'now writes|Added' -Because 'what is there is kept'
            } finally {
                # The configuration of the domain back to the defaults, for the other tests.
                Save-PSGPODomainConfiguration -Directory $Directory -Values @{} -Confirm:$false
            }
        }
    }

    # The approval workflow with two accounts of the domain, after the scripts of the lab (its OUs,
    # groups, technicians and delegations): tiers1 (Tier 1, a creator) in a process of its own with
    # its Kerberos ticket, the administrator of the CI as the approver.
    Describe 'Approval written to a domain controller' -Skip:(-not $ApprovalTest) {
        BeforeAll {
            $Server = $env:PSGPOTOOLS_TEST_LDAP_SERVER
            $Module = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
            $Directory = Get-PSGPODirectory -Server $Server
            # The configuration of the domain kept as it is, its workflow on for the test, every
            # other setting kept; written back byte for byte at the end.
            $Original = $Directory.ReadConfigurationFile()
            $Values = @{}
            foreach ($Setting in @(Get-PSGPOConfigurationSetting | Where-Object IsSet)) { $Values[$Setting.Key] = $Setting.Value }
            $Values['Workflow.Enabled'] = $true
            $Values['Workflow.Creators'] = 'GPO-Tier1-Admins, GPO-Tier2-Admins'
            Save-PSGPODomainConfiguration -Directory $Directory -Values $Values -Confirm:$false
            $Tier1Cache = $env:PSGPOTOOLS_TEST_TIER1_CCACHE
            if (-not $Tier1Cache) {
                $Tier1Cache = "FILE:$(Join-Path $TestDrive 'tiers1.ccache')"
                $Cache = $env:KRB5CCNAME
                try {
                    $env:KRB5CCNAME = $Tier1Cache
                    $null = 'H@rdenB0x!' | kinit "tiers1@$($Directory.DomainName.ToUpperInvariant())" 2>&1
                } finally { $env:KRB5CCNAME = $Cache }
            }
            # A script run as tiers1, in the scope of the module, with $d its directory; returns
            # what the script outputs last, as JSON, and every line it wrote.
            function Invoke-AsTier1 {
                param([string]$Script)
                $Code = "Import-Module '$Module' 3>`$null; & (Get-Module HGPM) { `$d = Get-PSGPODirectory -Server '$Server' 3>`$null; $Script } | ConvertTo-Json -Compress -Depth 4"
                $Saved = $env:KRB5CCNAME
                try {
                    $env:KRB5CCNAME = $Tier1Cache
                    $Lines = @(pwsh -NoProfile -NonInteractive -Command $Code 2>&1 | ForEach-Object { "$_" })
                } finally { $env:KRB5CCNAME = $Saved }
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $Lines -join "`n"; Result = $(try { $Lines[-1] | ConvertFrom-Json } catch { $null }) }
            }
            function Get-GpoDescriptor {
                param([string]$DistinguishedName)
                $Connection = New-PSGPODirectoryConnection -Directory $Directory
                try { Get-PSGPODomainSecurityDescriptor -Connection $Connection -DistinguishedName $DistinguishedName } finally { $Connection.Dispose() }
            }
            $DomainSid = (Get-PSGPOAccountGroupSid -Connection (New-PSGPODirectoryConnection -Directory $Directory) -DomainDistinguishedName $Directory.Domain.DistinguishedName -Account $Directory.Account)[0] -replace '-\d+$'
        }
        AfterAll {
            $Read = Get-PSGPODirectory -Server $Server
            foreach ($Name in 'CI - Approval', 'CI - Approval changed') {
                if ($Read.FindGpo($Name)) { Remove-PSGPO -Directory $Read -Name $Name -NoBackup -Confirm:$false 3>$null | Out-Null }
            }
            if ($Original) { $Directory.WriteConfigurationFile($Original) } else { $Directory.WriteConfigurationFile($null) }
        }

        It 'Makes the GPO of a creator wait, then gives it to Tier 0 at its approval, the permissions the creator added removed' {
            # tiers1 creates it: pending, nobody applies it; then it adds a permission of its own.
            $Created = Invoke-AsTier1 @'
$gpo = $d.NewGpo('CI - Approval')
$c = New-PSGPODirectoryConnection -Directory $d
try {
    $sd = Get-PSGPODomainSecurityDescriptor -Connection $c -DistinguishedName $gpo.DistinguishedName
    $sd.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, [GPOToolsAce]::ContainerInherit, 0x000F00FF, ($d.Workflow.DomainSid + '-513'), [guid]::Empty))
    Set-PSGPODomainDacl -Connection $c -DistinguishedName $gpo.DistinguishedName -Descriptor (Get-PSGPOExplicitDescriptor -Descriptor $sd) -Name $gpo.DisplayName
} finally { $c.Dispose() }
[pscustomobject]@{ State = $gpo.ApprovalState; Creator = $d.IsWorkflowCreator(); Dn = $gpo.DistinguishedName; Id = $gpo.Id.ToString() }
'@
            $Created.ExitCode | Should -Be 0 -Because $Created.Output
            $Created.Result.State | Should -Be 'Pending'
            $Created.Result.Creator | Should -BeTrue
            $Pending = Get-GpoDescriptor $Created.Result.Dn
            @($Pending.Dacl | Where-Object { Test-PSGPOApplyAce -Ace $_ }) | Should -BeNullOrEmpty -Because 'a pending GPO applies to nobody'
            $Pending.Owner | Should -Not -Be "$DomainSid-512" -Because 'its creator owns it'

            # The administrator approves it: Tier 0 owns it, the permissions the creator added are gone.
            $Read = Get-PSGPODirectory -Server $Server
            $Result = Approve-PSGPO -Directory $Read -Name 'CI - Approval' -CreatorRights ReadOnly -ApplyTo 'Authenticated Users' -BackupPath (Join-Path $TestDrive 'backups') -Confirm:$false 3>$null
            $Result.Problem | Should -BeNullOrEmpty
            @($Result.RemovedPermissions | Where-Object { $_ -match "$DomainSid-513" }).Count | Should -BeGreaterThan 0 -Because 'the approver is told'
            $Approved = Get-GpoDescriptor $Created.Result.Dn
            $Approved.Owner | Should -Be "$DomainSid-512"
            @($Approved.Dacl | Where-Object { $_.Sid -in "$DomainSid-513", $Pending.Owner -and -not ($_.Flags -band [GPOToolsAce]::Inherited) }) | Should -BeNullOrEmpty -Because 'nor the creator nor what it added keep a right'
            @($Approved.Dacl | Where-Object { $_.Sid -eq 'S-1-5-11' -and (Test-PSGPOApplyAce -Ace $_) }).Count | Should -Be 1
            $Folder = Get-PSGPOSysvolItemAcl -Directory $Read -Share 'SYSVOL' -Path "$($Read.DomainName)\Policies\{$($Created.Result.Id.ToUpperInvariant())}"
            $Folder.Owner | Should -Be "$DomainSid-512" -Because 'its SYSVOL folder too'
            @($Folder.Dacl | Where-Object { $_.Sid -in "$DomainSid-513", $Pending.Owner }) | Should -BeNullOrEmpty

            # tiers1 cannot change it anymore (ReadOnly).
            $Write = Invoke-AsTier1 @'
$gpo = $d.FindGpo('CI - Approval')
$written = try { $d.WritePolicyFile($gpo, 'Machine', [byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0)); $true } catch { $false }
[pscustomobject]@{ State = $gpo.ApprovalState; CanEdit = $gpo.CanEdit; Written = $written }
'@
            $Write.ExitCode | Should -Be 0 -Because $Write.Output
            $Write.Result.State | Should -Be 'Approved'
            $Write.Result.CanEdit | Should -BeFalse
            $Write.Result.Written | Should -BeFalse -Because 'the creator reads an approved GPO only'
        }

        It 'Does not approve a GPO its creator changed after the review' {
            $Created = Invoke-AsTier1 "`$gpo = `$d.NewGpo('CI - Approval changed'); [pscustomobject]@{ State = `$gpo.ApprovalState }"
            $Created.Result.State | Should -Be 'Pending' -Because $Created.Output
            $Read = Get-PSGPODirectory -Server $Server
            $Gpo = $Read.FindGpo('CI - Approval changed')
            $Stamp = Get-PSGPOReviewStamp -Directory $Read -Gpo $Gpo

            $Changed = Invoke-AsTier1 "`$gpo = `$d.FindGpo('CI - Approval changed'); `$d.WritePolicyFile(`$gpo, 'Machine', [byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0)); [pscustomobject]@{ Version = `$gpo.Version }"
            $Changed.ExitCode | Should -Be 0 -Because $Changed.Output

            { Invoke-PSGPOApproval -Directory $Read -Gpo $Gpo -CreatorRights ReadOnly -ApplyTo (Resolve-PSGPOApplyTo -Directory $Read -Name 'Authenticated Users') -BackupPath (Join-Path $TestDrive 'backups') -ReviewStamp $Stamp } |
                Should -Throw -ExpectedMessage '*changed since it was reviewed*'
            (Get-PSGPODirectory -Server $Server).FindGpo('CI - Approval changed').ApprovalState | Should -Be 'Pending'
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
            $ImportName = "PSGPOTools test GPO import $Stamp"
            $RulesName = "PSGPOTools test GPO rules $Stamp"
            # An OU of the test, then the directory read again to have it.
            $null = Invoke-PSGPOSambaTool -ArgumentList 'ou', 'add', $OuDN, '-H', "ldap://$Server", '--use-kerberos=required'
            $Directory = Get-PSGPODirectory -Server $Server
            $Ou = $Directory.FindSom($OuDN)
            # The changes of the tests go to an audit log of the test, not to that of the account.
            $script:AuditLog = Join-Path $TestDrive 'audit'
            Mock Get-PSGPOAuditPath { $script:AuditLog }
        }

        AfterAll {
            # Everything the tests created, whatever failed.
            foreach ($Name in $GpoName, $SecondName, $TerminalName, $ImportName, $RulesName) {
                $Gpo = (Get-PSGPODirectory -Server $Server).FindGpo($Name)
                if (-not $Gpo) { continue }
                $Id = '{' + $Gpo.Id.ToString().ToUpperInvariant() + '}'
                try { $null = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'dellink', $OuDN, $Id, '-H', "ldap://$Server", '--use-kerberos=required' } catch { }
                try { $null = Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'del', $Id, '-H', "ldap://$Server", '--use-kerberos=required' } catch { Write-Warning $_ }
            }
            try { $null = Invoke-PSGPOSambaTool -ArgumentList 'ou', 'delete', $OuDN, '-H', "ldap://$Server", '--use-kerberos=required', '--force-subtree-delete' } catch { Write-Warning $_ }
        }

        It 'Copies ADMX files into Policies of SYSVOL, as Install-PSGPOAdmx -CentralStore does' {
            # A folder of the test beside the central store, not the central store of the domain.
            $Folder = "PSGPOTools test admx $Stamp"
            $Source = Join-Path $TestDrive 'admx'
            $null = New-Item -ItemType Directory -Path (Join-Path $Source 'en-US') -Force
            [System.IO.File]::WriteAllText((Join-Path $Source 'Test.admx'), '<policyDefinitions/>')
            [System.IO.File]::WriteAllText((Join-Path $Source 'en-US' 'Test.adml'), '<policyDefinitionResources/>')
            try {
                $Store = Copy-PSGPOAdmxCentralStore -Directory $Directory -Source $Source -Folder $Folder
                $Store | Should -Be "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\$Folder"
                $Read = Read-PSGPOSysvolItem -Directory $Directory -Share 'SYSVOL' -Path "$($Directory.DomainName)\Policies\$Folder\en-US\Test.adml"
                [System.Text.Encoding]::UTF8.GetString($Read) | Should -Be '<policyDefinitionResources/>'
                # Again: the files there are replaced, the folders kept.
                $null = Copy-PSGPOAdmxCentralStore -Directory $Directory -Source $Source -Folder $Folder
            } finally {
                if ($IsWindows) { Remove-Item -LiteralPath "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\$Folder" -Recurse -Force -ErrorAction SilentlyContinue }
                else { try { $null = Invoke-PSGPOSmbClient -Server $Directory.Server -Share 'SYSVOL' -Command ('deltree "{0}\Policies\{1}"' -f $Directory.DomainName, $Folder) } catch { Write-Warning $_ } }
            }
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

        It 'Changes the permissions of the GPO in the domain and in its SYSVOL folder' {
            $Gpo = $Directory.FindGpo($GpoName)
            $Users = Resolve-PSGPOApplyTo -Directory $Directory -Name 'Domain Users'
            $Computers = Resolve-PSGPOApplyTo -Directory $Directory -Name 'Domain Computers'
            $Location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo

            (Set-PSGPOPermission -Name $GpoName -Directory $Directory -Account 'Domain Users' -Permission GpoEdit -Confirm:$false).Permission | Should -Be 'GpoEdit'
            (Get-PSGPOPermission -Name $GpoName -Server $Server | Where-Object Sid -EQ $Users.Sid).Permission | Should -Be 'GpoEdit' -Because 'the domain stored it'
            $Folder = Get-PSGPOSysvolItemAcl -Directory $Directory -Share $Location.Share -Path $Location.Path
            @($Folder.Dacl | Where-Object Sid -EQ $Users.Sid).Count | Should -Be 1 -Because 'the SYSVOL folder takes the ACL of the GPO'

            Set-PSGPOPermission -Name $GpoName -Directory $Directory -Account 'Domain Computers' -SecurityFiltering Add -Confirm:$false | Out-Null
            Set-PSGPOPermission -Name $GpoName -Directory $Directory -Account 'Authenticated Users' -SecurityFiltering Remove -Confirm:$false | Out-Null
            $Read = (Get-PSGPODirectory -Server $Server).FindGpo($GpoName)
            $Read.SecurityFiltering | Should -Be @($Computers.Name)

            # As it was: only Authenticated Users applies it, Domain Users has no permission.
            Set-PSGPOPermission -Name $GpoName -Directory $Directory -Account 'Authenticated Users' -SecurityFiltering Add -Confirm:$false | Out-Null
            Set-PSGPOPermission -Name $GpoName -Directory $Directory -Account 'Domain Computers' -Permission None -Confirm:$false | Out-Null
            Set-PSGPOPermission -Name $GpoName -Directory $Directory -Account 'Domain Users' -Permission None -Confirm:$false | Out-Null
            $Rows = @(Get-PSGPOPermission -Name $GpoName -Server $Server)
            $Rows.Sid | Should -Not -Contain $Users.Sid
            ($Rows | Where-Object Sid -EQ 'S-1-5-11').Permission | Should -Be 'GpoApply'
            $Folder = Get-PSGPOSysvolItemAcl -Directory $Directory -Share $Location.Share -Path $Location.Path
            @($Folder.Dacl | Where-Object Sid -EQ $Users.Sid).Count | Should -Be 0
        }

        It 'Imports the settings of a GPMC backup of another domain into a new GPO, with a migration table' {
            # The backup of the GPO TEST of the Windows lab, given a user right for APPLY_TEST of that domain.
            $Root = Join-Path $TestDrive 'gpmc'
            $Folder = Join-Path $Root '{CDACBF0D-55B7-453B-B0E6-29AA70A61AAF}'
            $SecEdit = Join-Path $Folder 'DomainSysvol' 'GPO' 'Machine' 'microsoft' 'windows nt' 'SecEdit'
            $null = New-Item -ItemType Directory -Path $SecEdit -Force
            foreach ($Name in 'Backup.xml', 'bkupInfo.xml') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Fixtures' 'GpmcBackup' '{CDACBF0D-55B7-453B-B0E6-29AA70A61AAF}' $Name) -Destination $Folder }
            [System.IO.File]::WriteAllText((Join-Path $SecEdit 'GptTmpl.inf'),
                "[Unicode]`r`nUnicode=yes`r`n[Privilege Rights]`r`nSeBatchLogonRight = *S-1-5-21-204864384-581126797-2929775416-1108,*S-1-5-32-551`r`n[Version]`r`nsignature=""`$CHICAGO`$""`r`nRevision=1`r`n",
                [System.Text.UnicodeEncoding]::new($false, $true))
            $Table = Join-Path $TestDrive 'lab.migtable'
            Save-PSGPOMigrationTable -Path $Table -Entry @([pscustomobject]@{ Type = 'GlobalGroup'; Source = 'APPLY_TEST@powershell.labo'; Destination = 'Domain Users'; Mode = 'Explicit' })
            $Users = Resolve-PSGPOApplyTo -Directory $Directory -Name 'Domain Users'

            # Its own GPO: the tests that follow write to a GPO without settings.
            $Result = Import-PSGPO -Path $Root -TargetName $ImportName -CreateIfNeeded -MigrationTable $Table -Directory $Directory -NoBackup -Confirm:$false
            $Result.Source.Kind | Should -Be 'GPMC'
            $Read = (Get-PSGPODirectory -Server $Server).FindGpo($ImportName)
            $Template = [System.Text.Encoding]::Unicode.GetString($Directory.ReadSecurityTemplate($Read))
            $Template | Should -BeLike "*SeBatchLogonRight = ``*$($Users.Sid),``*S-1-5-32-551*" -Because 'APPLY_TEST of the other domain is Domain Users of this one'
            $Read.MachineExtensionNames | Should -BeLike '*827D319E-6EAC-11D2-A4EA-00C04F79F83A*' -Because 'the computers apply the security settings it has now'
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

        It 'Enforces, disables and moves a link, and blocks the inheritance of the OU, as the domain reads them back' {
            $Second = $Ou.Links | Where-Object { $_.Gpo.DisplayName -eq $SecondName }
            $Directory.SetLink($Ou, $Second, $false, $true)
            $Directory.MoveLink($Ou, $Second, 1)
            $Directory.SetBlockInheritance($Ou, $true)

            $ReadOu = (Get-PSGPODirectory -Server $Server).FindSom($OuDN)
            @($ReadOu.Links | Sort-Object Order | ForEach-Object { $_.Gpo.DisplayName }) | Should -Be @($SecondName, $GpoName)
            $ReadSecond = $ReadOu.Links | Where-Object { $_.Gpo.DisplayName -eq $SecondName }
            $ReadSecond.Enabled | Should -BeFalse
            $ReadSecond.Enforced | Should -BeTrue
            $ReadOu.BlockInheritance | Should -BeTrue

            # Back as they were, for the next tests.
            $Directory.SetLink($Ou, $Second, $true, $false)
            $Directory.MoveLink($Ou, $Second, 2)
            $Directory.SetBlockInheritance($Ou, $false)
            $ReadOu = (Get-PSGPODirectory -Server $Server).FindSom($OuDN)
            @($ReadOu.Links | Sort-Object Order | ForEach-Object { $_.Gpo.DisplayName }) | Should -Be @($GpoName, $SecondName)
            @($ReadOu.Links.Enabled) | Should -Be @($true, $true)
            $ReadOu.BlockInheritance | Should -BeFalse
        }

        It 'Creates a WMI filter, links the GPO to it, changes the filter, reads both back, and deletes the filter once unlinked' {
            $Gpo = $Directory.FindGpo($GpoName)
            $FilterName = "PSGPOTools test WMI $Stamp"
            $Filter = $Directory.NewWmiFilter($FilterName, 'Test of PSGPOTools', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = "SELECT * FROM Win32_OperatingSystem WHERE Caption LIKE '%;%'" }))
            try {
                $Directory.SetWmiFilter($Gpo, $Filter)
                $Read = Get-PSGPODirectory -Server $Server
                $ReadFilter = $Read.FindWmiFilter($FilterName)
                $ReadFilter.Id | Should -Be $Filter.Id
                $ReadFilter.Description | Should -Be 'Test of PSGPOTools'
                $ReadFilter.Queries[0].Query | Should -Be "SELECT * FROM Win32_OperatingSystem WHERE Caption LIKE '%;%'"
                $Read.FindGpo($GpoName).WmiFilterId | Should -Be $Filter.Id

                # Changed in place: another name, no description, two queries; the GPO keeps it.
                $Directory.EditWmiFilter($Filter, "$FilterName (changed)", '', @(
                        [pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1' }
                        [pscustomobject]@{ Namespace = 'root\StandardCimv2'; Query = 'SELECT * FROM MSFT_NetAdapter' }))
                $Read = Get-PSGPODirectory -Server $Server
                $ReadFilter = $Read.FindWmiFilter("$FilterName (changed)")
                $ReadFilter.Id | Should -Be $Filter.Id
                $ReadFilter.Description | Should -BeNullOrEmpty
                $ReadFilter.GetQueryText() | Should -Be 'root\CIMv2: SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1; root\StandardCimv2: SELECT * FROM MSFT_NetAdapter'
                $Read.FindGpo($GpoName).WmiFilterId | Should -Be $Filter.Id
                # Changed meanwhile by another console: refused.
                $Read.EditWmiFilter($ReadFilter, $ReadFilter.Name, 'Other console', $ReadFilter.Queries)
                { $Directory.EditWmiFilter($Filter, $Filter.Name, 'This console', $Filter.Queries) } | Should -Throw -ExpectedMessage '*changed in the domain meanwhile*'

                { $Directory.RemoveWmiFilter($Filter) } | Should -Throw -ExpectedMessage '*is used by*'
                $Directory.SetWmiFilter($Gpo, $null)
                (Get-PSGPODirectory -Server $Server).FindGpo($GpoName).WmiFilterId | Should -BeNullOrEmpty
            } finally {
                if ($Gpo.WmiFilterId) { $Directory.SetWmiFilter($Gpo, $null) }
                $Directory.RemoveWmiFilter($Filter)
            }
            (Get-PSGPODirectory -Server $Server).FindWmiFilter($FilterName) | Should -BeNullOrEmpty
        }

        It 'Exports a WMI filter of the domain to a .mof file, with its author and dates, and imports it again' {
            $FilterName = "PSGPOTools test MOF $Stamp"
            $Filter = $Directory.NewWmiFilter($FilterName, 'Test "MOF" of PSGPOTools', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = "SELECT * FROM Win32_OperatingSystem WHERE Caption LIKE '%\%'" }))
            $Folder = Join-Path $TestDrive "mof-$Stamp"
            try {
                $Read = Get-PSGPODirectory -Server $Server
                $ReadFilter = $Read.FindWmiFilter($FilterName)
                $ReadFilter.Author | Should -Be $Directory.Account
                $ReadFilter.CreationDate | Should -Be $Filter.CreationDate
                $File = Export-PSGPOWmiFilter -Directory $Read -Name $FilterName -Path $Folder
                $Mof = ConvertFrom-PSGPOWmiFilterMof -Bytes ([System.IO.File]::ReadAllBytes($File.FullName))
                $Mof.Domain | Should -Be $Directory.DomainName
                $Mof.Id | Should -Be $Filter.Id
                $Mof.CreationDate | Should -Be $Filter.CreationDate
                $Mof.Description | Should -Be 'Test "MOF" of PSGPOTools'

                $Imported = Import-PSGPOWmiFilter -Directory $Directory -Path $File.FullName -Name "$FilterName (imported)"
                $Imported.Id | Should -Not -Be $Filter.Id
                $Again = (Get-PSGPODirectory -Server $Server).FindWmiFilter("$FilterName (imported)")
                $Again.GetQueryText() | Should -Be $Filter.GetQueryText()
                $Again.Description | Should -Be 'Test "MOF" of PSGPOTools'
            } finally {
                foreach ($Name in $FilterName, "$FilterName (imported)") {
                    $Left = $Directory.FindWmiFilter($Name)
                    if ($Left) { $Directory.RemoveWmiFilter($Left) }
                }
            }
        }

        It 'Delegates the WMI filters in the domain, as GPMC: who creates them, who changes one, the filters inheriting full control' {
            $FilterName = "PSGPOTools test WMI delegation $Stamp"
            $Users = Resolve-PSGPOApplyTo -Directory $Directory -Name 'Domain Users'
            $Filter = $Directory.NewWmiFilter($FilterName, '', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            $Level = { param($Name) @(Get-PSGPOWmiFilterPermission -Server $Server -Name $(if ($Name) { $Name }) | Where-Object Sid -EQ $Users.Sid | ForEach-Object { "$($_.Permission)$(if ($_.Inherited) { ' inherited' })" }) -join ',' }
            try {
                @(Get-PSGPOWmiFilterPermission -Directory $Directory | Where-Object Permission -EQ 'WmiFullControl').Count | Should -BeGreaterThan 0 -Because 'the administrators of the domain create and change every filter'
                $null = Set-PSGPOWmiFilterPermission -Directory $Directory -Account $Users.Sid -Permission WmiCreate -Confirm:$false
                & $Level | Should -Be 'WmiCreate'
                & $Level $FilterName | Should -BeNullOrEmpty
                $null = Set-PSGPOWmiFilterPermission -Directory $Directory -Account $Users.Sid -Permission WmiFullControl -Confirm:$false
                & $Level | Should -Be 'WmiFullControl'
                & $Level $FilterName | Should -Be 'WmiFullControl inherited' -Because 'the domain gives the filters what the container gives them'
                $null = Set-PSGPOWmiFilterPermission -Directory $Directory -Account $Users.Sid -Permission None -Confirm:$false
                & $Level | Should -BeNullOrEmpty
                & $Level $FilterName | Should -BeNullOrEmpty

                $null = Set-PSGPOWmiFilterPermission -Directory $Directory -Name $FilterName -Account $Users.Sid -Permission WmiEdit -Confirm:$false
                & $Level $FilterName | Should -Be 'WmiEdit'
                $null = Set-PSGPOWmiFilterPermission -Directory $Directory -Name $FilterName -Account $Users.Sid -Permission None -Confirm:$false
                & $Level $FilterName | Should -BeNullOrEmpty
            } finally {
                $null = Set-PSGPOWmiFilterPermission -Directory $Directory -Account $Users.Sid -Permission None -Confirm:$false -ErrorAction SilentlyContinue
                $Directory.RemoveWmiFilter($Filter)
            }
        }

        It 'Writes the changes the domain accepted to the audit log' {
            $Entries = @(Get-PSGPOAuditLog -Path $script:AuditLog -Domain $Directory.DomainName)
            @($Entries.Action) | Should -Contain 'NewGpo'
            @($Entries.Action) | Should -Contain 'NewLink'
            @($Entries.Action) | Should -Contain 'SetLink'
            @($Entries.Action) | Should -Contain 'SetBlockInheritance'
            ($Entries | Where-Object Action -EQ 'NewGpo' | Select-Object -Last 1).GpoName | Should -Be $GpoName
            ($Entries | Select-Object -First 1).Server | Should -Be $Directory.Server
        }

        It 'Reads the domain again in place, as Refresh does' {
            $Console = Get-PSGPODirectory -Server $Server
            $Held = $Console
            $Other = Get-PSGPODirectory -Server $Server
            $Other.SetBlockInheritance($Other.FindSom($OuDN), $true)
            try {
                Update-PSGPODirectoryFromDomain -Directory $Console
                [object]::ReferenceEquals($Held, $Console) | Should -BeTrue
                $Console.FindSom($OuDN).BlockInheritance | Should -BeTrue -Because 'the change of the other console shows'
            } finally {
                $Other.SetBlockInheritance($Other.FindSom($OuDN), $false)
            }
        }

        It 'Keeps the change another console made to the links meanwhile' {
            $Other = Get-PSGPODirectory -Server $Server
            $OtherOu = $Other.FindSom($OuDN)
            $Second = $Ou.Links | Where-Object { $_.Gpo.DisplayName -eq $SecondName }
            $Directory.SetLink($Ou, $Second, $true, $true)
            # The other console read the links before: it changes the links as the domain has them.
            $OtherSecond = $OtherOu.Links | Where-Object { $_.Gpo.DisplayName -eq $SecondName }
            $Other.MoveLink($OtherOu, $OtherSecond, 1)
            $OtherSecond.Enforced | Should -BeTrue -Because 'the enforced link the first console set is kept'
            $ReadOu = (Get-PSGPODirectory -Server $Server).FindSom($OuDN)
            ($ReadOu.Links | Where-Object { $_.Gpo.DisplayName -eq $SecondName }).Enforced | Should -BeTrue
            ($ReadOu.Links | Where-Object { $_.Gpo.DisplayName -eq $SecondName }).Order | Should -Be 1
            $Other.SetLink($OtherOu, $OtherSecond, $true, $false)
            $Other.MoveLink($OtherOu, $OtherSecond, 2)
            # The first console reads its links again (the next tests use it).
            $Directory.SetLinks($Ou, [GPOToolsGpoLink]::Format($OtherOu.Links))
            foreach ($Link in $Ou.Links) { $Link.Gpo = $Directory.FindGpoByDistinguishedName($Link.GpoDistinguishedName) }
        }

        It 'Writes the settings of a rule set in a new GPO, which the domain reads back, and audits it' {
            $Set = Get-PSGPOPolicyRuleSet -Path (Join-Path $PSScriptRoot 'Fixtures' 'PolicyRules' 'gpo2policyrules.PolicyRules')
            $Result = Import-PSGPOPolicyRuleSet -Directory $Directory -RuleSet $Set -TargetName $RulesName -PolicyName 'HGPM Test - Computer' -CreateIfNeeded -NoBackup -Confirm:$false 3>$null
            $Result.Registry | Should -Be 16
            $Result.SecurityTemplate | Should -Be 14
            $Result.Audit | Should -Be 4

            # Read again from the domain: every setting of the set, but the one it has no data of.
            $Read = Get-PSGPODirectory -Server $Server
            $Again = Get-PSGPOPolicyRuleSet -Directory $Read -Name $RulesName -SetName 'Domain'
            $Imported = [GPOToolsPolicyRuleSet]::new('Set')
            foreach ($Rule in $Set.Rules) { if ($Rule.PolicyName -eq 'HGPM Test - Computer') { $Imported.Rules.Add($Rule) } }
            $Rows = @(Compare-PSGPOPolicyRuleSet -RuleSet $Imported, $Again -DifferenceOnly)
            @($Rows | ForEach-Object Setting) | Should -Be @('BigEndian')
            $Gpo = $Read.FindGpo($RulesName)
            $Gpo.MachineExtensionNames.Contains('[{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}]') | Should -BeTrue -Because $Gpo.MachineExtensionNames
            $Gpo.GetComputerVersion() | Should -BeGreaterThan 0
            $Gpo.GetUserVersion() | Should -BeGreaterThan 0
            @(Get-ChildItem -LiteralPath $script:AuditLog -Filter '*.jsonl' | Get-Content | Where-Object { $_ -match '"Action":"ImportPolicyRuleSet"' }).Count | Should -Be 1
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

            # The first directory read the GPO before that change, as another console would have:
            # it refuses to write its copy over it, and writes nothing.
            $Other = [GPOToolsRegistryPol]::new()
            { $Directory.WritePolicyFile($Gpo, 'Machine', $Other.ToBytes()) } | Should -Throw -ExpectedMessage '*changed since it was read (version 1, now 65537)*'
            [Linq.Enumerable]::SequenceEqual([byte[]]$Read.ReadPolicyFile($Again, 'Machine'), [byte[]]$Pol.ToBytes()) | Should -BeTrue
            (Get-PSGPODirectory -Server $Server).FindGpo($GpoName).Version | Should -Be 0x00010001
            # Read again, it writes: the GPO the next tests change.
            $Gpo.Version = (Get-PSGPODirectory -Server $Server).FindGpo($GpoName).Version
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

        It 'Writes the preferences of the GPO in SYSVOL and declares their extension as GPMC does' {
            $Gpo = $Directory.FindGpo($GpoName)
            $Registry = Get-PSGPOPreferenceExtension -Id Registry
            $Before = (Get-PSGPODirectory -Server $Server).FindGpo($GpoName).Version
            $File = [GPOToolsPreferenceFile]::Create($Registry.Root, $Registry.RootClsid)
            $null = New-PSGPOPreferenceItem -File $File -Type $Registry.Items[0] -Values @{ key = 'SOFTWARE\PSGPOTools'; name = 'Test'; type = 'REG_SZ'; value = 'on' }
            $Directory.WritePreferenceFile($Gpo, 'Machine', $Registry.Path, $File.ToBytes(), $Registry.Cse, $Registry.Tool)

            $Read = Get-PSGPODirectory -Server $Server
            $Again = $Read.FindGpo($GpoName)
            $Again.Version | Should -Be ($Before + 1)
            [Linq.Enumerable]::SequenceEqual([byte[]]$Read.ReadPreferenceFile($Again, 'Machine', $Registry.Path), [byte[]]$File.ToBytes()) | Should -BeTrue
            $Again.MachineExtensionNames.Contains('[{00000000-0000-0000-0000-000000000000}') | Should -BeTrue
            $Again.MachineExtensionNames.Contains('[{B087BE9D-ED37-454F-AF9C-04291E351182}{BEE07A6A-EC9F-4659-B8C9-0B1937907C83}]') | Should -BeTrue
            @(Get-PSGPOPreferenceItem -File ([GPOToolsPreferenceFile]::Parse($Read.ReadPreferenceFile($Again, 'Machine', $Registry.Path))) -Extension $Registry).Name | Should -Be @('Test')
        }

        It 'Backs up the GPO from SYSVOL until it changes, and tells what changed' {
            $Root = Join-Path $TestDrive 'domain-backups'
            $Gpo = $Directory.FindGpo($GpoName)
            $First = Backup-PSGPO -Directory $Directory -Path $Root -Name $GpoName
            $First.Result | Should -Be 'Created'
            $First.Modified | Should -Not -BeNullOrEmpty -Because 'whenChanged of the GPO names the backup'
            @($First.Files.Path) | Should -Contain 'GPT.INI'
            @($First.Files.Path) | Should -Contain 'Machine\Registry.pol'
            @($First.Files.Path) | Should -Contain 'Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf'
            [Linq.Enumerable]::SequenceEqual([System.IO.File]::ReadAllBytes((Join-Path $First.Path 'Files' 'Machine' 'Registry.pol')),
                [byte[]]$Directory.ReadPolicyFile($Gpo, 'Machine')) | Should -BeTrue
            (Backup-PSGPO -Directory $Directory -Path $Root -Name $GpoName).Result | Should -Be 'Unchanged'

            $Template = [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($Gpo))
            Set-PSGPOSecurityValue -Template $Template -Setting (Get-PSGPOSecuritySetting | Where-Object Key -EQ 'MinimumPasswordLength') -Value 16
            $Directory.WriteSecurityTemplate($Gpo, $Template.ToBytes())
            $Second = Backup-PSGPO -Directory $Directory -Path $Root -Name $GpoName
            $Second.Result | Should -Be 'Created'
            $Change = Compare-PSGPOBackup -ReferenceBackup $First -DifferenceBackup $Second | Where-Object Name -EQ 'Minimum password length'
            "$($Change.Change): $($Change.Before) -> $($Change.After)" | Should -Be 'Changed: 14 characters -> 16 characters'

            # Back to the first backup: its files in SYSVOL, a higher version in GPT.INI and the directory.
            $Before = (Get-PSGPODirectory -Server $Server).FindGpo($GpoName).Version
            $Result = Restore-PSGPO -Backup $First -Directory $Directory -Confirm:$false
            $Result.BackupBefore | Should -Not -BeNullOrEmpty
            $Read = Get-PSGPODirectory -Server $Server
            $Again = $Read.FindGpo($GpoName)
            $Again.GetComputerVersion() | Should -Be (($Before -band 0xFFFF) + 1)
            $Again.GetUserVersion() | Should -Be (($Before -shr 16) + 1)
            [System.Text.Encoding]::ASCII.GetString((Read-PSGPOSysvolFile -Directory $Read -Gpo $Again -Path 'GPT.INI')) | Should -Match "(?m)^Version=$($Again.Version)\r?$"
            $Template = [GPOToolsSecurityTemplate]::Parse($Read.ReadSecurityTemplate($Again))
            $Template.GetValue('System Access', 'MinimumPasswordLength') | Should -Be '14'
            $Again.MachineExtensionNames | Should -Be $First.MachineExtensionNames
            $Restored = Backup-PSGPO -Directory $Read -Path $Root -Name $GpoName
            Compare-PSGPOBackup -ReferenceBackup $First -DifferenceBackup $Restored | Should -BeNullOrEmpty
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

            # Read again with the domain: the names of the groups, as GPMC shows the filtering.
            $Read = Get-PSGPODirectory -Server $Server
            $Read.FindGpo($SecondName).SecurityFiltering | Should -Be @("APPLY_$SecondName")
            $Read.FindGpo($SecondName).DeniedTo | Should -Be @("DENY_$SecondName")
            ($Read.Gpos | Where-Object Id -EQ ([guid]'31B2F340-016D-11D2-945F-00C04FB984F9')).SecurityFiltering | Should -Be @('Authenticated Users')
        }

        It 'Renames a GPO in the domain, and refuses a copy read before someone renamed it' {
            $Gpo = $Directory.FindGpo($SecondName)
            $Id = $Gpo.Id
            try {
                $Directory.RenameGpo($Gpo, "$SecondName renamed")
                $Read = Get-PSGPODirectory -Server $Server
                $Stale = $Read.Gpos | Where-Object Id -EQ $Id
                $Stale.DisplayName | Should -Be "$SecondName renamed"
                $Stale.FileSysPath | Should -Be $Gpo.FileSysPath -Because 'its GUID, so its folder, does not change'
                $Directory.RenameGpo($Gpo, $SecondName)
                { $Read.RenameGpo($Stale, "$SecondName again") } | Should -Throw -ExpectedMessage '*changed in the domain meanwhile*'
                (Get-PSGPODirectory -Server $Server).FindGpo($SecondName).Id | Should -Be $Id
            } finally {
                # The other tests and the cleanup find it by its name.
                $Now = (Get-PSGPODirectory -Server $Server).Gpos | Where-Object Id -EQ $Id
                if ($Now -and $Now.DisplayName -ne $SecondName) { Set-PSGPODomainGpoName -Directory $Directory -Gpo $Now -DisplayName $SecondName }
                $Gpo.DisplayName = $SecondName
            }
        }

        It 'Creates a GPO from a terminal without waiting for a password (the window froze)' -Skip:(-not (Get-Command script -ErrorAction SilentlyContinue)) {
            # samba-tool gpo create asks for a password on the terminal, even with Kerberos.
            $Script = Join-Path $TestDrive 'create-from-terminal.ps1'
            $Module = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
            Set-Content -LiteralPath $Script -Value @"
Import-Module '$Module'
& (Get-Module HGPM) { Invoke-PSGPOSambaTool -ArgumentList 'gpo', 'create', '$TerminalName', '-H', 'ldap://$Server', '--use-kerberos=required' }
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

        It 'Deletes the links of an OU, the gPLink removed with the last one, and keeps the GPOs' {
            $Read = Get-PSGPODirectory -Server $Server
            $ReadOu = $Read.FindSom($OuDN)
            $Read.RemoveLink($ReadOu, ($ReadOu.Links | Where-Object { $_.Gpo.DisplayName -eq $GpoName }))
            @($ReadOu.Links.Gpo.DisplayName) | Should -Be @('Default Domain Policy')
            $ReadOu.Links[0].Order | Should -Be 1
            @((Get-PSGPODirectory -Server $Server).FindSom($OuDN).Links.Gpo.DisplayName) | Should -Be @('Default Domain Policy')

            # A stale copy whose link is gone from the domain: refused, nothing written.
            $StaleOu = $Directory.FindSom($OuDN)
            $StaleLink = $StaleOu.Links | Where-Object { $_.Gpo.DisplayName -eq $GpoName }
            { $Directory.RemoveLink($StaleOu, $StaleLink) } | Should -Throw -ExpectedMessage '*not linked there anymore*'

            $Read.RemoveLink($ReadOu, $ReadOu.Links[0])
            $ReadOu.Links.Count | Should -Be 0
            $Connection = New-PSGPODirectoryConnection -Directory $Read
            try { $Entry = Invoke-PSGPOLdapSearch -Connection $Connection -SearchBase $OuDN -Scope Base -Attribute 'gPLink' }
            finally { $Connection.Dispose() }
            Get-PSGPOLdapValue $Entry 'gPLink' | Should -BeNullOrEmpty -Because 'samba-tool gpo dellink removes the attribute with the last link'
            (Get-PSGPODirectory -Server $Server).FindGpo($GpoName) | Should -Not -BeNullOrEmpty -Because 'the GPO itself is kept'
        }

        It 'Deletes a GPO, its links first, then creates it again from its backup' {
            $Root = Join-Path $TestDrive "bin-$([guid]::NewGuid())"
            $Read = Get-PSGPODirectory -Server $Server
            $Gpo = $Read.FindGpo($TerminalName)
            if (-not $Gpo) { $Gpo = $Read.NewGpo($TerminalName) }
            $ReadOu = $Read.FindSom($OuDN)
            $null = $Read.NewLink($ReadOu, $Gpo)
            $Id = $Gpo.Id

            $Removed = Remove-PSGPO -Name $TerminalName -Directory $Read -BackupPath $Root -Confirm:$false
            $Removed.Links | Should -Be @($OuDN)
            $Fresh = Get-PSGPODirectory -Server $Server
            $Fresh.FindGpo($TerminalName) | Should -BeNullOrEmpty
            @($Fresh.FindSom($OuDN).Links | Where-Object GpoDistinguishedName -Like "*$Id*").Count | Should -Be 0 -Because 'its links were deleted first'
            $Location = Get-PSGPOSysvolLocation -Directory $Fresh -Gpo $Gpo
            Read-PSGPOSysvolFile -Directory $Fresh -Gpo $Gpo -Path 'GPT.INI' | Should -BeNullOrEmpty -Because "its folder $($Location.Path) is gone"

            $Restored = Get-PSGPOBackup -Path $Root -Deleted -Directory $Fresh | Where-Object Id -EQ $Id | Restore-PSGPO -Directory $Fresh -RestoreLink -Confirm:$false
            $Restored.Problems | Should -BeNullOrEmpty
            $Again = (Get-PSGPODirectory -Server $Server).FindGpo($TerminalName)
            $Again.Id | Should -Be $Restored.Id
            @((Get-PSGPODirectory -Server $Server).FindSom($OuDN).Links.Gpo.DisplayName) | Should -Contain $TerminalName
        }
    }

    Describe 'Fine-grained password policies written to a domain controller' -Skip:(-not $LdapWrite -or $IsWindows) {
        BeforeAll {
            $Server = $env:PSGPOTOOLS_TEST_LDAP_SERVER
            $Stamp = Get-Date -Format 'MMddHHmmss'
            $Ldap = "ldap://$Server"
            # A user of the test, in a global and in a domain local security group of the test.
            $UserName = "psotest$Stamp"
            $GlobalName = "PSO test global $Stamp"
            $LocalName = "PSO test local $Stamp"
            $PolicyName = "PSO test $Stamp"
            $RenamedName = "PSO test renamed $Stamp"
            $LocalPolicyName = "PSO test local $Stamp"
            $null = Invoke-PSGPOSambaTool -ArgumentList 'user', 'add', $UserName, '--random-password', '-H', $Ldap, '--use-kerberos=required'
            $null = Invoke-PSGPOSambaTool -ArgumentList 'group', 'add', $GlobalName, '--group-scope=Global', '--group-type=Security', '-H', $Ldap, '--use-kerberos=required'
            $null = Invoke-PSGPOSambaTool -ArgumentList 'group', 'add', $LocalName, '--group-scope=Domain', '--group-type=Security', '-H', $Ldap, '--use-kerberos=required'
            foreach ($Group in $GlobalName, $LocalName) { $null = Invoke-PSGPOSambaTool -ArgumentList 'group', 'addmembers', $Group, $UserName, '-H', $Ldap, '--use-kerberos=required' }
            $script:AuditLog = Join-Path $TestDrive 'audit'
            Mock Get-PSGPOAuditPath { $script:AuditLog }
        }

        AfterAll {
            # Everything the tests created, whatever failed.
            $Store = Connect-PSGPOPasswordPolicyStore -Server $Server
            foreach ($Name in $PolicyName, $RenamedName, $LocalPolicyName) {
                $Policy = $Store.FindPolicy($Name)
                if (-not $Policy) { continue }
                try {
                    if ($Policy.ProtectedFromAccidentalDeletion) { $Changed = $Policy.Clone(); $Changed.ProtectedFromAccidentalDeletion = $false; $null = $Store.SetPolicy($Policy, $Changed) }
                    $Store.RemovePolicy($Policy)
                } catch { Write-Warning $_ }
            }
            foreach ($Group in $GlobalName, $LocalName) { try { $null = Invoke-PSGPOSambaTool -ArgumentList 'group', 'delete', $Group, '-H', $Ldap, '--use-kerberos=required' } catch { Write-Warning $_ } }
            try { $null = Invoke-PSGPOSambaTool -ArgumentList 'user', 'delete', $UserName, '-H', $Ldap, '--use-kerberos=required' } catch { Write-Warning $_ }
        }

        It 'Reads the password policy of the domain, and how its groups pass a PSO on' {
            $Store = Connect-PSGPOPasswordPolicyStore -Server $Server
            $Store.DomainPolicy.IsDefault | Should -BeTrue
            $Store.DomainPolicy.PasswordHistoryCount | Should -BeGreaterOrEqual 0
            $Store.CanCreate | Should -BeTrue -Because 'the account of the tests administers the domain'
            $Store.GroupRule | Should -Be $(if ($Store.ServerType -eq 'Samba AD') { 'Security' } else { 'GlobalSecurity' })
            $Default = Get-PSGPODefaultPasswordPolicy -Server $Server
            $Default.MinPasswordLength | Should -Be $Store.DomainPolicy.MinPasswordLength
        }

        It 'Creates a PSO applied to a group, protected from accidental deletion, as the domain controller applies it' {
            $New = New-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $PolicyName -Precedence 50 -MinPasswordLength 15 -MaxPasswordAge 0 -LockoutThreshold 5 -LockoutDuration 0 -AppliesTo $GlobalName -Description 'HGPM test' -Confirm:$false
            $New.Id | Should -Not -Be ([guid]::Empty)
            $Read = Get-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $PolicyName
            $Read.MinPasswordLength | Should -Be 15
            $Read.MaxPasswordAge | Should -Be ([TimeSpan]::Zero)
            $Read.LockoutDuration | Should -Be ([TimeSpan]::Zero)
            $Read.ProtectedFromAccidentalDeletion | Should -BeTrue -Because 'the domain stored the deny ACE of Everyone'
            $Read.AppliesTo | Should -HaveCount 1
            $Result = Get-PSGPOResultantPasswordPolicy -Server $Server -Identity $UserName
            $Result.Source | Should -Be 'DomainController'
            $Result.AppliedPolicy | Should -Be $PolicyName
            $Result.Differs | Should -BeFalse -Because 'the computation finds what the domain controller applies'
            Remove-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $PolicyName -Confirm:$false -ErrorVariable Problem -ErrorAction SilentlyContinue
            "$Problem" | Should -BeLike '*protected from accidental deletion*'
            $Audit = @(Get-Content -LiteralPath (Get-ChildItem -LiteralPath $script:AuditLog -Filter '*.jsonl')[0].FullName | ConvertFrom-Json)
            ($Audit | Where-Object Action -EQ 'NewPasswordPolicy').Details.MinPasswordLength | Should -Be 15
        }

        It 'Renames it and applies it directly, and refuses a change made meanwhile' {
            $Set = Set-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $PolicyName -NewName $RenamedName -Precedence 40 -Confirm:$false
            $Set.DistinguishedName | Should -BeLike "CN=$RenamedName,CN=Password Settings Container,*"
            (Add-PSGPOFineGrainedPasswordPolicySubject -Server $Server -Name $RenamedName -Subject $UserName -Confirm:$false).AppliesTo | Should -HaveCount 2
            $Result = Get-PSGPOResultantPasswordPolicy -Server $Server -Identity $UserName
            $Result.AppliedPolicy | Should -Be $RenamedName
            $Result.Candidates[0].AppliesThrough | Should -Contain 'Direct'
            # Read here, then changed by another console: the first one is refused.
            $Store = Connect-PSGPOPasswordPolicyStore -Server $Server
            $Policy = $Store.FindPolicy($RenamedName)
            $null = Set-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $RenamedName -MinPasswordLength 16 -Confirm:$false
            $Changed = $Policy.Clone(); $Changed.MinPasswordLength = 17
            { $Store.SetPolicy($Policy, $Changed) } | Should -Throw -ExpectedMessage '*changed in the domain meanwhile*'
            (Get-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $RenamedName).MinPasswordLength | Should -Be 16
        }

        It 'Finds the PSO the domain controller applies through a domain local group' {
            $null = New-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $LocalPolicyName -Precedence 1 -AppliesTo $LocalName -ProtectedFromAccidentalDeletion $false -Confirm:$false
            $null = Remove-PSGPOFineGrainedPasswordPolicySubject -Server $Server -Name $RenamedName -Subject $UserName -Confirm:$false
            $Result = Get-PSGPOResultantPasswordPolicy -Server $Server -Identity $UserName
            $Result.Differs | Should -BeFalse -Because 'Samba AD and Windows count their own groups, and the computation follows the domain controller'
            $Expected = if ((Connect-PSGPOPasswordPolicyStore -Server $Server).ServerType -eq 'Samba AD') { $LocalPolicyName } else { $RenamedName }
            $Result.AppliedPolicy | Should -Be $Expected
        }

        It 'Deletes a PSO once its protection is cleared' {
            $null = Set-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $RenamedName -ProtectedFromAccidentalDeletion $false -Confirm:$false
            (Get-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $RenamedName).ProtectedFromAccidentalDeletion | Should -BeFalse
            Remove-PSGPOFineGrainedPasswordPolicy -Server $Server -Name $RenamedName, $LocalPolicyName -Confirm:$false
            @(Get-PSGPOFineGrainedPasswordPolicy -Server $Server -Name "PSO test*$Stamp") | Should -BeNullOrEmpty
        }
    }
}
