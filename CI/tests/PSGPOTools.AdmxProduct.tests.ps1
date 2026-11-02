#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The ADMX files of other products than Windows (PSGPOAdmxProduct.ps1, Install-PSGPOProductAdmx,
# Get-PSGPOProductAdmx): the catalog that pins their packages and files, the reading of a package
# (zip archive, cabinet, the cabinet a program holds) and its files found by their content, the
# check of a folder given with -SourcePath, and the install into a folder or the central store
# (the download mocked). The real packages are installed on the labs.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.ZipFile
        $script:Sha256 = { param([byte[]]$Bytes) [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)) }
        $script:Utf8 = [System.Text.UTF8Encoding]::new($false)
        # An .admx file declaring $Namespace, with one policy naming a string and a presentation.
        function New-TestAdmx {
            param([string]$Namespace, [string]$Using = 'Microsoft.Policies.Windows')
            @"
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitions revision="1.0" schemaVersion="1.0">
  <policyNamespaces>
    <target prefix="test" namespace="$Namespace" />
    <using prefix="windows" namespace="$Using" />
  </policyNamespaces>
  <resources minRequiredRevision="1.0" />
  <categories><category name="Cat" displayName="`$(string.Cat)" /></categories>
  <policies>
    <policy name="One" class="User" displayName="`$(string.One)" explainText="`$(string.One_Help)" presentation="`$(presentation.One)" key="Software\Policies\Test" valueName="One">
      <parentCategory ref="Cat" />
      <supportedOn ref="windows:SUPPORTED_Windows7" />
    </policy>
  </policies>
</policyDefinitions>
"@
        }
        function New-TestAdml {
            param([string]$Text = 'One', [switch]$WithoutHelp)
            $help = if ($WithoutHelp) { '' } else { "<string id=`"One_Help`">$Text help</string>" }
            "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<policyDefinitionResources revision=`"1.0`" schemaVersion=`"1.0`"><displayName/><description/><resources><stringTable><string id=`"Cat`">Test</string><string id=`"One`">$Text</string>$help</stringTable><presentationTable><presentation id=`"One`" /></presentationTable></resources></policyDefinitionResources>`n"
        }
        # A zip archive of entries (path -> text).
        function New-TestZip {
            param([string]$Path, [System.Collections.IDictionary]$Entry)
            $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Entry.Keys) {
                    $writer = [System.IO.StreamWriter]::new($archive.CreateEntry($name).Open(), $script:Utf8)
                    try { $writer.Write($Entry[$name]) } finally { $writer.Dispose() }
                }
            } finally {
                $archive.Dispose()
            }
        }
        # A product pinned: its package (bytes of $Package) and its files (path -> text).
        function New-TestProduct {
            param([string]$Name, [string]$Package, [System.Collections.IDictionary]$File, [string]$Format = 'Zip')
            $bytes = [System.IO.File]::ReadAllBytes($Package)
            [pscustomobject]@{
                Name = $Name; DisplayName = "Test $Name"; Publisher = 'Contoso'; Version = '1.0'
                Page = 'https://contoso.example/admx'; Uri = "https://contoso.example/$Name.zip"; FileName = "$Name.zip"
                Size = $bytes.Length; Sha256 = & $script:Sha256 $bytes; Format = $Format
                Files = @(foreach ($path in $File.Keys) { [pscustomobject]@{ Path = $path; Sha256 = & $script:Sha256 ($script:Utf8.GetBytes($File[$path])) } })
            }
        }

        # Vendor: an .admx file, its .adml files in en-US and fr-FR (fr-fr in the package), and the
        # templates of another system the install leaves.
        $script:VendorFiles = [ordered]@{ 'Vendor.admx' = (New-TestAdmx 'Contoso.Policies.Vendor'); 'en-US/Vendor.adml' = (New-TestAdml 'One'); 'fr-FR/Vendor.adml' = (New-TestAdml 'Un') }
        $script:VendorZip = Join-Path $TestDrive 'Vendor.zip'
        New-TestZip -Path $script:VendorZip -Entry ([ordered]@{
                'windows/Vendor.admx' = $script:VendorFiles['Vendor.admx']; 'windows/en-US/Vendor.adml' = $script:VendorFiles['en-US/Vendor.adml']
                'windows/fr-fr/Vendor.adml' = $script:VendorFiles['fr-FR/Vendor.adml']; 'mac/Vendor.plist' = '<plist/>'; 'README.md' = 'Contoso'
            })
        $script:Vendor = New-TestProduct -Name 'Vendor' -Package $script:VendorZip -File $script:VendorFiles
        # Suite: shares Common.admx with Other, as Chrome and Google Update share google.admx.
        $script:CommonAdmx = New-TestAdmx 'Contoso.Policies'
        $script:SuiteFiles = [ordered]@{ 'Common.admx' = $script:CommonAdmx; 'Suite.admx' = (New-TestAdmx 'Contoso.Policies.Suite' 'Contoso.Policies'); 'en-US/Common.adml' = (New-TestAdml 'Common'); 'en-US/Suite.adml' = (New-TestAdml 'Suite') }
        $script:SuiteZip = Join-Path $TestDrive 'Suite.zip'
        New-TestZip -Path $script:SuiteZip -Entry ([ordered]@{ 'Common.admx' = $script:SuiteFiles['Common.admx']; 'Suite.admx' = $script:SuiteFiles['Suite.admx']; 'en-US/Common.adml' = $script:SuiteFiles['en-US/Common.adml']; 'en-US/Suite.adml' = $script:SuiteFiles['en-US/Suite.adml'] })
        $script:Suite = New-TestProduct -Name 'Suite' -Package $script:SuiteZip -File $script:SuiteFiles
        $script:OtherFiles = [ordered]@{ 'Common.admx' = $script:CommonAdmx; 'Other.admx' = (New-TestAdmx 'Contoso.Policies.Other' 'Contoso.Policies'); 'en-US/Common.adml' = (New-TestAdml 'Common'); 'en-US/Other.adml' = (New-TestAdml 'Other') }
        $script:OtherZip = Join-Path $TestDrive 'Other.zip'
        New-TestZip -Path $script:OtherZip -Entry ([ordered]@{ 'x/Common.admx' = $script:OtherFiles['Common.admx']; 'x/Other.admx' = $script:OtherFiles['Other.admx']; 'x/en-US/Common.adml' = $script:OtherFiles['en-US/Common.adml']; 'x/en-US/Other.adml' = $script:OtherFiles['en-US/Other.adml'] })
        $script:Other = New-TestProduct -Name 'Other' -Package $script:OtherZip -File $script:OtherFiles
        $script:Downloads = @{ 'Vendor' = $script:VendorZip; 'Suite' = $script:SuiteZip; 'Other' = $script:OtherZip }
    }

    Describe 'Catalog of the ADMX files of products' {
        BeforeAll { $script:Pinned = @(Read-PSGPOAdmxProductFile) }

        It 'Pins Office, Firefox, Adobe Acrobat and Reader, Edge, Chrome and Google Update' {
            $script:Pinned.Name | Should -Be @('Office', 'Firefox', 'AdobeAcrobat', 'AdobeReader', 'Edge', 'Chrome', 'GoogleUpdate')
        }

        It 'Pins the package of <Name>: its address at its publisher, its size and SHA-256' -ForEach @(Read-PSGPOAdmxProductFile | ForEach-Object { @{ Name = $_.Name; Product = $_ } }) {
            $Product.DisplayName | Should -Not -BeNullOrEmpty
            $Product.Publisher | Should -BeIn 'Microsoft', 'Mozilla', 'Adobe', 'Google'
            $Product.Version | Should -Not -BeNullOrEmpty
            $Product.Uri | Should -BeLike 'https://*'
            $Product.Page | Should -BeLike 'https://*'
            $Product.FileName | Should -Be ([uri]::UnescapeDataString(([uri]$Product.Uri).Segments[-1]))
            $Product.Size | Should -BeGreaterThan 1000
            $Product.Sha256 | Should -MatchExactly '^[0-9A-F]{64}$'
            $Product.Format | Should -BeIn 'Zip', 'Cabinet', 'CabinetExecutable'
        }

        It 'Pins each file of <Name> at its path in a PolicyDefinitions folder, every .admx file with its en-US .adml file' -ForEach @(Read-PSGPOAdmxProductFile | ForEach-Object { @{ Name = $_.Name; Product = $_ } }) {
            $Paths = @($Product.Files.Path)
            $Paths.Count | Should -Be @($Paths | Sort-Object -Unique).Count -Because 'a path is pinned once'
            foreach ($File in $Product.Files) {
                $File.Sha256 | Should -MatchExactly '^[0-9A-F]{64}$'
                if ($File.Path -match '/') {
                    $File.Path | Should -Match '^[a-z]{2,3}(-[A-Za-z0-9]+)+/[^/]+\.adml$'
                    $Culture = $File.Path.Split('/')[0]
                    $Culture | Should -BeExactly ([cultureinfo]::GetCultureInfo($Culture).Name) -Because 'a language folder is named after its culture (fr-FR)'
                } else {
                    $File.Path | Should -Match '^[^/]+\.admx$'
                    $Paths | Should -Contain "en-US/$([System.IO.Path]::ChangeExtension($File.Path, '.adml'))"
                }
            }
        }

        It 'Lists the products, their languages and the files they share' {
            $Products = @(Get-PSGPOProductAdmx)
            $Products.Count | Should -Be $script:Pinned.Count
            $Office = $Products | Where-Object Name -EQ 'Office'
            $Office.PSObject.TypeNames | Should -Contain 'PSGPOTools.AdmxProduct'
            $Office.Languages | Should -Contain 'fr-FR'
            $Office.AdmxFiles | Should -Contain 'word16.admx'
            (Get-PSGPOProductAdmx -Name chrome).Shared | Should -Be @('google.admx') -Because 'Google Update holds google.admx too'
            (Get-PSGPOProductAdmx -Name Firefox).Shared | Should -BeNullOrEmpty
        }

        It 'Names the products it pins, and -SourcePath, for another one' {
            { Get-PSGPOProductAdmx -Name Zoom } | Should -Throw "*pins no ADMX files of 'Zoom'*Office, Firefox*-SourcePath*"
        }
    }

    Describe 'Reading a package' {
        It 'Finds the files pinned by their content, wherever and whatever the package names them' {
            # The package of Office holds its languages side by side: word16.adml, word16.adml0...
            $Files = [ordered]@{ 'Vendor.admx' = $script:VendorFiles['Vendor.admx']; 'de-DE/Vendor.adml' = (New-TestAdml 'Eins'); 'en-US/Vendor.adml' = (New-TestAdml 'One') }
            $Zip = Join-Path $TestDrive 'numbered.zip'
            New-TestZip -Path $Zip -Entry ([ordered]@{ 'Vendor.admx' = $Files['Vendor.admx']; 'Vendor.adml' = $Files['de-DE/Vendor.adml']; 'Vendor.adml0' = $Files['en-US/Vendor.adml']; 'Vendor.opal' = 'x' })
            $Product = New-TestProduct -Name 'Numbered' -Package $Zip -File $Files
            Mock Expand-PSGPOAdmxZipEntry {
                # As cabextract leaves them: their names in the cabinet.
                $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
                try { foreach ($entry in $archive.Entries) { $null = New-Item -ItemType Directory -Path $Folder -Force; [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Folder $entry.Name)) } } finally { $archive.Dispose() }
            }
            $Folder = Join-Path $TestDrive 'numbered'
            Expand-PSGPOAdmxProductPackage -Package $Zip -Product $Product -Folder $Folder -Language 'de-DE', 'en-US' | Should -Be 3
            Get-Content -LiteralPath (Join-Path $Folder 'de-DE' 'Vendor.adml') -Raw | Should -Match 'Eins'
            Get-Content -LiteralPath (Join-Path $Folder 'en-US' 'Vendor.adml') -Raw | Should -Match '>One<'
        }

        It 'Takes the .admx files and the languages asked for only, from a zip archive' {
            $Folder = Join-Path $TestDrive 'zip'
            Expand-PSGPOAdmxProductPackage -Package $script:VendorZip -Product $script:Vendor -Folder $Folder -Language 'fr-FR' | Should -Be 2
            @(Get-ChildItem -LiteralPath $Folder -File -Recurse | ForEach-Object { $_.FullName.Substring($Folder.Length + 1) -replace '\\', '/' } | Sort-Object) | Should -Be @('fr-FR/Vendor.adml', 'Vendor.admx')
        }

        It 'Refuses a package without a file pinned, or with another content' {
            $Zip = Join-Path $TestDrive 'tampered.zip'
            New-TestZip -Path $Zip -Entry ([ordered]@{ 'Vendor.admx' = $script:VendorFiles['Vendor.admx']; 'en-US/Vendor.adml' = (New-TestAdml 'Changed') })
            { Expand-PSGPOAdmxProductPackage -Package $Zip -Product $script:Vendor -Folder (Join-Path $TestDrive 'never-tampered') -Language 'en-US' } | Should -Throw '*does not hold the ADMX files HGPM pins for Test Vendor*en-US/Vendor.adml*nothing is installed*'
            Test-Path -LiteralPath (Join-Path $TestDrive 'never-tampered') | Should -BeFalse
        }

        It 'Reads the zip archive a cabinet holds, whatever expand names it' {
            Mock Expand-PSGPOAdmxCabinet {
                $null = New-Item -ItemType Directory -Path $Folder -Force
                Copy-Item -LiteralPath $script:VendorZip -Destination (Join-Path $Folder 'vendorpolicytemplates.cab')
            }
            $Product = $script:Vendor.PSObject.Copy()
            $Product.Format = 'Cabinet'
            $Folder = Join-Path $TestDrive 'cabinet'
            Expand-PSGPOAdmxProductPackage -Package (Join-Path $TestDrive 'Vendor.cab') -Product $Product -Folder $Folder -Language 'en-US' | Should -Be 2
            Test-Path -LiteralPath (Join-Path $Folder 'en-US' 'Vendor.adml') | Should -BeTrue
            Test-PSGPOZipFile -Path $script:VendorZip | Should -BeTrue
            Test-PSGPOZipFile -Path (Join-Path $Folder 'Vendor.admx') | Should -BeFalse
        }

        It 'Takes the cabinet a program holds after its sections, without running it' {
            # MZ, the PE header at 0x40, one section of 0x100 bytes at 0x200, then the cabinet
            # (MSCF, its size), then the signature of the program.
            $Cabinet = [byte[]]@(0x4D, 0x53, 0x43, 0x46, 0, 0, 0, 0, 24, 0, 0, 0) + [byte[]](1..12)
            $Program = [byte[]]::new(0x300)
            $Program[0] = 0x4D; $Program[1] = 0x5A
            [BitConverter]::GetBytes([int]0x40).CopyTo($Program, 0x3C)
            ([byte[]](0x50, 0x45, 0, 0)).CopyTo($Program, 0x40)
            [BitConverter]::GetBytes([uint16]1).CopyTo($Program, 0x46)
            [BitConverter]::GetBytes([uint16]0xE0).CopyTo($Program, 0x54)
            $Section = 0x40 + 24 + 0xE0
            [BitConverter]::GetBytes([uint32]0x100).CopyTo($Program, $Section + 16)
            [BitConverter]::GetBytes([uint32]0x200).CopyTo($Program, $Section + 20)
            $Exe = Join-Path $TestDrive 'package.exe'
            [System.IO.File]::WriteAllBytes($Exe, $Program + $Cabinet + [byte[]](9, 9, 9))
            Save-PSGPOAdmxEmbeddedCabinet -Path $Exe -Destination (Join-Path $TestDrive 'package.cab')
            [System.IO.File]::ReadAllBytes((Join-Path $TestDrive 'package.cab')) | Should -Be $Cabinet
            { Save-PSGPOAdmxEmbeddedCabinet -Path $script:VendorZip -Destination (Join-Path $TestDrive 'never.cab') } | Should -Throw '*holds no cabinet after its program*'
        }

        It 'Says to install cabextract when no tool reads a cabinet' -Skip:$IsWindows {
            Mock Get-Command { } -ParameterFilter { $Name -contains 'cabextract' -or $Name -contains '7z' }
            { Expand-PSGPOAdmxCabinet -Path (Join-Path $TestDrive 'package.cab') -Folder (Join-Path $TestDrive 'never-cab') } | Should -Throw '*install it*apt install cabextract*'
        }

        It 'Reads the target and the namespaces used of the .admx files of a folder' {
            $Folder = Join-Path $TestDrive 'namespaces'
            $null = New-Item -ItemType Directory -Path $Folder -Force
            [System.IO.File]::WriteAllText((Join-Path $Folder 'Suite.admx'), $script:SuiteFiles['Suite.admx'])
            [System.IO.File]::WriteAllText((Join-Path $Folder 'Broken.admx'), '<policyDefinitions><policyNamespaces><target')
            $Read = @(Get-PSGPOAdmxNamespace -Path $Folder)
            $Read.Count | Should -Be 1 -Because 'a file that cannot be read is left out'
            $Read[0].Target | Should -Be 'Contoso.Policies.Suite'
            $Read[0].Using | Should -Be @('Contoso.Policies')
        }
    }

    Describe 'Checking a PolicyDefinitions folder' {
        BeforeAll {
            function New-TestSource {
                param([string]$Path, [string[]]$Culture = @('en-US', 'fr-fr'), [switch]$WithoutHelp)
                $null = New-Item -ItemType Directory -Path @($Culture | ForEach-Object { Join-Path $Path $_ }) -Force
                [System.IO.File]::WriteAllText((Join-Path $Path 'Zoom.admx'), (New-TestAdmx 'Zoom.Policies'))
                foreach ($Item in $Culture) { [System.IO.File]::WriteAllText((Join-Path $Path $Item 'Zoom.adml'), (New-TestAdml 'Zoom' -WithoutHelp:($WithoutHelp -and $Item -ne 'en-US'))) }
            }
        }

        It 'Finds no problem in a folder GPMC reads, its languages named after their culture' {
            $Source = Join-Path $TestDrive 'source-ok'
            New-TestSource -Path $Source
            $Languages = @(Get-PSGPOAdmxSourceLanguage -Path $Source)
            $Languages.Culture | Should -Be @('en-US', 'fr-FR')
            @(Test-PSGPOAdmxSourceFolder -Path $Source -Language $Languages) | Should -BeNullOrEmpty
        }

        It 'Finds a string missing, an .adml file missing, a file that cannot be read' {
            $Source = Join-Path $TestDrive 'source-bad'
            New-TestSource -Path $Source -WithoutHelp
            $null = New-Item -ItemType Directory -Path (Join-Path $Source 'de-DE') -Force
            [System.IO.File]::WriteAllText((Join-Path $Source 'de-DE' 'Other.adml'), (New-TestAdml))
            [System.IO.File]::WriteAllText((Join-Path $Source 'Broken.admx'), '<policyDefinitions>')
            $Problems = @(Test-PSGPOAdmxSourceFolder -Path $Source -Language @(Get-PSGPOAdmxSourceLanguage -Path $Source))
            $Problems | Should -Contain 'fr-FR\Zoom.adml lacks 1 strings of Zoom.admx: One_Help.'
            $Problems | Should -Contain 'Zoom.admx has no .adml file in de-DE.'
            @($Problems | Where-Object { $_ -like 'Broken.admx cannot be read*' }).Count | Should -Be 1
        }
    }

    Describe 'Install-PSGPOProductAdmx' {
        BeforeAll {
            Mock Read-PSGPOAdmxProductFile { $script:Vendor, $script:Suite, $script:Other }
            Mock Invoke-WebRequest { Copy-Item -LiteralPath $script:Downloads[[System.IO.Path]::GetFileNameWithoutExtension(([uri]$Uri).Segments[-1])] -Destination $OutFile }
        }
        BeforeEach {
            $script:Target = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            # The folder of the ADMX files of Windows.
            $null = New-Item -ItemType Directory -Path $script:Target
            [System.IO.File]::WriteAllText((Join-Path $script:Target 'windows.admx'), (New-TestAdmx 'Microsoft.Policies.Windows' 'Microsoft.Policies.Products'))
        }

        It 'Installs the .admx files and the languages asked for of a product, from its publisher' {
            $Result = Install-PSGPOProductAdmx -Name Vendor -Path $script:Target -UICulture fr-FR -Confirm:$false
            $Result.PSObject.TypeNames | Should -Contain 'PSGPOTools.AdmxInstall'
            $Result.Path | Should -Be ([System.IO.Path]::GetFullPath($script:Target))
            $Result.Product | Should -Be 'Vendor'
            $Result.Package | Should -Be 'Test Vendor 1.0'
            $Result.Languages | Should -Be @('fr-FR')
            $Result.Files | Should -Be 2
            Test-Path -LiteralPath (Join-Path $script:Target 'fr-FR' 'Vendor.adml') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:Target 'Vendor.plist') | Should -BeFalse
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://contoso.example/Vendor.zip' }
        }

        It 'Leaves a language a product does not have with a warning, refuses when it has none of them' {
            $Result = Install-PSGPOProductAdmx -Name Suite -Path $script:Target -UICulture en-US, fr-FR -Confirm:$false -WarningVariable Warnings 3>$null
            $Result.Languages | Should -Be @('en-US')
            "$Warnings" | Should -BeLike '*Test Suite 1.0 has no fr-FR .adml files*en-US*'
            { Install-PSGPOProductAdmx -Name Vendor -Path $script:Target -UICulture de-DE -Confirm:$false 3>$null } | Should -Throw '*None of the languages asked for (de-DE) in Test Vendor 1.0: en-US, fr-FR*'
        }

        It 'Installs several products, and every language with -AllLanguages' {
            $Results = @(Install-PSGPOProductAdmx -Name Vendor, Suite -Path $script:Target -AllLanguages -Confirm:$false)
            $Results.Product | Should -Be @('Vendor', 'Suite')
            $Results[0].Languages | Should -Be @('en-US', 'fr-FR')
            @(Get-ChildItem -LiteralPath $script:Target -File -Filter '*.admx').Name | Sort-Object | Should -Be @('Common.admx', 'Suite.admx', 'Vendor.admx', 'windows.admx')
        }

        It 'Replaces the files of a product already there with -Force only, not for a file it shares' {
            $null = Install-PSGPOProductAdmx -Name Suite -Path $script:Target -UICulture en-US -Confirm:$false
            { Install-PSGPOProductAdmx -Name Suite -Path $script:Target -UICulture en-US -Confirm:$false } | Should -Throw '*ADMX files of Test Suite 1.0 are already in*(Suite.admx)*-Force*'
            $Result = Install-PSGPOProductAdmx -Name Other -Path $script:Target -UICulture en-US -Confirm:$false
            $Result.Files | Should -Be 4 -Because 'Common.admx, shared with Suite, does not stop it'
            $null = Install-PSGPOProductAdmx -Name Suite -Path $script:Target -UICulture en-US -Force -Confirm:$false
        }

        It 'Refuses a file that declares the namespace of a file of another name already there' {
            [System.IO.File]::WriteAllText((Join-Path $script:Target 'Contoso-old.admx'), (New-TestAdmx 'Contoso.Policies.Vendor'))
            { Install-PSGPOProductAdmx -Name Vendor -Path $script:Target -UICulture en-US -Confirm:$false } | Should -Throw '*Vendor.admx declares the namespace Contoso.Policies.Vendor, which Contoso-old.admx*declares already*nothing is installed*'
            Test-Path -LiteralPath (Join-Path $script:Target 'Vendor.admx') | Should -BeFalse
        }

        It 'Warns when the files of Windows the product uses are not there' {
            Remove-Item -LiteralPath (Join-Path $script:Target 'windows.admx')
            $null = Install-PSGPOProductAdmx -Name Vendor -Path $script:Target -UICulture en-US -Confirm:$false -WarningVariable Warnings 3>$null
            "$Warnings" | Should -BeLike '*use those of Windows (windows.admx)*Install-PSGPOAdmx*'
        }

        It 'Refuses a download that is not the package pinned, and installs nothing' {
            Mock Invoke-WebRequest { [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1..10)) }
            { Install-PSGPOProductAdmx -Name Vendor -Path $script:Target -Confirm:$false } | Should -Throw '*download of https://contoso.example/Vendor.zip is not the package HGPM pins, Test Vendor 1.0*nothing is installed*'
            Test-Path -LiteralPath (Join-Path $script:Target 'Vendor.admx') | Should -BeFalse
        }

        It 'Installs from -PackagePath without downloading, for one product' {
            $Result = Install-PSGPOProductAdmx -Name Vendor -PackagePath $script:VendorZip -Path $script:Target -UICulture en-US -Confirm:$false
            $Result.Files | Should -Be 2
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            { Install-PSGPOProductAdmx -Name Vendor, Suite -PackagePath $script:VendorZip -Path $script:Target -Confirm:$false } | Should -Throw '*-PackagePath with one product*'
            { Install-PSGPOProductAdmx -Name Vendor -PackagePath (Join-Path $TestDrive 'missing.zip') -Path $script:Target -Confirm:$false } | Should -Throw "*No file*missing.zip*Vendor.zip*"
        }

        It 'Says to give the package with -PackagePath when it cannot be downloaded' {
            Mock Invoke-WebRequest { throw 'No such host is known.' }
            { Install-PSGPOProductAdmx -Name Vendor -Path $script:Target -Confirm:$false } | Should -Throw '*Cannot download https://contoso.example/Vendor.zip*https://contoso.example/admx*-PackagePath*'
        }

        It 'Downloads nothing with -WhatIf' {
            Install-PSGPOProductAdmx -Name Vendor -Path $script:Target -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path $script:Target 'Vendor.admx') | Should -BeFalse
        }

        It 'Installs a folder checked with -SourcePath, its languages named after their culture' {
            $Source = Join-Path $TestDrive 'zoom'
            $null = New-Item -ItemType Directory -Path (Join-Path $Source 'en-us'), (Join-Path $Source 'fr-fr') -Force
            [System.IO.File]::WriteAllText((Join-Path $Source 'Zoom.admx'), (New-TestAdmx 'Zoom.Policies'))
            foreach ($Culture in 'en-us', 'fr-fr') { [System.IO.File]::WriteAllText((Join-Path $Source $Culture 'Zoom.adml'), (New-TestAdml 'Zoom')) }
            $Result = Install-PSGPOProductAdmx -SourcePath $Source -Path $script:Target -AllLanguages -Confirm:$false
            $Result.Product | Should -BeNullOrEmpty
            $Result.Files | Should -Be 3
            @(Get-ChildItem -LiteralPath $script:Target -Directory).Name | Should -BeExactly @('en-US', 'fr-FR') -Because 'the SYSVOL of Samba tells fr-fr and fr-FR apart'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'Refuses a folder GPMC cannot read, and installs nothing' {
            $Source = Join-Path $TestDrive 'zoom-bad'
            $null = New-Item -ItemType Directory -Path (Join-Path $Source 'en-US') -Force
            [System.IO.File]::WriteAllText((Join-Path $Source 'Zoom.admx'), (New-TestAdmx 'Zoom.Policies'))
            [System.IO.File]::WriteAllText((Join-Path $Source 'en-US' 'Zoom.adml'), (New-TestAdml 'Zoom' -WithoutHelp))
            { Install-PSGPOProductAdmx -SourcePath $Source -Path $script:Target -UICulture en-US -Confirm:$false } | Should -Throw "*GPMC cannot read the ADMX files of*1 problems*lacks 1 strings*nothing is installed*"
            Test-Path -LiteralPath (Join-Path $script:Target 'Zoom.admx') | Should -BeFalse
            { Install-PSGPOProductAdmx -SourcePath (Join-Path $TestDrive 'nowhere') -Path $script:Target -Confirm:$false } | Should -Throw "*No folder*nowhere*"
        }

        It 'Writes the central store of the domain controller, and the audit log' {
            $Directory = [GPOToolsLdapDirectory]::new('hardenbox.labo', 'DC=hardenbox,DC=labo', 'dc.hardenbox.labo', 'Samba AD')
            Mock Get-PSGPOAdmxCentralStoreFile { 'windows.admx', 'Common.admx' }
            Mock Get-PSGPOAdmxCentralStoreNamespace { }
            Mock Copy-PSGPOAdmxCentralStore {
                $script:Copied = @(Get-ChildItem -LiteralPath $Source -File -Recurse | ForEach-Object { $_.FullName.Substring($Source.Length + 1) -replace '\\', '/' } | Sort-Object)
                '\\dc.hardenbox.labo\SYSVOL\hardenbox.labo\Policies\PolicyDefinitions'
            }
            Mock Write-PSGPOAuditEntry { }
            $Result = Install-PSGPOProductAdmx -Name Other -CentralStore -Directory $Directory -UICulture en-US -Confirm:$false
            $Result.Path | Should -Be '\\dc.hardenbox.labo\SYSVOL\hardenbox.labo\Policies\PolicyDefinitions'
            $script:Copied | Should -Be @('Common.admx', 'en-US/Common.adml', 'en-US/Other.adml', 'Other.admx')
            Should -Invoke Write-PSGPOAuditEntry -Times 1 -Exactly -ParameterFilter { $Action -eq 'InstallAdmx' -and $Details.Product -eq 'Other' -and $Details.Version -eq '1.0' -and $Details.Files -eq 4 -and $Details.Sha256 -eq $script:Other.Sha256 }
        }

        It 'Keeps the files of a product in the central store unless -Force' {
            $Directory = [GPOToolsLdapDirectory]::new('hardenbox.labo', 'DC=hardenbox,DC=labo', 'dc.hardenbox.labo', 'Samba AD')
            Mock Get-PSGPOAdmxCentralStoreFile { 'windows.admx', 'vendor.admx' }
            Mock Copy-PSGPOAdmxCentralStore { }
            { Install-PSGPOProductAdmx -Name Vendor -CentralStore -Directory $Directory -Confirm:$false } | Should -Throw "*already in '\\dc.hardenbox.labo\SYSVOL\hardenbox.labo\Policies\PolicyDefinitions' (Vendor.admx)*-Force*"
            Should -Invoke Copy-PSGPOAdmxCentralStore -Times 0 -Exactly
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'Refuses the central store of a domain that is not read from a domain controller' {
            { Install-PSGPOProductAdmx -Name Vendor -CentralStore -Directory ([GPOToolsDirectory]::new('hardenbox.labo')) -Confirm:$false } | Should -Throw '*central store is in SYSVOL*'
        }

        It 'Lists the .admx files of the central store of a Samba domain controller (smbclient)' -Skip:$IsWindows {
            $Directory = [GPOToolsLdapDirectory]::new('hardenbox.labo', 'DC=hardenbox,DC=labo', 'dc.hardenbox.labo', 'Samba AD')
            Mock Assert-PSGPOKerberosOnly { }
            Mock Invoke-PSGPOSmbClient { '  windows.admx                        A    45672  Mon Nov  2 10:00:00 2026', '  word16.admx                         A   476750  Mon Nov  2 10:00:01 2026', '', '		10218772 blocks of size 1024. 4419664 blocks available' }
            @(Get-PSGPOAdmxCentralStoreFile -Directory $Directory) | Should -Be @('windows.admx', 'word16.admx')
        }
    }
}
