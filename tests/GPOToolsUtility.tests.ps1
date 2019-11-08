using module '..\PSGPOTool\Classes\GPOToolsUtility.psm1'

$TestPath = Split-Path $MyInvocation.MyCommand.Path

Push-Location -Path $TestPath
Set-Location -Path $TestPath

#Describe "Test AdmxSupportedOn class"
#Describe "Test AdmxNamespace class"
#Describe "Test AdmxCategory class"
#Describe "Test AdmxPolicy class"

Describe "Test GpoToolsAdmx class" {
    Context "Test constructor method for Admx WindowsBackup" {
        $ADMXPath = (Get-Item -Path "..\sources\PolicyDefinitions\WindowsBackup.admx").FullName
        $ADMX = [GPOToolsAdmx]::New($ADMXPath)
        $UsingTab = @(
            [pscustomobject]@{
                prefix = 'backup'
                namespace = 'Microsoft.Policies.Backup'
            },
            [pscustomobject]@{
                prefix = 'windows'
                namespace = 'Microsoft.Policies.Windows'
            },
            [pscustomobject]@{
                prefix = 'server'
                namespace = 'Microsoft.Policies.Server'
            }
        )
        $CatTab = @(
            [PscustomObject]@{
                Name = 'Backup'
                DisplayName = 'Backup'
                ParentCategoryName = 'windows:WindowsComponents'
            },
            [PscustomObject]@{
                Name = 'BackupServer'
                DisplayName = 'BackupServer'
                ParentCategoryName = 'backup:Backup'
            }
        )
        It "Test object type"{
            $ADMX -is [GPOToolsAdmx] | Should be $true
        }

        It "Test FilePath property"{
            $ADMX.FilePath -is [string] | Should be $true
            $ADMX.FilePath | Should be $ADMXPath
        }

        It "Test BaseName Property"{
            $ADMX.BaseName -is [string] | Should be $true
            $ADMX.BaseName | Should be "WindowsBackup"
        }

        It "Test Target Property" {
            $ADMX.Target -is [AdmxNamespace] | Should be $true
            $ADMX.Target.prefix | Should be 'windowsbackup'
            $ADMX.Target.Namespace | Should be 'Microsoft.Policies.WindowsBackup'
        }

        It "Test Using Property" {
            $ADMX.Using -is [System.Collections.ArrayList] | Should be $true
            $ADMX.Using.count | Should be $UsingTab.Count
            for ($i = 0 ; $i -lt $ADMX.Using.count; $i++){
                $ADMX.Using[$i] -is [AdmxNamespace] | should be $true
                $ADMX.Using[$i].prefix | Should be $UsingTab[$i].prefix
                $ADMX.Using[$i].namespace | Should be $UsingTab[$i].namespace
            }
        }

        It "Test SupportedOnDefinition" {
            $ADMX.SupportedOnDefinition -is [System.Collections.ArrayList] | Should be $true
            $ADMX.SupportedOnDefinition.count | Should be 0
        }

        It "Test Category" {
            $ADMX.Categories -is [System.Collections.ArrayList] | Should be $true
            $ADMX.Categories.count | Should be 2
            for ($i = 0 ; $i -lt $ADMX.Categories.count; $i++){
                $ADMX.Categories[$i].Name | Should be $CatTab[$i].Name
                $ADMX.Categories[$i].DisplayName | Should be $CatTab[$i].DisplayName
                $ADMX.Categories[$i].ParentCategoryName | Should be $CatTab[$i].ParentCategoryName
                #$ADMX.Categories[$i].ExplainText
            }
        }

        #It "Test policy"
    }

    Context "Test constructor method for Admx WindowsUpdate" {
        $ADMXPath = (Get-Item -Path "..\sources\PolicyDefinitions\WindowsUpdate.admx").FullName
        $ADMX = [GPOToolsAdmx]::New($ADMXPath)
        $UsingTab = @(
            [pscustomobject]@{
                prefix = 'windows'
                namespace = 'Microsoft.Policies.Windows'
            }
        )
        $TabSupportedOn = @(
            [pscustomobject]@{
                Name = 'WU_SUPPORTED_Windows7ToXPSP2'
                DisplayName = 'WU_SUPPORTED_Windows7ToXPSP2'
            },
            [pscustomobject]@{
                Name = 'WU_SUPPORTED_Windows7_To_Win2kSP3_Or_XPSP1'
                DisplayName = 'WU_SUPPORTED_Windows7_To_Win2kSP3_Or_XPSP1'
            },
            [pscustomobject]@{
                Name = 'WU_SUPPORTED_Win2kSP3_Or_XPSP1_NoWinRT'
                DisplayName = 'WU_SUPPORTED_Win2kSP3_Or_XPSP1_NoWinRT'
            },
            [pscustomobject]@{
                Name = 'WU_SUPPORTED_WindowsXPSP1_NoWinRT'
                DisplayName = 'WU_SUPPORTED_WindowsXPSP1_NoWinRT'
            },
            [pscustomobject]@{
                Name = 'WU_SUPPORTED_Win2kSP3_Or_XPSP1_Through_Win81_or_Server2012R2'
                DisplayName = 'WU_SUPPORTED_Win2kSP3_Or_XPSP1_Through_Win81_or_Server2012R2'
            },
            [pscustomobject]@{
                Name = 'WU_SUPPORTED_WindowsVista_Through_Win81_or_Server2012R2'
                DisplayName = 'WU_SUPPORTED_WindowsVista_Through_Win81_or_Server2012R2'
            }
        )
        $CatTab = @(
            [Pscustomobject]@{
                Name = 'WindowsUpdateCat'
                DisplayName = 'WindowsUpdateCat'
                ParentCategoryName = 'windows:WindowsComponents'
            },
            [Pscustomobject]@{
                Name = 'DeferUpdateCat'
                DisplayName = 'DeferUpdateCat'
                ParentCategoryName = 'WindowsUpdateCat'
            }
        )
        It "Test object type"{
            $ADMX -is [GPOToolsAdmx] | Should be $true
        }

        It "Test FilePath property"{
            $ADMX.FilePath -is [string] | Should be $true
            $ADMX.FilePath | Should be $ADMXPath
        }

        It "Test BaseName Property"{
            $ADMX.BaseName -is [string] | Should be $true
            $ADMX.BaseName | Should be "WindowsUpdate"
        }

        It "Test Target Property" {
            $ADMX.Target -is [AdmxNamespace] | Should be $true
            $ADMX.Target.prefix | Should be 'wuau'
            $ADMX.Target.Namespace | Should be 'Microsoft.Policies.WindowsUpdate'
        }

        It "Test Using Property" {
            $ADMX.Using -is [System.Collections.ArrayList] | Should be $true
            $ADMX.Using.count | Should be $UsingTab.Count
            for ($i = 0 ; $i -lt $ADMX.Using.count; $i++){
                $ADMX.Using[$i] -is [AdmxNamespace] | should be $true
                $ADMX.Using[$i].prefix | Should be $UsingTab[$i].prefix
                $ADMX.Using[$i].namespace | Should be $UsingTab[$i].namespace
            }
        }

        It "Test SupportedOnDefinition"{
            $ADMX.SupportedOnDefinition -is [System.Collections.ArrayList] | Should be $true
            $ADMX.SupportedOnDefinition.count | Should be $TabSupportedOn.count
            for ($i = 0 ; $i -lt $ADMX.SupportedOnDefinition.count; $i++){
                $ADMX.SupportedOnDefinition[$i].Name | Should be $TabSupportedOn[$i].Name
                $ADMX.SupportedOnDefinition[$i].DisplayName | Should be $TabSupportedOn[$i].DisplayName
            }
        }

        It "Test Category" {
            $ADMX.Categories -is [System.Collections.ArrayList] | Should be $true
            $ADMX.Categories.count | Should be $CatTab.count
            for ($i = 0 ; $i -lt $ADMX.Categories.count; $i++){
                $ADMX.Categories[$i].Name | Should be $CatTab[$i].Name
                $ADMX.Categories[$i].DisplayName | Should be $CatTab[$i].DisplayName
                $ADMX.Categories[$i].ParentCategoryName | Should be $CatTab[$i].ParentCategoryName
                #$ADMX.Categories[$i].ExplainText
            }
        }

        #It "Test policy"
    }
}

