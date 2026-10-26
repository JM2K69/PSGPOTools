#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Guards against what a hostile file, another tool or another domain could do: paths of a backup
# outside the GPO folder, a backup of another domain with the GUID of a GPO here, two GPOs with
# the same name, a GPO changed since it was read, the order of the writes of an approval.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
    }

    Describe 'Paths of the files of a GPO' {
        It 'Accepts a path in the GPO folder: <Path>' -ForEach @(
            @{ Path = 'Machine\Registry.pol' }
            @{ Path = 'Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf' }
            @{ Path = 'User/Preferences/Drives/Drives.xml' }
            @{ Path = 'GPT.INI' }
        ) {
            { Assert-PSGPOGpoFilePath -Path $Path } | Should -Not -Throw
        }

        It 'Refuses a path outside the GPO folder, or that would end a command: <Path>' -ForEach @(
            @{ Path = '..\{31B2F340-016D-11D2-945F-00C04FB984F9}\Machine\Registry.pol' }
            @{ Path = 'Machine\..\..\x' }
            @{ Path = '\Windows\x' }
            @{ Path = '/etc/x' }
            @{ Path = 'C:\x' }
            @{ Path = 'Machine\a"; rm x' }
            @{ Path = 'Machine\\Registry.pol' }
            @{ Path = '' }
        ) {
            { Assert-PSGPOGpoFilePath -Path $Path } | Should -Throw -ExpectedMessage 'Not a path of a file in a GPO folder*'
        }

        It 'Ignores a backup whose manifest names a file outside the GPO folder, and lists the others' {
            $Root = Join-Path $TestDrive "backups-$([guid]::NewGuid())"
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Good = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $Hostile = Join-Path (Split-Path -Parent $Good.Path) 'hostile'
            Copy-Item -LiteralPath $Good.Path -Destination $Hostile -Recurse
            $Manifest = Get-Content -LiteralPath (Join-Path $Hostile 'manifest.json') -Raw | ConvertFrom-Json -AsHashtable
            # The Registry.pol of the Default Domain Policy, its hash written by the same hand.
            $Manifest.Files = @(@{ Path = '..\{31B2F340-016D-11D2-945F-00C04FB984F9}\Machine\Registry.pol'; Size = 0; Sha256 = 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855' })
            $Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Hostile 'manifest.json')

            $Warnings = @(Get-PSGPOBackup -Path $Root 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            "$Warnings" | Should -BeLike '*Backup ignored, its manifest is not valid*Not a path of a file in a GPO folder*'
            @(Get-PSGPOBackup -Path $Root 3>$null).Path | Should -Be @($Good.Path)
        }
    }

    Describe 'Backups of another domain' {
        It 'Never restores one on a GPO of this domain with its GUID (the default GPOs)' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Backup = Backup-PSGPO -Directory $Directory -Path (Join-Path $TestDrive "own-$([guid]::NewGuid())") -Name $Gpo.DisplayName
            $Backup.Domain = 'fabrikam.com'
            $Version = $Gpo.Version
            { Restore-PSGPO -Backup $Backup -Directory $Directory -Confirm:$false } | Should -Throw -ExpectedMessage '*of fabrikam.com, not of corp.contoso.com*not restored here*'
            $Gpo.Version | Should -Be $Version
        }
    }

    Describe 'GPO names given to the commands' {
        It 'Matches <Pattern> to <Name>: <Expected>' -ForEach @(
            @{ Pattern = 'Servers [Lyon]'; Name = 'Servers [Lyon]'; Expected = $true }
            @{ Pattern = 'servers [lyon]'; Name = 'Servers [Lyon]'; Expected = $true }
            @{ Pattern = 'Servers [Lyon]'; Name = 'Servers L'; Expected = $false }
            @{ Pattern = 'a[b'; Name = 'a[b'; Expected = $true }
            @{ Pattern = 'C - *'; Name = 'C - Servers'; Expected = $true }
            @{ Pattern = '* [Lyon]'; Name = 'Servers [Lyon]'; Expected = $true }
            @{ Pattern = '* [Lyon]'; Name = 'Servers L'; Expected = $false }
        ) {
            Test-PSGPONameMatch -Name $Name -Pattern $Pattern | Should -Be $Expected
        }

        It 'Backs up and compares each of two GPOs with the same name' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Twin = [GPOToolsGpo]@{ DisplayName = $Gpo.DisplayName; Id = [guid]::NewGuid() }
            [void]$Directory.AddExistingGpo($Twin)
            @(Find-PSGPOByName -Directory $Directory -Name $Gpo.DisplayName, 'C - Servers - Security*').Id | Should -Be @($Gpo.Id, $Twin.Id)
            $Backups = @(Backup-PSGPO -Directory $Directory -Path (Join-Path $TestDrive "twins-$([guid]::NewGuid())") -Name $Gpo.DisplayName)
            @($Backups.Id) | Should -Be @($Gpo.Id, $Twin.Id)
        }
    }

    Describe 'A GPO changed since it was read' {
        It 'Is not written over: its file is not saved, and its version is the same' {
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Gpo = [GPOToolsGpo]@{ DisplayName = 'Servers'; Id = [guid]::NewGuid(); DistinguishedName = 'CN={1},CN=Policies,CN=System,DC=contoso,DC=com'; Version = 3 }
            Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
            # Another console saved it meanwhile: version 4 in the domain.
            Mock Invoke-PSGPOLdapSearch { [pscustomobject]@{ DistinguishedName = $SearchBase; Attributes = @{ versionNumber = @('4') } } }
            Mock Write-PSGPOSysvolFile { }
            { Save-PSGPODomainGpoFile -Directory $Directory -Gpo $Gpo -Path 'Machine\Registry.pol' -Bytes ([byte[]]@(1)) -Folder Machine `
                    -Extension '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}' -Tool '{D02B1F72-3407-48AE-BA88-E8213C6761F1}' } |
                Should -Throw -ExpectedMessage '*changed since it was read (version 3, now 4)*not saved*'
            Should -Invoke Write-PSGPOSysvolFile -Times 0
            $Gpo.Version | Should -Be 3
        }
    }

    Describe 'Approval of a GPO of the domain' {
        BeforeEach {
            $Domain = 'S-1-5-21-1-2-3'
            $Creator = "$Domain-1125"
            $Tier1 = "$Domain-1123"
            $Admins = "$Domain-512"
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Directory.Workflow = [pscustomobject]@{
                Enabled = $true; IsApprover = $true; IsCreator = $false; ApproverSids = @($Admins); CreatorSids = @($Tier1)
                ApprovedOwner = 'Domain Admins'; ApprovedOwnerSid = $Admins; DomainSid = $Domain
            }
            $Gpo = [GPOToolsGpo]@{ DisplayName = 'Servers'; Id = [guid]::NewGuid(); DistinguishedName = 'CN={1},CN=Policies,CN=System,DC=contoso,DC=com' }
            $Pending = [GPOToolsSecurityDescriptor]::new()
            $Pending.Owner = $Creator
            $Pending.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 2, 0x000F00FF, $Admins, [guid]::Empty))
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 0, 0x000F00FF, $Creator, [guid]::Empty))
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 2, 0x000200B7, $Tier1, [guid]::Empty))
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 2, 0x00020094, 'S-1-5-11', [guid]::Empty))
            # Added by the creator outside the console.
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 2, 0x000F00FF, "$Domain-4000", [guid]::Empty))
            $script:Bytes = $Pending.ToBytes()
            $script:Writes = [System.Collections.Generic.List[string]]::new()
            Mock New-PSGPODirectoryConnection { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru }
            Mock Invoke-PSGPOLdapBinarySearch {
                @([pscustomobject]@{ DistinguishedName = $SearchBase; Values = @{ nTSecurityDescriptor = @(, $script:Bytes) } }
                    [pscustomobject]@{ DistinguishedName = "CN=Machine,$SearchBase"; Values = @{ nTSecurityDescriptor = @(, $script:Bytes) } })
            }
            Mock Get-PSGPOAccountGroupSid { , [string[]]@($Creator, $Tier1) }
            Mock Set-PSGPODomainOwnerAndDacl { $script:Writes.Add("AD $DistinguishedName $($Descriptor.ToSddl())") }
            Mock Set-PSGPOGpoFolderAcl { $script:Writes.Add("SYSVOL $($Descriptor.Owner)") }
        }

        It 'Writes SYSVOL, then the objects the GPO holds, then the GPO: its owner, which approves it, last' {
            $Removed = Approve-PSGPODomainGpo -Directory $Directory -Gpo $Gpo -CreatorRights ReadOnly -ApplyToSid 'S-1-5-11' 3>$null
            $script:Writes.Count | Should -Be 3
            $script:Writes[0] | Should -Be "SYSVOL $Admins"
            $script:Writes[1] | Should -BeLike 'AD CN=Machine,*'
            $script:Writes[2] | Should -BeLike "AD CN={1},*O:$Admins*"
            $script:Writes[2] | Should -Not -Match "$Domain-4000|$Creator\)|$Tier1\)"
            @($Removed | Where-Object { $_ -match "$Domain-4000" }).Count | Should -BeGreaterThan 0 -Because 'the approver is told'
        }

        It 'Leaves the GPO pending when SYSVOL cannot be written' {
            Mock Set-PSGPOGpoFolderAcl { throw 'access denied' }
            { Approve-PSGPODomainGpo -Directory $Directory -Gpo $Gpo -CreatorRights ReadOnly -ApplyToSid 'S-1-5-11' } | Should -Throw -ExpectedMessage '*is not approved*still pending*'
            Should -Invoke Set-PSGPODomainOwnerAndDacl -Times 0
        }

        It 'Does not approve a GPO that changed since it was reviewed, and writes nothing in the directory' {
            $Gpo.ReviewStamp = 'REVIEWED'
            Mock Get-PSGPOReviewStamp { 'CHANGED' }
            { Approve-PSGPODomainGpo -Directory $Directory -Gpo $Gpo -CreatorRights ReadOnly -ApplyToSid 'S-1-5-11' } | Should -Throw -ExpectedMessage '*is not approved: it changed since it was reviewed*still pending*review it again*'
            $script:Writes | Should -Be @("SYSVOL $Admins") -Because 'compared once the creator cannot write the folder anymore'
            Should -Invoke Set-PSGPODomainOwnerAndDacl -Times 0

            Mock Get-PSGPOReviewStamp { 'REVIEWED' }
            $script:Writes.Clear()
            $null = Approve-PSGPODomainGpo -Directory $Directory -Gpo $Gpo -CreatorRights ReadOnly -ApplyToSid 'S-1-5-11' 3>$null
            $script:Writes.Count | Should -Be 3 -Because 'the same content: approved'
        }

        It 'Stamps what an approver reviews: the files of the GPO and the attributes that make it apply' {
            $Memory = Import-PSGPODirectory -Path $SamplePath
            $Reviewed = $Memory.Gpos[0]
            $First = Get-PSGPOReviewStamp -Directory $Memory -Gpo $Reviewed
            $First | Should -Match '^[0-9A-F]{64}$'
            Get-PSGPOReviewStamp -Directory $Memory -Gpo $Reviewed | Should -Be $First -Because 'nothing changed'
            $Reviewed.Version++
            Get-PSGPOReviewStamp -Directory $Memory -Gpo $Reviewed | Should -Not -Be $First -Because 'its version changed'
            $Reviewed.Version--
            $Reviewed.WmiFilterId = [guid]::NewGuid()
            Get-PSGPOReviewStamp -Directory $Memory -Gpo $Reviewed | Should -Not -Be $First -Because 'its WMI filter changed'
            $Reviewed.WmiFilterId = $null
            # A file changed, its version and extensions as they were (another tool than the console).
            $Version = $Reviewed.Version
            $Extensions = $Reviewed.MachineExtensionNames
            $Memory.WritePolicyFile($Reviewed, 'Machine', [byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0))
            $Reviewed.Version = $Version
            $Reviewed.MachineExtensionNames = $Extensions
            Get-PSGPOReviewStamp -Directory $Memory -Gpo $Reviewed | Should -Not -Be $First -Because 'a file changed'
        }

        It 'Tells the approval a GPO applies while pending' {
            $Gpo.ApprovalState = 'Pending'
            $Gpo.SecurityFiltering = @()
            $Gpo.AppliesWhilePending() | Should -BeFalse
            $Gpo.SecurityFiltering = @('Authenticated Users')
            $Gpo.AppliesWhilePending() | Should -BeTrue
        }
    }

    Describe 'A GPO redirected to another folder (gPCFileSysPath)' {
        BeforeAll {
            $Id = [guid]'6AC1786C-016F-11D2-945F-00C04FB984F9'
        }

        It 'Uses the folder of the GPO, whatever the case: <Path>' -ForEach @(
            @{ Path = '\\contoso.com\SysVol\contoso.com\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}' }
            @{ Path = '\\CONTOSO.COM\sysvol\contoso.com\Policies\{6ac1786c-016f-11d2-945f-00c04fb984f9}\' }
        ) {
            $Directory = [GPOToolsDirectory]::new('contoso.com')
            $Gpo = [GPOToolsGpo]@{ DisplayName = 'Servers'; Id = $Id; FileSysPath = $Path }
            $Directory.IsGpoRedirected($Gpo) | Should -BeFalse
            $Location = Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo
            $Location.Share | Should -BeIn 'SysVol', 'sysvol'
            $Location.Path | Should -BeLike 'contoso.com\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}'
        }

        It 'Neither reads nor writes a GPO whose gPCFileSysPath is another folder: <Path>' -ForEach @(
            # The configuration of the console, another GPO, another share, another server.
            @{ Path = '\\contoso.com\SysVol\contoso.com\PSGPOTools' }
            @{ Path = '\\contoso.com\SysVol\contoso.com\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}' }
            @{ Path = '\\contoso.com\SysVol\contoso.com\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}\..\..\PSGPOTools' }
            @{ Path = '\\contoso.com\NETLOGON\contoso.com\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}' }
            @{ Path = '\\dc1.contoso.com\C$\Windows\System32' }
            @{ Path = '\\evil.contoso.com\SysVol\contoso.com\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}' }
            @{ Path = '\\contoso.com\SysVol\contoso.com\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}"; rm x' }
        ) {
            $Directory = [GPOToolsDirectory]::new('contoso.com')
            $Gpo = [GPOToolsGpo]@{ DisplayName = 'Servers'; Id = $Id; FileSysPath = $Path }
            $Directory.IsGpoRedirected($Gpo) | Should -BeTrue
            { Get-PSGPOSysvolLocation -Directory $Directory -Gpo $Gpo } | Should -Throw -ExpectedMessage "*'Servers' is redirected*"
        }

        It 'Does not approve a redirected GPO, and says it in the tree and in its details' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.Workflow = [pscustomobject]@{ Enabled = $true; IsApprover = $true; IsCreator = $false; ApprovedOwner = 'Domain Admins'; ApprovedOwnerSid = 'S-1-5-21-1-2-3-512' }
            $Gpo = $Directory.Gpos[0]
            $Gpo.ApprovalState = 'Pending'
            $Gpo.FileSysPath = '\\{0}\SysVol\{0}\PSGPOTools' -f $Directory.DomainName
            { $Directory.ApproveGpo($Gpo, 'ReadOnly', 'S-1-5-11', 'Authenticated Users') } | Should -Throw -ExpectedMessage '*is redirected*It is not approved.'
            $Gpo.ApprovalState | Should -Be 'Pending'

            $Roots = New-PSGPODirectoryTree -Directory $Directory -ShowUnmanaged $true
            $Node = @($Roots[0].Children | Where-Object Tag -EQ 'GroupPolicyObjects').Children | Where-Object { [object]::ReferenceEquals($_.Tag, $Gpo) }
            $Node.Header | Should -BeLike '*(redirected to another folder)'
            $Node.IconBrush | Should -Be '#C50F1F'
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo
            ($Detail.Properties | Where-Object Key -EQ 'Redirected').Value | Should -BeLike "The computers read its settings from *PSGPOTools, not from its folder *"
        }

        It 'Denies the creators that keep editing an approved GPO writing its gPCFileSysPath, and still shows them as Edit settings' {
            $Domain = 'S-1-5-21-1-2-3'
            $Tier1 = "$Domain-1123"
            $Pending = [GPOToolsSecurityDescriptor]::new()
            $Pending.Owner = "$Domain-1125"
            $Pending.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 0, 0x000F00FF, "$Domain-1125", [guid]::Empty))
            $Pending.Dacl.Add([GPOToolsAce]::new(0, 2, 0x000200B7, $Tier1, [guid]::Empty))
            $Approved = ConvertTo-PSGPOApprovedDescriptor -Descriptor $Pending -OwnerSid "$Domain-512" -TrustedSids @("$Domain-512") -RemoveSids @("$Domain-1125", $Tier1) `
                -EditSids @($Tier1) -ApplySid 'S-1-5-11' -Container
            $Deny = @($Approved.Dacl | Where-Object { $_.Sid -eq $Tier1 -and (Test-PSGPOFileSysPathDenyAce -Ace $_) })
            $Deny.Count | Should -Be 1
            $Approved.Dacl[0].IsDeny() | Should -BeTrue -Because 'a deny ACE comes first'
            (Get-PSGPOPermissionFromDescriptor -Descriptor $Approved | Where-Object Sid -EQ $Tier1).Permission | Should -Be 'GpoEdit'
            # Another level for the group: the deny stays.
            Remove-PSGPOAccountAce -Descriptor $Approved -Sid $Tier1
            @($Approved.Dacl | Where-Object { $_.Sid -eq $Tier1 -and (Test-PSGPOFileSysPathDenyAce -Ace $_) }).Count | Should -Be 1

            $ReadOnly = ConvertTo-PSGPOApprovedDescriptor -Descriptor $Pending -OwnerSid "$Domain-512" -TrustedSids @("$Domain-512") -RemoveSids @("$Domain-1125", $Tier1) -ApplySid 'S-1-5-11' -Container
            @($ReadOnly.Dacl | Where-Object { Test-PSGPOFileSysPathDenyAce -Ace $_ }).Count | Should -Be 0 -Because 'without their rights, nothing to deny'
        }

        It 'Sets gPCFileSysPath back to the folder of the GPO before deleting it, so that another folder is not deleted' {
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Samba AD')
            $Gpo = [GPOToolsGpo]@{ DisplayName = 'Servers'; Id = $Id; DistinguishedName = 'CN={6AC1786C-016F-11D2-945F-00C04FB984F9},CN=Policies,CN=System,DC=contoso,DC=com' }
            $script:Order = [System.Collections.Generic.List[string]]::new()
            $script:Searches = 0
            Mock New-PSGPODirectoryConnection {
                [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru |
                    Add-Member -MemberType ScriptMethod -Name SendRequest -Value { param($Request) $script:Order.Add("modify $(@($Request.Modifications | ForEach-Object { "$($_.Operation) $($_[0])" }) -join ' | ')") } -PassThru
            }
            Mock Invoke-PSGPOLdapSearch {
                $script:Searches++
                # Redirected when read before the deletion; gone after it.
                if ($script:Searches -eq 1) { [pscustomobject]@{ Attributes = @{ gPCFileSysPath = @('\\contoso.com\SysVol\contoso.com\PSGPOTools') } } }
            }
            Mock Invoke-PSGPOSambaTool { $script:Order.Add('samba-tool gpo del') }
            Mock Remove-PSGPOWindowsGpo { $script:Order.Add('Remove-GPO') }
            Remove-PSGPODomainGpo -Directory $Directory -Gpo $Gpo 3>$null
            $script:Order.Count | Should -Be 2
            $script:Order[0] | Should -Be 'modify Delete \\contoso.com\SysVol\contoso.com\PSGPOTools | Add \\contoso.com\SysVol\contoso.com\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}'
            $script:Order[1] | Should -BeIn 'samba-tool gpo del', 'Remove-GPO'
        }
    }

    Describe 'SYSVOL with -Credential on Windows' -Skip:(-not $IsWindows) {
        BeforeEach {
            $script:PSGPOSysvolConnections.Clear()
            $Directory = [GPOToolsLdapDirectory]::new('contoso.com', 'DC=contoso,DC=com', 'dc1.contoso.com', 'Active Directory')
            # A test account: nothing is connected, New-PSDrive is mocked.
            $Directory.Credential = [pscredential]::new('CONTOSO\admin1', (ConvertTo-SecureString 'not-a-password' -AsPlainText -Force))
        }

        It 'Reaches the share with the account of the directory, once' {
            Mock New-PSDrive { }
            Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL'
            Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL'
            Should -Invoke New-PSDrive -Times 1 -Exactly -ParameterFilter { $Root -eq '\\dc1.contoso.com\SYSVOL' -and $Credential.UserName -eq 'CONTOSO\admin1' }
        }

        It 'Says how to close the connections of another account' {
            Mock New-PSDrive { throw 'Multiple connections to a server or shared resource by the same user, using more than one user name, are not allowed (1219).' }
            { Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL' } | Should -Throw -ExpectedMessage '*already reached with another account*net use*'
        }

        It 'Does nothing without -Credential' {
            Mock New-PSDrive { }
            $Directory.Credential = $null
            Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL'
            Should -Invoke New-PSDrive -Times 0
        }
    }

    Describe 'Reading a large domain' {
        It 'Reads 2 000 GPOs and 1 000 OUs, sorted, in a few seconds' {
            $Gpos = foreach ($i in 1..2000) {
                $Id = [guid]::NewGuid().ToString().ToUpperInvariant()
                [pscustomobject]@{ DistinguishedName = "CN={$Id},CN=Policies,CN=System,DC=contoso,DC=com"
                    Attributes = @{ cn = @("{$Id}"); displayName = @("GPO $(2001 - $i)"); versionNumber = @('0'); flags = @('0') } }
            }
            $Ous = foreach ($i in 1..1000) {
                [pscustomobject]@{ DistinguishedName = "OU=OU$i,DC=contoso,DC=com"; Attributes = @{ name = @("OU$i"); gPLink = @("[LDAP://$($Gpos[$i].DistinguishedName);0]") } }
            }
            $Domain = [pscustomobject]@{ DistinguishedName = 'DC=contoso,DC=com'; Attributes = @{} }
            $Time = Measure-Command { $script:Read = ConvertTo-PSGPOLdapDirectory -Server dc1 -DomainEntry $Domain -OrganizationalUnitEntry $Ous -GpoEntry $Gpos }
            $Time.TotalSeconds | Should -BeLessThan 30
            $script:Read.Gpos[0].DisplayName | Should -Be 'GPO 1'
            $script:Read.Gpos[1].DisplayName | Should -Be 'GPO 10' -Because 'sorted once, by name'
            $script:Read.Gpos[1999].DisplayName | Should -Be 'GPO 999'
            $script:Read.FindSom('OU=OU5,DC=contoso,DC=com').Links[0].Gpo.DisplayName | Should -Be $Gpos[5].Attributes.displayName[0]

            # A delegated account: it edits no GPO, and links GPOs to one OU in two.
            foreach ($Gpo in $script:Read.Gpos) { $Gpo.CanEdit = $false }
            $script:Read.Domain.CanLink = $false
            foreach ($Som in $script:Read.Domain.Children) { $Som.CanLink = ([int]($Som.Name.Substring(2)) % 2) -eq 0 }
            $Time = Measure-Command { $script:Visible = @($script:Read.GetVisibleGpos()) }
            $Time.TotalSeconds | Should -BeLessThan 5
            $script:Visible.Count | Should -Be 500
            @($script:Read.Gpos | Select-Object -First 200 | Where-Object { $script:Read.IsGpoVisible($_) }).Id |
                Should -Be @($script:Visible | Where-Object { @($script:Read.Gpos | Select-Object -First 200) -contains $_ }).Id
        }
    }
}
