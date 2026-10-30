#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The security posture of the management of the GPOs (Test-PSGPOSecurityPosture): a domain as the
# workflow leaves it, then each right too wide, in the directory (CN=Policies, the GPOs, the links)
# and in SYSVOL (Policies, the central store, the configuration of HGPM). The directory and SYSVOL
# are mocked: their descriptors are built here.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')
        $D = 'S-1-5-21-1-2-3'
        $Gpc = [guid]'f30e3bc2-9ff0-11d1-b603-0000f80367c1'
        $GpLink = [guid]'f30e3bbe-9ff0-11d1-b603-0000f80367c1'
        $GpOptions = [guid]'f30e3bbf-9ff0-11d1-b603-0000f80367c1'
        $FileSysPath = [guid]'f30e3bc1-9ff0-11d1-b603-0000f80367c1'
        $VersionNumber = [guid]'bf967a76-0de6-11d0-a285-00aa003049e2'
        $DisplayName = [guid]'bf967953-0de6-11d0-a285-00aa003049e2'
        $KeyCredentialLink = [guid]'5b47d60f-6090-40b2-9f37-2a4de88f3063'

        function New-TestAce {
            param([string]$Sid, [uint32]$Mask, [byte]$Flags = 0, [guid]$Object = [guid]::Empty, [byte]$Type = 0)
            if ($Object -ne [guid]::Empty -and $Type -eq 0) { $Type = 5 }
            [GPOToolsAce]::new($Type, $Flags, $Mask, $Sid, $Object)
        }
        function New-TestDescriptor {
            param([string]$Owner, [GPOToolsAce[]]$Ace)
            $Descriptor = [GPOToolsSecurityDescriptor]::new()
            $Descriptor.Owner = $Owner
            $Descriptor.Group = $Owner
            $Descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            foreach ($Item in $Ace) { $Descriptor.Dacl.Add($Item) }
            $Descriptor
        }
        function Get-TestFinding {
            param([string]$Check)
            @($script:Result | Where-Object { $_.Check -eq $Check })
        }
    }

    Describe 'Security posture of the management of the GPOs' {
        BeforeEach {
            $Directory = New-TestLdapDirectory
            $Gpo = @{ Domain = $TestLdapDefaultDomainPolicy; Dc = $TestLdapDefaultDcPolicy; Workstations = $TestLdapWorkstationsPolicy }
            $GpoDescriptor = {
                New-TestDescriptor "$D-512" @(
                    New-TestAce "$D-512" 0x000F01FF 0x02
                    New-TestAce 'S-1-5-18' 0x000F01FF 0x02
                    New-TestAce 'S-1-5-11' 0x00020094 0x02
                    New-TestAce 'S-1-5-11' 0x00000100 0x02 ([GPOToolsSecurityDescriptor]::ApplyGroupPolicy)
                    # Key Admins writes msDS-KeyCredentialLink of every object, inherited from the domain.
                    New-TestAce "$D-526" 0x00000020 0x12 $KeyCredentialLink
                )
            }
            $script:TestPosture = @{
                DomainDN = $TestLdapDomainDN
                Setting = [pscustomobject]@{ Enabled = $true; Approvers = @('Domain Admins'); Creators = @('GPO-Tier1-Admins'); ApprovedOwner = 'Domain Admins'; CreatorRights = 'ReadOnly' }
                Configuration = @{ Audit = @{ Enabled = $true; Path = '\\fs1\gpo-audit' }; Log = @{ SystemLog = $true } }
                Accounts = @{ 'Domain Admins' = "$D-512"; 'GPO-Tier1-Admins' = "$D-1123"; 'GPO-Tier2-Admins' = "$D-1124"; 'tech1' = "$D-1125" }
                # The groups of each account (tokenGroups): Tier 0 operators are in Domain Admins.
                Groups = @{ "$D-1300" = @("$D-512"); "$D-1125" = @("$D-1123", "$D-513") }
                Names = @{ "$D-512" = 'Domain Admins'; "$D-513" = 'Domain Users'; "$D-1123" = 'GPO-Tier1-Admins'; "$D-1124" = 'GPO-Tier2-Admins'; "$D-1125" = 'tech1'; "$D-1200" = 'helpdesk'; 'S-1-5-11' = 'Authenticated Users' }
                Members = @{}
                Schema = @{ gPLink = $GpLink; gPOptions = $GpOptions; gPCFileSysPath = $FileSysPath; versionNumber = $VersionNumber }
                # The sites of the forest: none linked by default.
                Sites = [ordered]@{ 'Default-First-Site-Name' = @{ GpLink = ''; Descriptor = New-TestDescriptor "$D-519" @(New-TestAce "$D-519" 0x000F01FF 0x02; New-TestAce 'S-1-5-11' 0x00020094 0x02) } }
                Domain = New-TestDescriptor "$D-512" @(
                    New-TestAce "$D-512" 0x000F01FF 0x02
                    New-TestAce 'S-1-5-18' 0x000F01FF 0x02
                    New-TestAce 'S-1-5-11' 0x00020094 0x02
                    New-TestAce "$D-526" 0x00000020 0x02 $KeyCredentialLink
                    # A group of Tier 0 operators, in Domain Admins, links GPOs to the domain.
                    New-TestAce "$D-1300" 0x00000030 0x02 $GpLink
                )
                Ous = [ordered]@{
                    "OU=Lyon,$TestLdapDomainDN" = New-TestDescriptor "$D-512" @(New-TestAce "$D-512" 0x000F01FF 0x02)
                    # The OU of Tier 1: its creators link GPOs there.
                    "OU=Workstations,OU=Lyon,$TestLdapDomainDN" = New-TestDescriptor "$D-512" @(New-TestAce "$D-512" 0x000F01FF 0x02; New-TestAce "$D-1123" 0x00000030 0x02 $GpLink)
                    "OU=Domain Controllers,$TestLdapDomainDN" = New-TestDescriptor "$D-512" @(New-TestAce "$D-512" 0x000F01FF 0x02; New-TestAce 'S-1-5-11' 0x00020094 0x02)
                }
                Policies = New-TestDescriptor "$D-512" @(
                    New-TestAce "$D-512" 0x000F01FF 0x02
                    New-TestAce "$D-1123" 0x00000001 0 $Gpc
                    New-TestAce "$D-520" 0x00000001 0 $Gpc
                    New-TestAce 'S-1-3-0' 0x000F01FF 0x0A
                )
                Gpos = [ordered]@{ $Gpo.Domain = & $GpoDescriptor; $Gpo.Dc = & $GpoDescriptor; $Gpo.Workstations = & $GpoDescriptor }
                Folders = @{
                    'hardenbox.labo\Policies' = New-TestDescriptor 'S-1-5-32-544' @(
                        New-TestAce 'S-1-5-32-544' 0x001F01FF 0x03
                        New-TestAce 'S-1-5-18' 0x001F01FF 0x03
                        New-TestAce 'S-1-5-11' 0x001200A9 0x03
                        New-TestAce 'S-1-5-32-549' 0x001200A9 0x03
                        New-TestAce "$D-520" 0x001301BF 0x03
                        New-TestAce 'S-1-3-0' 0x001F01FF 0x0B
                        New-TestAce "$D-1123" 0x001200AD 0
                    )
                    'hardenbox.labo\Policies\PolicyDefinitions' = New-TestDescriptor 'S-1-5-32-544' @(New-TestAce 'S-1-5-32-544' 0x001F01FF 0x03; New-TestAce 'S-1-5-11' 0x001200A9 0x03)
                    'hardenbox.labo\PSGPOTools' = New-TestDescriptor "$D-500" @(New-TestAce 'S-1-5-32-544' 0x001F01FF 0x03; New-TestAce 'S-1-5-11' 0x001200A9 0x03)
                }
            }

            Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
            Mock Get-PSGPOWorkflowSetting { $script:TestPosture.Setting }
            Mock Get-PSGPOConfigurationData { $script:TestPosture.Configuration }
            Mock Find-PSGPODomainAccount {
                foreach ($Item in $Name) {
                    $Found = $script:TestPosture.Accounts[$Item]
                    if (-not $Found) { throw "No account named '$Item' in the domain." }
                    [pscustomobject]@{ Name = $Item; Sid = $Found }
                }
            }
            Mock Invoke-PSGPOLdapSearch {
                [pscustomobject]@{ DistinguishedName = ''; Attributes = @{
                        schemanamingcontext = [string[]]@('CN=Schema,CN=Configuration,DC=hardenbox,DC=labo')
                        configurationnamingcontext = [string[]]@('CN=Configuration,DC=hardenbox,DC=labo')
                    }
                }
            }
            Mock Invoke-PSGPOLdapBinarySearch {
                $T = $script:TestPosture
                $Entry = { param([string]$Dn, [hashtable]$Values) [pscustomobject]@{ DistinguishedName = $Dn; Values = $Values } }
                $Utf8 = [System.Text.Encoding]::UTF8
                if ($SearchBase -like 'CN=Schema,*') {
                    foreach ($Name in $T.Schema.Keys) { & $Entry "CN=$Name,$SearchBase" @{ lDAPDisplayName = @(, $Utf8.GetBytes($Name)); schemaIDGUID = @(, $T.Schema[$Name].ToByteArray()) } }
                } elseif ($SearchBase -like 'CN=Sites,*') {
                    foreach ($Name in $T.Sites.Keys) {
                        & $Entry "CN=$Name,$SearchBase" @{ cn = @(, $Utf8.GetBytes($Name)); gPLink = @(, $Utf8.GetBytes($T.Sites[$Name].GpLink)); nTSecurityDescriptor = @(, $T.Sites[$Name].Descriptor.ToBytes()) }
                    }
                } elseif ($Filter -like '(objectSid=*') {
                    & $Entry "CN=Group Policy Creator Owners,CN=Users,$($T.DomainDN)" @{ member = @($T.Members.Keys | ForEach-Object { , $Utf8.GetBytes($_) }) }
                } elseif ($T.Members.Contains($SearchBase)) {
                    & $Entry $SearchBase @{ objectSid = @(, [GPOToolsSecurityDescriptor]::ConvertSidToBytes($T.Members[$SearchBase])) }
                } elseif ($SearchBase -eq $T.DomainDN -and $Scope -eq 'Base') {
                    & $Entry $SearchBase @{ objectSid = @(, [GPOToolsSecurityDescriptor]::ConvertSidToBytes('S-1-5-21-1-2-3')); nTSecurityDescriptor = @(, $T.Domain.ToBytes()) }
                } elseif ($Filter -eq '(objectClass=organizationalUnit)') {
                    foreach ($Dn in $T.Ous.Keys) { & $Entry $Dn @{ nTSecurityDescriptor = @(, $T.Ous[$Dn].ToBytes()) } }
                } elseif ($SearchBase -like 'CN=Policies,*' -and $Scope -eq 'Base') {
                    & $Entry $SearchBase @{ nTSecurityDescriptor = @(, $T.Policies.ToBytes()) }
                } elseif ($SearchBase -like 'CN=Policies,*') {
                    foreach ($Id in $T.Gpos.Keys) { & $Entry "CN=$Id,$SearchBase" @{ cn = @(, $Utf8.GetBytes($Id)); nTSecurityDescriptor = @(, $T.Gpos[$Id].ToBytes()) } }
                }
            }
            Mock Get-PSGPOAccountGroupSid { , [string[]](@($Sid) + @($script:TestPosture.Groups[$Sid])) }
            Mock Test-PSGPOSysvolFolder { $script:TestPosture.Folders.ContainsKey($Path) }
            Mock Get-PSGPOSysvolItemAcl {
                $Item = $script:TestPosture.Folders[$Path]
                if ($Item -is [string]) { throw $Item }
                [GPOToolsSecurityDescriptor]::Parse($Item.ToBytes())
            }
            Mock Resolve-PSGPODomainSid {
                $Names = @{}
                foreach ($Item in $Sid) { $Names[$Item] = if ($script:TestPosture.Names[$Item]) { $script:TestPosture.Names[$Item] } else { $Item } }
                $Names
            }
        }

        Context 'Rights an ACE gives' {
            It 'Counts what it gives the object itself, not what is only inherited, nor a deny' {
                Test-PSGPOAceGrant -Ace (New-TestAce 'S-1-5-11' 0x20) -Mask 0x20 | Should -BeTrue
                Test-PSGPOAceGrant -Ace (New-TestAce 'S-1-5-11' 0x20 0x0A) -Mask 0x20 | Should -BeFalse -Because 'inherit only'
                Test-PSGPOAceGrant -Ace (New-TestAce 'S-1-5-11' 0x20 0 -Type 1) -Mask 0x20 | Should -BeFalse -Because 'a deny'
                Test-PSGPOAceGrant -Ace (New-TestAce 'S-1-5-11' 0x20094) -Mask 0x20 | Should -BeFalse -Because 'read only'
            }

            It 'Counts writing a property for the properties asked only, unless it also writes the DACL or the owner' {
                Test-PSGPOAceGrant -Ace (New-TestAce 'S-1-5-11' 0x20 0 $GpLink) -Mask $script:PSGPODirectoryWriteMask -Property $GpLink | Should -BeTrue
                Test-PSGPOAceGrant -Ace (New-TestAce 'S-1-5-11' 0x20 0 $DisplayName) -Mask $script:PSGPODirectoryWriteMask -Property $GpLink | Should -BeFalse
                Test-PSGPOAceGrant -Ace (New-TestAce 'S-1-5-11' 0x20 0 $DisplayName) -Mask $script:PSGPODirectoryWriteMask -Property $GpLink -AnyProperty | Should -BeTrue -Because 'the schema was not read'
                Test-PSGPOAceGrant -Ace (New-TestAce 'S-1-5-11' 0x40020 0 $DisplayName) -Mask $script:PSGPODirectoryWriteMask -Property $GpLink | Should -BeTrue -Because 'it writes the DACL'
                # An ACE for the users only does not give the OU.
                $Ace = New-TestAce 'S-1-5-11' 0x20 0x02 $GpLink
                $Ace.InheritedObjectType = [guid]'bf967aba-0de6-11d0-a285-00aa003049e2'
                Test-PSGPOAceGrant -Ace $Ace -Mask $script:PSGPODirectoryWriteMask -Class $script:PSGPOObjectClass.OrganizationalUnit -Property $GpLink | Should -BeFalse
            }
        }

        Context 'A domain' {
            It 'Finds nothing in a domain as the workflow leaves it' {
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                $script:Result | Should -BeNullOrEmpty -Because ($script:Result | Format-List | Out-String)
            }

            It 'Finds the members of Group Policy Creator Owners outside of the Tier 0' {
                $script:TestPosture.Members["CN=tech1,CN=Users,$TestLdapDomainDN"] = "$D-1125"
                $script:TestPosture.Members["CN=ops,CN=Users,$TestLdapDomainDN"] = "$D-1300"
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                $Found = Get-TestFinding 'GroupPolicyCreatorOwners'
                $Found.Count | Should -Be 1 -Because 'an account in Domain Admins is of the Tier 0'
                $Found.Severity | Should -Be 'High'
                $Found.Principal | Should -Be 'tech1'

                $script:TestPosture.Setting.Enabled = $false
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                (Get-TestFinding 'GroupPolicyCreatorOwners').Severity | Should -Be 'Medium' -Because 'without the workflow, every GPO applies at once anyway'
                (Get-TestFinding 'Workflow').Severity | Should -Be 'Low'
            }

            It 'Finds who creates GPOs beyond the creators of the workflow, and who changes who can' {
                $script:TestPosture.Policies.Dacl.Add((New-TestAce "$D-513" 0x1 0 $Gpc))
                $script:TestPosture.Policies.Dacl.Add((New-TestAce "$D-1200" 0x1 0 $Gpc))
                $script:TestPosture.Policies.Dacl.Add((New-TestAce "$D-1123" 0x40000))
                # Creating another class is not creating GPOs.
                $script:TestPosture.Policies.Dacl.Add((New-TestAce "$D-1124" 0x1 0 ([guid]'bf967a86-0de6-11d0-a285-00aa003049e2')))
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                $Found = Get-TestFinding 'GpoCreation'
                @($Found.Principal | Sort-Object) | Should -Be @('Domain Users', 'GPO-Tier1-Admins', 'helpdesk')
                ($Found | Where-Object Principal -EQ 'Domain Users').Detail | Should -BeLike 'A group of every account*'
                ($Found | Where-Object Principal -EQ 'helpdesk').Detail | Should -BeLike '*not a group of creators of the workflow*'
                ($Found | Where-Object Principal -EQ 'GPO-Tier1-Admins').Detail | Should -BeLike '*the DACL or the owner of CN=Policies*'
            }

            It 'Finds a GPO every account changes, and one applying to the domain controllers changed outside of the Tier 0' {
                $script:TestPosture.Gpos[$Gpo.Workstations].Dacl.Add((New-TestAce "$D-513" 0x20 0 $VersionNumber))
                $script:TestPosture.Gpos[$Gpo.Dc].Dacl.Add((New-TestAce "$D-1123" 0x000200B7))
                # Its display name only: what the computers apply does not change.
                $script:TestPosture.Gpos[$Gpo.Dc].Dacl.Add((New-TestAce "$D-1124" 0x20 0 $DisplayName))
                $script:TestPosture.Gpos[$Gpo.Domain].Owner = "$D-1125"
                # The same right on a GPO of an OU of Tier 1: expected.
                $script:TestPosture.Gpos[$Gpo.Workstations].Dacl.Add((New-TestAce "$D-1123" 0x000200B7))
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                $All = Get-TestFinding 'GpoEditableByAll'
                $All.Count | Should -Be 1
                $All.Target | Should -Be 'Workstations'
                $All.Principal | Should -Be 'Domain Users'
                $Tier0 = Get-TestFinding 'Tier0Gpo'
                @($Tier0 | ForEach-Object { "$($_.Target)|$($_.Principal)" } | Sort-Object) | Should -Be @('Default Domain Controllers Policy|GPO-Tier1-Admins', 'Default Domain Policy|tech1')
                ($Tier0 | Where-Object Principal -EQ 'tech1').Detail | Should -BeLike 'It owns the GPO, linked to hardenbox.labo*'
            }

            It 'Finds who links GPOs to the domain or to the domain controllers outside of the Tier 0, and every account linking anywhere' {
                $script:TestPosture.Domain.Dacl.Add((New-TestAce "$D-1123" 0x20 0x02 $GpLink))
                $script:TestPosture.Ous["OU=Domain Controllers,$TestLdapDomainDN"].Dacl.Add((New-TestAce "$D-1200" 0x20 0 $GpOptions))
                $script:TestPosture.Ous["OU=Lyon,$TestLdapDomainDN"].Dacl.Add((New-TestAce 'S-1-5-11' 0x20 0x02 $GpLink))
                # Its description only, on the domain: not a link.
                $script:TestPosture.Domain.Dacl.Add((New-TestAce "$D-1124" 0x20 0 $DisplayName))
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                @(Get-TestFinding 'Tier0Link' | ForEach-Object { "$($_.Target)|$($_.Principal)" } | Sort-Object) | Should -Be @("hardenbox.labo|GPO-Tier1-Admins", "OU=Domain Controllers,$TestLdapDomainDN|helpdesk")
                $All = Get-TestFinding 'LinkByAll'
                $All.Target | Should -Be "OU=Lyon,$TestLdapDomainDN"
                $All.Principal | Should -Be 'Authenticated Users'
            }

            It 'Finds who links GPOs to a site, and a GPO linked to a site changed outside of the Tier 0: the domain controllers of the site apply it' {
                $Site = $script:TestPosture.Sites['Default-First-Site-Name']
                $Site.GpLink = "[LDAP://$(Get-TestLdapGpoDN $Gpo.Workstations);0]"
                $Site.Descriptor.Dacl.Add((New-TestAce "$D-1200" 0x20 0 $GpLink))
                $script:TestPosture.Gpos[$Gpo.Workstations].Dacl.Add((New-TestAce "$D-1123" 0x000200B7))
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                $Link = Get-TestFinding 'Tier0Link'
                "$($Link.Target)|$($Link.Principal)" | Should -Be 'Default-First-Site-Name (site)|helpdesk'
                $Changed = Get-TestFinding 'Tier0Gpo'
                "$($Changed.Target)|$($Changed.Principal)" | Should -Be 'Workstations|GPO-Tier1-Admins' -Because 'linked to an OU of Tier 1 only, it would be expected'
                $Changed.Detail | Should -BeLike '*linked to the site Default-First-Site-Name*'
            }

            It 'Finds who owns or changes the folders of SYSVOL outside of the Tier 0' {
                $script:TestPosture.Folders['hardenbox.labo\Policies\PolicyDefinitions'].Owner = "$D-1125"
                $script:TestPosture.Folders['hardenbox.labo\Policies'].Dacl.Add((New-TestAce "$D-1200" 0x001200AD 0))
                $script:TestPosture.Folders['hardenbox.labo\PSGPOTools'].Dacl.Add((New-TestAce "$D-513" 0x001301BF 0x03))
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                $Store = Get-TestFinding 'CentralStore'
                $Store.Severity | Should -Be 'High'
                $Store.Principal | Should -Be 'tech1'
                $Store.Detail | Should -BeLike 'It owns the central store*'
                (Get-TestFinding 'PoliciesFolder').Principal | Should -Be 'helpdesk'
                (Get-TestFinding 'PoliciesFolder').Detail | Should -BeLike 'It creates folders in Policies, and is not a group of creators*'
                (Get-TestFinding 'ConfigurationFolder').Detail | Should -BeLike 'A group of every account. It can change the configuration of HGPM*'
            }

            It 'Says when there is no central store while the creators create folders, or when a folder cannot be read' {
                $script:TestPosture.Folders.Remove('hardenbox.labo\Policies\PolicyDefinitions')
                $script:TestPosture.Folders['hardenbox.labo\PSGPOTools'] = 'NT_STATUS_ACCESS_DENIED'
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                (Get-TestFinding 'CentralStore').Severity | Should -Be 'Medium'
                (Get-TestFinding 'CentralStore').Detail | Should -BeLike 'There is no central store*Install-PSGPOAdmx -CentralStore*'
                (Get-TestFinding 'ConfigurationFolder').Detail | Should -BeLike 'Its permissions cannot be read (NT_STATUS_ACCESS_DENIED)*'

                # No creators: nobody could create it.
                $script:TestPosture.Setting.Creators = @()
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                Get-TestFinding 'CentralStore' | Should -BeNullOrEmpty
            }

            It 'Finds the problems of the configuration, the most severe first' {
                $script:TestPosture.Setting.Approvers = @('Domain Admins', 'Approvers-Gone')
                $script:TestPosture.Setting.Creators = @('GPO-Tier1-Admins', 'Domain Admins')
                $script:TestPosture.Configuration = @{ Audit = @{ Enabled = $true; Path = '' }; Log = @{ SystemLog = $false } }
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                (Get-TestFinding 'Configuration').Detail | Should -BeLike 'Approvers-Gone is not an account of the domain*'
                (Get-TestFinding 'WorkflowRoles').Detail | Should -BeLike '*in Workflow.Approvers and Workflow.Creators*'
                (Get-TestFinding 'AuditLog').Severity | Should -Be 'Low'
                (Get-TestFinding 'SystemLog').Severity | Should -Be 'Low'
                $Order = @{ High = 0; Medium = 1; Low = 2 }
                $Ranks = @($script:Result | ForEach-Object { $Order[$_.Severity] })
                $Ranks | Should -Be @($Ranks | Sort-Object)
            }

            It 'Checks every attribute written when the schema cannot be read' {
                Mock Invoke-PSGPOLdapSearch { throw 'no rootDSE' }
                $script:TestPosture.Gpos[$Gpo.Dc].Dacl.Add((New-TestAce "$D-1124" 0x20 0 $DisplayName))
                $script:Result = Get-PSGPOPostureData -Directory $Directory
                (Get-TestFinding 'Tier0Gpo').Principal | Should -Be 'GPO-Tier2-Admins'
            }
        }

        Context 'Test-PSGPOSecurityPosture' {
            BeforeEach {
                Mock Use-PSGPODomainConfiguration { }
                Mock Write-PSGPOSystemLog { }
                $script:Findings = @(
                    [pscustomobject]@{ PSTypeName = 'PSGPOTools.PostureFinding'; Severity = 'High'; Check = 'Tier0Link'; Target = 'hardenbox.labo'; Principal = 'helpdesk'; Detail = 'It can link a GPO here.' }
                    [pscustomobject]@{ PSTypeName = 'PSGPOTools.PostureFinding'; Severity = 'High'; Check = 'CentralStore'; Target = '\\dc\SYSVOL\x'; Principal = 'tech1'; Detail = 'It owns the central store.' }
                    [pscustomobject]@{ PSTypeName = 'PSGPOTools.PostureFinding'; Severity = 'Low'; Check = 'AuditLog'; Target = 'Audit.Path'; Principal = ''; Detail = 'No central audit log.' }
                )
                Mock Get-PSGPOPostureData { , $script:Findings }
            }

            It 'Returns the findings, and sends nothing to the log of the system without -SystemLog' {
                $Found = @(Test-PSGPOSecurityPosture -Directory $Directory)
                $Found.Count | Should -Be 3
                $Found[0].PSObject.TypeNames | Should -Contain 'PSGPOTools.PostureFinding'
                Should -Invoke Write-PSGPOSystemLog -Times 0
            }

            It 'Sends a summary (4000) and each High finding (4001) with -SystemLog' {
                $null = Test-PSGPOSecurityPosture -Directory $Directory -SystemLog
                Should -Invoke Write-PSGPOSystemLog -Times 1 -Exactly -ParameterFilter { $EventId -eq 4000 -and $Level -eq 'Warning' -and $Message -like '*2 high, 0 medium, 1 low*' }
                Should -Invoke Write-PSGPOSystemLog -Times 2 -Exactly -ParameterFilter { $EventId -eq 4001 -and $Level -eq 'Warning' }
                Should -Invoke Write-PSGPOSystemLog -Times 1 -Exactly -ParameterFilter { $EventId -eq 4001 -and $Message -like '*CentralStore: \\dc\SYSVOL\x - tech1: It owns the central store.' }

                $script:Findings = @($script:Findings | Where-Object Severity -NE 'High')
                $null = Test-PSGPOSecurityPosture -Directory $Directory -SystemLog
                Should -Invoke Write-PSGPOSystemLog -Times 1 -Exactly -ParameterFilter { $EventId -eq 4000 -and $Level -eq 'Information' }
            }

            It 'Refuses a directory that is not read over LDAP' {
                { Test-PSGPOSecurityPosture -Directory ([GPOToolsDirectory]::new('contoso.com')) } | Should -Throw '*read over LDAP*'
            }
        }
    }
}
