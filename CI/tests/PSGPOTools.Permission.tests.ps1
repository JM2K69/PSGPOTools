#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Permissions of a GPO as the Delegation and Scope tabs of GPMC change them (PSGPOPermission.ps1):
# the levels read from a DACL as Samba and GPMC write it, the ACEs a change writes, the directory
# in memory and over LDAP, and Get-/Set-PSGPOPermission.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $Domain = 'S-1-5-21-99285962-3314789183-2679996994'
        $Apply = [GPOToolsSecurityDescriptor]::ApplyGroupPolicy
        $CI = [GPOToolsAce]::ContainerInherit
        # The DACL samba-tool gpo create gives a GPO, as read on the lab, with one editor ($Domain-1123).
        function New-SambaDescriptor {
            $Descriptor = [GPOToolsSecurityDescriptor]::new()
            $Descriptor.Owner = "$Domain-512"
            $Descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            foreach ($Ace in @(
                    [GPOToolsAce]::new(0, $CI, 0xF00FF, "$Domain-512", [guid]::Empty)
                    [GPOToolsAce]::new(0, $CI, 0xF00FF, "$Domain-519", [guid]::Empty)
                    [GPOToolsAce]::new(0, ($CI -bor [GPOToolsAce]::InheritOnly), 0xF00FF, 'S-1-3-0', [guid]::Empty)
                    [GPOToolsAce]::new(0, 0, 0xF00FF, "$Domain-512", [guid]::Empty)
                    [GPOToolsAce]::new(0, $CI, 0xF00FF, 'S-1-5-18', [guid]::Empty)
                    [GPOToolsAce]::new(0, $CI, 0x20094, 'S-1-5-11', [guid]::Empty)
                    [GPOToolsAce]::new(5, $CI, 0x100, 'S-1-5-11', [GPOToolsSecurityDescriptor]::ApplyGroupPolicy)
                    [GPOToolsAce]::new(0, $CI, 0x20094, 'S-1-5-9', [guid]::Empty)
                    [GPOToolsAce]::new(0, $CI, 0x200BF, "$Domain-1123", [guid]::Empty))) {
                $Descriptor.Dacl.Add($Ace)
            }
            $Descriptor
        }
        function Get-Level {
            param($Descriptor, [string]$Sid)
            (@(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor) | Where-Object { $_.Sid -eq $Sid -and -not $_.Inherited }).Permission
        }
    }

    Describe 'Levels of the permissions of a GPO' {
        It 'Reads the levels of GPMC from the DACL Samba and GPMC write' {
            $Rows = @(Get-PSGPOPermissionFromDescriptor -Descriptor (New-SambaDescriptor))
            ($Rows | Where-Object Sid -EQ "$Domain-512").Permission | Should -Be 'GpoEditDeleteModifySecurity' -Because 'its two ACEs make one account'
            ($Rows | Where-Object Sid -EQ 'S-1-5-11').Permission | Should -Be 'GpoApply'
            ($Rows | Where-Object Sid -EQ 'S-1-5-9').Permission | Should -Be 'GpoRead'
            ($Rows | Where-Object Sid -EQ "$Domain-1123").Permission | Should -Be 'GpoEdit'
            $Rows.Sid | Should -Not -Contain 'S-1-3-0' -Because 'CREATOR OWNER (inherit only) is not an account of the GPO'
            @($Rows.Sid | Where-Object { $_ -eq "$Domain-512" }).Count | Should -Be 1
        }

        It 'Reads Edit settings as the approval workflow writes it, a denial and other rights as Custom' {
            Get-PSGPOPermissionLevel -Mask 0x200B7 | Should -Be 'GpoEdit'
            Get-PSGPOPermissionLevel -Mask 0x20094 -Applies $true -Denied $true | Should -Be 'GpoCustom'
            Get-PSGPOPermissionLevel -Mask 0x20000 | Should -Be 'GpoCustom'
            Get-PSGPOPermissionLevel -Mask 0x20094 | Should -Be 'GpoRead'
            Get-PSGPOPermissionLevel -Mask 0x20194 -Applies $true | Should -Be 'GpoApply' -Because 'every extended right in one ACE applies the GPO too'
        }

        It 'Lists the inherited permissions apart, after the explicit ones' {
            $Descriptor = New-SambaDescriptor
            $Descriptor.Dacl.Add([GPOToolsAce]::new(0, ($CI -bor [GPOToolsAce]::Inherited), 0xF01FF, "$Domain-519", [guid]::Empty))
            $Rows = @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor)
            $Rows[-1].Inherited | Should -BeTrue
            $Rows[-1].Sid | Should -Be "$Domain-519"
            @($Rows | Where-Object { $_.Sid -eq "$Domain-519" }).Count | Should -Be 2
        }

        It 'Gives a level in place of what the account had, with the masks of GPMC' -ForEach @(
            @{ Permission = 'GpoRead'; Expected = '(A;CI;0x00020094;;;{0})' }
            @{ Permission = 'GpoApply'; Expected = '(A;CI;0x00020094;;;{0})(OA;CI;0x00000100;edacfd8f-ffb3-11d1-b41d-00a0c968f939;;{0})' }
            @{ Permission = 'GpoEdit'; Expected = '(A;CI;0x000200bf;;;{0})' }
            @{ Permission = 'GpoEditDeleteModifySecurity'; Expected = '(A;CI;0x000f00ff;;;{0})' }
            @{ Permission = 'None'; Expected = '' }
        ) {
            $Descriptor = New-SambaDescriptor
            $Sid = "$Domain-1123"
            Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid $Sid -Permission $Permission
            (-join @($Descriptor.Dacl | Where-Object Sid -EQ $Sid | ForEach-Object { $_.ToSddl() })) | Should -Be ($Expected -f $Sid)
            $Descriptor.Dacl.Count | Should -BeGreaterThan 7 -Because 'the other accounts keep their ACEs'
        }

        It 'Keeps Apply Group Policy for an editor that applied the GPO, not for a reader' {
            $Descriptor = New-SambaDescriptor
            Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid 'S-1-5-11' -Permission 'GpoEdit'
            $Row = @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor) | Where-Object Sid -EQ 'S-1-5-11'
            $Row.Permission | Should -Be 'GpoEdit'
            $Row.Applies | Should -BeTrue -Because 'the security filtering does not change with the delegation'
            Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid 'S-1-5-11' -Permission 'GpoRead'
            Get-Level $Descriptor 'S-1-5-11' | Should -Be 'GpoRead'
        }

        It 'Keeps the inherited ACEs and those of CREATOR OWNER' {
            $Descriptor = New-SambaDescriptor
            $Descriptor.Dacl.Add([GPOToolsAce]::new(0, ($CI -bor [GPOToolsAce]::Inherited), 0x20094, "$Domain-1123", [guid]::Empty))
            Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid "$Domain-1123" -Permission 'None'
            @($Descriptor.Dacl | Where-Object Sid -EQ "$Domain-1123").Count | Should -Be 1
            ($Descriptor.Dacl | Where-Object Sid -EQ "$Domain-1123").Flags -band [GPOToolsAce]::Inherited | Should -BeTrue
            Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid 'S-1-3-0' -Permission 'None'
            @($Descriptor.Dacl | Where-Object Sid -EQ 'S-1-3-0').Count | Should -Be 1
        }
    }

    Describe 'Security filtering of a GPO' {
        It 'Adds an account: it reads and applies the GPO' {
            $Descriptor = New-SambaDescriptor
            Set-PSGPOFilteringAce -Descriptor $Descriptor -Sid "$Domain-2001" -Apply $true
            Get-Level $Descriptor "$Domain-2001" | Should -Be 'GpoApply'
            $Descriptor.GetSecurityFiltering().Apply | Should -Be @('S-1-5-11', "$Domain-2001")
        }

        It 'Adds an editor without taking its rights' {
            $Descriptor = New-SambaDescriptor
            Set-PSGPOFilteringAce -Descriptor $Descriptor -Sid "$Domain-1123" -Apply $true
            $Row = @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor) | Where-Object Sid -EQ "$Domain-1123"
            $Row.Permission | Should -Be 'GpoEdit'
            $Row.Applies | Should -BeTrue
        }

        It 'Removes the denial of an account it adds' {
            $Descriptor = New-SambaDescriptor
            $Descriptor.AddAce([GPOToolsAce]::new(6, $CI, 0x100, "$Domain-2001", $Apply))
            Set-PSGPOFilteringAce -Descriptor $Descriptor -Sid "$Domain-2001" -Apply $true
            $Descriptor.GetSecurityFiltering().Deny | Should -BeNullOrEmpty
            Get-Level $Descriptor "$Domain-2001" | Should -Be 'GpoApply'
        }

        It 'Removes an account: it no longer reads the GPO when that was all it did, Authenticated Users keeps reading it' {
            $Descriptor = New-SambaDescriptor
            Set-PSGPOFilteringAce -Descriptor $Descriptor -Sid "$Domain-2001" -Apply $true
            Set-PSGPOFilteringAce -Descriptor $Descriptor -Sid "$Domain-2001" -Apply $false
            @($Descriptor.Dacl | Where-Object Sid -EQ "$Domain-2001").Count | Should -Be 0
            Set-PSGPOFilteringAce -Descriptor $Descriptor -Sid 'S-1-5-11' -Apply $false
            Get-Level $Descriptor 'S-1-5-11' | Should -Be 'GpoRead' -Because 'the computers must read every GPO (MS16-072)'
            $Descriptor.GetSecurityFiltering().Apply | Should -BeNullOrEmpty
        }

        It 'Says when no computer can read the GPO (MS16-072)' {
            $Descriptor = New-SambaDescriptor
            Test-PSGPOComputerReadable -Permission @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor) | Should -BeTrue
            Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid 'S-1-5-11' -Permission 'None'
            Test-PSGPOComputerReadable -Permission @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor) | Should -BeFalse
            Set-PSGPOPermissionAce -Descriptor $Descriptor -Sid "$Domain-515" -Permission 'GpoRead'
            Test-PSGPOComputerReadable -Permission @(Get-PSGPOPermissionFromDescriptor -Descriptor $Descriptor) | Should -BeTrue -Because 'Domain Computers read it'
        }
    }

    Describe 'Permissions of the GPOs of a directory' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Samples' 'Directory.sample.json')
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
        }

        It 'Lists and changes the permissions of a GPO in memory, and its security filtering with them' {
            $Rows = @(Get-PSGPOPermission -Name $Gpo.DisplayName -Directory $Directory)
            ($Rows | Where-Object Trustee -EQ 'Authenticated Users').Permission | Should -Be 'GpoApply'
            ($Rows | Where-Object Trustee -EQ 'Domain Admins').Permission | Should -Be 'GpoEditDeleteModifySecurity'
            $Rows[0].PSObject.TypeNames | Should -Contain 'PSGPOTools.Permission'

            (Set-PSGPOPermission -Name $Gpo.DisplayName -Directory $Directory -Account 'Servers-Paris' -SecurityFiltering Add).Permission | Should -Be 'GpoApply'
            Set-PSGPOPermission -Name $Gpo.DisplayName -Directory $Directory -Account 'NT AUTHORITY\Authenticated Users' -SecurityFiltering Remove | Out-Null
            $Gpo.SecurityFiltering | Should -Be @('Servers-Paris')
            (Set-PSGPOPermission -Name $Gpo.DisplayName -Directory $Directory -Account 'Tier1-Admins' -Permission GpoEdit).Permission | Should -Be 'GpoEdit'
            Set-PSGPOPermission -Name $Gpo.DisplayName -Directory $Directory -Account 'Tier1-Admins' -Permission None | Should -BeNullOrEmpty
            @(Get-PSGPOPermission -Name $Gpo.DisplayName -Directory $Directory).Trustee | Should -Not -Contain 'Tier1-Admins'
        }

        It 'Changes nothing with -WhatIf' {
            Set-PSGPOPermission -Name $Gpo.DisplayName -Directory $Directory -Account 'Tier1-Admins' -Permission GpoEdit -WhatIf
            @(Get-PSGPOPermission -Name $Gpo.DisplayName -Directory $Directory).Trustee | Should -Not -Contain 'Tier1-Admins'
        }

        It 'Refuses a GPO waiting for its approval, a GPO the account cannot edit, and a read-only directory' {
            $Gpo.ApprovalState = 'Pending'
            { $Directory.SetGpoPermission($Gpo, 'Tier1-Admins', 'GpoEdit') } | Should -Throw '*waits for its approval*'
            $Gpo.ApprovalState = $null
            $Gpo.CanEdit = $false
            { $Directory.SetGpoSecurityFiltering($Gpo, 'Tier1-Admins', $true) } | Should -Throw '*cannot edit the GPO*'
            $Gpo.CanEdit = $true
            $Directory.IsReadOnly = $true
            { $Directory.SetGpoPermission($Gpo, 'Tier1-Admins', 'GpoEdit') } | Should -Throw '*read-only*'
            { $Directory.SetGpoPermission($Gpo, 'Tier1-Admins', 'FullControl') } | Should -Throw '*Unknown permission*'
        }

        It 'Writes the DACL of the GPO in the directory, then the ACL of its SYSVOL folder, and logs it' {
            $Ldap = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Ldap.Account = 'CONTOSO\admin1'
            $LdapGpo = $Ldap.AddGpo('C - Servers', [guid]::Empty)
            Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -PassThru }
            Mock Get-PSGPODomainSecurityDescriptor { New-SambaDescriptor }
            Mock Set-PSGPODomainDacl { $script:Written = $Descriptor }
            Mock Set-PSGPOGpoFolderAcl { $script:Folder = $Descriptor }
            Mock Resolve-PSGPODomainSid { $Names = @{}; foreach ($Value in $Sid) { $Names[$Value] = "name of $Value" }; $Names }
            Mock Write-PSGPOAuditEntry { $script:Audit = @{ Action = $Action; Details = $Details } }

            $Ldap.SetGpoSecurityFiltering($LdapGpo, "$Domain-2001", $true)
            @($script:Written.Dacl | Where-Object Sid -EQ "$Domain-2001").Count | Should -Be 2
            Should -Invoke Set-PSGPOGpoFolderAcl -Times 1 -Exactly
            $script:Audit.Action | Should -Be 'SetGpoSecurityFiltering'
            $script:Audit.Details.Sid | Should -Be "$Domain-2001"
            $LdapGpo.SecurityFiltering | Should -Be @('name of S-1-5-11') -Because 'the filtering is the one the domain stored, read again'

            Mock Set-PSGPOGpoFolderAcl { throw 'NT_STATUS_ACCESS_DENIED' }
            { $Ldap.SetGpoPermission($LdapGpo, "$Domain-2001", 'GpoEdit') } | Should -Throw '*changed in the directory, not in SYSVOL*'
        }
    }
}
