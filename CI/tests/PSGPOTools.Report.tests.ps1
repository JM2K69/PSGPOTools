#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# What a reviewer of a GPO sees: its scripts (scripts.ini, psscripts.ini), the settings the console
# does not interpret, and its report (Get-PSGPOReport), as an object, XML and HTML.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        $Startup = '{42B5FAAE-6536-11D2-AE5A-0000F87571E3}{40B6664F-4972-11D1-A7CA-0000F87571E3}'
        function New-TestFiles {
            $Files = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
            $List = [GPOToolsScriptsFile]::Parse($null)
            $List.SetScripts('Startup', @([pscustomobject]@{ CmdLine = 'Install-Agent.cmd'; Parameters = '/quiet' }, [pscustomobject]@{ CmdLine = '\\corp\netlogon\map.cmd'; Parameters = '' }))
            $PowerShell = [GPOToolsScriptsFile]::Parse($null)
            $PowerShell.SetScripts('Startup', @([pscustomobject]@{ CmdLine = 'Set-Baseline.ps1'; Parameters = '' }))
            Set-PSGPOScriptOrder -PowerShellFile $PowerShell -Kind Startup -Order First
            $Files['Machine\Scripts\scripts.ini'] = $List.ToBytes()
            $Files['Machine\Scripts\psscripts.ini'] = $PowerShell.ToBytes()
            $Files['Machine\Scripts\Startup\Install-Agent.cmd'] = [System.Text.Encoding]::UTF8.GetBytes('@echo off')
            $Files
        }
    }

    Describe 'scripts.ini and psscripts.ini' {
        It 'Writes them as the Group Policy editor does: UTF-16 with its byte order mark, numbered from 0' {
            $List = [GPOToolsScriptsFile]::Parse($null)
            $List.SetScripts('Logon', @([pscustomobject]@{ CmdLine = 'map.cmd'; Parameters = 'H:' }, [pscustomobject]@{ CmdLine = 'printers.vbs'; Parameters = '' }))
            $Bytes = $List.ToBytes()
            $Bytes[0..1] | Should -Be @(0xFF, 0xFE)
            [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) | Should -Be "`r`n[Logon]`r`n0CmdLine=map.cmd`r`n0Parameters=H:`r`n1CmdLine=printers.vbs`r`n1Parameters=`r`n"
        }

        It 'Reads them in their order, and keeps the keys it does not know' {
            $Text = "[Startup]`r`n1CmdLine=second.cmd`r`n1Parameters=`r`n0CmdLine=first.cmd`r`n0Parameters=-a`r`nComment=kept`r`n[Other]`r`nKey=Value`r`n"
            $List = [GPOToolsScriptsFile]::Parse([System.Text.Encoding]::UTF8.GetBytes($Text))
            @($List.GetScripts('Startup').CmdLine) | Should -Be @('first.cmd', 'second.cmd')
            $List.GetScripts('Startup')[0].Parameters | Should -Be '-a'
            $List.SetScripts('Startup', @($List.GetScripts('Startup')[1]))
            $Written = [System.Text.Encoding]::Unicode.GetString($List.ToBytes(), 2, $List.ToBytes().Length - 2)
            $Written | Should -BeLike "*Comment=kept*0CmdLine=second.cmd*"
            $Written | Should -BeLike '*`[Other`]*Key=Value*'
            $List.SetScripts('Startup', @())
            [System.Text.Encoding]::Unicode.GetString($List.ToBytes(), 2, $List.ToBytes().Length - 2) | Should -Not -BeLike '*CmdLine*'
        }

        It 'Says whether the PowerShell scripts run first or last, and refuses a script of two lines' {
            $PowerShell = [GPOToolsScriptsFile]::Parse($null)
            Get-PSGPOScriptOrder -PowerShellFile $PowerShell -Kind Shutdown | Should -BeNullOrEmpty
            Set-PSGPOScriptOrder -PowerShellFile $PowerShell -Kind Shutdown -Order Last
            $PowerShell.GetConfig('EndExecutePSFirst') | Should -Be 'false'
            Get-PSGPOScriptOrder -PowerShellFile $PowerShell -Kind Shutdown | Should -Be 'Last'
            Set-PSGPOScriptOrder -PowerShellFile $PowerShell -Kind Shutdown -Order ''
            $PowerShell.IsEmpty() | Should -BeTrue
            { $PowerShell.SetScripts('Startup', @([pscustomobject]@{ CmdLine = "a.cmd`r`nb.cmd"; Parameters = '' })) } | Should -Throw '*one line*'
        }

        It 'Finds the file of a script in the folder of its kind, not one outside the GPO' {
            Get-PSGPOScriptGpoPath -Scope Machine -Kind Startup -CmdLine 'Set-Baseline.ps1' | Should -Be 'Machine\Scripts\Startup\Set-Baseline.ps1'
            Get-PSGPOScriptGpoPath -Scope User -Kind Logon -CmdLine 'tools/map.cmd' | Should -Be 'User\Scripts\Logon\tools\map.cmd'
            foreach ($Outside in '\\corp\netlogon\map.cmd', 'C:\Scripts\a.cmd', '%SystemRoot%\a.cmd', '..\..\Registry.pol') {
                Get-PSGPOScriptGpoPath -Scope Machine -Kind Startup -CmdLine $Outside | Should -BeNullOrEmpty -Because $Outside
            }
        }
    }

    Describe 'The scripts in the Settings tab' {
        It 'Lists each script with its file in the GPO, the order of the PowerShell scripts, and the files no script runs' {
            $Files = New-TestFiles
            $Files['Machine\Scripts\Startup\old.cmd'] = [byte[]](1, 2, 3)
            $Rows = @(Get-PSGPOConfiguredScript -Files $Files -Scope Machine)
            @($Rows | ForEach-Object { "$($_.Path) | $($_.Name) | $($_.State)" }) | Should -Be @(
                'Policies > Windows Settings > Scripts (Startup/Shutdown) > Startup | Install-Agent.cmd | Script'
                'Policies > Windows Settings > Scripts (Startup/Shutdown) > Startup | \\corp\netlogon\map.cmd | Script'
                'Policies > Windows Settings > Scripts (Startup/Shutdown) > Startup | Set-Baseline.ps1 | PowerShell script'
                'Policies > Windows Settings > Scripts (Startup/Shutdown) > Startup | Windows PowerShell scripts | Run first'
                'Policies > Windows Settings > Scripts (Startup/Shutdown) | Machine\Scripts\Startup\old.cmd | Not run')
            $Rows[0].Options -split '\r?\n' | Should -Be @('Order: 1', 'Parameters: /quiet', 'In the GPO: Machine\Scripts\Startup\Install-Agent.cmd', '9 bytes', "SHA-256 $((Get-PSGPOFileHash -Bytes $Files['Machine\Scripts\Startup\Install-Agent.cmd']).Substring(0, 12))")
            $Rows[1].Options | Should -BeLike '*Outside the GPO: the computers run it from there'
            $Rows[2].Options | Should -BeLike '*Not in the GPO: Machine\Scripts\Startup\Set-Baseline.ps1'
            $Rows[2].IsExtra | Should -BeTrue
        }

        It 'Shows a change of the file a script runs when two versions are compared' {
            $Before = New-TestFiles
            $After = New-TestFiles
            $After['Machine\Scripts\Startup\Install-Agent.cmd'] = [System.Text.Encoding]::UTF8.GetBytes('@echo off & net user evil /add')
            $Property = @{ DisplayName = 'T'; Status = 'Enabled'; SecurityFiltering = @(); DeniedTo = @(); Links = @(); MachineExtensionNames = "[$Startup]" }
            $Changes = @(Compare-PSGPOSettingReport -Reference @(Get-PSGPOSettingReport -Files $Before -Property $Property) -Difference @(Get-PSGPOSettingReport -Files $After -Property $Property))
            $Changes.Count | Should -Be 1
            $Changes[0].Change | Should -Be 'Changed'
            $Changes[0].Name | Should -Be 'Install-Agent.cmd'
            $Changes[0].After | Should -BeLike '*30 bytes*'
        }
    }

    Describe 'What the console does not interpret' {
        It 'Lists the extensions whose settings it does not read, and the files no reader reads, but not those that apply nothing' {
            $Files = New-TestFiles
            $Files['User\Documents & Settings\fdeploy1.ini'] = [byte[]](65, 66)
            $Files['GPO.cmt'] = [byte[]](65)
            $Files['Adm\system.adm'] = [byte[]](65)
            $Files['Machine\comment.cmtx'] = [byte[]](65)
            $Settings = Get-PSGPOFolderSetting -Files $Files -MachineExtensionNames "[$Startup][{C6DC5466-785A-11D2-84D0-00C04FB169F7}{942A8E4F-A261-11D1-A760-00C04FB9603F}]" `
                -UserExtensionNames '[{00000000-0000-0000-0000-000000000000}{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}][{5794DAFD-BE60-433f-88A2-1A31939AC01F}{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}][{25537BA6-77A8-11D2-9B6C-0000F8080861}{88E729D6-BDC1-11D1-BD2A-00C04FB9603F}][{12345678-1234-1234-1234-123456789ABC}{00000000-0000-0000-0000-000000000001}]'
            @($Settings.Uninterpreted | ForEach-Object { "$($_.Path) | $($_.Name) | $($_.State)" }) | Should -Be @(
                'Client-side extensions | Software Installation | Computer'
                'Client-side extensions | Folder Redirection | User'
                'Client-side extensions | {12345678-1234-1234-1234-123456789ABC} | User'
                'Files of the GPO | User\Documents & Settings\fdeploy1.ini | 2 bytes')
            ($Settings.Uninterpreted | Where-Object Name -EQ 'Software Installation').Options | Should -Be ("Its settings are in files of the GPO that the console does not read.$([Environment]::NewLine){C6DC5466-785A-11D2-84D0-00C04FB169F7}")
            $Settings.Known.Contains('Machine\Scripts\Startup\Install-Agent.cmd') | Should -BeTrue
            @($Settings.Machine).Count | Should -Be 4 -Because 'the scripts are read'
        }

        It 'Says it in the details of a GPO, without reading its files' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.Gpos[0]
            $Gpo.UserExtensionNames = '[{25537BA6-77A8-11D2-9B6C-0000F8080861}{88E729D6-BDC1-11D1-BD2A-00C04FB9603F}]'
            ((Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo).Properties | Where-Object Key -EQ 'Not interpreted').Value |
                Should -Be 'Folder Redirection: the computers apply their settings, the console does not show them (Settings tab)'
            $Gpo.UserExtensionNames = ''
            (Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo).Properties.Key | Should -Not -Contain 'Not interpreted'
        }

        It 'Says it before the approval of Approve-PSGPO, in a warning and in its confirmation' {
            $Content = [pscustomobject]@{
                Attributes = [ordered]@{ gPCMachineExtensionNames = ''; gPCUserExtensionNames = '[{25537BA6-77A8-11D2-9B6C-0000F8080861}{88E729D6-BDC1-11D1-BD2A-00C04FB9603F}]' }
                Files = [ordered]@{ 'User\Documents & Settings\fdeploy1.ini' = [byte[]](1) }
            }
            @(Get-PSGPOReviewUninterpreted -Content $Content).Name | Should -Be @('Folder Redirection', 'User\Documents & Settings\fdeploy1.ini')
        }
    }

    Describe 'The scripts written to a GPO' {
        It 'Writes the lists and the file of a script with one increase of the version, and declares their extension' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.IsReadOnly = $false
            $Gpo = $Directory.Gpos[0]
            $Version = $Gpo.Version
            $Directory.WriteScriptFiles($Gpo, 'Machine', (New-TestFiles))
            $Gpo.GetComputerVersion() | Should -Be (($Version -band 0xFFFF) + 1)
            $Gpo.MachineExtensionNames.Contains("[$Startup]") | Should -BeTrue
            [GPOToolsScriptsFile]::Parse($Directory.ReadGpoFile($Gpo, 'Machine\Scripts\psscripts.ini')).GetScripts('Startup').CmdLine | Should -Be 'Set-Baseline.ps1'
            { $Directory.WriteScriptFiles($Gpo, 'Machine', [ordered]@{ 'Machine\Registry.pol' = [byte[]](1) }) } | Should -Throw '*Not a file of the scripts*'
            { $Directory.WriteScriptFiles($Gpo, 'User', [ordered]@{ 'User\Scripts\..\..\GPT.INI' = [byte[]](1) }) } | Should -Throw '*Not a path of a file in a GPO folder*'
        }

        It 'Reads the text of a script, not a program' {
            ConvertFrom-PSGPOScriptContent -Bytes ([System.Text.Encoding]::UTF8.GetBytes('Write-Host 1')) | Should -Be 'Write-Host 1'
            ConvertFrom-PSGPOScriptContent -Bytes ([byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes('echo')) | Should -Be 'echo'
            ConvertFrom-PSGPOScriptContent -Bytes ([byte[]](0x4D, 0x5A, 0x90, 0)) | Should -BeNullOrEmpty
        }
    }

    Describe 'A GPO read under -WhatIf' -Skip:$IsWindows {
        It 'Copies its folder to read it: Approve-PSGPO -WhatIf reads what it would approve' {
            . (Join-Path $PSScriptRoot 'Fixtures' 'LdapDirectory.ps1')
            $Directory = New-TestLdapDirectory
            $Gpo = $Directory.FindGpo('Default Domain Policy')
            Mock Invoke-PSGPOSmbClient {
                $Folder = [regex]::Match($Command, 'lcd "([^"]+)"').Groups[1].Value
                if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "lcd: $Folder does not exist" }
                [System.IO.File]::WriteAllText((Join-Path $Folder 'GPT.INI'), '[General]')
                , @()
            }
            $WhatIfPreference = $true
            try { $Files = Read-PSGPOSysvolFolder -Directory $Directory -Gpo $Gpo } finally { $WhatIfPreference = $false }
            @($Files.Keys) | Should -Be @('GPT.INI')
        }
    }

    Describe 'Get-PSGPOReport' {
        BeforeAll {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.IsReadOnly = $false
            $Gpo = $Directory.Gpos | Where-Object { $Directory.GetLinksOf($_).Count } | Select-Object -First 1
            $Directory.WriteScriptFiles($Gpo, 'Machine', (New-TestFiles))
            $Directory.GpoFiles["$($Gpo.Id)\User\Documents & Settings\fdeploy1.ini"] = [byte[]](65)
        }

        It 'Gives the report of a GPO as an object: its details, links, extensions, settings and what it does not interpret' {
            $Report = Get-PSGPOReport -Directory $Directory -Name $Gpo.DisplayName
            $Report.PSObject.TypeNames | Should -Contain 'PSGPOTools.GpoReport'
            $Report.Id | Should -Be $Gpo.Id
            @($Report.Links).Count | Should -BeGreaterThan 0
            ($Report.Extensions | Where-Object Name -EQ 'Scripts').Interpreted | Should -BeTrue
            @($Report.Computer.Name) | Should -Contain 'Install-Agent.cmd'
            @($Report.NotInterpreted.Name) | Should -Be @('User\Documents & Settings\fdeploy1.ini')
        }

        It 'Writes it as XML, in English, and as an HTML page in the language of the interface' {
            $Xml = [xml](Get-PSGPOReport -Directory $Directory -Name $Gpo.DisplayName -ReportType Xml)
            $Xml.DocumentElement.NamespaceURI | Should -Be 'https://jm2k69.github.io/PSGPOTools/schemas/gpo-report/1'
            $Xml.GpoReports.Gpo.name | Should -Be $Gpo.DisplayName
            @($Xml.GpoReports.Gpo.Computer.Setting | ForEach-Object name) | Should -Contain 'Install-Agent.cmd'
            $Xml.GpoReports.Gpo.NotInterpreted.Setting.name | Should -Be 'User\Documents & Settings\fdeploy1.ini'

            $File = Join-Path $TestDrive 'report.html'
            $Written = Get-PSGPOReport -Directory $Directory -Name $Gpo.DisplayName -ReportType Html -Path $File -Language fr-FR
            $Written.FullName | Should -Be $File
            $Html = Get-Content -LiteralPath $File -Raw -Encoding utf8
            $Html | Should -BeLike '<!DOCTYPE html>*<html lang="fr-FR">*'
            $Html | Should -BeLike "*$([System.Net.WebUtility]::HtmlEncode($Gpo.DisplayName))*"
            $Html | Should -BeLike '*Scripts (démarrage/arrêt)*Install-Agent.cmd*'
            $Html | Should -BeLike "*Paramètres que la console n*interprète pas (1)*fdeploy1.ini*"
            Get-PSGPOText 'Settings' | Should -Be 'Settings' -Because 'the language of the session comes back'
        }

        It 'Refuses -Path for objects, and says which GPO it does not know' {
            { Get-PSGPOReport -Directory $Directory -Name $Gpo.DisplayName -Path (Join-Path $TestDrive 'x.xml') } | Should -Throw '*-ReportType Xml or Html*'
            Get-PSGPOReport -Directory $Directory -Name 'No such GPO' -ErrorVariable Problem -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            "$Problem" | Should -BeLike "*No GPO named 'No such GPO'*"
        }
    }
}
