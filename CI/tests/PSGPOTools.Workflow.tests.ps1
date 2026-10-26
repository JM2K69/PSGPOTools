#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Approval workflow (Workflow of the configuration of the domain): the rights a pending and an
# approved GPO get, the roles read from the groups of the account, the delegation of the creation
# of GPOs, and the workflow of a directory in memory.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        $Domain = 'S-1-5-21-1-2-3'
        $Creator = "$Domain-1125"
        $Tier1 = "$Domain-1123"
        $Tier2 = "$Domain-1124"
        $Admins = "$Domain-512"
        # The descriptor of a GPO just created by $Creator: what Samba gives it.
        function New-CreatedDescriptor {
            $Descriptor = [GPOToolsSecurityDescriptor]::new()
            $Descriptor.Owner = $Creator
            $Descriptor.Group = "$Domain-513"
            $Descriptor.Control = [GPOToolsSecurityDescriptor]::DaclProtected
            $Descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            $Descriptor.Dacl.Add([GPOToolsAce]::new(0, 2, 0x000F00FF, $Admins, [guid]::Empty))
            $Descriptor.Dacl.Add([GPOToolsAce]::new(0, 0x0A, 0x000F00FF, 'S-1-3-0', [guid]::Empty))
            $Descriptor.Dacl.Add([GPOToolsAce]::new(0, 0, 0x000F00FF, $Creator, [guid]::Empty))
            $Descriptor.Dacl.Add([GPOToolsAce]::new(0, 2, 0x00020094, 'S-1-5-11', [guid]::Empty))
            $Descriptor.Dacl.Add([GPOToolsAce]::new(5, 2, 0x00000100, 'S-1-5-11', [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
            $Descriptor
        }
        function Get-Sddl { param($Descriptor) $Descriptor.ToSddl() }
        # The owners an approved GPO may have.
        $Trusted = @($Admins, "$Domain-519", 'S-1-5-32-544', 'S-1-5-18')
        # A workflow of a directory in memory.
        function New-Workflow {
            param([bool]$Approver, [bool]$Creator)
            [pscustomobject]@{
                Enabled = $true; Problem = $null; IsApprover = $Approver; IsCreator = $Creator
                Approvers = @('Domain Admins'); ApproverSids = @($Admins); Creators = @('GPO-Tier1-Admins'); CreatorSids = @($Tier1)
                AccountCreatorSids = @(if ($Creator) { $Tier1 }); ApprovedOwner = 'Domain Admins'; ApprovedOwnerSid = $Admins; CreatorRights = 'ReadOnly'
            }
        }
    }

    Describe 'Rights of a GPO waiting for its approval' {
        It 'Applies to nobody, keeps reading for everyone, and lets the groups of creators edit it' {
            $Pending = ConvertTo-PSGPOPendingDescriptor -Descriptor (New-CreatedDescriptor) -EditSids $Tier1
            (Get-Sddl $Pending) | Should -Not -Match 'edacfd8f' -Because 'nobody applies it'
            $Pending.GetSecurityFiltering().Apply | Should -BeNullOrEmpty
            (Get-Sddl $Pending) | Should -Match '\(A;CI;0x00020094;;;S-1-5-11\)' -Because 'the computers keep reading it'
            (Get-Sddl $Pending) | Should -Match "\(A;CI;0x000200b7;;;$Tier1\)"
            $Pending.Owner | Should -Be $Creator -Because 'its creator owns it until the approval'
            # Again: no second ACE for the group.
            @((ConvertTo-PSGPOPendingDescriptor -Descriptor $Pending -EditSids $Tier1).Dacl | Where-Object Sid -EQ $Tier1).Count | Should -Be 1
        }

        It 'Removes Apply Group Policy from an ACE that gives other rights with it, and keeps them' {
            $Descriptor = New-CreatedDescriptor
            $Descriptor.Dacl.Add([GPOToolsAce]::new(0, 2, 0x00020194, "$Domain-2000", [guid]::Empty))
            $Pending = ConvertTo-PSGPOPendingDescriptor -Descriptor $Descriptor
            ($Pending.Dacl | Where-Object Sid -EQ "$Domain-2000").Mask | Should -Be 0x00020094
        }
    }

    Describe 'Rights of an approved GPO' {
        It 'Is owned by the owner of the approved GPOs, without the ACEs of the creator and of the creators, applied by Authenticated Users' {
            $Pending = ConvertTo-PSGPOPendingDescriptor -Descriptor (New-CreatedDescriptor) -EditSids $Tier1
            $Approved = ConvertTo-PSGPOApprovedDescriptor -Descriptor $Pending -OwnerSid $Admins -TrustedSids $Trusted -RemoveSids $Creator, $Tier1, $Tier2 -ApplySid 'S-1-5-11' -Container
            $Approved.Owner | Should -Be $Admins
            @($Approved.Dacl | Where-Object { $_.Sid -in $Creator, $Tier1 }).Count | Should -Be 0
            $Approved.GetSecurityFiltering().Apply | Should -Be @('S-1-5-11')
            @($Approved.Dacl | Where-Object { $_.Sid -eq 'S-1-5-11' -and $_.Type -eq 0 }).Count | Should -Be 1 -Because 'Authenticated Users read it already'
            (Get-Sddl $Approved) | Should -Match '\(A;CIIO;0x000f00ff;;;S-1-3-0\)' -Because 'the rest of the ACL is kept'
        }

        It 'Lets the groups of creators edit its settings (EditSettings), and applies it to a group' {
            $Approved = ConvertTo-PSGPOApprovedDescriptor -Descriptor (New-CreatedDescriptor) -OwnerSid $Admins -TrustedSids $Trusted -RemoveSids $Creator, $Tier1 -EditSids $Tier1 -ApplySid "$Domain-3000" -Container
            (Get-Sddl $Approved) | Should -Match "\(A;CI;0x000200b7;;;$Tier1\)"
            $Approved.GetSecurityFiltering().Apply | Should -Be @("$Domain-3000") -Because 'Authenticated Users no longer apply it'
            (Get-Sddl $Approved) | Should -Match "\(A;CI;0x00020094;;;$Domain-3000\)"
        }

        It 'Denies the GPO to a group' {
            $Approved = ConvertTo-PSGPOApprovedDescriptor -Descriptor (New-CreatedDescriptor) -OwnerSid $Admins -TrustedSids $Trusted -RemoveSids $Creator -ApplySid "$Domain-3000" -DenySid "$Domain-3001" -Container
            $Filtering = $Approved.GetSecurityFiltering()
            $Filtering.Apply | Should -Be @("$Domain-3000")
            $Filtering.Deny | Should -Be @("$Domain-3001")
            $Approved.Dacl[0].IsDeny() | Should -BeTrue -Because 'a deny ACE comes first'
        }

        It 'Keeps the inherited ACEs of an object the GPO holds, and changes its owner' {
            $Inner = New-CreatedDescriptor
            $Inner.Dacl.Add([GPOToolsAce]::new(0, 0x12, 0x000200B7, $Tier1, [guid]::Empty))
            $Approved = ConvertTo-PSGPOApprovedDescriptor -Descriptor $Inner -OwnerSid $Admins -TrustedSids $Trusted -RemoveSids $Creator, $Tier1
            $Approved.Owner | Should -Be $Admins
            @($Approved.Dacl | Where-Object Sid -EQ $Creator).Count | Should -Be 0
            @($Approved.Dacl | Where-Object Sid -EQ $Tier1).Count | Should -Be 1 -Because 'an inherited ACE follows its parent'
            (Get-Sddl $Approved) | Should -Not -Match 'edacfd8f' -Because 'the security filtering is on the GPO itself, an object it holds only inherits it'
            (Get-Sddl $Approved) | Should -Match '\(A;CI;0x00020094;;;S-1-5-11\)'
            @((Get-PSGPOExplicitDescriptor -Descriptor $Approved).Dacl | Where-Object { $_.Flags -band 0x10 }).Count | Should -Be 0
        }

        It 'Removes, and reports, the permissions someone added while it was pending' {
            $Pending = ConvertTo-PSGPOPendingDescriptor -Descriptor (New-CreatedDescriptor) -EditSids $Tier1
            # What its creator, its owner, can add outside the console.
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 2, 0x000F01FF, "$Domain-4000", [guid]::Empty))
            $Pending.Dacl.Add([GPOToolsAce]::new(5, 2, 0x00000100, "$Domain-4001", [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 2, 0x00040000, 'S-1-3-4', [guid]::Empty))
            $Pending.Dacl.Insert(0, [GPOToolsAce]::new(1, 2, 0x000F01FF, $Admins, [guid]::Empty))
            $Pending.Dacl[([array]::IndexOf(@($Pending.Dacl.Sid), 'S-1-5-11'))].Mask = 0x000200BF
            $Unexpected = [System.Collections.Generic.List[string]]::new()
            $Approved = ConvertTo-PSGPOApprovedDescriptor -Descriptor $Pending -OwnerSid $Admins -TrustedSids $Trusted -RemoveSids $Creator, $Tier1 -ApplySid "$Domain-3000" -Unexpected $Unexpected -Container
            @($Approved.Dacl | Where-Object { $_.Sid -in "$Domain-4000", "$Domain-4001", 'S-1-3-4', $Creator, $Tier1 }).Count | Should -Be 0
            @($Approved.Dacl | Where-Object { $_.IsDeny() }).Count | Should -Be 0 -Because 'only the deny ACE the approver chooses'
            ($Approved.Dacl | Where-Object { $_.Sid -eq 'S-1-5-11' -and $_.Type -eq 0 }).Mask | Should -Be 0x00020094 -Because 'Authenticated Users only read it'
            $Approved.GetSecurityFiltering().Apply | Should -Be @("$Domain-3000")
            $Unexpected.Count | Should -Be 5 -Because 'the ACEs of the creator and of the creators are expected'
            "$Unexpected" | Should -Match "$Domain-4000"
            "$Unexpected" | Should -Not -Match "$Creator\)"
        }

        It 'Gives Authenticated Users the read of the GPO when it has none' {
            $Descriptor = New-CreatedDescriptor
            [void]$Descriptor.Dacl.RemoveAll([Predicate[GPOToolsAce]] { param($Ace) $Ace.Sid -eq 'S-1-5-11' })
            $Approved = ConvertTo-PSGPOApprovedDescriptor -Descriptor $Descriptor -OwnerSid $Admins -TrustedSids $Trusted -RemoveSids $Creator -ApplySid "$Domain-3000" -Container
            (Get-Sddl $Approved) | Should -Match '\(A;CI;0x00020094;;;S-1-5-11\)' -Because 'the computers must read every GPO (MS16-072)'
        }
    }

    Describe 'Helpers of the workflow' {
        It 'Escapes a value of an LDAP filter' {
            ConvertTo-PSGPOLdapFilterValue -Value 'a*b(c)\d' | Should -Be 'a\2ab\28c\29\5cd'
        }

        It 'Reads the workflow of the configuration, its groups split' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.WriteConfigurationFile([System.Text.Encoding]::UTF8.GetBytes("@{ Workflow = @{ Enabled = `$true; Creators = 'GPO-Tier1-Admins, GPO-Tier2-Admins ,'; CreatorRights = 'EditSettings' } }"))
            try {
                Use-PSGPODomainConfiguration -Directory $Directory -Force
                $Setting = Get-PSGPOWorkflowSetting
                $Setting.Enabled | Should -BeTrue
                $Setting.Creators | Should -Be @('GPO-Tier1-Admins', 'GPO-Tier2-Admins')
                $Setting.Approvers | Should -Be @('Domain Admins')
                $Setting.CreatorRights | Should -Be 'EditSettings'
            } finally {
                Use-PSGPODomainConfiguration -Directory $null
            }
        }

        It 'Refuses a workflow <Case>' -ForEach @(
            @{ Case = 'without creators'; Content = "@{ Workflow = @{ Enabled = `$true } }"; Message = '*Workflow.Creators must name*' }
            @{ Case = 'with unknown rights for the creators'; Content = "@{ Workflow = @{ CreatorRights = 'Owner' } }"; Message = '*CreatorRights must be ReadOnly or EditSettings*' }
            @{ Case = 'with two owners'; Content = "@{ Workflow = @{ ApprovedOwner = 'A, B' } }"; Message = '*ApprovedOwner is one group*' }
        ) {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.WriteConfigurationFile([System.Text.Encoding]::UTF8.GetBytes($Content))
            try {
                "$(@(Use-PSGPODomainConfiguration -Directory $Directory -Force 3>&1))" | Should -BeLike $Message
                (Get-PSGPOWorkflowSetting).Enabled | Should -BeFalse -Because 'the defaults apply'
            } finally {
                Use-PSGPODomainConfiguration -Directory $null
            }
        }
    }

    Describe 'Roles and approval states read from the domain' {
        BeforeEach {
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Directory.Account = 'CONTOSO\tech1'
            foreach ($Item in @(@('Approved GPO', '{11111111-1111-1111-1111-111111111111}'), @('Pending GPO', '{22222222-2222-2222-2222-222222222222}'))) {
                $Gpo = [GPOToolsGpo]@{ DisplayName = $Item[0]; Id = [guid]$Item[1]; DistinguishedName = "CN=$($Item[1]),CN=Policies,CN=System,DC=contoso,DC=com" }
                [void]$Directory.AddExistingGpo($Gpo)
            }
            Mock Get-PSGPOWorkflowSetting { [pscustomobject]@{ Enabled = $true; Approvers = @('Domain Admins'); Creators = @('GPO-Tier1-Admins'); ApprovedOwner = 'Domain Admins'; CreatorRights = 'ReadOnly' } }
            Mock Find-PSGPODomainAccount {
                foreach ($N in $Name) { [pscustomobject]@{ Name = $N; Sid = @{ 'Domain Admins' = $Admins; 'GPO-Tier1-Admins' = $Tier1 }[$N] } }
            }
            Mock Get-PSGPOAccountGroupSid { , [string[]]@($Creator, "$Domain-513", $Tier1) }
            Mock Invoke-PSGPOLdapBinarySearch {
                if ($Scope -eq 'Base') { return [pscustomobject]@{ DistinguishedName = $SearchBase; Values = @{ objectSid = @(, [GPOToolsSecurityDescriptor]::ConvertSidToBytes($Domain)) } } }
                foreach ($Pair in @(@('11111111-1111-1111-1111-111111111111', $Admins), @('22222222-2222-2222-2222-222222222222', $Creator))) {
                    $Descriptor = [GPOToolsSecurityDescriptor]::new()
                    $Descriptor.Owner = $Pair[1]
                    [pscustomobject]@{ DistinguishedName = "CN={$($Pair[0].ToUpperInvariant())},CN=Policies,CN=System,DC=contoso,DC=com"; Values = @{ nTSecurityDescriptor = @(, $Descriptor.ToBytes()) } }
                }
            }
            Mock Resolve-PSGPODomainSid { @{ $Admins = 'Domain Admins'; $Creator = 'tech1' } }
        }

        It 'Finds a creator, and the GPOs it owns waiting for an approval' {
            Update-PSGPODomainWorkflow -Connection ([pscustomobject]@{}) -Directory $Directory
            $Directory.Workflow.IsCreator | Should -BeTrue
            $Directory.Workflow.IsApprover | Should -BeFalse
            $Directory.Workflow.AccountCreatorSids | Should -Be @($Tier1)
            $Directory.IsWorkflowCreator() | Should -BeTrue
            $Directory.FindGpo('Approved GPO').ApprovalState | Should -Be 'Approved'
            $Pending = $Directory.FindGpo('Pending GPO')
            $Pending.ApprovalState | Should -Be 'Pending'
            $Pending.Owner | Should -Be 'tech1'
        }

        It 'Stops the creation of GPOs when the groups of the workflow cannot be found' {
            Mock Find-PSGPODomainAccount { throw "No account named 'GPO-Tier1-Admins' in the domain." }
            $Output = @(Update-PSGPODomainWorkflow -Connection ([pscustomobject]@{}) -Directory $Directory 3>&1)
            "$Output" | Should -BeLike '*cannot be read, no GPO can be created until it is fixed*'
            $Directory.CanCreateGpo | Should -BeFalse
            $Directory.Workflow.Problem | Should -BeLike "*No account named 'GPO-Tier1-Admins'*"
        }

        It 'Stops the creation of GPOs when the account of the console is <Case>' -ForEach @(
            @{ Case = 'unknown'; Account = $null }
            @{ Case = 'not found in the domain'; Account = 'CONTOSO\nobody' }
        ) {
            $Directory.Account = $Account
            Mock Get-PSGPOAccountGroupSid { }
            $null = @(Update-PSGPODomainWorkflow -Connection ([pscustomobject]@{}) -Directory $Directory 3>&1)
            $Directory.CanCreateGpo | Should -BeFalse -Because 'its GPOs would be approved at once'
            $Directory.IsWorkflowCreator() | Should -BeFalse
            $Directory.Workflow.Problem | Should -Not -BeNullOrEmpty
        }

        It 'Reads the SID of the domain from the domain, not from the owner of the approved GPOs' {
            Mock Get-PSGPOWorkflowSetting { [pscustomobject]@{ Enabled = $true; Approvers = @('Domain Admins'); Creators = @('GPO-Tier1-Admins'); ApprovedOwner = 'Administrators'; CreatorRights = 'ReadOnly' } }
            Mock Find-PSGPODomainAccount {
                foreach ($N in $Name) { [pscustomobject]@{ Name = $N; Sid = @{ 'Domain Admins' = $Admins; 'GPO-Tier1-Admins' = $Tier1; 'Administrators' = 'S-1-5-32-544' }[$N] } }
            }
            Update-PSGPODomainWorkflow -Connection ([pscustomobject]@{}) -Directory $Directory
            $Directory.Workflow.DomainSid | Should -Be $Domain
            $Directory.FindGpo('Approved GPO').ApprovalState | Should -Be 'Approved' -Because 'Domain Admins of the domain own it'
        }

        It 'Has no workflow when it is not enabled' {
            Mock Get-PSGPOWorkflowSetting { [pscustomobject]@{ Enabled = $false } }
            Update-PSGPODomainWorkflow -Connection ([pscustomobject]@{}) -Directory $Directory
            $Directory.Workflow | Should -BeNullOrEmpty
            $Directory.FindGpo('Pending GPO').ApprovalState | Should -BeNullOrEmpty
        }

        Context 'Without a configuration of the domain it can use' {
            BeforeEach {
                Mock Get-PSGPOWorkflowSetting { [pscustomobject]@{ Enabled = $false } }
                $Directory.IsDomainAdministrator = $false
                $script:Saved = $script:PSGPOConfigurationState
                # CN=Policies as Initialize-PSGPOWorkflow leaves it: the creators create GPOs.
                $script:Policies = [GPOToolsSecurityDescriptor]::new()
                $script:Policies.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
                $script:Policies.Dacl.Add([GPOToolsAce]::new(5, 0, 0x1, "$Domain-520", [guid]'f30e3bc2-9ff0-11d1-b603-0000f80367c1'))
                $script:Policies.Dacl.Add([GPOToolsAce]::new(0, 2, 0xF01FF, $Admins, [guid]::Empty))
                $script:Policies.Dacl.Add([GPOToolsAce]::new(5, 0, 0x1, $Tier1, [guid]'f30e3bc2-9ff0-11d1-b603-0000f80367c1'))
                Mock Get-PSGPODomainSecurityDescriptor { $script:Policies }
            }
            AfterEach { $script:PSGPOConfigurationState = $script:Saved }

            It 'Stops the creation of GPOs when the configuration is <Case>' -ForEach @(
                @{ Case = 'not used'; Exists = $true; Problem = 'the domain needs 99.0 at least'; Expected = '*is not used (the domain needs 99.0 at least)*unknown*' }
                @{ Case = 'missing while the domain delegates the creation of GPOs'; Exists = $false; Problem = $null; Expected = '*delegates the creation of GPOs*dc1.contoso.com has no configuration of the domain*' }
            ) {
                $script:PSGPOConfigurationState = @{ Directory = $Directory; Path = 'SYSVOL\contoso.com\PSGPOTools\Configuration.psd1'; Exists = $Exists; Override = @{}; Unknown = @{}; Problem = $Problem }
                $Output = @(Update-PSGPODomainWorkflow -Connection ([pscustomobject]@{}) -Directory $Directory 3>&1)
                "$Output" | Should -BeLike '*is unknown, no GPO can be created until it is fixed*'
                $Directory.CanCreateGpo | Should -BeFalse -Because 'a GPO of a creator would apply at once'
                $Directory.Workflow.Problem | Should -BeLike $Expected
                $Directory.IsWorkflowCreator() | Should -BeFalse
            }

            It 'Lets an administrator of the domain work, and a domain that does not delegate the creation of GPOs' {
                $script:PSGPOConfigurationState = @{ Directory = $Directory; Path = 'x'; Exists = $false; Override = @{}; Unknown = @{}; Problem = $null }
                $Directory.IsDomainAdministrator = $true
                Update-PSGPODomainWorkflow -Connection ([pscustomobject]@{}) -Directory $Directory
                $Directory.Workflow | Should -BeNullOrEmpty
                $Directory.CanCreateGpo | Should -BeTrue

                $Directory.IsDomainAdministrator = $false
                $script:Policies.Dacl.RemoveAt(2)
                Update-PSGPODomainWorkflow -Connection ([pscustomobject]@{}) -Directory $Directory
                $Directory.Workflow | Should -BeNullOrEmpty -Because 'Group Policy Creator Owners and the administrators are no delegation of the workflow'
                $Directory.CanCreateGpo | Should -BeTrue
            }

            It 'Does not create an empty configuration on a domain controller without it, when the domain delegates the creation of GPOs' {
                Mock Use-PSGPODomainConfiguration { $script:PSGPOConfigurationState = @{ Directory = $Directory; Path = 'SYSVOL\contoso.com\PSGPOTools\Configuration.psd1'; Exists = $false; Override = @{}; Unknown = @{}; Problem = $null } }
                Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
                Mock Save-PSGPODomainConfiguration { }
                $Directory.IsDomainAdministrator = $true
                $Output = @(Initialize-PSGPODomainConfiguration -Directory $Directory 3>&1)
                $Output[-1] | Should -BeFalse
                "$($Output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })" | Should -BeLike '*is not created: the domain delegates the creation of GPOs*Copy it to dc1.contoso.com*'
                Should -Invoke Save-PSGPODomainConfiguration -Times 0
            }
        }
    }

    Describe 'Delegation of the creation of GPOs' {
        It 'Says what is missing, then adds it, without Group Policy Creator Owners' {
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            Mock Get-PSGPOWorkflowSetting { [pscustomobject]@{ Enabled = $true; Approvers = @('Domain Admins'); Creators = @('GPO-Tier1-Admins'); ApprovedOwner = 'Domain Admins'; CreatorRights = 'ReadOnly' } }
            Mock Find-PSGPODomainAccount { foreach ($N in $Name) { [pscustomobject]@{ Name = $N; Sid = @{ 'Domain Admins' = $Admins; 'GPO-Tier1-Admins' = $Tier1 }[$N] } } }
            Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
            $script:Policies = [GPOToolsSecurityDescriptor]::new()
            $script:Policies.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            $script:Policies.Dacl.Add([GPOToolsAce]::new(0, 0, 0x000F01FF, $Admins, [guid]::Empty))
            $script:Policies.Dacl.Add([GPOToolsAce]::new(0, 0x12, 0x000F01FF, "$Domain-519", [guid]::Empty))
            $script:Folder = [GPOToolsSecurityDescriptor]::new()
            $script:Folder.Control = [GPOToolsSecurityDescriptor]::DaclProtected
            $script:Folder.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            $script:Folder.Dacl.Add([GPOToolsAce]::new(0, 3, 0x001F01FF, 'S-1-5-32-544', [guid]::Empty))
            Mock Get-PSGPODomainSecurityDescriptor { [GPOToolsSecurityDescriptor]::Parse($script:Policies.ToBytes()) }
            Mock Set-PSGPODomainDacl { $script:WrittenPolicies = $Descriptor }
            Mock Get-PSGPOSysvolItemAcl { [GPOToolsSecurityDescriptor]::Parse($script:Folder.ToBytes()) }
            Mock Set-PSGPOSysvolItemAcl { $script:WrittenFolder = $Descriptor }

            $Check = @(Set-PSGPODomainWorkflowDelegation -Directory $Directory)
            @($Check.State | Select-Object -Unique) | Should -Be @('Missing')
            $Check.Count | Should -Be 3
            Should -Invoke Set-PSGPODomainDacl -Times 0
            Should -Invoke Set-PSGPOSysvolItemAcl -Times 0

            $Applied = @(Set-PSGPODomainWorkflowDelegation -Directory $Directory -Apply)
            @($Applied.State | Select-Object -Unique) | Should -Be @('Added')
            (Get-Sddl $script:WrittenPolicies) | Should -Match "\(OA;;0x00000001;f30e3bc2-9ff0-11d1-b603-0000f80367c1;;$Tier1\)"
            (Get-Sddl $script:WrittenPolicies) | Should -Not -Match "S-1-5-21-1-2-3-519" -Because 'the inherited ACEs are computed again by the directory'
            (Get-Sddl $script:WrittenFolder) | Should -Match "\(A;;0x001200ad;;;$Tier1\)"
            (Get-Sddl $script:WrittenFolder) | Should -Match '\(A;OICIIO;0x001f01ff;;;S-1-3-0\)'
            (Get-Sddl $script:WrittenFolder) | Should -Not -Match "$Domain-520" -Because 'not Group Policy Creator Owners'

            $script:Policies = $script:WrittenPolicies
            $script:Folder = $script:WrittenFolder
            @((Set-PSGPODomainWorkflowDelegation -Directory $Directory).State | Select-Object -Unique) | Should -Be @('Present')
        }
    }

    Describe 'Workflow of a directory in memory' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.Account = 'CORP\tech1'
            $Root = Join-Path $TestDrive "approval-$([guid]::NewGuid())"
        }

        It 'Makes the GPO of a creator wait for its approval, without security filtering until then' {
            $Directory.Workflow = New-Workflow -Creator $true
            $Gpo = $Directory.NewGpo('T1 - Proxy')
            $Gpo.ApprovalState | Should -Be 'Pending'
            $Gpo.SecurityFiltering | Should -BeNullOrEmpty
            { $Directory.NewFilteringGroups($Gpo, '') } | Should -Throw '*waits for its approval*'
            { $Directory.ApproveGpo($Gpo, 'ReadOnly', 'S-1-5-11', 'Authenticated Users') } | Should -Throw '*is not an approver*'
            # An approver creates approved GPOs.
            $Directory.Workflow = New-Workflow -Approver $true
            $Directory.NewGpo('T0 - Baseline').ApprovalState | Should -Be 'Approved'
        }

        It 'Deletes the GPO when it cannot wait for its approval, rather than leave it applying to everyone' {
            # A directory whose domain refuses the rights of a pending GPO.
            Invoke-Expression 'class PSGPOTestRefusedDirectory : GPOToolsDirectory { PSGPOTestRefusedDirectory([string]$Name) : base($Name) {} hidden [void] SavePendingGpo([GPOToolsGpo]$Gpo) { throw "access denied" } }'
            $Refusing = Invoke-Expression '[PSGPOTestRefusedDirectory]::new("corp.contoso.com")'
            $Refusing.Workflow = New-Workflow -Creator $true
            { $Refusing.NewGpo('T1 - Refused') } | Should -Throw "*'T1 - Refused' is not created: it cannot wait for its approval (access denied)*"
            $Refusing.FindGpo('T1 - Refused') | Should -BeNullOrEmpty
        }

        It 'Gives the window rows it can bind, for every kind of node' {
            # A row in a PSObject (the output of the pipeline) is shown empty by Avalonia.
            $Directory.Workflow = New-Workflow -Creator $true
            $Pending = $Directory.NewGpo('T1 - Proxy')
            $Deleted = [pscustomobject]@{ PSTypeName = 'PSGPOTools.Backup'; DisplayName = 'Gone'; Id = [guid]::NewGuid(); BackedUp = [datetime]::UtcNow; Status = 'Enabled'; SecurityFiltering = @('Authenticated Users'); DeniedTo = @(); Links = @(); Path = '/tmp/x' }
            foreach ($Item in @($Directory.Domain, $Directory.FindSom('OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com'), $Pending, $Directory.FindGpo('Default Domain Policy'), 'GroupPolicyObjects', 'DeletedGpos', $Deleted)) {
                $Rows = (Get-PSGPODirectoryDetail -Directory $Directory -Item $Item -DeletedGpo @($Deleted)).Properties
                @($Rows).Count | Should -BeGreaterThan 0
                [System.Linq.Enumerable]::Count([System.Linq.Enumerable]::OfType[System.Management.Automation.PSObject]([object[]]@($Rows))) | Should -Be 0 -Because "the rows of $Item are bound by the window"
            }
            $Keys = @((Get-PSGPODirectoryDetail -Directory $Directory -Item $Pending).Properties.Key)
            $Keys | Should -Contain 'Approval'
            $Keys | Should -Contain 'Security filtering'
            $Keys[2] | Should -Be 'Your rights'
        }

        It 'Approves a pending GPO, and backs it up as its approved version' {
            $Directory.Workflow = New-Workflow -Creator $true
            $Gpo = $Directory.NewGpo('T1 - Proxy')
            $Directory.Workflow = New-Workflow -Approver $true
            $Directory.Account = 'CORP\admin'
            Approve-PSGPO -Name 'Default Domain Policy' -Directory $Directory -BackupPath $Root -Confirm:$false -ErrorVariable Refused -ErrorAction SilentlyContinue
            "$Refused" | Should -BeLike '*does not wait for an approval*'

            $Result = Approve-PSGPO -Name 'T1 - Proxy' -Directory $Directory -CreatorRights EditSettings -ApplyTo 'APPLY_T1 - Proxy' -BackupPath $Root -Confirm:$false
            $Result.Owner | Should -Be 'Domain Admins'
            $Result.CreatedBy | Should -Be 'CORP\tech1'
            $Result.AppliedBy | Should -Be 'APPLY_T1 - Proxy'
            $Result.Problem | Should -BeNullOrEmpty
            $Gpo.ApprovalState | Should -Be 'Approved'
            $Gpo.SecurityFiltering | Should -Be @('APPLY_T1 - Proxy')
            $Backup = Get-PSGPOBackup -Path $Root -Approved
            $Backup.Id | Should -Be $Gpo.Id
            $Backup.Comment | Should -Be 'Approved by CORP\admin, created by CORP\tech1: the creators edit its settings; applied by APPLY_T1 - Proxy.'
            (Get-PSGPODrift -Directory $Directory -Path $Root -Name 'T1 - Proxy').State | Should -Be 'InSync'
        }

        It 'Creates the security filtering groups at the approval: the GPO applies to APPLY_ and is denied to DENY_' {
            $Directory.Workflow = New-Workflow -Creator $true
            $Gpo = $Directory.NewGpo('T1 - Proxy')
            $Directory.Workflow = New-Workflow -Approver $true
            { Approve-PSGPO -Name 'T1 - Proxy' -Directory $Directory -CreateFilteringGroups -ApplyTo 'X' -BackupPath $Root -Confirm:$false } | Should -Throw '*do not give -ApplyTo or -DenyTo*'
            { Approve-PSGPO -Name 'T1 - Proxy' -Directory $Directory -GroupContainer 'OU=Groups' -BackupPath $Root -Confirm:$false } | Should -Throw '*-GroupContainer is where*'

            $Result = Approve-PSGPO -Name 'T1 - Proxy' -Directory $Directory -CreateFilteringGroups -GroupContainer 'OU=Users,OU=Lyon,OU=Sites' -BackupPath $Root -Confirm:$false
            $Result.AppliedBy | Should -Be 'APPLY_T1 - Proxy'
            $Result.DeniedTo | Should -Be 'DENY_T1 - Proxy'
            $Result.GroupsCreated | Should -Be @(
                'CN=APPLY_T1 - Proxy,OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com'
                'CN=DENY_T1 - Proxy,OU=Users,OU=Lyon,OU=Sites,DC=corp,DC=contoso,DC=com')
            $Gpo.SecurityFiltering | Should -Be @('APPLY_T1 - Proxy')
            $Gpo.DeniedTo | Should -Be @('DENY_T1 - Proxy')
            (Get-PSGPOBackup -Path $Root -Approved).Comment | Should -BeLike '*applied by APPLY_T1 - Proxy, denied to DENY_T1 - Proxy.'
        }

        It 'Approves a GPO with the groups it already has, and is not approved when its groups cannot be created' {
            $Directory.Workflow = New-Workflow -Creator $true
            $Gpo = $Directory.NewGpo('T1 - Proxy')
            $Directory.Workflow = New-Workflow -Approver $true
            { $Directory.NewApprovalGroups($Gpo, '') } | Should -Not -Throw
            $Existing = Find-PSGPOFilteringGroup -Directory $Directory -Gpo $Gpo
            $Existing.Apply.Name | Should -Be 'APPLY_T1 - Proxy'
            $Existing.Deny.Name | Should -Be 'DENY_T1 - Proxy'

            # Its groups exist: creating them again fails, and the GPO stays pending.
            { Approve-PSGPO -Name 'T1 - Proxy' -Directory $Directory -CreateFilteringGroups -BackupPath $Root -Confirm:$false -ErrorAction Stop } | Should -Throw '*security filtering groups cannot be created*already exists*'
            $Gpo.ApprovalState | Should -Be 'Pending'

            # Without -ApplyTo: its own groups.
            $Result = Approve-PSGPO -Name 'T1 - Proxy' -Directory $Directory -BackupPath $Root -Confirm:$false
            $Result.AppliedBy | Should -Be 'APPLY_T1 - Proxy'
            $Result.DeniedTo | Should -Be 'DENY_T1 - Proxy'
            $Result.GroupsCreated | Should -BeNullOrEmpty
        }

        It 'Refuses the groups of the approval to an account that is not an approver' {
            $Directory.Workflow = New-Workflow -Creator $true
            $Gpo = $Directory.NewGpo('T1 - Proxy')
            { $Directory.NewApprovalGroups($Gpo, '') } | Should -Throw '*is not an approver*'
        }
    }
    Describe 'GPOs waiting for approval in the tree' {
        It 'Lists them in a node of their own, expanded when the console opens, and says how many are below an OU' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            # The first link of a GPO to an OU (not to the domain).
            $Soms = [System.Collections.Generic.List[object]]::new()
            $Queue = [System.Collections.Generic.Queue[object]]::new(@($Directory.Domain))
            while ($Queue.Count) { $Som = $Queue.Dequeue(); $Soms.Add($Som); foreach ($Child in $Som.Children) { $Queue.Enqueue($Child) } }
            $Pair = @(foreach ($Som in $Soms) { foreach ($Link in $Som.Links) { if ($Som.Parent -and $Link.Gpo) { [pscustomobject]@{ Som = $Som; Gpo = $Link.Gpo } } } })[0]
            $Pair | Should -Not -BeNullOrEmpty -Because 'the sample links a GPO to an OU'
            $Roots = New-PSGPODirectoryTree -Directory $Directory -ShowUnmanaged $true
            @($Roots[0].Children.Tag) | Should -Not -Contain 'PendingGpos' -Because 'no node without a GPO waiting'

            $Pair.Gpo.ApprovalState = 'Pending'
            $Roots = New-PSGPODirectoryTree -Directory $Directory -ShowUnmanaged $true
            $Node = @($Roots[0].Children) | Where-Object Tag -EQ 'PendingGpos'
            $Node.Header | Should -Be 'Waiting for approval (1)'
            $Node.IsExpanded | Should -BeTrue -Because 'found at once when the console opens'
            @($Node.Children.Tag) | Should -Be @($Pair.Gpo)
            # Every OU on the way to its link says it, the domain does not.
            $Ou = $Pair.Som
            while ($Ou.Parent) {
                $Found = $null
                $Stack = [System.Collections.Generic.Stack[object]]::new(@($Roots[0]))
                while ($Stack.Count) { $Item = $Stack.Pop(); if ([object]::ReferenceEquals($Item.Tag, $Ou)) { $Found = $Item; break }; foreach ($Child in $Item.Children) { $Stack.Push($Child) } }
                $Found.Header | Should -BeLike '* (1 waiting for approval)'
                $Ou = $Ou.Parent
            }
            $Roots[0].Header | Should -Not -BeLike '*waiting for approval*'

            # Collapsed by the account: kept so when the tree is built again.
            $Keys = [System.Collections.Generic.HashSet[string]]::new()
            $null = $Keys.Add((Get-PSGPODirectoryNodeKey $Roots[0]))
            $Again = New-PSGPODirectoryTree -Directory $Directory -ShowUnmanaged $true -Expanded $Keys
            (@($Again[0].Children) | Where-Object Tag -EQ 'PendingGpos').IsExpanded | Should -BeFalse

            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item 'PendingGpos'
            $Detail.Title | Should -Be "GPOs waiting for approval in $($Directory.DomainName)"
            @($Detail.Properties).Count | Should -Be 1
            $Detail.Properties[0].Value | Should -BeLike 'Linked to *'
        }

        It 'Shows a creator its own GPOs waiting, not the ones of another tier; an approver every one' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Soms = [System.Collections.Generic.List[object]]::new()
            $Queue = [System.Collections.Generic.Queue[object]]::new(@($Directory.Domain))
            while ($Queue.Count) { $Som = $Queue.Dequeue(); $Soms.Add($Som); foreach ($Child in $Som.Children) { $Queue.Enqueue($Child) } }
            $Pair = @(foreach ($Som in $Soms) { foreach ($Link in $Som.Links) { if ($Som.Parent -and $Link.Gpo) { [pscustomobject]@{ Som = $Som; Gpo = $Link.Gpo } } } })[0]
            $Mine = $Directory.NewGpo('T1 - Proxy')
            $Mine.ApprovalState = 'Pending'
            # A GPO of another tier: waiting, the creator does not edit it.
            $Pair.Gpo.ApprovalState = 'Pending'
            $Pair.Gpo.CanEdit = $false

            $Directory.Workflow = New-Workflow -Creator $true
            $Roots = New-PSGPODirectoryTree -Directory $Directory -ShowUnmanaged $true
            $Node = @($Roots[0].Children) | Where-Object Tag -EQ 'PendingGpos'
            $Node.Header | Should -Be 'Waiting for approval (1)'
            @($Node.Children.Tag) | Should -Be @($Mine)
            $Stack = [System.Collections.Generic.Stack[object]]::new(@($Roots[0]))
            $Headers = while ($Stack.Count) { $Item = $Stack.Pop(); $Item.Header; foreach ($Child in $Item.Children) { $Stack.Push($Child) } }
            @($Headers | Where-Object { $_ -like '* waiting for approval)' -and $_ -notlike '*(waiting for approval)' }) | Should -BeNullOrEmpty -Because 'no OU counts the GPO of another tier'
            @((Get-PSGPODirectoryDetail -Directory $Directory -Item 'PendingGpos').Properties.Key) | Should -Be @('T1 - Proxy')

            $Directory.Workflow = New-Workflow -Approver $true
            $Roots = New-PSGPODirectoryTree -Directory $Directory -ShowUnmanaged $true
            (@($Roots[0].Children) | Where-Object Tag -EQ 'PendingGpos').Header | Should -Be 'Waiting for approval (2)'
        }
    }
}
