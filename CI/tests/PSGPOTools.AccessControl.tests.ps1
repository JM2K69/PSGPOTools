#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Security descriptors ([MS-DTYP] 2.4.6, GPOToolsSecurityDescriptor), the security filtering of a
# GPO and its GPO status. The fixture is the security descriptor of the Default Domain Policy of a
# Samba 4.22 domain, as read over LDAP (owner, group, DACL).
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $DefaultDomainPolicy = [Convert]::FromHexString(
            '010004901400000030000000000000004C000000010500000000000515000000CAFBEA053FAB93C54282BD9F00020000010500000000000515000000CAFBEA05' +
            '3FAB93C54282BD9F000200000400EC000800000000022400FF000F00010500000000000515000000CAFBEA053FAB93C54282BD9F0002000000022400FF000F' +
            '00010500000000000515000000CAFBEA053FAB93C54282BD9F07020000000A1400FF000F0001010000000000030000000000002400FF000F000105000000000005' +
            '15000000CAFBEA053FAB93C54282BD9F0002000000021400FF000F00010100000000000512000000000214009400020001010000000000050B00000005022800' +
            '00010000010000008FFDACEDB3FFD111B41D00A0C968F93901010000000000050B0000000002140094000200010100000000000509000000')
        $Domain = 'S-1-5-21-99285962-3314789183-2679996994'
        $Apply = 'edacfd8f-ffb3-11d1-b41d-00a0c968f939'
    }

    Describe 'Security descriptors' {
        It 'Reads the security descriptor of a GPO and writes it back byte for byte' {
            $Descriptor = [GPOToolsSecurityDescriptor]::Parse($DefaultDomainPolicy)
            $Descriptor.Owner | Should -Be "$Domain-512"
            $Descriptor.Group | Should -Be "$Domain-512"
            $Descriptor.Dacl.Count | Should -Be 8
            [Convert]::ToHexString($Descriptor.ToBytes()) | Should -Be ([Convert]::ToHexString($DefaultDomainPolicy))
        }

        It 'Gives the SDDL of the descriptor with SIDs and hexadecimal rights' {
            ([GPOToolsSecurityDescriptor]::Parse($DefaultDomainPolicy)).ToSddl() | Should -Be (
                "O:$Domain-512G:$Domain-512D:P(A;CI;0x000f00ff;;;$Domain-512)(A;CI;0x000f00ff;;;$Domain-519)(A;CIIO;0x000f00ff;;;S-1-3-0)" +
                "(A;;0x000f00ff;;;$Domain-512)(A;CI;0x000f00ff;;;S-1-5-18)(A;CI;0x00020094;;;S-1-5-11)" +
                "(OA;CI;0x00000100;$Apply;;S-1-5-11)(A;CI;0x00020094;;;S-1-5-9)")
        }

        It 'Derives the ACL of the SYSVOL folder as Samba does (dsacl2fsacl)' {
            # What samba-tool gpo create set on the folder of a new GPO (smbcacls --numeric --sddl).
            ([GPOToolsSecurityDescriptor]::Parse($DefaultDomainPolicy)).ConvertToFileSystem().ToSddl() | Should -Be (
                "O:$Domain-512G:$Domain-512D:P(A;OICI;0x001f01ff;;;$Domain-512)(A;OICI;0x001f01ff;;;$Domain-519)(A;OICIIO;0x001f01ff;;;S-1-3-0)" +
                "(A;OICI;0x001f01ff;;;$Domain-512)(A;OICI;0x001f01ff;;;S-1-5-18)(A;OICI;0x001200a9;;;S-1-5-11)" +
                "(OA;OICI;0x00000000;$Apply;;S-1-5-11)(A;OICI;0x001200a9;;;S-1-5-9)")
        }

        It 'Leaves the deny entries and the Pre-Windows 2000 group out of the SYSVOL ACL' {
            $Descriptor = [GPOToolsSecurityDescriptor]::Parse($DefaultDomainPolicy)
            $Descriptor.SetSecurityFiltering($null, "$Domain-1104")
            $Descriptor.Dacl.Add([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, 2, 0x20094, 'S-1-5-32-554', [guid]::Empty))
            $Files = $Descriptor.ConvertToFileSystem()
            $Files.Dacl.Sid | Should -Not -Contain "$Domain-1104"
            $Files.Dacl.Sid | Should -Not -Contain 'S-1-5-32-554'
        }

        It 'Converts SIDs to bytes and back' {
            foreach ($Sid in 'S-1-5-11', 'S-1-3-0', 'S-1-5-32-554', "$Domain-1104", 'S-1-16-12288') {
                $Bytes = [GPOToolsSecurityDescriptor]::ConvertSidToBytes($Sid)
                [GPOToolsSecurityDescriptor]::ConvertSidToString($Bytes, 0) | Should -Be $Sid
            }
            { [GPOToolsSecurityDescriptor]::ConvertSidToBytes('Domain Admins') } | Should -Throw -ExpectedMessage '*Not a SID*'
        }

        It 'Keeps the entries it does not edit byte for byte' {
            $Descriptor = [GPOToolsSecurityDescriptor]::Parse($DefaultDomainPolicy)
            # An audit ACE (type 2) in the DACL position, as a callback ACE would be.
            $Raw = [byte[]]@(2, 0x40, 20, 0, 0xFF, 0x01, 0x1F, 0) + [GPOToolsSecurityDescriptor]::ConvertSidToBytes('S-1-1-0')
            $Descriptor.Dacl.Add([GPOToolsAce]::Parse($Raw, 0))
            $Again = [GPOToolsSecurityDescriptor]::Parse($Descriptor.ToBytes())
            $Again.Dacl.Count | Should -Be 9
            [Convert]::ToHexString($Again.Dacl[8].ToBytes()) | Should -Be ([Convert]::ToHexString($Raw))
        }
    }

    Describe 'Security filtering of a GPO' {
        It 'Applies the GPO to the members of APPLY only, never to the members of DENY, as GPMC' {
            $Descriptor = [GPOToolsSecurityDescriptor]::Parse($DefaultDomainPolicy)
            $Descriptor.SetSecurityFiltering("$Domain-1103", "$Domain-1104")
            $Sddl = $Descriptor.ToSddl()
            # The deny first, the group of the GPO after the other explicit entries.
            $Descriptor.Dacl[0].ToSddl() | Should -Be "(OD;CI;0x00000100;$Apply;;$Domain-1104)"
            @($Descriptor.Dacl | Select-Object -Last 2 | ForEach-Object { $_.ToSddl() }) |
                Should -Be @("(A;CI;0x00020094;;;$Domain-1103)", "(OA;CI;0x00000100;$Apply;;$Domain-1103)")
            # Authenticated Users read the GPO (MS16-072) but no longer apply it.
            $Sddl | Should -Match ([regex]::Escape('(A;CI;0x00020094;;;S-1-5-11)'))
            $Sddl | Should -Not -Match ([regex]::Escape("$Apply;;S-1-5-11)"))
            # Written and read again unchanged.
            ([GPOToolsSecurityDescriptor]::Parse($Descriptor.ToBytes())).ToSddl() | Should -Be $Sddl
        }

        It 'Puts a deny entry before the allow entries and after the other deny entries' {
            $Descriptor = [GPOToolsSecurityDescriptor]::Parse($DefaultDomainPolicy)
            $Descriptor.SetSecurityFiltering($null, "$Domain-1104")
            $Descriptor.SetSecurityFiltering($null, "$Domain-1105")
            $Descriptor.Dacl[0].Sid | Should -Be "$Domain-1104"
            $Descriptor.Dacl[1].Sid | Should -Be "$Domain-1105"
            $Descriptor.Dacl[2].IsDeny() | Should -BeFalse
            # Without an APPLY group, Authenticated Users still apply it.
            $Descriptor.ToSddl() | Should -Match ([regex]::Escape("$Apply;;S-1-5-11)"))
        }

        It 'Names the groups after the GPO, without the characters a group name cannot hold' {
            Get-PSGPOFilteringGroupName -Prefix APPLY -GpoName 'C - Servers - Security Baseline' | Should -Be 'APPLY_C - Servers - Security Baseline'
            Get-PSGPOFilteringGroupName -Prefix DENY -GpoName ' Proxy: http/https [v2]* ' | Should -Be 'DENY_Proxy_ http_https _v2__'
            Get-PSGPOFilteringGroupName -Prefix DENY -GpoName 'Ends with dots...' | Should -Be 'DENY_Ends with dots'
            { Get-PSGPOFilteringGroupName -Prefix APPLY -GpoName ('x' * 60) } | Should -Throw -ExpectedMessage '*longer than 64 characters*'
        }
    }

    Describe 'GPO status and filtering groups of a directory in memory' {
        BeforeEach {
            $Directory = [GPOToolsDirectory]::new('contoso.com')
            $Gpo = $Directory.NewGpo('Workstations')
        }

        It 'Sets the GPO status' {
            $Directory.SetGpoStatus($Gpo, 2)
            $Gpo.GetStatus() | Should -Be 'Computer configuration settings disabled'
            { $Directory.SetGpoStatus($Gpo, 4) } | Should -Throw -ExpectedMessage '*0 to 3*'
            $Gpo.Flags | Should -Be 2
        }

        It 'Creates the groups in the users container by default, once' {
            $Directory.GetUsersContainer() | Should -Be 'CN=Users,DC=contoso,DC=com'
            $Groups = $Directory.NewFilteringGroups($Gpo, $null)
            @($Groups.DistinguishedName) | Should -Be @('CN=APPLY_Workstations,CN=Users,DC=contoso,DC=com', 'CN=DENY_Workstations,CN=Users,DC=contoso,DC=com')
            { $Directory.NewFilteringGroups($Gpo, 'CN=Users,DC=contoso,DC=com') } | Should -Throw -ExpectedMessage '*already exists*'
            @($Directory.NewFilteringGroups($Gpo, 'OU=Groups,DC=contoso,DC=com').DistinguishedName)[0] | Should -Be 'CN=APPLY_Workstations,OU=Groups,DC=contoso,DC=com'
        }

        It 'Refuses the changes on a read-only directory' {
            $Directory.IsReadOnly = $true
            { $Directory.SetGpoStatus($Gpo, 1) } | Should -Throw -ExpectedMessage '*read-only*'
            { $Directory.NewFilteringGroups($Gpo, $null) } | Should -Throw -ExpectedMessage '*read-only*'
        }

        It 'Reads the users container of the domain from its well-known objects' {
            Mock New-PSGPOLdapConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -PassThru }
            Mock Invoke-PSGPOLdapSearch -ParameterFilter { $SearchBase -eq '' } {
                [pscustomobject]@{ DistinguishedName = ''; Attributes = @{ defaultNamingContext = @('DC=contoso,DC=com'); dnsHostName = @('dc1.contoso.com') } }
            }
            Mock Invoke-PSGPOLdapSearch -ParameterFilter { $SearchBase -eq 'DC=contoso,DC=com' -and $Scope -eq 'Base' } {
                [pscustomobject]@{ DistinguishedName = 'DC=contoso,DC=com'; Attributes = @{ wellKnownObjects = @(
                    'B:32:AA312825768811D1ADED00C04FD8D5CD:CN=Computers,DC=contoso,DC=com',
                    'B:32:A9D1CA15768811D1ADED00C04FD8D5CD:OU=People,DC=contoso,DC=com') } }
            }
            Mock Invoke-PSGPOLdapSearch { }
            (Get-PSGPODirectory -Server 'dc1.contoso.com').GetUsersContainer() | Should -Be 'OU=People,DC=contoso,DC=com'
        }
    }
}
