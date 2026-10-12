#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Platform detection and reading of the directory over LDAP (Get-PSGPODirectory). The model is
# built from LDAP search entries without a server; the tests against a real domain controller
# run only when PSGPOTOOLS_TEST_LDAP_SERVER names one (with a Kerberos ticket on Linux):
#   PSGPOTOOLS_TEST_LDAP_SERVER=dc.hardenbox.labo pwsh -File CI/Invoke-Tests.ps1
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    # Evaluated during discovery, in the module scope (see PSGPOTools.Gui.tests.ps1).
    $LdapServer = $env:PSGPOTOOLS_TEST_LDAP_SERVER

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

        It 'Reads the domain, read-only' {
            $Directory | Should -BeOfType ([GPOToolsLdapDirectory])
            $Directory.DomainName | Should -Be 'hardenbox.labo'
            $Directory.Domain.DistinguishedName | Should -Be $TestLdapDomainDN
            $Directory.Server | Should -Be 'dc.hardenbox.labo'
            $Directory.IsReadOnly | Should -BeTrue
            $Directory.Source | Should -Be 'read over LDAP from dc.hardenbox.labo, read-only'
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

        It 'Refuses to create GPOs and links, and changes nothing' {
            { $Directory.NewGpo('New') } | Should -Throw -ExpectedMessage '*hardenbox.labo is read-only (read over LDAP from dc.hardenbox.labo, read-only)*'
            { $Directory.NewLink($Lyon, $Directory.Gpos[0]) } | Should -Throw -ExpectedMessage '*read-only*'
            $Directory.Gpos.Count | Should -Be 5
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

        It 'Reads the domain of the domain controller, read-only' {
            $Directory | Should -BeOfType ([GPOToolsLdapDirectory])
            $Directory.Domain.DistinguishedName | Should -Match '^DC='
            $Directory.IsReadOnly | Should -BeTrue
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
}
