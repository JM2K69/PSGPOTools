#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Where the ADMX files come from: the languages of a PolicyDefinitions folder (the names of its
# folders of .adml files), the language to load, the folders found on this computer and the
# settings remembered between sessions.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        # A PolicyDefinitions folder with the given language folders (and a folder that is not one).
        function New-PolicyDefinitions {
            param([string]$Name, [string[]]$Culture)
            $Path = Join-Path $TestDrive $Name
            $null = New-Item -ItemType Directory -Path $Path -Force
            Set-Content -LiteralPath (Join-Path $Path 'test.admx') -Value '<policyDefinitions/>'
            foreach ($Folder in $Culture) {
                $null = New-Item -ItemType Directory -Path (Join-Path $Path $Folder) -Force
                Set-Content -LiteralPath (Join-Path $Path $Folder 'test.adml') -Value '<policyDefinitionResources/>'
            }
            # Not a language: no .adml file, or not a culture name.
            $null = New-Item -ItemType Directory -Path (Join-Path $Path 'de-DE') -Force
            $null = New-Item -ItemType Directory -Path (Join-Path $Path 'Templates and more') -Force
            Set-Content -LiteralPath (Join-Path $Path 'Templates and more' 'x.adml') -Value ''
            $Path
        }
        $SettingsBefore = $env:PSGPOTOOLS_SETTINGS_PATH
    }
    AfterAll { $env:PSGPOTOOLS_SETTINGS_PATH = $SettingsBefore }

    Describe 'Languages of a PolicyDefinitions folder' {
        It 'Are the names of the folders holding .adml files' {
            $Path = New-PolicyDefinitions 'Languages' 'en-US', 'fr-FR'
            @(Get-PSGPOAdmxCulture -Path $Path) | Should -Be @('en-US', 'fr-FR')
            @(Get-PSGPOAdmxCulture -Path (Join-Path $TestDrive 'Missing')) | Should -BeNullOrEmpty
        }

        It 'Detects <Expected> for a session in "<Current>" with <Available>' -ForEach @(
            @{ Current = 'fr-FR'; Available = @('en-US', 'fr-FR'); Expected = 'fr-FR' }
            @{ Current = 'fr-CA'; Available = @('en-US', 'fr-FR'); Expected = 'fr-FR' }
            @{ Current = 'de-AT'; Available = @('en-US', 'fr-FR'); Expected = 'en-US' }
            @{ Current = ''; Available = @('en-US', 'fr-FR'); Expected = 'en-US' }
            @{ Current = ''; Available = @('fr-FR'); Expected = 'fr-FR' }
            @{ Current = 'ja-JP'; Available = @('es-ES', 'fr-FR'); Expected = $null }
        ) {
            $Path = New-PolicyDefinitions "Detect $Current $($Available -join ' ')" $Available
            $Language = Resolve-PSGPOAdmxCulture -Path $Path -Current ([cultureinfo]::GetCultureInfo($Current))
            $Language.Culture | Should -Be $Expected
            @($Language.Available) | Should -Be $Available
        }

        It 'Takes the language asked for, whatever its case, and refuses a missing one' {
            $Path = New-PolicyDefinitions 'Requested' 'en-US', 'fr-FR'
            (Resolve-PSGPOAdmxCulture -Path $Path -Requested 'FR-fr').Culture | Should -Be 'fr-FR'
            { Resolve-PSGPOAdmxCulture -Path $Path -Requested 'it-IT' } | Should -Throw -ExpectedMessage "*No 'it-IT' language folder*en-US, fr-FR*"
        }

        It 'Refuses a folder without language folders' {
            $Path = New-PolicyDefinitions 'NoLanguage' @()
            { Resolve-PSGPOAdmxCulture -Path $Path } | Should -Throw -ExpectedMessage '*No language folder with .adml files*'
        }

        It 'Asks Initialize-PSGPOAdmx for -UICulture when several languages fit' {
            $Path = New-PolicyDefinitions 'Ambiguous' 'es-ES', 'fr-FR'
            $Before = [cultureinfo]::CurrentUICulture
            try {
                [cultureinfo]::CurrentUICulture = [cultureinfo]::GetCultureInfo('ja-JP')
                { Initialize-PSGPOAdmx -Path $Path } | Should -Throw -ExpectedMessage '*Several languages*es-ES, fr-FR*give -UICulture*'
            } finally {
                [cultureinfo]::CurrentUICulture = $Before
            }
        }
    }

    Describe 'PolicyDefinitions folders and settings of the user' {
        BeforeEach {
            $env:PSGPOTOOLS_SETTINGS_PATH = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        }

        It 'Remembers the settings between sessions, and ignores unreadable ones' {
            (Get-PSGPOUserSetting).Count | Should -Be 0
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = '/srv/PolicyDefinitions'; UICulture = 'fr-FR' }
            Set-PSGPOUserSetting -Values @{ UICulture = 'en-US' }
            $Settings = Get-PSGPOUserSetting
            $Settings.PolicyDefinitions | Should -Be '/srv/PolicyDefinitions'
            $Settings.UICulture | Should -Be 'en-US'

            Set-Content -LiteralPath $env:PSGPOTOOLS_SETTINGS_PATH -Value '{ not json'
            (Get-PSGPOUserSetting).Count | Should -Be 0
        }

        It 'Finds the folder chosen last and the copy next to the module, once each' {
            $Path = New-PolicyDefinitions 'Chosen' 'en-US'
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $Path }
            $Found = @(Get-PSGPOAdmxCandidate)
            $Found | Should -Contain ([System.IO.Path]::GetFullPath($Path))
            $Found | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')))
            ($Found | Select-Object -Unique).Count | Should -Be $Found.Count
        }

        It 'Puts the central store of the domain first, then the folder chosen last' {
            $Store = New-PolicyDefinitions 'CentralStore' 'en-US'
            $Path = New-PolicyDefinitions 'ChosenLast' 'en-US'
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $Path }
            Mock Get-PSGPOAdmxCentralStore { [System.IO.Path]::GetFullPath($Store) }
            $Found = @(Get-PSGPOAdmxCandidate)
            $Found[0] | Should -Be ([System.IO.Path]::GetFullPath($Store))
            $Found[1] | Should -Be ([System.IO.Path]::GetFullPath($Path))
        }

        It 'Finds the central store in the SYSVOL of a Samba domain controller' -Skip:$IsWindows {
            $Sysvol = Join-Path $TestDrive 'sysvol'
            $null = New-PolicyDefinitions (Join-Path 'sysvol' 'hardenbox.labo' 'Policies' 'PolicyDefinitions') 'en-US'
            $null = New-Item -ItemType Directory -Path (Join-Path $Sysvol 'other.labo' 'Policies') -Force
            @(Get-PSGPOAdmxCentralStore -SambaSysvol $Sysvol) | Should -Be @([System.IO.Path]::GetFullPath((Join-Path $Sysvol 'hardenbox.labo' 'Policies' 'PolicyDefinitions')))
        }

        It 'Loads the central store when Initialize-PSGPOAdmx has no -Path' {
            $Store = [System.IO.Path]::GetFullPath((New-PolicyDefinitions 'CentralStoreDefault' 'en-US'))
            Mock Get-PSGPOAdmxCentralStore { $Store }
            # Stops before the files are read: the folder chosen is what is checked.
            Mock Resolve-PSGPOAdmxCulture { throw 'stop' }
            { Initialize-PSGPOAdmx } | Should -Throw 'stop'
            Should -Invoke Resolve-PSGPOAdmxCulture -Times 1 -Exactly -ParameterFilter { $Path -eq $Store }
        }

        It 'Leaves out a folder without .admx file' {
            $Empty = Join-Path $TestDrive 'Empty'
            $null = New-Item -ItemType Directory -Path $Empty -Force
            Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $Empty }
            Get-PSGPOAdmxCandidate | Should -Not -Contain ([System.IO.Path]::GetFullPath($Empty))
        }
    }
}
