#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The ADMX files of Windows installed from the package of Microsoft (PSGPOAdmxInstall.ps1,
# Install-PSGPOAdmx): the catalog that pins the package and its files, the hash of a set of files,
# the languages chosen, and the install from a package (the download and the extraction mocked),
# into a folder or the central store. The real package is extracted by CI/Get-AdmxSource.ps1
# before the tests; the copy into a real SYSVOL is tested in PSGPOTools.Ldap.tests.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $Sources = Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions'
        # A small PolicyDefinitions folder: two .admx files and two languages (named as the
        # package names them: fr-fr).
        function New-TestPolicyDefinitions {
            param([string]$Path, [string[]]$Culture = @('en-US', 'fr-FR'))
            $null = New-Item -ItemType Directory -Path @($Culture | ForEach-Object { Join-Path $Path $_ }) -Force
            foreach ($Name in 'One', 'Two') {
                [System.IO.File]::WriteAllText((Join-Path $Path "$Name.admx"), "<policyDefinitions>`n  <!-- $Name -->`n</policyDefinitions>`n")
                foreach ($Item in $Culture) { [System.IO.File]::WriteAllText((Join-Path $Path $Item "$Name.adml"), "<policyDefinitionResources culture='$(([cultureinfo]$Item).Name)'>$Name</policyDefinitionResources>`n") }
            }
        }
        $script:Source = Join-Path $TestDrive 'source'
        New-TestPolicyDefinitions -Path $script:Source
        $script:Catalog = @(Get-PSGPOAdmxSet -Path $script:Source)
        # The same files as the package holds them: the languages in lower case but en-US.
        $script:Packaged = Join-Path $TestDrive 'packaged'
        New-TestPolicyDefinitions -Path $script:Packaged -Culture 'en-US', 'fr-fr'
    }

    Describe 'Catalog of the ADMX files' {
        It 'Pins the files of the package, those CI/Get-AdmxSource.ps1 installed in sources/PolicyDefinitions' {
            $Pinned = @(Get-PSGPOAdmxCatalog)
            $Actual = @(Get-PSGPOAdmxSet -Path $Sources)
            $Pinned.Count | Should -Be $Actual.Count
            foreach ($Set in $Actual) {
                $Entry = $Pinned | Where-Object Name -CEQ $Set.Name
                $Entry | Should -Not -BeNullOrEmpty -Because "the set $($Set.Name) is pinned"
                $Entry.Files | Should -Be $Set.Files
                $Entry.Sha256 | Should -Be $Set.Sha256 -Because "the files of $($Set.Name) are those pinned"
            }
            $Pinned.Name | Should -Contain '.'
            $Pinned.Name | Should -Contain 'en-US'
            $Pinned.Name | Should -Contain 'fr-FR' -Because 'a language is named after its culture, whatever the case of its folder'
            @(Get-ChildItem -LiteralPath $Sources -Directory).Name | Should -Contain 'fr-FR' -Because 'the folders installed are named after their culture (the package has fr-fr)'
        }

        It 'Pins the package of Microsoft: its address on download.microsoft.com, its size and SHA-256' {
            $Package = Get-PSGPOAdmxPackage
            $Package.Uri | Should -BeLike 'https://download.microsoft.com/*.msi'
            $Package.FileName | Should -Be ([uri]::UnescapeDataString(([uri]$Package.Uri).Segments[-1]))
            $Package.Page | Should -BeLike 'https://www.microsoft.com/*'
            $Package.Name | Should -BeLike 'Administrative Templates (.admx) for Windows*'
            $Package.Size | Should -BeGreaterThan 1MB
            $Package.Sha256 | Should -MatchExactly '^[0-9A-F]{64}$'
        }

        It 'Gives a set the same hash whatever the case of the names, another one for other content' {
            $Upper = Join-Path $TestDrive 'upper'
            $Lower = Join-Path $TestDrive 'lower'
            $null = New-Item -ItemType Directory -Path $Upper, $Lower -Force
            [System.IO.File]::WriteAllText((Join-Path $Upper 'AppHVSI.admx'), "<a>`r`n<b/>`r`n</a>`r`n")
            [System.IO.File]::WriteAllText((Join-Path $Lower 'apphvsi.admx'), "<a>`r`n<b/>`r`n</a>`r`n")
            Get-PSGPOAdmxSetHash -File (Get-ChildItem -LiteralPath $Lower -File) | Should -Be (Get-PSGPOAdmxSetHash -File (Get-ChildItem -LiteralPath $Upper -File))
            [System.IO.File]::WriteAllText((Join-Path $Lower 'apphvsi.admx'), "<a>`n<b/>`n</a>`n")
            Get-PSGPOAdmxSetHash -File (Get-ChildItem -LiteralPath $Lower -File) | Should -Not -Be (Get-PSGPOAdmxSetHash -File (Get-ChildItem -LiteralPath $Upper -File)) -Because 'the files are hashed as the package holds them'
        }
    }

    Describe 'Languages to install' {
        BeforeAll { $Available = 'de-DE', 'en-US', 'fr-FR' }

        It 'Takes en-US and the language of the session by default' {
            @(Resolve-PSGPOAdmxLanguage -Available $Available -Current ([cultureinfo]'fr-FR')) | Should -Be @('en-US', 'fr-FR')
            @(Resolve-PSGPOAdmxLanguage -Available $Available -Current ([cultureinfo]'de-AT')) | Should -Be @('en-US', 'de-DE') -Because 'the same language in another country'
            @(Resolve-PSGPOAdmxLanguage -Available $Available -Current ([cultureinfo]'en-GB')) | Should -Be @('en-US')
            @(Resolve-PSGPOAdmxLanguage -Available $Available -Current ([cultureinfo]'ja-JP')) | Should -Be @('en-US')
        }

        It 'Takes the cultures asked for, whatever their case, or all of them' {
            @(Resolve-PSGPOAdmxLanguage -Available $Available -Language 'FR-fr') | Should -Be @('fr-FR')
            @(Resolve-PSGPOAdmxLanguage -Available $Available -All) | Should -Be $Available
            { Resolve-PSGPOAdmxLanguage -Available $Available -Language 'xx-XX' } | Should -Throw "*No 'xx-XX' language*de-DE, en-US, fr-FR*"
        }
    }

    Describe 'Extraction of the package' {
        It 'Says to install msitools when msiextract is missing' -Skip:$IsWindows {
            Mock Get-Command { } -ParameterFilter { $Name -eq 'msiextract' }
            { Expand-PSGPOAdmxMsi -Package (Join-Path $TestDrive 'package.msi') -Folder (Join-Path $TestDrive 'never-msi') } | Should -Throw '*install msitools*apt install msitools*'
        }

        It 'Finds the PolicyDefinitions folder of the package, wherever the tool puts it' {
            $Expanded = Join-Path $TestDrive 'expanded'
            $Folder = Join-Path $Expanded 'Program Files' 'Microsoft Group Policy' 'Windows 11 Sep 2026 Update (26H2)' 'PolicyDefinitions'
            New-TestPolicyDefinitions -Path $Folder -Culture 'en-US', 'fr-fr'
            (Get-PSGPOAdmxPackageFolder -Path $Expanded).FullName | Should -Be ([System.IO.DirectoryInfo]$Folder).FullName
            { Get-PSGPOAdmxPackageFolder -Path (Join-Path $Folder 'en-US') -Package 'package.msi' } | Should -Throw "*No PolicyDefinitions folder of .admx files in 'package.msi'*"
        }
    }

    Describe 'Install-PSGPOAdmx' {
        BeforeAll {
            Mock Get-PSGPOAdmxCatalog { $script:Catalog }
            # The package: bytes of a test, pinned by their size and SHA-256.
            $script:PackageFile = Join-Path $TestDrive 'package.msi'
            [System.IO.File]::WriteAllBytes($script:PackageFile, [byte[]](1..200))
            $script:Pin = [pscustomobject]@{
                Name     = 'Administrative Templates (.admx) for Windows 11 (test)'
                Page     = 'https://www.microsoft.com/en-us/download/details.aspx?id=1'
                Uri      = 'https://download.microsoft.com/download/test/Administrative%20Templates.msi'
                FileName = 'Administrative Templates.msi'
                Size     = 200
                Sha256   = (Get-FileHash -LiteralPath $script:PackageFile -Algorithm SHA256).Hash
            }
            Mock Get-PSGPOAdmxPackage { $script:Pin }
            Mock Invoke-WebRequest { Copy-Item -LiteralPath $script:Download -Destination $OutFile }
            # msiexec /a or msiextract: the PolicyDefinitions folder of the package under Program Files.
            Mock Expand-PSGPOAdmxMsi {
                $Target = Join-Path $Folder 'Program Files' 'Microsoft Group Policy' 'Windows 11 (test)' 'PolicyDefinitions'
                $null = New-Item -ItemType Directory -Path $Target -Force
                Copy-Item -Path (Join-Path $script:Extracted '*') -Destination $Target -Recurse
            }
        }
        BeforeEach {
            $script:Download = $script:PackageFile
            $script:Extracted = $script:Packaged
        }

        It 'Installs the .admx files and the languages asked for, from the package of Microsoft' {
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            $Result = Install-PSGPOAdmx -Path $Path -UICulture fr-FR -Confirm:$false
            $Result.Path | Should -Be ([System.IO.Path]::GetFullPath($Path))
            $Result.Languages | Should -Be @('fr-FR')
            $Result.Files | Should -Be 4
            $Result.Package | Should -Be $script:Pin.Name
            @(Get-ChildItem -LiteralPath $Path -File -Filter '*.admx').Name | Sort-Object | Should -Be @('One.admx', 'Two.admx')
            @(Get-ChildItem -LiteralPath $Path -Directory).Name | Should -BeExactly @('fr-FR') -Because 'the folder of a language is named after its culture (fr-fr in the package), only the languages asked for'
            Test-Path -LiteralPath (Join-Path $Path 'fr-FR' 'One.adml') | Should -BeTrue
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:Pin.Uri }
        }

        It 'Installs every language with -AllLanguages' {
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            $Result = Install-PSGPOAdmx -Path $Path -AllLanguages -Confirm:$false
            $Result.Languages | Should -Be @('en-US', 'fr-FR')
            $Result.Files | Should -Be 6
        }

        It 'Refuses a download that is not the package pinned, and extracts nothing' {
            $script:Download = Join-Path $TestDrive 'other.msi'
            [System.IO.File]::WriteAllBytes($script:Download, [byte[]](200..1))
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            { Install-PSGPOAdmx -Path $Path -UICulture en-US -Confirm:$false } | Should -Throw '*download of https://download.microsoft.com/*is not the package HGPM pins*SHA-256*nothing is installed*'
            Should -Invoke Expand-PSGPOAdmxMsi -Times 0 -Exactly
            Test-Path -LiteralPath $Path | Should -BeFalse
        }

        It 'Installs from -MsiPath without downloading, and refuses another file' {
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            $Result = Install-PSGPOAdmx -Path $Path -UICulture en-US -MsiPath $script:PackageFile -Confirm:$false
            $Result.Files | Should -Be 4
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            $Other = Join-Path $TestDrive 'other-copy.msi'
            [System.IO.File]::WriteAllBytes($Other, [byte[]](1..199))
            { Install-PSGPOAdmx -Path (Join-Path $TestDrive 'never') -MsiPath $Other -Confirm:$false } | Should -Throw "*other-copy.msi' is not the package HGPM pins*"
            { Install-PSGPOAdmx -Path (Join-Path $TestDrive 'never') -MsiPath (Join-Path $TestDrive 'missing.msi') -Confirm:$false } | Should -Throw "*No file*missing.msi*Administrative Templates.msi*"
            Test-Path -LiteralPath (Join-Path $TestDrive 'never') | Should -BeFalse
        }

        It 'Refuses a package whose files are not those pinned, and installs nothing' {
            $Tampered = Join-Path $TestDrive 'tampered'
            New-TestPolicyDefinitions -Path $Tampered -Culture 'en-US', 'fr-fr'
            [System.IO.File]::WriteAllText((Join-Path $Tampered 'Two.admx'), "<policyDefinitions>changed</policyDefinitions>`n")
            $script:Extracted = $Tampered
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            { Install-PSGPOAdmx -Path $Path -UICulture en-US -Confirm:$false } | Should -Throw '*does not hold the ADMX files HGPM pins*.admx files differ*nothing is installed*'
            Test-Path -LiteralPath $Path | Should -BeFalse
        }

        It 'Refuses a package without a language asked for' {
            $Partial = Join-Path $TestDrive 'partial'
            New-TestPolicyDefinitions -Path $Partial -Culture 'en-US'
            $script:Extracted = $Partial
            { Install-PSGPOAdmx -Path (Join-Path $TestDrive 'never') -UICulture fr-FR -Confirm:$false } | Should -Throw '*none of the fr-FR .adml files*'
        }

        It 'Keeps the ADMX files already there unless -Force, then keeps those of other products' {
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            $null = New-Item -ItemType Directory -Path $Path
            [System.IO.File]::WriteAllText((Join-Path $Path 'Vendor.admx'), '<policyDefinitions/>')
            { Install-PSGPOAdmx -Path $Path -UICulture en-US -Confirm:$false } | Should -Throw '*already in*-Force*'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            $null = Install-PSGPOAdmx -Path $Path -UICulture en-US -Force -Confirm:$false
            @(Get-ChildItem -LiteralPath $Path -File -Filter '*.admx').Name | Sort-Object | Should -Be @('One.admx', 'Two.admx', 'Vendor.admx')
        }

        It 'Downloads nothing with -WhatIf' {
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            Install-PSGPOAdmx -Path $Path -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            Test-Path -LiteralPath $Path | Should -BeFalse
        }

        It 'Says to give the package with -MsiPath when it cannot be downloaded' {
            Mock Invoke-WebRequest { throw 'No such host is known.' }
            { Install-PSGPOAdmx -Path (Join-Path $TestDrive 'never') -Confirm:$false } | Should -Throw '*Cannot download https://download.microsoft.com/*No such host*details.aspx?id=1*-MsiPath*'
        }

        It 'Writes the central store of the domain controller, and the audit log' {
            $Directory = [GPOToolsLdapDirectory]::new('hardenbox.labo', 'DC=hardenbox,DC=labo', 'dc.hardenbox.labo', 'Samba AD')
            Mock Test-PSGPOAdmxCentralStore { $false }
            Mock Copy-PSGPOAdmxCentralStore {
                $script:Copied = @(Get-ChildItem -LiteralPath $Source -File -Recurse | ForEach-Object { $_.FullName.Substring($Source.Length + 1) -replace '\\', '/' } | Sort-Object)
                '\\dc.hardenbox.labo\SYSVOL\hardenbox.labo\Policies\PolicyDefinitions'
            }
            Mock Write-PSGPOAuditEntry { }
            $Result = Install-PSGPOAdmx -CentralStore -Directory $Directory -UICulture en-US, fr-FR -Confirm:$false
            $Result.Path | Should -Be '\\dc.hardenbox.labo\SYSVOL\hardenbox.labo\Policies\PolicyDefinitions'
            $script:Copied | Should -Be @('en-US/One.adml', 'en-US/Two.adml', 'fr-FR/One.adml', 'fr-FR/Two.adml', 'One.admx', 'Two.admx')
            Should -Invoke Write-PSGPOAuditEntry -Times 1 -Exactly -ParameterFilter { $Action -eq 'InstallAdmx' -and $Details.Files -eq 6 -and $Details.Package -eq $script:Pin.Name -and $Details.Sha256 -eq $script:Pin.Sha256 }
        }

        It 'Keeps the central store that has ADMX files unless -Force' {
            $Directory = [GPOToolsLdapDirectory]::new('hardenbox.labo', 'DC=hardenbox,DC=labo', 'dc.hardenbox.labo', 'Samba AD')
            Mock Test-PSGPOAdmxCentralStore { $true }
            Mock Copy-PSGPOAdmxCentralStore { }
            { Install-PSGPOAdmx -CentralStore -Directory $Directory -Confirm:$false } | Should -Throw '*central store of hardenbox.labo has ADMX files*-Force*'
            Should -Invoke Copy-PSGPOAdmxCentralStore -Times 0 -Exactly
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'Refuses the central store of a domain that is not read from a domain controller' {
            $Directory = [GPOToolsDirectory]::new('hardenbox.labo')
            { Install-PSGPOAdmx -CentralStore -Directory $Directory -Confirm:$false } | Should -Throw '*central store is in SYSVOL*'
        }
    }

    Describe 'ADMX folders found' {
        It 'Finds the files of Install-PSGPOAdmx in the data folder of the user' {
            $Data = @(Get-PSGPOAdmxInstallFolder)[-1]
            Mock Get-PSGPOAdmxInstallFolder { (Join-Path $TestDrive 'module-admx'), (Join-Path $TestDrive 'data-admx') }
            Copy-Item -LiteralPath $script:Source -Destination (Join-Path $TestDrive 'data-admx') -Recurse
            Mock Get-PSGPOUserSetting { [pscustomobject]@{ PolicyDefinitions = $null } }
            @(Get-PSGPOAdmxCandidate) | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'data-admx')))
            $Data | Should -BeLike '*PSGPOTools*PolicyDefinitions'
        }
    }
}
