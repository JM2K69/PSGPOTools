#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The add-ons of HGPM (PSGPOAddOn.ps1, Register-PSGPOAddOn): modules HGPM.<name> tagged
# HGPMAddOn, found and loaded once in a process, refused for another contract, left out when they
# fail; their hooks (the image of the windows, the HTML reports), each called in a try, and their
# version beside that of HGPM. The add-ons of the tests are modules written in TestDrive, first in
# PSModulePath.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $script:Core = "$((Get-PSGPOModuleVersion).Version)"
        $script:Logo = Join-Path (Get-Module HGPM).ModuleBase 'Resources' 'hgpm.png'
        $script:SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
        # An add-on: a module HGPM.<Name> in $Root, its manifest tagged HGPMAddOn (or not), its code.
        function New-TestAddOn {
            param([string]$Root, [string]$Name, [string]$Version, [string]$Code, [switch]$Untagged)
            $folder = Join-Path $Root $Name $Version
            $null = New-Item -ItemType Directory -Path $folder -Force
            $tags = if ($Untagged) { "'Other'" } else { "'HGPMAddOn'" }
            Set-Content -LiteralPath (Join-Path $folder "$Name.psd1") -Value @"
@{
    RootModule = '$Name.psm1'
    ModuleVersion = '$Version'
    GUID = '$([guid]::NewGuid())'
    RequiredModules = @(@{ ModuleName = 'HGPM'; RequiredVersion = '$((Import-PowerShellDataFile (Join-Path (Get-Module HGPM).ModuleBase 'HGPM.psd1')).ModuleVersion)' })
    FunctionsToExport = '*'
    PrivateData = @{ PSData = @{ Tags = @($tags) } }
}
"@
            Set-Content -LiteralPath (Join-Path $folder "$Name.psm1") -Value $Code
            $folder
        }

        $script:Modules = Join-Path $TestDrive 'Modules'
        # Its version from its manifest: the module being imported has none yet.
        $script:AddOnFolder = New-TestAddOn -Root $script:Modules -Name 'HGPM.TestHooks' -Version '1.2.3.4' -Code @'
function Get-TestHooksValue { 'hooks' }
Register-PSGPOAddOn -Name 'HGPM.TestHooks' -Contract 1 -Edition 'Test Edition' -WindowLogo {
    param($Kind)
    Join-Path $PSScriptRoot "$Kind.png"
} -ReportHtml {
    param($Html)
    $Html.Replace('<!-- hgpm:head -->', '<style>h2 { color: #123abc; }</style>').Replace('<!-- hgpm:body-start -->', '<p class="test-start">Contoso</p>').Replace('<!-- hgpm:body-end -->', '<p class="test-end">Confidential</p>')
} -ReportFormat @{
    Name = 'Test'; Extension = '.TST'; TypeName = @{ 'en-US' = 'Test file'; 'fr-FR' = 'Fichier de test' }
    Save = { param($Html, $Path) [System.IO.File]::WriteAllText($Path, "TEST`n$Html") }
}
'@
        Copy-Item -LiteralPath $script:Logo -Destination (Join-Path $script:AddOnFolder 'Icon.png')
        Copy-Item -LiteralPath $script:Logo -Destination (Join-Path $script:AddOnFolder 'Header.png')
        $null = New-TestAddOn -Root $script:Modules -Name 'HGPM.TestOld' -Version '0.1.0' -Code @'
function Get-TestOldValue { 'old' }
Register-PSGPOAddOn -Name 'HGPM.TestOld' -Contract 99 -Edition 'Old'
'@
        $null = New-TestAddOn -Root $script:Modules -Name 'HGPM.TestBroken' -Version '1.0.0' -Code @'
