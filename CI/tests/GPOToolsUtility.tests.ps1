#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The classes are only visible inside the module, so the whole file runs in its scope.
# InModuleScope at the top level needs the module during discovery, hence BeforeDiscovery.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        $script:PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path
    }

    Describe 'GpoToolsAdmx class' {
        Context 'Constructor with WindowsBackup.admx' {
            BeforeAll {
                $ADMXPath = Join-Path $PolicyDefinitions 'WindowsBackup.admx'
                $ADMX = [GPOToolsAdmx]::New($ADMXPath)
                $UsingTab = @(
                    @{ prefix = 'backup'; namespace = 'Microsoft.Policies.Backup' },
                    @{ prefix = 'windows'; namespace = 'Microsoft.Policies.Windows' },
                    @{ prefix = 'server'; namespace = 'Microsoft.Policies.Server' }
                )
                $CatTab = @(
                    @{ Name = 'Backup'; DisplayName = 'Backup'; ParentCategory = @{ prefix = 'windows'; name = 'WindowsComponents' } },
                    @{ Name = 'BackupServer'; DisplayName = 'BackupServer'; ParentCategory = @{ prefix = 'backup'; name = 'Backup' } }
                )
                $PolTab = @(
                    @{ Name = 'AllowOnlySystemBackup'; ValueName = 'OnlySystemBackup' },
                    @{ Name = 'DisallowLocallyAttachedStorageAsBackupTarget'; ValueName = 'NoBackupToDisk' },
                    @{ Name = 'DisallowNetworkAsBackupTarget'; ValueName = 'NoBackupToNetwork' },
                    @{ Name = 'DisallowOpticalMediaAsBackupTarget'; ValueName = 'NoBackupToOptical' },
                    @{ Name = 'DisallowRunOnceBackups'; ValueName = 'NoRunNowBackup' }
                )
            }

            It 'Creates a GPOToolsAdmx object' {
                $ADMX | Should -BeOfType ([GPOToolsAdmx])
            }

            It 'Sets FilePath and BaseName' {
                $ADMX.FilePath | Should -Be $ADMXPath
                $ADMX.BaseName | Should -Be 'WindowsBackup'
            }

            It 'Reads the target namespace' {
                $ADMX.Target | Should -BeOfType ([AdmxNamespace])
                $ADMX.Target.prefix | Should -Be 'windowsbackup'
                $ADMX.Target.namespace | Should -Be 'Microsoft.Policies.WindowsBackup'
            }

            It 'Reads the using namespaces' {
                $ADMX.Using.Count | Should -Be $UsingTab.Count
                for ($i = 0; $i -lt $UsingTab.Count; $i++) {
                    $ADMX.Using[$i] | Should -BeOfType ([AdmxNamespace])
                    $ADMX.Using[$i].prefix | Should -Be $UsingTab[$i].prefix
                    $ADMX.Using[$i].namespace | Should -Be $UsingTab[$i].namespace
                }
            }

            It 'Has no SupportedOn definition' {
                $ADMX.SupportedOnDefinition.Count | Should -Be 0
            }

            It 'Reads the categories' {
                $ADMX.Categories.Count | Should -Be $CatTab.Count
                for ($i = 0; $i -lt $CatTab.Count; $i++) {
                    $ADMX.Categories[$i].Name | Should -Be $CatTab[$i].Name
                    $ADMX.Categories[$i].DisplayName | Should -Be $CatTab[$i].DisplayName
                    $ADMX.Categories[$i].ParentCategory.prefix | Should -Be $CatTab[$i].ParentCategory.prefix
                    $ADMX.Categories[$i].ParentCategory.name | Should -Be $CatTab[$i].ParentCategory.name
                }
            }

            It 'Reads the policies' {
                $ADMX.Policies.Count | Should -Be $PolTab.Count
                for ($i = 0; $i -lt $PolTab.Count; $i++) {
                    $Policy = $ADMX.Policies[$i]
                    $Policy.Name | Should -Be $PolTab[$i].Name
                    $Policy.DisplayName | Should -Be $PolTab[$i].Name
                    $Policy.Class | Should -Be 'Machine'
                    $Policy.RegKey | Should -Be 'Software\Policies\Microsoft\Windows\Backup\Server'
                    $Policy.ValueName | Should -Be $PolTab[$i].ValueName
                    $Policy.ParentCategory.prefix | Should -Be 'windowsbackup'
                    $Policy.ParentCategory.name | Should -Be 'BackupServer'
                    $Policy.enableValue | Should -Be 1
                    $Policy.disableValue | Should -Be 0
                }
            }
        }

        Context 'Constructor with WindowsUpdate.admx' {
            BeforeAll {
                $ADMX = [GPOToolsAdmx]::New((Join-Path $PolicyDefinitions 'WindowsUpdate.admx'))
                $SupportedOnNames = @(
                    'WU_SUPPORTED_Windows7ToXPSP2',
                    'WU_SUPPORTED_Windows7_To_Win2kSP3_Or_XPSP1',
                    'WU_SUPPORTED_Win2kSP3_Or_XPSP1_NoWinRT',
                    'WU_SUPPORTED_WindowsXPSP1_NoWinRT',
                    'WU_SUPPORTED_Win2kSP3_Or_XPSP1_Through_Win81_or_Server2012R2',
                    'WU_SUPPORTED_WindowsVista_Through_Win81_or_Server2012R2'
                )
                $PolTab = @(
                    @{ Name = 'NoAutoUpdate'; Class = 'User'; RegKey = 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
                       ValueName = 'NoAutoUpdate'; ParentCategory = @{ prefix = 'windows'; name = 'System' } },
                    @{ Name = 'AUDontShowUasPolicy'; Class = 'Both'; RegKey = 'Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
                       ValueName = 'NoAUShutdownOption'; ParentCategory = @{ prefix = 'wuau'; name = 'WindowsUpdateCat' } }
                )
            }

            It 'Reads the target and using namespaces' {
                $ADMX.BaseName | Should -Be 'WindowsUpdate'
                $ADMX.Target.prefix | Should -Be 'wuau'
                $ADMX.Target.namespace | Should -Be 'Microsoft.Policies.WindowsUpdate'
                $ADMX.Using.Count | Should -Be 1
                $ADMX.Using[0].namespace | Should -Be 'Microsoft.Policies.Windows'
            }

            It 'Reads the SupportedOn definitions' {
                $ADMX.SupportedOnDefinition.Name | Should -Be $SupportedOnNames
                $ADMX.SupportedOnDefinition.DisplayName | Should -Be $SupportedOnNames
            }

            It 'Reads the categories and their parent references' {
                $ADMX.Categories.Name | Should -Be @('WindowsUpdateCat', 'DeferUpdateCat')
                $ADMX.Categories[0].ParentCategory.prefix | Should -Be 'windows'
                $ADMX.Categories[0].ParentCategory.name | Should -Be 'WindowsComponents'
                # An unprefixed reference resolves to the file's own prefix.
                $ADMX.Categories[1].ParentCategory.prefix | Should -Be 'wuau'
                $ADMX.Categories[1].ParentCategory.name | Should -Be 'WindowsUpdateCat'
            }

            It 'Reads the policies' {
                $ADMX.Policies.Count | Should -Be 40
                for ($i = 0; $i -lt $PolTab.Count; $i++) {
                    $Policy = $ADMX.Policies[$i]
                    $Policy.Name | Should -Be $PolTab[$i].Name
                    $Policy.Class | Should -Be $PolTab[$i].Class
                    $Policy.RegKey | Should -Be $PolTab[$i].RegKey
                    $Policy.ValueName | Should -Be $PolTab[$i].ValueName
                    $Policy.ParentCategory.prefix | Should -Be $PolTab[$i].ParentCategory.prefix
                    $Policy.ParentCategory.name | Should -Be $PolTab[$i].ParentCategory.name
                }
            }
        }
    }

    Describe 'GpoToolsAdml class' {
        BeforeAll {
            $ADMLFile = Get-Item -Path (Join-Path $PolicyDefinitions 'fr-FR' 'WindowsBackup.adml')
            $ADML = [GPOToolsAdml]::new($ADMLFile.FullName)
        }

        It 'Sets FilePath and BaseName' {
            $ADML | Should -BeOfType ([GPOToolsAdml])
            $ADML.FilePath | Should -Be $ADMLFile.FullName
            $ADML.BaseName | Should -Be $ADMLFile.BaseName
        }

        It 'Loads the localized string <Id>' -ForEach @(
            @{ Id = 'AllowOnlySystemBackup'; Pattern = 'Autoriser\suniquement\sla\ssauvegarde\sdu\ssyst\xE8me' }
            @{ Id = 'DisallowLocallyAttachedStorageAsBackupTarget'; Pattern = 'Ne\spas\sautoriser\sun\sp\xE9riph\xE9rique\sde\sstockage\sconnect\xE9\slocalement' }
            @{ Id = 'Backup'; Pattern = 'Sauvegarde' }
            @{ Id = 'windowscomponents'; Pattern = 'Composants Windows' }
        ) {
            $ADML.StringTable.ContainsKey($Id) | Should -BeTrue
            $ADML.GetString($Id) | Should -Match $Pattern
        }

        It 'GetString returns $null for an unknown or empty id' {
            $ADML.GetString('DoesNotExist') | Should -BeNullOrEmpty
            $ADML.GetString('') | Should -BeNullOrEmpty
            $ADML.GetString($null) | Should -BeNullOrEmpty
        }
    }

    Describe 'GPOToolsSupportedOn class' {
        BeforeAll {
            $ADMX = [GpoToolsAdmx]::new((Join-Path $PolicyDefinitions 'Windows.admx'))
            $ADML = [GpoToolsAdml]::new((Join-Path $PolicyDefinitions 'fr-FR' 'Windows.adml'))
        }

        It 'Resolves the localized display name' {
            $Support = [GPOToolsSupportedOn]::new($ADMX.SupportedOnDefinition[0], $ADML)
            $Support.Name | Should -Be 'SUPPORTED_AllowWebPrinting'
            $Support.DisplayName | Should -Match 'Windows\s2000\sou\sversion\sult\xE9rieure,\sex\xE9cutant\sIIS'
        }

        It 'LoadAdmxAdml returns every definition' {
            $LoadAdm = [GPOToolsSupportedOn]::LoadAdmxAdml($ADMX, $ADML)
            $LoadAdm.Count | Should -Be $ADMX.SupportedOnDefinition.Count
            $LoadAdm[1].Name | Should -Be 'SUPPORTED_IE6SP1'
            $LoadAdm[1].DisplayName | Should -Match 'Au\sminimum\sInternet\sExplorer\s6\sService\sPack\s1'
        }
    }

    Describe 'GPOToolsCategory class' {
        BeforeAll {
            $ADMX = [GpoToolsAdmx]::new((Join-Path $PolicyDefinitions 'Windows.admx'))
            $ADML = [GpoToolsAdml]::new((Join-Path $PolicyDefinitions 'fr-FR' 'Windows.adml'))
        }
        BeforeEach {
            [GPOToolsUtility]::RemoveAll()
        }

        It 'Constructor resolves the localized texts' {
            $Category = [GPOToolsCategory]::new($ADMX.Categories[0], $ADMX.Categories, $ADML)
            $Category.Name | Should -Be 'System'
            $Category.DisplayName | Should -Match 'Syst\xE8me'
            $Category.ExplainText | Should -Match 'Autorise\sla\sconfiguration\sde\sdivers\sparam\xE8tres'
        }

        It 'LoadAdmxAdml loads every category once with its parent' {
            [GPOToolsCategory]::LoadAdmxAdml($ADMX, $ADML)
            $Categories = [GPOToolsUtility]::Categories

            $Categories.Count | Should -Be $ADMX.Categories.Count
            ($Categories.Name | Sort-Object -Unique).Count | Should -Be $Categories.Count
            $Internet = $Categories | Where-Object Name -EQ 'InternetManagement'
            $Internet.ParentCategory | Should -BeOfType ([GPOToolsCategory])
            $Internet.ParentCategory.Name | Should -Be 'System'
        }

        It 'Creates a parent category declared later in the same ADMX' {
            # Load a child before its parent: the parent must be created on the fly, not dropped.
            $Child = $ADMX.Categories | Where-Object Name -EQ 'InternetManagement'
            $Created = [GPOToolsCategory]::Create($Child, $ADMX.Categories, $ADML)

            $Created.ParentCategory.Name | Should -Be 'System'
            [GPOToolsUtility]::Categories.Name | Should -Contain 'System'
            [GPOToolsCategory]::LoadAdmxAdml($ADMX, $ADML)
            @([GPOToolsUtility]::Categories | Where-Object Name -EQ 'System').Count | Should -Be 1
        }

        It 'Create returns the already loaded category' {
            $First = [GPOToolsCategory]::Create($ADMX.Categories[0], $ADMX.Categories, $ADML)
            $Second = [GPOToolsCategory]::Create($ADMX.Categories[0], $ADMX.Categories, $ADML)
            [object]::ReferenceEquals($First, $Second) | Should -BeTrue
            [GPOToolsUtility]::CheckCategoryPresence($ADMX.Categories[0].Name, $ADMX.Categories[0].target) | Should -BeTrue
        }
    }

    Describe 'GPOToolsUtility class' {
        BeforeAll {
            $ADMXFile = Get-Item -Path (Join-Path $PolicyDefinitions 'WindowsBackup.admx')
        }

        It 'GetADMLPathFromADMX builds the culture path' {
            [GPOToolsUtility]::GetADMLPathFromADMX($ADMXFile, [cultureinfo]'fr-FR') |
                Should -Be (Join-Path $PolicyDefinitions 'fr-FR' 'WindowsBackup.adml')
        }

        It 'GetADMLPathFromADMX ignores the case of the culture folder and of the ADML file' {
            # Microsoft ships inetres.admx / InetRes.adml, kdc.admx / KDC.adml: they must load on Linux too.
            $Folder = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'CaseStore')
            $Admx = New-Item -ItemType File -Path (Join-Path $Folder 'kdc.admx')
            $Culture = New-Item -ItemType Directory -Path (Join-Path $Folder 'en-us')
            $Adml = New-Item -ItemType File -Path (Join-Path $Culture 'KDC.adml')
            [GPOToolsUtility]::GetADMLPathFromADMX($Admx, [cultureinfo]'en-US') | Should -Be $Adml.FullName
            { [GPOToolsUtility]::GetADMLPathFromADMX($Admx, [cultureinfo]'fr-FR') } | Should -Throw "*doesn't exist*"
        }

        It 'Loads the ADMX whose ADML name differs in case (<File>)' -ForEach @(
            @{ File = 'inetres.admx' }
            @{ File = 'kdc.admx' }
            @{ File = 'messaging.admx' }
        ) {
            [GPOToolsUtility]::RemoveAll()
            [GPOToolsUtility]::InitiateAdmxAdml((Get-Item (Join-Path $PolicyDefinitions $File)), [cultureinfo]'en-US') 3>$null
            @([GPOToolsUtility]::Policies | Where-Object FileName -EQ $File).Count | Should -BeGreaterThan 0
        }

        It 'FindDependancyFile finds <Namespace>' -ForEach @(
            @{ Namespace = 'Microsoft.Policies.Windows'; File = 'Windows.admx' }
            @{ Namespace = 'Microsoft.Policies.Server'; File = 'WindowsServer.admx' }
        ) {
            $Dep = [GPOToolsUtility]::FindDependancyFile($ADMXFile.FullName, $Namespace)
            $Dep | Should -BeOfType ([System.IO.FileInfo])
            $Dep.FullName | Should -Be (Join-Path $PolicyDefinitions $File)
        }

        It 'FindDependancyFile throws for a missing namespace' {
            { [GPOToolsUtility]::FindDependancyFile($ADMXFile.FullName, 'Microsoft.Policies.Backup') } |
                Should -Throw '*No dependancy file found for Microsoft.Policies.Backup*'
        }

        It 'InitiateAdmxAdml loads the folder and RemoveAll empties every store' {
            [GPOToolsUtility]::RemoveAll()
            { [GPOToolsUtility]::InitiateAdmxAdml((Get-Item $PolicyDefinitions), [cultureinfo]'fr-FR') } | Should -Not -Throw
            [GPOToolsUtility]::Policies.Count | Should -BeGreaterThan 0
            [GPOToolsUtility]::Categories.Count | Should -BeGreaterThan 0

            { [GPOToolsUtility]::RemoveAll() } | Should -Not -Throw
            [GPOToolsUtility]::SupportOnTable | Should -BeNullOrEmpty
            [GPOToolsUtility]::Categories | Should -BeNullOrEmpty
            [GPOToolsUtility]::Policies | Should -BeNullOrEmpty
            [GPOToolsUtility]::TargetLoad | Should -BeNullOrEmpty
            [GPOToolsUtility]::CategoryIndex.Count | Should -Be 0
            [GPOToolsUtility]::NamespaceIndex.Count | Should -Be 0
        }
    }
}
