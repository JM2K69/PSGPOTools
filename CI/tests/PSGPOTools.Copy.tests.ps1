#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The copy of a GPO in its domain (Copy-PSGPO, PSGPOCopy.ps1), as Copy and Paste of GPMC: its
# settings, status, client-side extensions, WMI filter and comment, not its links; the permissions
# of a new GPO, or those of the GPO copied. On the sample directory changed in memory.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        # The permissions of a GPO, not inherited, as text: one 'Sid=Permission/Applies' per account.
        function Get-PermissionText {
            param($Directory, $Gpo)
            @($Directory.GetGpoPermissions($Gpo) | Where-Object { -not $_.Inherited } | ForEach-Object { "$($_.Sid)=$($_.Permission)/$($_.Applies)" } | Sort-Object)
        }
    }

    Describe 'Copy-PSGPO' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.IsReadOnly = $false
            $Source = $Directory.FindGpo('C - Kiosks - Assigned Access')
            $Pol = [GPOToolsRegistryPol]::new()
            $Pol.Entries.Add([GPOToolsPolEntry]::new('Software\Policies\Contoso\Kiosk', 'ShowClock', [GPOToolsPolType]::DWord, [BitConverter]::GetBytes([uint32]1)))
            $Directory.WritePolicyFile($Source, 'Machine', $Pol.ToBytes())
            $Directory.WriteGpoComment($Source, 'Kiosks of the halls')
            $Directory.SetGpoStatus($Source, 1)
        }

        It 'Gives the new GPO the settings, the status, the extensions, the WMI filter and the comment of the GPO, not its links' {
            $Filter = $Directory.NewWmiFilter('Kiosks', 'Kiosk computers', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_ComputerSystem' }))
            $Directory.SetWmiFilter($Source, $Filter)
            $Copy = Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'C - Kiosks - Assigned Access (test)' -Confirm:$false
            $Copy | Should -BeOfType ([GPOToolsGpo])
            $Copy.Id | Should -Not -Be $Source.Id
            $Directory.FindGpo('C - Kiosks - Assigned Access (test)') | Should -Be $Copy
            $Directory.ReadGpoFile($Copy, 'Machine\Registry.pol') | Should -Be $Directory.ReadGpoFile($Source, 'Machine\Registry.pol')
            $Directory.ReadGpoComment($Copy) | Should -BeExactly 'Kiosks of the halls'
            $Copy.Flags -band 3 | Should -Be 1
            $Copy.MachineExtensionNames | Should -BeExactly $Source.MachineExtensionNames
            "$($Copy.UserExtensionNames)" | Should -BeExactly "$($Source.UserExtensionNames)"
            $Copy.WmiFilterId | Should -Be $Filter.Id
            @($Directory.GetLinksOf($Copy)) | Should -BeNullOrEmpty -Because 'a copy is linked where it applies, as GPMC'
            $Copy.Version | Should -BeGreaterThan 0 -Because 'its settings are new to the computers'
        }

        It 'Copies a GPO without files: its status only' {
            $Empty = $Directory.NewGpo('C - Empty')
            $Directory.SetGpoStatus($Empty, 2)
            $Copy = Copy-PSGPO -Directory $Directory -Name 'C - Empty' -TargetName 'C - Empty (copy)' -Confirm:$false
            $Copy.Flags -band 3 | Should -Be 2
            @($Directory.ReadGpoFolder($Copy).Keys | Where-Object { $_ -ne 'GPT.INI' }) | Should -BeNullOrEmpty
        }

        It 'Gives the copy the permissions of a new GPO by default' {
            $Directory.SetGpoPermission($Source, 'S-1-5-21-1-2-3-1500', 'GpoEdit')
            $New = $Directory.NewGpo('C - Reference')
            $Copy = Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'C - Copy' -Confirm:$false
            Get-PermissionText $Directory $Copy | Should -Be (Get-PermissionText $Directory $New)
        }

        It 'Gives the copy the permissions of the GPO with -CopyAcl, its security filtering with them' {
            $Directory.SetGpoPermission($Source, 'S-1-5-21-1-2-3-1500', 'GpoEdit')
            $Directory.SetGpoSecurityFiltering($Source, 'S-1-5-21-1-2-3-1500', $true)
            $Directory.SetGpoPermission($Source, 'S-1-5-21-1-2-3-1600', 'GpoApply')
            $Directory.SetGpoPermission($Source, 'Enterprise Admins', 'None')
            $Directory.SetGpoPermission($Source, 'S-1-5-11', 'GpoRead')
            $Copy = Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'C - Copy' -CopyAcl -Confirm:$false
            Get-PermissionText $Directory $Copy | Should -Be (Get-PermissionText $Directory $Source)
            Get-PermissionText $Directory $Copy | Should -Contain 'S-1-5-21-1-2-3-1500=GpoEdit/True'
            @(Get-PermissionText $Directory $Copy) -like 'Enterprise Admins=*' | Should -BeNullOrEmpty -Because 'what a new GPO gives and the GPO does not is taken back'
        }

        It 'Says the permissions -CopyAcl cannot give (denied, custom), and gives the others' {
            $Descriptor = $Directory.LoadGpoDescriptor($Source)
            $Descriptor.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDeniedObject, [GPOToolsAce]::ContainerInherit, [GPOToolsSecurityDescriptor]::ControlAccess, 'S-1-5-21-1-2-3-1700', [GPOToolsSecurityDescriptor]::ApplyGroupPolicy))
            $Copy = Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'C - Copy' -CopyAcl -Confirm:$false -WarningVariable Warnings 3>$null
            $Copy | Should -Not -BeNullOrEmpty
            @($Warnings).Count | Should -Be 1
            "$($Warnings[0])" | Should -BeLike "*Permission not copied to 'C - Copy': S-1-5-21-1-2-3-1700 (Custom, denied)*"
            @($Directory.GetGpoPermissions($Copy).Sid) | Should -Not -Contain 'S-1-5-21-1-2-3-1700'
        }

        It 'Refuses a name taken, a GPO it does not find, and a name that gives several GPOs' {
            { Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'U - Lyon - Printers' -Confirm:$false } | Should -Throw "*A GPO named 'U - Lyon - Printers' already exists*"
            { Copy-PSGPO -Directory $Directory -Name 'No such GPO' -TargetName 'C - Copy' -Confirm:$false } | Should -Throw "*No GPO named 'No such GPO'*"
            { Copy-PSGPO -Directory $Directory -Name 'U - * - Printers' -TargetName 'C - Copy' -Confirm:$false } | Should -Throw '*gives 2*'
            $Directory.FindGpo('C - Copy') | Should -BeNullOrEmpty
        }

        It 'Changes nothing with -WhatIf' {
            $Count = $Directory.Gpos.Count
            Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'C - Copy' -WhatIf 6>$null | Should -BeNullOrEmpty
            $Directory.Gpos.Count | Should -Be $Count
        }

        It 'Makes the copy of a creator of the approval workflow wait, and refuses -CopyAcl to it' {
            $Directory.Workflow = [pscustomobject]@{
                Enabled = $true; Problem = $null; IsApprover = $false; IsCreator = $true
                Approvers = @('Domain Admins'); ApproverSids = @('S-1-5-21-1-2-3-512'); Creators = @('GPO-Tier1-Admins'); CreatorSids = @('S-1-5-21-1-2-3-1500')
                AccountCreatorSids = @('S-1-5-21-1-2-3-1500'); ApprovedOwner = 'Domain Admins'; ApprovedOwnerSid = 'S-1-5-21-1-2-3-512'; CreatorRights = 'ReadOnly'
            }
            { Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'C - Copy' -CopyAcl -Confirm:$false } | Should -Throw '*without -CopyAcl*'
            $Copy = Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'C - Copy' -Confirm:$false
            $Copy.ApprovalState | Should -Be 'Pending'
            $Directory.ReadGpoComment($Copy) | Should -BeExactly 'Kiosks of the halls'
        }

        It 'Returns the GPO created, and says what failed after its creation' {
            Mock Copy-PSGPOContent { throw 'SYSVOL unreachable' }
            $Copy = Copy-PSGPO -Directory $Directory -Name $Source.DisplayName -TargetName 'C - Copy' -Confirm:$false -ErrorVariable Problems -ErrorAction SilentlyContinue
            $Copy.DisplayName | Should -Be 'C - Copy'
            @($Problems | ForEach-Object { "$_" }) -like '*is created, but not completed*' | Should -BeLike "*The GPO 'C - Copy' is created, but not completed: SYSVOL unreachable*"
        }
    }

    Describe 'Text of a permission not copied' {
        It 'Names the account and its level, denied or not' {
            Get-PSGPOCopySkippedText -Row ([pscustomobject]@{ Name = 'CONTOSO\Kiosk-Deny'; Permission = 'GpoCustom'; Denied = $true }) | Should -BeExactly 'CONTOSO\Kiosk-Deny (Custom, denied)'
            Get-PSGPOCopySkippedText -Row ([pscustomobject]@{ Name = 'CONTOSO\Helpdesk'; Permission = 'GpoCustom'; Denied = $false }) | Should -BeExactly 'CONTOSO\Helpdesk (Custom)'
        }
    }
}