Describe "Test GPOToolsADML class"{
    Context "Test constructor method"{
        $UICulture = [cultureinfo]::CurrentCulture
        $ADMLFile = Get-Item -Path "..\sources\PolicyDefinitions\$UICulture\WindowsBackup.adml"
        $ADMLPath = $ADMLFile.FullName
        $StringTableTest = @{
            # Warning to encoding script for special caractere
            AllowOnlySystemBackup = 'Autoriser uniquement la sauvegarde du syst�me'
            DisallowLocallyAttachedStorageAsBackupTarget = 'Ne pas autoriser un p�riph�rique de stockage connect� localement � faire office de cible de sauvegarde'
            Backup = 'Sauvegarde'
            windowscomponents = 'Composants Windows'
        }

        $ADML = [GPOToolsAdml]::new($ADMLPath)
        It "Test GPOToolsADML type"{
            $ADML -is [GPOToolsADML] | Should Be $true
        }

        It "Test GPOToolsADML properties"{
            $ADML.FilePath | Should Be $ADMLPath
            $ADML.BaseName | Should Be $ADMLFile.BaseName
        }

        It 'Test GPOToolsADML StringTable'{
            $StringTableTest.GetEnumerator() | Foreach-Object {
                $ADML.StringTable.ContainsKey($_.Key) | Should Be $true
                $ADML.StringTable."$($_.Key)" | Should Be $_.Value
            }
        }
    }
}

