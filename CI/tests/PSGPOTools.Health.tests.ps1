#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The health of the GPOs and their replication between the domain controllers (Test-PSGPOHealth,
# Get-PSGPOReplicationStatus, the Status tab of the domain): three domain controllers simulated,
# their directory over LDAP and their SYSVOL mocked (the labs have one domain controller each).
# SYSVOL is read through Read-PSGPOSysvolItem on Windows and smbclient elsewhere: both mocked.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')
        $Dc1 = 'dc1.hardenbox.labo'
        $Dc2 = 'dc2.hardenbox.labo'
        $Dc3 = 'dc3.hardenbox.labo'
        $OnlyOnDc2 = '{EEEEEEEE-0000-4000-8000-000000000002}'
        $Orphan = '{DEADBEEF-0000-4000-8000-000000000001}'
        $RegistryExtensions = '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'

        function New-TestGptIni {
            param([long]$Version)
            [System.Text.Encoding]::ASCII.GetBytes("[General]`r`nVersion=$Version`r`n")
        }

        # The folders of Policies as Get-PSGPOSysvolPolicyFolder gives them: '{GUID}' = 'Path:Size', ...
        function New-TestFolderSet {
            param([System.Collections.IDictionary]$Folders)
            $Result = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Name in $Folders.Keys) {
                $Files = [System.Collections.Generic.List[object]]::new()
                foreach ($Spec in @($Folders[$Name])) {
                    $Path, $Size = $Spec -split ':'
                    $Files.Add([pscustomobject]@{ Path = $Path; Size = $(if ($Size) { [long]$Size } else { 30 }) })
                }
                $Result[$Name] = [pscustomobject]@{ Files = $Files; Problem = $null }
            }
            , $Result
        }

        function Get-TestGpoEntry {
            param([object[]]$Entries, [string]$Id)
            $Entries | Where-Object { $_.Attributes['cn'][0] -eq $Id }
        }

        # The GUID of a path of a GPO folder ({GUID}\GPT.INI).
        function Get-TestPathId {
            param([string]$Path)
            if ($Path -match '\{([0-9A-Fa-f-]{36})\}') { "{$($Matches[1].ToUpperInvariant())}" }
        }
    }

    Describe 'Listing of Policies by smbclient' {
        It 'Gives the folders of the GPOs and their files, without the other folders of Policies' {
            $Lines = @(
                '  .                                   D        0  Tue Oct 27 14:00:48 2026'
                '  ..                                  D        0  Tue Oct 27 13:46:16 2026'
                '  {31B2F340-016D-11D2-945F-00C04FB984F9}      D        0  Sun Oct 11 15:26:09 2026'
                '  {6AC1786C-016F-11D2-945F-00C04FB984F9}_NTFRS_1a2b3c4d      D        0  Sun Oct 11 15:26:09 2026'
                '  PolicyDefinitions                   D        0  Mon Oct  5 09:00:00 2026'
                ''
                '		24379392 blocks of size 1024. 10239680 blocks available'
                '\hardenbox.labo\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}'
                '  .                                   D        0  Sun Oct 11 15:26:09 2026'
                '  GPT.INI                             N       26  Sun Oct 11 15:26:09 2026'
                '  MACHINE                             D        0  Sun Oct 11 15:26:09 2026'
                ''
                '\hardenbox.labo\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}\MACHINE\Microsoft\Windows NT\SecEdit'
                '  GptTmpl.inf                         A     1098  Sun Oct 11 15:26:09 2026'
                '  My Settings File.txt                AH      12  Sun Oct 11 15:26:09 2026'
                ''
                '\hardenbox.labo\Policies\PolicyDefinitions'
                '  windows.admx                        A    40000  Mon Oct  5 09:00:00 2026'
                'NT_STATUS_ACCESS_DENIED listing \hardenbox.labo\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}_NTFRS_1a2b3c4d\*'
            )
            $Folders = ConvertFrom-PSGPOSmbClientListing -Line $Lines -Root 'hardenbox.labo\Policies'
            @($Folders.Keys) | Should -Be @('{31B2F340-016D-11D2-945F-00C04FB984F9}', '{6AC1786C-016F-11D2-945F-00C04FB984F9}_NTFRS_1a2b3c4d')
            $Default = $Folders['{31b2f340-016d-11d2-945f-00c04fb984f9}']
            @($Default.Files.Path) | Should -Be @('GPT.INI', 'MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf', 'MACHINE\Microsoft\Windows NT\SecEdit\My Settings File.txt')
            @($Default.Files.Size) | Should -Be @(26, 1098, 12)
            $Default.Problem | Should -BeNullOrEmpty
            $Folders['{6AC1786C-016F-11D2-945F-00C04FB984F9}_NTFRS_1a2b3c4d'].Problem | Should -Be 'NT_STATUS_ACCESS_DENIED ({6AC1786C-016F-11D2-945F-00C04FB984F9}_NTFRS_1a2b3c4d)'
        }

        It 'Throws when smbclient did not list Policies' {
            { ConvertFrom-PSGPOSmbClientListing -Line @('tree connect failed: NT_STATUS_ACCESS_DENIED') -Root 'hardenbox.labo\Policies' } |
                Should -Throw 'smbclient did not list hardenbox.labo\Policies: tree connect failed: NT_STATUS_ACCESS_DENIED'
            { ConvertFrom-PSGPOSmbClientListing -Line @('NT_STATUS_ACCESS_DENIED listing \hardenbox.labo\Policies\*') -Root 'hardenbox.labo\Policies' } |
                Should -Throw 'smbclient cannot list hardenbox.labo\Policies: NT_STATUS_ACCESS_DENIED'
        }
    }

    Describe 'Files of a GPO that hold settings' {
        It 'Is <Expected> for <Path> holding "<Text>"' -ForEach @(
            @{ Path = 'Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf'; Text = "[Unicode]`r`nUnicode=yes`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1"; Expected = $false }
            @{ Path = 'Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf'; Text = "[Unicode]`r`nUnicode=yes`r`n[System Access]`r`nMinimumPasswordAge = 1"; Expected = $true }
            @{ Path = 'Machine\Microsoft\Windows NT\Audit\audit.csv'; Text = 'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value'; Expected = $false }
            @{ Path = 'Machine\Microsoft\Windows NT\Audit\audit.csv'; Text = "Machine Name,Policy Target,Subcategory`r`n,System,Audit Logon"; Expected = $true }
            @{ Path = 'User\Scripts\scripts.ini'; Text = "[Logon]`r`n"; Expected = $false }
            @{ Path = 'User\Scripts\scripts.ini'; Text = "[Logon]`r`n0CmdLine=logon.cmd`r`n0Parameters="; Expected = $true }
            @{ Path = 'Machine\Preferences\Registry\Registry.xml'; Text = '<RegistrySettings clsid="{A3CCFC41-DFDB-43a5-8D26-0FE8B954DA51}"/>'; Expected = $false }
            @{ Path = 'Machine\Preferences\Registry\Registry.xml'; Text = '<RegistrySettings clsid="{A3CCFC41-DFDB-43a5-8D26-0FE8B954DA51}"><Registry clsid="{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}" name="x"/></RegistrySettings>'; Expected = $true }
        ) {
            Test-PSGPOSettingFile -Path $Path -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text)) | Should -Be $Expected
        }

        It 'Reads GptTmpl.inf in UTF-16 as GPMC writes it' {
            $Bytes = [byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes("[Unicode]`r`nUnicode=yes`r`n[Event Audit]`r`nAuditLogonEvents = 3")
            Test-PSGPOSettingFile -Path 'Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf' -Bytes $Bytes | Should -BeTrue
        }
    }

    Describe 'Replication and health of the GPOs' {
        BeforeEach {
            $Set = Get-TestLdapEntrySet
            (Get-TestGpoEntry $Set.Gpos $TestLdapWorkstationsPolicy).Attributes['gpcmachineextensionnames'] = [string[]]$RegistryExtensions
            # The directory read from dc1, its PDC emulator: the baseline.
            $Directory = ConvertTo-PSGPOLdapDirectory -Server $Dc1 -VendorName 'Samba Team (https://www.samba.org)' -DomainEntry $Set.Domain -OrganizationalUnitEntry $Set.Ous -GpoEntry $Set.Gpos 3>$null
            $Directory.PdcEmulator = $Dc1
            # dc2: Workstations not replicated yet, the Default Domain Controllers Policy missing, a GPO of its own.
            $Dc2Set = Get-TestLdapEntrySet
            (Get-TestGpoEntry $Dc2Set.Gpos $TestLdapWorkstationsPolicy).Attributes['versionnumber'] = [string[]]'131073'
            $Dc2Gpos = @($Dc2Set.Gpos | Where-Object { $_.Attributes['cn'][0] -ne $TestLdapDefaultDcPolicy }) +
                @(New-TestLdapEntry "CN=$OnlyOnDc2,CN=Policies,CN=System,$TestLdapDomainDN" @{ cn = $OnlyOnDc2; displayName = 'Only on dc2'; versionNumber = '1' })
            $script:Ldap = @{ $Dc1 = $Set.Gpos; $Dc2 = $Dc2Gpos }
            $script:Down = @($Dc3)
            $Ws2 = '{8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E31}'
            $NoName = '{8F4C1B2E-3D5A-4C7B-9E61-0A2B3C4D5E32}'
            # dc1: Workstations with another version in SYSVOL, the second Workstations without GPT.INI,
            # the GPO without a name without a folder, a folder without a GPO.
            $script:Folders = @{
                $Dc1 = New-TestFolderSet ([ordered]@{
                        $TestLdapDefaultDomainPolicy = 'GPT.INI', 'Machine\Registry.pol:8'
                        $TestLdapDefaultDcPolicy = 'GPT.INI', 'MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf:300'
                        $TestLdapWorkstationsPolicy = 'GPT.INI', 'Machine\Registry.pol:120', 'User\Registry.pol:64'
                        $Ws2 = 'Machine\Registry.pol:8'
                        $Orphan = 'GPT.INI'
                    })
                $Dc2 = New-TestFolderSet ([ordered]@{
                        $TestLdapDefaultDomainPolicy = 'GPT.INI'
                        $TestLdapWorkstationsPolicy = 'GPT.INI'
                        $Ws2 = 'GPT.INI'
                        $NoName = 'GPT.INI'
                        $OnlyOnDc2 = 'GPT.INI'
                    })
            }
            # The version of the GPT.INI of each folder; dc2 has the former SYSVOL of the Default Domain Policy.
            $script:Sysvol = @{
                $Dc1 = @{ $TestLdapDefaultDomainPolicy = 3; $TestLdapDefaultDcPolicy = 1; $TestLdapWorkstationsPolicy = 131073; $Orphan = 1 }
                $Dc2 = @{ $TestLdapDefaultDomainPolicy = 2; $TestLdapWorkstationsPolicy = 131073; $Ws2 = 0; $NoName = 0; $OnlyOnDc2 = 1 }
            }
            Mock New-PSGPOLdapConnection {
                if ($Server -in $script:Down) { throw "The LDAP server $Server is unavailable." }
                [pscustomobject]@{ Server = $Server } | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -PassThru
            }
            Mock Invoke-PSGPOLdapSearch {
                if ($SearchBase -eq '') { return New-TestLdapEntry '' @{ dnsHostName = $Connection.Server; vendorName = 'Samba Team (https://www.samba.org)' } }
                if ($Scope -eq 'Base') { return $Set.Domain }
                if ($Filter -like '*groupPolicyContainer*') { return $script:Ldap[$Connection.Server] }
            }
            Mock Get-PSGPODomainController { $Dc1, $Dc2, $Dc3 }
            Mock Get-PSGPOSysvolPolicyFolder { , $script:Folders[$Directory.Server] }
            Mock Assert-PSGPOKerberosOnly { }
            # Windows reads each GPT.INI, Linux all of them in one smbclient.
            Mock Read-PSGPOSysvolItem {
                $Version = $script:Sysvol[$Directory.Server][(Get-TestPathId $Path)]
                if ($null -ne $Version) { , (New-TestGptIni $Version) }
            }
            Mock Invoke-PSGPOSmbClient {
                foreach ($Get in [regex]::Matches($Command, 'get "([^"]+)" "([^"]+)"')) {
                    $Version = $script:Sysvol[$Server][(Get-TestPathId $Get.Groups[1].Value)]
                    if ($null -ne $Version) { [System.IO.File]::WriteAllBytes($Get.Groups[2].Value, (New-TestGptIni $Version)) }
                    else { "NT_STATUS_OBJECT_NAME_NOT_FOUND opening remote file \$($Get.Groups[1].Value)" }
                }
            }
            Mock Read-PSGPOSysvolFile {
                if ($Path -like '*GptTmpl.inf') { , [System.Text.Encoding]::UTF8.GetBytes("[Unicode]`r`nUnicode=yes`r`n[System Access]`r`nMinimumPasswordAge = 1") }
            }
        }

        It 'Compares each domain controller to the baseline, as the Status tab of GPMC' {
            $Rows = @(Get-PSGPOReplicationStatus -Directory $Directory)
            $State = { param($Server) @($Rows | Where-Object DomainController -EQ $Server | ForEach-Object { '{0}={1}' -f $(if ($_.DisplayName) { $_.DisplayName } else { $_.Id }), $_.State }) }
            & $State $Dc1 | Should -Be @(
                'Default Domain Controllers Policy=InSync'
                'Default Domain Policy=InSync'
                'Workstations=SysvolDiffers'
                'Workstations=SysvolDiffers'
                "$NoName=SysvolDiffers"
                "$Orphan=OrphanFolder"
            )
            & $State $Dc2 | Should -Be @(
                'Default Domain Controllers Policy=Missing'
                'Default Domain Policy=SysvolDiffers'
                'Workstations=DirectoryDiffers'
                'Workstations=InSync'
                "$NoName=InSync"
                'Only on dc2=Extra'
            )
            & $State $Dc3 | Should -Be @('=Unreachable')
            @($Rows | Where-Object DomainController -EQ $Dc1).IsBaseline | Should -Not -Contain $false

            $Workstations = $Rows | Where-Object { $_.DomainController -eq $Dc2 -and $_.Id -eq [guid]$TestLdapWorkstationsPolicy }
            $Workstations.DirectoryVersion | Should -Be 131073
            $Workstations.BaselineVersion | Should -Be 131074
            $Workstations.Detail | Should -Be "user 2, computer 1 in the directory, user 2, computer 2 on ${Dc1}: the replication of the directory is not done."
            ($Rows | Where-Object { $_.DomainController -eq $Dc2 -and $_.DisplayName -eq 'Default Domain Policy' }).Detail |
                Should -Be "user 0, computer 3 in the directory, user 0, computer 2 in SYSVOL: Samba does not replicate SYSVOL, copy the folder of the GPO from $Dc1."
            ($Rows | Where-Object { $_.DomainController -eq $Dc1 -and $_.Id -eq [guid]$NoName }).Detail |
                Should -Be 'the GPO has no folder in SYSVOL: the computers fail to apply the GPO.'
            ($Rows | Where-Object { $_.DomainController -eq $Dc1 -and $_.Id -eq [guid]$TestLdapWorkstationsPolicy }).Detail |
                Should -Be 'user 2, computer 2 in the directory, user 2, computer 1 in SYSVOL: a change of the GPO stopped halfway; the computers apply SYSVOL.'
            ($Rows | Where-Object DomainController -EQ $Dc3).Detail | Should -BeLike 'The domain controller cannot be read: *unavailable*'
        }

        It 'Checks the GPOs on the baseline: their folder, their versions, their client-side extensions' {
            $Findings = @(Test-PSGPOHealth -Directory $Directory | Where-Object DomainController -EQ $Dc1 | Where-Object Check -NE 'OrphanFolder')
            @($Findings | ForEach-Object { '{0} {1} {2}' -f $_.Severity, $_.Check, $_.Target }) | Should -Be @(
                'Warning Extension Default Domain Controllers Policy'
                'Error Version Workstations'
                'Warning Extension Workstations'
                'Error Folder Workstations'
                "Error Folder $NoName"
                'Warning Link Workstations'
            )
            $Findings[0].Detail | Should -Be 'MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf holds settings, but the GPO does not declare their client-side extension (Security) for the computers: they are not applied. Save one of them again in the console to declare it.'
            $Findings[1].Detail | Should -Be 'user 2, computer 2 in the directory, user 2, computer 1 in SYSVOL: a change of the GPO stopped halfway, and the computers apply SYSVOL. Save a setting of the GPO again.'
            $Findings[1].Id | Should -Be ([guid]$TestLdapWorkstationsPolicy)
            $Findings[2].Detail | Should -BeLike 'User\Registry.pol holds settings*(Registry Policy) for the users*'
            $Findings[3].Detail | Should -Be 'the folder of the GPO has no GPT.INI: the computers fail to apply the GPO.'
            $Findings[5].Detail | Should -Be "A link to $(Get-TestLdapGpoDN $TestLdapMissingPolicy), which is not a GPO of the domain: the computers ignore it. Delete the link."
            Should -Invoke Read-PSGPOSysvolFile -Times 1 -Exactly -Because 'only the file without its extension is read, and an empty Registry.pol is not'
        }

        It 'Reports the folders without a GPO, the other domain controllers and the one that cannot be read' {
            $Findings = @(Test-PSGPOHealth -Directory $Directory | Where-Object { $_.DomainController -ne $Dc1 -or $_.Check -eq 'OrphanFolder' })
            @($Findings | ForEach-Object { '{0} {1} {2} {3}' -f $_.Severity, $_.Check, $_.Target, $_.DomainController }) | Should -Be @(
                "Warning OrphanFolder $Orphan $Dc1"
                "Warning Replication Default Domain Controllers Policy $Dc2"
                "Warning Replication Default Domain Policy $Dc2"
                "Warning Replication Workstations $Dc2"
                "Warning Replication Only on dc2 $Dc2"
                "Warning DomainController $Dc3 $Dc3"
            )
            $Findings[0].Id | Should -Be ([guid]$Orphan)
        }

        It 'Throws when the baseline cannot be read' {
            $script:Down = @($Dc1)
            { Test-PSGPOHealth -Directory $Directory } | Should -Throw "The baseline domain controller $Dc1 cannot be read: *unavailable*"
        }

        It 'Checks only the GPOs named, without the folders and links, on the domain controllers given' {
            $Findings = @(Test-PSGPOHealth -Directory $Directory -Name 'Default*' -DomainController $Dc2)
            @($Findings | ForEach-Object { '{0} {1} {2}' -f $_.Check, $_.Target, $_.DomainController }) | Should -Be @(
                "Extension Default Domain Controllers Policy $Dc1"
                "Replication Default Domain Controllers Policy $Dc2"
                "Replication Default Domain Policy $Dc2"
            )
            Should -Invoke Get-PSGPODomainController -Times 0 -Exactly
            Should -Invoke New-PSGPOLdapConnection -Times 0 -Exactly -ParameterFilter { $Server -eq $Dc3 }
        }

        It 'Returns nothing for a healthy domain' {
            $script:Ldap = @{ $Dc1 = @(Get-TestGpoEntry $Set.Gpos $TestLdapDefaultDomainPolicy) }
            $script:Folders = @{ $Dc1 = New-TestFolderSet ([ordered]@{ $TestLdapDefaultDomainPolicy = 'GPT.INI' }) }
            $Healthy = ConvertTo-PSGPOLdapDirectory -Server $Dc1 -DomainEntry $Set.Domain -GpoEntry $script:Ldap[$Dc1]
            Mock Get-PSGPODomainController { $Dc1 }
            @(Test-PSGPOHealth -Directory $Healthy) | Should -BeNullOrEmpty
            @(Get-PSGPOReplicationStatus -Directory $Healthy).State | Should -Be @('InSync')
        }

        It 'Reads SYSVOL again for the details of the GPOs' {
            $script:PSGPOSysvolVersions['kept'] = @{ Version = 1 }
            $null = Get-PSGPOReplicationStatus -Directory $Directory -DomainController $Dc2
            $script:PSGPOSysvolVersions.ContainsKey('kept') | Should -BeFalse
        }

        It 'Refuses a directory that is not read from a domain controller' {
            { Test-PSGPOHealth -Directory ([GPOToolsDirectory]::new('contoso.com')) } | Should -Throw '*read over LDAP*'
            { Get-PSGPOReplicationStatus -Directory ([GPOToolsDirectory]::new('contoso.com')) } | Should -Throw '*read over LDAP*'
        }
    }

    Describe 'GPT.INI of the GPOs read by smbclient' -Skip:$IsWindows {
        It 'Reads them in one smbclient, and stops when the share is refused' {
            $Directory = New-TestLdapDirectory
            $Folders = New-TestFolderSet ([ordered]@{ $TestLdapDefaultDomainPolicy = 'GPT.INI'; $TestLdapDefaultDcPolicy = 'GPT.INI' })
            Mock Assert-PSGPOKerberosOnly { }
            Mock Invoke-PSGPOSmbClient {
                foreach ($Get in [regex]::Matches($Command, 'get "([^"]+)" "([^"]+)"')) {
                    if ($Get.Groups[1].Value -like "*$TestLdapDefaultDcPolicy*") { "NT_STATUS_ACCESS_DENIED opening remote file \$($Get.Groups[1].Value)" }
                    else { [System.IO.File]::WriteAllBytes($Get.Groups[2].Value, [System.Text.Encoding]::ASCII.GetBytes("[General]`r`nVersion=3`r`n")) }
                }
            }
            $Read = Read-PSGPOSysvolGptIni -Directory $Directory -Gpo @($Directory.Gpos) -Folders $Folders
            Should -Invoke Invoke-PSGPOSmbClient -Times 1 -Exactly
            Get-PSGPOGptIniVersion -Bytes $Read[([guid]$TestLdapDefaultDomainPolicy).ToString()].Bytes | Should -Be 3
            $Read[([guid]$TestLdapDefaultDcPolicy).ToString()].Problem | Should -Be 'GPT.INI cannot be read: NT_STATUS_ACCESS_DENIED'
            $Read[([guid]$TestLdapWorkstationsPolicy).ToString()].Problem | Should -Be 'the GPO has no folder in SYSVOL'

            Mock Invoke-PSGPOSmbClient { 'tree connect failed: NT_STATUS_ACCESS_DENIED' }
            { Read-PSGPOSysvolGptIni -Directory $Directory -Gpo @($Directory.Gpos) -Folders $Folders } | Should -Throw '*tree connect failed*'
        }
    }
}