function Get-TestBrokenValue { 'broken' }
throw 'The broken add-on of the tests.'
'@
        $null = New-TestAddOn -Root $script:Modules -Name 'HGPM.TestSilent' -Version '1.0.0' -Code 'function Get-TestSilentValue { ''silent'' }'
        $null = New-TestAddOn -Root $script:Modules -Name 'HGPM.TestUntagged' -Version '1.0.0' -Untagged -Code 'function Get-TestUntaggedValue { ''untagged'' }'

        $script:PathBefore = $env:PSModulePath
        $script:NoAddOnBefore = $env:PSGPOTOOLS_NO_ADDON
        # The add-ons of this process, as at the import of the module.
        function Reset-TestAddOn {
            Get-Module 'HGPM.Test*' | Remove-Module -Force
            $script:PSGPOAddOn = @{ Searched = $false; Found = @(); Loaded = $false; Items = [System.Collections.Generic.List[object]]::new(); Logo = @{} }
        }
        # A report of the sample directory, in HTML.
        function Get-TestReportHtml {
            $directory = Import-PSGPODirectory -Path $script:SamplePath
            ConvertTo-PSGPOReportHtml -Report (Get-PSGPOReportData -Directory $directory -Gpo @($directory.Gpos)[0])
        }
    }
    AfterAll {
        $env:PSModulePath = $script:PathBefore
        $env:PSGPOTOOLS_NO_ADDON = $script:NoAddOnBefore
        Reset-TestAddOn
    }

    Describe 'Add-ons found and loaded' {
        BeforeEach {
            Reset-TestAddOn
            $env:PSModulePath = $script:Modules + [System.IO.Path]::PathSeparator + $script:PathBefore
            $env:PSGPOTOOLS_NO_ADDON = $null
        }

        It 'Finds the modules HGPM.* tagged HGPMAddOn, the newest of each, and none with PSGPOTOOLS_NO_ADDON=1' {
            @(Find-PSGPOAddOn | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('HGPM.TestBroken', 'HGPM.TestHooks', 'HGPM.TestOld', 'HGPM.TestSilent')
            Reset-TestAddOn
            $env:PSGPOTOOLS_NO_ADDON = '1'
            @(Find-PSGPOAddOn) | Should -BeNullOrEmpty
            @(Get-PSGPOAddOnState) | Should -BeNullOrEmpty
        }

        It 'Loads an add-on once, its version from its manifest; refuses another contract, says why one fails' {
            $AddOns = @(Get-PSGPOAddOnState)
            $Hooks = $AddOns | Where-Object Name -EQ 'HGPM.TestHooks'
            $Hooks.State | Should -Be 'Loaded'
            $Hooks.Edition | Should -Be 'Test Edition'
            $Hooks.Version | Should -Be ([version]'1.2.3.4') -Because 'read in its manifest, as the module being imported has no version yet'
            $Hooks.Contract | Should -Be 1
            $Hooks.Path | Should -Be $script:AddOnFolder
            Get-TestHooksValue | Should -Be 'hooks' -Because 'the add-on is imported in the session'
            $Old = $AddOns | Where-Object Name -EQ 'HGPM.TestOld'
            $Old.State | Should -Be 'Refused'
            $Old.Version | Should -Be ([version]'0.1.0')
            $Old.Reason | Should -BeLike "*built for the contract 99*HGPM $script:Core gives the contract 1*"
            ($AddOns | Where-Object Name -EQ 'HGPM.TestBroken').State | Should -Be 'Failed'
            ($AddOns | Where-Object Name -EQ 'HGPM.TestBroken').Reason | Should -BeLike '*broken add-on of the tests*'
            ($AddOns | Where-Object Name -EQ 'HGPM.TestSilent').Reason | Should -BeLike '*did not register itself*'
            @($AddOns | Where-Object Name -EQ 'HGPM.TestUntagged') | Should -BeNullOrEmpty
            # Once: the second call imports nothing.
            Mock Import-Module { }
            $null = Get-PSGPOAddOnState
            Should -Invoke Import-Module -Times 0 -Exactly
            @(Get-PSGPOLoadedAddOn).Name | Should -Be @('HGPM.TestHooks')
        }

        It 'Shows the version of HGPM with those of the add-ons loaded, never the Gallery' {
            Get-PSGPOEditionVersion | Should -Be "$script:Core + Test Edition 1.2.3.4"
            Mock Get-PSGPOLatestGalleryVersion { [semver]'99.0.0' }
            $Item = Get-PSGPOVersionStatusItem
            $Item.Text | Should -Be "HGPM $script:Core + Test Edition 1.2.3.4"
            $Item.ToolTip | Should -BeLike '*updated with the package of Test Edition*'
            Should -Invoke Get-PSGPOLatestGalleryVersion -Times 0 -Exactly
        }

        It 'Says the add-ons installed at the import, without the Gallery' {
            Mock Get-PSGPOLatestGalleryVersion { [semver]'99.0.0' }
            Mock Test-PSGPOUpdateCheckSkipped { $false }
            $Banner = Write-PSGPOImportBanner 6>&1 | Out-String
            # Installed, before they are loaded: each one found.
            $Banner | Should -BeLike "*HGPM $script:Core + TestBroken 1.0.0 + TestHooks 1.2.3.4 + TestOld 0.1.0 + TestSilent 1.0.0*"
            $Banner | Should -Not -BeLike '*available on the PowerShell Gallery*'
            Should -Invoke Get-PSGPOLatestGalleryVersion -Times 0 -Exactly
        }

        It 'Refuses Register-PSGPOAddOn for another contract, or another name than HGPM.<name>' {
            { Register-PSGPOAddOn -Name 'HGPM.Direct' -Version '1.0' -Contract 2 } | Should -Throw '*built for the contract 2 of the add-on points*'
            ($script:PSGPOAddOn.Items | Where-Object Name -EQ 'HGPM.Direct').State | Should -Be 'Refused'
            { Register-PSGPOAddOn -Name 'Other.Module' -Version '1.0' -Contract 1 } | Should -Throw
        }
    }

    Describe 'Hooks' {
        BeforeEach {
            Reset-TestAddOn
            $env:PSModulePath = $script:Modules + [System.IO.Path]::PathSeparator + $script:PathBefore
            $env:PSGPOTOOLS_NO_ADDON = $null
        }

        It 'Gives the windows the image of HGPM without an add-on, the one of the add-on with it' {
            $env:PSGPOTOOLS_NO_ADDON = '1'
            Get-PSGPOLogoPath | Should -Be $script:Logo
            Get-PSGPOLogoPath -Kind Header | Should -Be $script:Logo
            Reset-TestAddOn
            $env:PSGPOTOOLS_NO_ADDON = $null
            Get-PSGPOLogoPath | Should -Be (Join-Path $script:AddOnFolder 'Icon.png')
            Get-PSGPOLogoPath -Kind Header | Should -Be (Join-Path $script:AddOnFolder 'Header.png')
        }

        It 'Keeps the image of HGPM when the add-on gives no file, or fails' {
            Add-PSGPOAddOnItem -Name 'HGPM.Missing' -Version '1.0' -Contract 1 -State Loaded -WindowLogo { param($Kind) Join-Path $TestDrive "missing-$Kind.png" }
            $script:PSGPOAddOn.Loaded = $true
            Get-PSGPOLogoPath | Should -Be $script:Logo
            Reset-TestAddOn
            Add-PSGPOAddOnItem -Name 'HGPM.Throws' -Version '1.0' -Contract 1 -State Loaded -WindowLogo { throw 'no image here' }
            $script:PSGPOAddOn.Loaded = $true
            Get-PSGPOLogoPath -Kind Header | Should -Be $script:Logo
        }

        It 'Marks in a report where an add-on adds, and changes nothing without one' {
            $env:PSGPOTOOLS_NO_ADDON = '1'
            $Html = Get-TestReportHtml
            $Html | Should -BeLike "*<!-- hgpm:head -->`n</head>`n<body>`n<!-- hgpm:body-start -->*"
            $Html | Should -BeLike "*<!-- hgpm:body-end -->`n</body>`n</html>*"
            $Html | Should -Not -BeLike '*class="test-start"*'
        }

        It 'Lets an add-on change a report through its markers, with its version beside that of HGPM' {
            $Html = Get-TestReportHtml
            $Html | Should -BeLike '*<style>h2 { color: #123abc; }</style>*</head>*'
            $Html | Should -BeLike '*<body>*<p class="test-start">Contoso</p>*'
            $Html | Should -BeLike '*<p class="test-end">Confidential</p>*</body>*'
            $Html | Should -Not -BeLike '*<!-- hgpm:*'
            $Html | Should -BeLike "*with HGPM $script:Core + Test Edition 1.2.3.4*"
        }

        It 'Keeps a report as HGPM makes it when the add-on fails or returns nothing' {
            Add-PSGPOAddOnItem -Name 'HGPM.Throws' -Version '1.0' -Contract 1 -State Loaded -ReportHtml { throw 'no report here' }
            Add-PSGPOAddOnItem -Name 'HGPM.Nothing' -Version '1.0' -Contract 1 -State Loaded -ReportHtml { }
            $script:PSGPOAddOn.Loaded = $true
            Invoke-PSGPOAddOnReportHtml -Html '<html><!-- hgpm:head --></html>' | Should -BeExactly '<html><!-- hgpm:head --></html>'
        }

        It 'Saves a report in the format an add-on gives for the extension of the file, its type in the language of the interface' {
            $Format = @(Get-PSGPOAddOnReportFormat)
            $Format.Count | Should -Be 1
            $Format[0].Name | Should -Be 'Test'
            $Format[0].Extension | Should -Be 'tst' -Because 'the extension is kept without its dot, in lower case'
            $Format[0].TypeName | Should -Be 'Test file'
            $Format[0].Edition | Should -Be 'Test Edition'
            $Before = $script:PSGPOLanguage
            try {
                $script:PSGPOLanguage = 'fr-FR'
                @(Get-PSGPOAddOnReportFormat)[0].TypeName | Should -Be 'Fichier de test'
                $script:PSGPOLanguage = 'de-DE'
                @(Get-PSGPOAddOnReportFormat)[0].TypeName | Should -Be 'Test file' -Because 'English when the language has no text'
            } finally { $script:PSGPOLanguage = $Before }

            $Test = Join-Path $TestDrive 'report.TST'
            (Write-PSGPOReportHtmlFile -Html '<html>x</html>' -Path $Test).FullName | Should -Be $Test
            [System.IO.File]::ReadAllText($Test) | Should -BeExactly "TEST`n<html>x</html>"
            $Page = Join-Path $TestDrive 'report.html'
            $null = Write-PSGPOReportHtmlFile -Html '<html>x</html>' -Path $Page
            [System.IO.File]::ReadAllText($Page) | Should -BeExactly '<html>x</html>'

            # Get-PSGPOReport: the HTML report, branded by the add-on, in its format.
            $Directory = Import-PSGPODirectory -Path $script:SamplePath
            $Gpo = @($Directory.Gpos)[0]
            $File = Get-PSGPOReport -Name $Gpo.DisplayName -Directory $Directory -ReportType Html -Path (Join-Path $TestDrive 'gpo.tst')
            $Text = [System.IO.File]::ReadAllText($File.FullName)
            $Text | Should -BeLike "TEST`n<!DOCTYPE html>*"
            $Text | Should -BeLike '*<p class="test-start">Contoso</p>*'
        }

        It 'Says the error of a format, and a format that wrote no file; keeps HTML without an add-on' {
            $Fails = ConvertTo-PSGPOAddOnReportFormat -Format @{ Name = 'Fails'; Extension = 'bad'; TypeName = 'Bad'; Save = { throw 'no printer here' } }
            $Silent = ConvertTo-PSGPOAddOnReportFormat -Format @{ Name = 'Silent'; Extension = 'nil'; TypeName = 'Nil'; Save = { } }
            Add-PSGPOAddOnItem -Name 'HGPM.Formats' -Version '1.0' -Contract 1 -State Loaded -ReportFormat $Fails, $Silent
            $script:PSGPOAddOn.Loaded = $true
            { Write-PSGPOReportHtmlFile -Html '<html/>' -Path (Join-Path $TestDrive 'r.bad') } | Should -Throw '*no printer here*'
            # A file of before is not taken for the one asked.
            $Old = Join-Path $TestDrive 'r.nil'
            Set-Content -LiteralPath $Old -Value 'old'
            { Write-PSGPOReportHtmlFile -Html '<html/>' -Path $Old } | Should -Throw '*wrote no file*'
            Test-Path -LiteralPath $Old | Should -BeFalse

            Reset-TestAddOn
            $env:PSGPOTOOLS_NO_ADDON = '1'
            @(Get-PSGPOAddOnReportFormat) | Should -BeNullOrEmpty
            $null = Write-PSGPOReportHtmlFile -Html '<html/>' -Path (Join-Path $TestDrive 'r.tst')
            [System.IO.File]::ReadAllText((Join-Path $TestDrive 'r.tst')) | Should -BeExactly '<html/>' -Because 'without the add-on, the HTML page'
        }

        It 'Lets an add-on refuse a change before it is made, and complete the line of the audit log' {
            $Before = $env:PSGPOTOOLS_TEST_TICKET
            try {
                $env:PSGPOTOOLS_TEST_TICKET = $null
                Add-PSGPOAddOnItem -Name 'HGPM.Gate' -Version '1.0' -Contract 1 -State Loaded -BeforeChange {
                    param($Directory)
                    if (-not $env:PSGPOTOOLS_TEST_TICKET) { throw "Type the ticket of the change of $($Directory.DomainName) first." }
                } -AuditEntry {
                    param($Entry)
                    $Entry.Details['Ticket'] = $env:PSGPOTOOLS_TEST_TICKET
                }
                Add-PSGPOAddOnItem -Name 'HGPM.Broken' -Version '1.0' -Contract 1 -State Loaded -AuditEntry { throw 'no audit here' }
                $script:PSGPOAddOn.Loaded = $true
                # A directory in memory (a sample, a file read) is not the domain: no add-on asked.
                $Directory = Import-PSGPODirectory -Path $script:SamplePath
                $Directory.IsReadOnly = $false
                $Gpo = @($Directory.Gpos)[0]
                $Name = $Gpo.DisplayName
                $Directory.RenameGpo($Gpo, 'Renamed by the test')
                $Gpo.DisplayName | Should -Be 'Renamed by the test'
                # The domain: each change asks the add-ons first.
                $Domain = [GPOToolsLdapDirectory]::new('corp.contoso.com', 'DC=corp,DC=contoso,DC=com', 'dc1.corp.contoso.com', 'Samba AD')
                { $Domain.AssertWritable() } | Should -Throw '*Type the ticket of the change of corp.contoso.com first.*'
                $env:PSGPOTOOLS_TEST_TICKET = 'CHG0001'
                { $Domain.AssertWritable() } | Should -Not -Throw
                $Details = @{ From = $Name }
                Write-PSGPOAuditEntry -Directory $Directory -Action 'RenameGpo' -Target $Gpo.DisplayName -Gpo $Gpo -Details $Details
                $Line = @(Get-PSGPOAuditLog -Path (Get-PSGPOAuditPath) -Action 'RenameGpo' | Where-Object Target -EQ 'Renamed by the test')[0]
                $Line.Details.Ticket | Should -Be 'CHG0001' -Because 'the add-on completes the line, the one that fails leaves it'
                $Line.Details.From | Should -Be $Name
                $Details.ContainsKey('Ticket') | Should -BeFalse -Because 'the table of the caller is not changed'
            } finally { $env:PSGPOTOOLS_TEST_TICKET = $Before }
        }

        It 'Gives the console the fields of the add-ons, checked, in the language of the interface' {
            $Field = @{ Name = 'Ticket'; Label = @{ 'en-US' = 'Ticket'; 'fr-FR' = 'Billet' }; Placeholder = 'CHG0000000'; ToolTip = 'The ticket of the change'; Width = 140; Get = { 'CHG1' }; Set = { param($Value) } }
            $null = Register-PSGPOAddOn -Name 'HGPM.Field' -Version '1.0' -Contract 1 -ConsoleField $Field
            $script:PSGPOAddOn.Loaded = $true
            $Fields = @(Get-PSGPOAddOnConsoleField)
            $Fields.Count | Should -Be 1
            $Fields[0].Label | Should -Be 'Ticket'
            $Fields[0].Placeholder | Should -Be 'CHG0000000'
            $Fields[0].Width | Should -Be 140
            & $Fields[0].Get | Should -Be 'CHG1'
            $Before = $script:PSGPOLanguage
            try { $script:PSGPOLanguage = 'fr-FR'; @(Get-PSGPOAddOnConsoleField)[0].Label | Should -Be 'Billet' } finally { $script:PSGPOLanguage = $Before }

            $Set = { param($Value) }
            { Register-PSGPOAddOn -Name 'HGPM.Field1' -Version '1.0' -Contract 1 -ConsoleField @{ Name = 'a b'; Label = 'x'; Get = $Set; Set = $Set } } | Should -Throw '*is not letters and digits*'
            { Register-PSGPOAddOn -Name 'HGPM.Field2' -Version '1.0' -Contract 1 -ConsoleField @{ Name = 'T'; Get = $Set; Set = $Set } } | Should -Throw '*has no Label*'
            { Register-PSGPOAddOn -Name 'HGPM.Field3' -Version '1.0' -Contract 1 -ConsoleField @{ Name = 'T'; Label = 'x'; Set = $Set } } | Should -Throw '*its Get is not a scriptblock*'
            { Register-PSGPOAddOn -Name 'HGPM.Field4' -Version '1.0' -Contract 1 -ConsoleField @{ Name = 'T'; Label = 'x'; Get = $Set; Set = $Set; Width = 20 } } | Should -Throw '*Width*is not 80 to 400 pixels*'
            { Register-PSGPOAddOn -Name 'HGPM.Field5' -Version '1.0' -Contract 1 -ConsoleField @{ Name = 'T'; Label = 'x'; Get = $Set; Set = $Set }, @{ Name = 'T'; Label = 'y'; Get = $Set; Set = $Set } } | Should -Throw '*gives the field T twice*'
        }

        It 'Gives the audit log window the columns of the add-ons, checked, three at most, in the language of the interface' {
            $Get = { param($Entry) $Entry.Details.Ticket }
            $null = Register-PSGPOAddOn -Name 'HGPM.Columns' -Version '1.0' -Contract 1 -AuditColumn @(
                @{ Name = 'Ticket'; Header = @{ 'en-US' = 'Ticket'; 'fr-FR' = 'Billet' }; Width = 110; Filter = $true; All = @{ 'en-US' = 'All the tickets'; 'fr-FR' = 'Tous les billets' }; Get = $Get }
                @{ Name = 'Site'; Header = 'Site'; Get = $Get }
            )
            $null = Register-PSGPOAddOn -Name 'HGPM.Columns2' -Version '1.0' -Contract 1 -AuditColumn @{ Name = 'Team'; Header = 'Team'; Filter = $true; Get = $Get }, @{ Name = 'Extra'; Header = 'Extra'; Get = $Get }
            $script:PSGPOAddOn.Loaded = $true
            $Columns = @(Get-PSGPOAddOnAuditColumn)
            $Columns.Count | Should -Be 3 -Because 'the window has three places for the columns of the add-ons'
            $Columns.Name | Should -Be 'Ticket', 'Site', 'Team'
            $Columns[0].Header | Should -Be 'Ticket'
            $Columns[0].Width | Should -Be 110
            $Columns[0].Filter | Should -BeTrue
            $Columns[0].All | Should -Be 'All the tickets'
            $Columns[1].Width | Should -Be 130
            $Columns[1].Filter | Should -BeFalse
            $Columns[2].All | Should -Be 'Team: all'
            & $Columns[0].Get ([pscustomobject]@{ Details = @{ Ticket = 'CHG1' } }) | Should -Be 'CHG1'
            $Before = $script:PSGPOLanguage
            try {
                $null = Set-PSGPOLanguage -Language 'fr-FR'
                $French = @(Get-PSGPOAddOnAuditColumn)
                $French[0].Header | Should -Be 'Billet'
                $French[0].All | Should -Be 'Tous les billets'
                $French[2].All | Should -Be 'Team : toutes les valeurs'
            } finally { $null = Set-PSGPOLanguage -Language $(if ($Before) { $Before } else { 'en-US' }) }

            { Register-PSGPOAddOn -Name 'HGPM.Column1' -Version '1.0' -Contract 1 -AuditColumn 'Ticket' } | Should -Throw '*each column is a hashtable*'
            { Register-PSGPOAddOn -Name 'HGPM.Column2' -Version '1.0' -Contract 1 -AuditColumn @{ Name = 'a b'; Header = 'x'; Get = $Get } } | Should -Throw '*is not letters and digits*'
            { Register-PSGPOAddOn -Name 'HGPM.Column3' -Version '1.0' -Contract 1 -AuditColumn @{ Name = 'T'; Get = $Get } } | Should -Throw '*has no Header*'
            { Register-PSGPOAddOn -Name 'HGPM.Column4' -Version '1.0' -Contract 1 -AuditColumn @{ Name = 'T'; Header = 'x'; Get = 'Ticket' } } | Should -Throw '*its Get is not a scriptblock*'
            { Register-PSGPOAddOn -Name 'HGPM.Column5' -Version '1.0' -Contract 1 -AuditColumn @{ Name = 'T'; Header = 'x'; Get = $Get; Width = 1000 } } | Should -Throw '*Width*is not 60 to 400 pixels*'
            { Register-PSGPOAddOn -Name 'HGPM.Column6' -Version '1.0' -Contract 1 -AuditColumn @{ Name = 'T'; Header = 'x'; Get = $Get }, @{ Name = 'T'; Header = 'y'; Get = $Get } } | Should -Throw '*gives the column T twice*'
            @($script:PSGPOAddOn.Items | Where-Object Name -Match '^HGPM\.Column\d$') | Should -BeNullOrEmpty
        }

        It 'Tells the approver what the add-ons say, and lets an add-on refuse an approval before anything is written' {
            $Before = $env:PSGPOTOOLS_TEST_TICKET
            try {
                $env:PSGPOTOOLS_TEST_TICKET = $null
                Add-PSGPOAddOnItem -Name 'HGPM.Approval' -Version '1.0' -Contract 1 -State Loaded -ApprovalNote {
                    param($Directory, $Gpo)
                    "Request of $($Gpo.DisplayName): CHG0001"
                    ''
                    'Created by bob'
                } -BeforeApproval {
                    param($Directory, $Gpo)
                    if ($env:PSGPOTOOLS_TEST_TICKET -ne 'CHG0001') { throw "The approval of the GPO '$($Gpo.DisplayName)' needs the ticket CHG0001." }
                }
                Add-PSGPOAddOnItem -Name 'HGPM.Mute' -Version '1.0' -Contract 1 -State Loaded -ApprovalNote { throw 'no note here' }
                $script:PSGPOAddOn.Loaded = $true
                $Directory = Import-PSGPODirectory -Path $script:SamplePath
                $Directory.IsReadOnly = $false
                $Gpo = @($Directory.Gpos)[0]
                @(Get-PSGPOAddOnApprovalNote -Directory $Directory -Gpo $Gpo) | Should -Be "Request of $($Gpo.DisplayName): CHG0001", 'Created by bob' -Because 'the empty lines are left out, and the add-on that fails tells nothing'

                $Backups = Join-Path $TestDrive 'approval-backups'
                $Approval = @{ Directory = $Directory; Gpo = $Gpo; CreatorRights = 'ReadOnly'; ApplyTo = [pscustomobject]@{ Name = 'Authenticated Users'; Sid = 'S-1-5-11' }; BackupPath = $Backups }
                { Invoke-PSGPOApproval @Approval } | Should -Throw "*The approval of the GPO '$($Gpo.DisplayName)' needs the ticket CHG0001.*"
                Test-Path -LiteralPath $Backups | Should -BeFalse -Because 'nothing is done once the add-on refuses'
            } finally { $env:PSGPOTOOLS_TEST_TICKET = $Before }
        }

        It 'Refuses a format of report that does not fit: the add-on is not loaded' {
            $Save = { param($Html, $Path) }
            { Register-PSGPOAddOn -Name 'HGPM.Format1' -Version '1.0' -Contract 1 -ReportFormat 'pdf' } | Should -Throw '*each format is a hashtable*'
            { Register-PSGPOAddOn -Name 'HGPM.Format2' -Version '1.0' -Contract 1 -ReportFormat @{ Name = 'Page'; Extension = 'htm'; TypeName = 'x'; Save = $Save } } | Should -Throw '*.htm is a format of HGPM*'
            { Register-PSGPOAddOn -Name 'HGPM.Format3' -Version '1.0' -Contract 1 -ReportFormat @{ Name = 'P'; Extension = 'p d f'; TypeName = 'x'; Save = $Save } } | Should -Throw '*is not letters and digits*'
            { Register-PSGPOAddOn -Name 'HGPM.Format4' -Version '1.0' -Contract 1 -ReportFormat @{ Name = 'P'; Extension = 'pdf'; Save = $Save } } | Should -Throw '*has no TypeName*'
            { Register-PSGPOAddOn -Name 'HGPM.Format5' -Version '1.0' -Contract 1 -ReportFormat @{ Name = 'P'; Extension = 'pdf'; TypeName = 'x'; Save = 'print' } } | Should -Throw '*Save is not a scriptblock*'
            { Register-PSGPOAddOn -Name 'HGPM.Format6' -Version '1.0' -Contract 1 -ReportFormat @{ Name = 'A'; Extension = 'pdf'; TypeName = 'x'; Save = $Save }, @{ Name = 'B'; Extension = 'PDF'; TypeName = 'y'; Save = $Save } } | Should -Throw '*extension .pdf twice*'
            @($script:PSGPOAddOn.Items | Where-Object Name -Like 'HGPM.Format*') | Should -BeNullOrEmpty
        }
    }
}