Describe "Test GPOToolsSupportedOn class" {
    Context "Test method constructor" {
        $ADMXFile = Get-Item -Path "..\sources\PolicyDefinitions\Windows.admx"
        $ADMLFile = Get-Item -Path "..\sources\PolicyDefinitions\$([cultureinfo]::CurrentUICulture)\Windows.adml"
        $ADMX = [GpoToolsAdmx]::new($ADMXFile)
        $ADML = [GpoToolsAdml]::new($ADMLFile)
        $Support = [GPOToolsSupportedOn]::new($ADMX.SupportedOnDefinition[0],$ADML)
        $LoadAdm = [GPOToolsSupportedOn]::LoadAdmxAdml($ADMX,$ADML)
        $TestSup = @(
            [PScustomObject]@{
                Name = 'SUPPORTED_AllowWebPrinting'
                DisplayNamePattern = "Windows\s2000\sou\sversion\sult�rieure,\sex�cutant\sIIS.\sNon\spris\sen\scharge\spar\sWindows\sServer\s2003"
            },
            [PScustomObject]@{
                Name = 'SUPPORTED_WindowsServer_And_XPproTo7'
                DisplayNamePattern = "Windows\sServer\s2003\set\sles\sversions\sde\sWindows\s�\spartir\sde\sWindows\sXP\sProfessionnel\sjusqu'�\sWindows\s7\."
            }
        )


        It "Test constructor method"{
            $Support -is [GPOToolsSupportedOn] | Should be $true
            $Support.Name | Should be 'SUPPORTED_AllowWebPrinting'
            $Support.DisplayName -match "Windows\s2000\sou\sversion\sult�rieure,\sex�cutant\sIIS.\sNon\spris\sen\scharge\spar\sWindows\sServer\s2003" | should be $true
        }

        It "Test LoadAdmxAdml static method" {

        }
    }
}

Describe "Test GPOToolsUtility class" {
    Context "Test static method" {
        $ADMXFile = Get-Item -Path "..\sources\PolicyDefinitions\WindowsBackup.admx"
        $ADMXPath = $ADMXFile.FullName
        $ParentPath = Split-Path -Path $ADMXPath
        $Dep1 = [GPOToolsUtility]::FindDependancyFile($ADMXPath,'Microsoft.Policies.Windows')
        #$Dep2 = [GPOToolsUtility]::FindDependancyFile($ADMXPath,'Microsoft.Policies.Backup') # Dependancy not found
        $Dep2 = [GPOToolsUtility]::FindDependancyFile($ADMXPath,'Microsoft.Policies.Server')

        $AdmlPath = [GPOToolsUtility]::GetADMLPathFromADMX($ADMXFile,[cultureinfo]::CurrentCulture)
        It "Test GetADMLPathFromADMX"{
            $AdmlPath | Should be "$ParentPath\$([cultureinfo]::CurrentCulture)\WindowsBackup.adml"
        }

        It "Test FindDependancyFile"{
            $Dep1 -is [System.IO.FileInfo] | Should Be $True
            $Dep1.FullName | Should Be "$ParentPath\Windows.admx"

            $Dep2 -is [System.IO.FileInfo] | Should Be $True
            $Dep2.FullName | Should Be "$ParentPath\WindowsServer.admx"
        }

        It "Test RemoveAll"{
            [GPOToolsUtility]::RemoveAll()
            $null -eq [GPOToolsUtility]::SupportOnTable | Should Be $true
            $null -eq [GPOToolsUtility]::Categories | Should Be $true
            $null -eq [GPOToolsUtility]::Policies | Should Be $true
            $null -eq [GPOToolsUtility]::TargetLoad | Should Be $true
        }

        [GpotoolsUtility]::InitiateAdmxAdml($ADMXFile,[cultureinfo]::CurrentCulture)
    }
}