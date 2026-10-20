#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The ADMX files of the repository downloaded from GitHub (PSGPOAdmxInstall.ps1, Install-PSGPOAdmx):
# the catalog that pins them, the hash of a set of files, the languages chosen, and the install
# from an archive like the one of GitHub (the download mocked), into a folder or the central store.
# The copy into a real SYSVOL is tested in PSGPOTools.Ldap.tests.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $Sources = Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions'
        # A small PolicyDefinitions folder: two .admx files, en-US and fr-FR.
        function New-TestPolicyDefinitions {
            param([string]$Path)
            $null = New-Item -ItemType Directory -Path (Join-Path $Path 'en-US'), (Join-Path $Path 'fr-FR') -Force
            foreach ($Name in 'One', 'Two') {
                [System.IO.File]::WriteAllText((Join-Path $Path "$Name.admx"), "<policyDefinitions>`n  <!-- $Name -->`n</policyDefinitions>`n")
                foreach ($Culture in 'en-US', 'fr-FR') { [System.IO.File]::WriteAllText((Join-Path $Path $Culture "$Name.adml"), "<policyDefinitionResources culture='$Culture'>$Name</policyDefinitionResources>`n") }
            }
        }
        # A zip as GitHub serves the archive of a ref: <repository>-<ref>/sources/PolicyDefinitions/...
        function New-TestArchive {
            param([string]$PolicyDefinitions, [string]$Path)
            $Root = Join-Path $TestDrive "archive-$([guid]::NewGuid().ToString('N'))"
            $Target = Join-Path $Root 'PSGPOTools-0.1.2-alpha' 'sources'
            $null = New-Item -ItemType Directory -Path $Target -Force
            Copy-Item -LiteralPath $PolicyDefinitions -Destination (Join-Path $Target 'PolicyDefinitions') -Recurse
            $null = New-Item -ItemType File -Path (Join-Path $Root 'PSGPOTools-0.1.2-alpha' 'README.md') -Force
            [System.IO.Compression.ZipFile]::CreateFromDirectory($Root, $Path)
            $Path
        }
        $script:Source = Join-Path $TestDrive 'source'
        New-TestPolicyDefinitions -Path $script:Source
        $script:Catalog = @(Get-PSGPOAdmxSet -Path $script:Source)
        $script:Archive = New-TestArchive -PolicyDefinitions $script:Source -Path (Join-Path $TestDrive 'good.zip')
    }

    Describe 'Catalog of the ADMX files' {
        It 'Pins the files of sources/PolicyDefinitions (CI/Update-AdmxCatalog.ps1 run after a change of them)' {
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
        }

        It 'Gives a set the same hash with CR LF or LF, and whatever the case of the names' {
            $Lf = Join-Path $TestDrive 'lf'
            $Crlf = Join-Path $TestDrive 'crlf'
            $null = New-Item -ItemType Directory -Path $Lf, $Crlf -Force
            [System.IO.File]::WriteAllText((Join-Path $Lf 'AppHVSI.admx'), "<a>`n<b/>`n</a>`n")
            [System.IO.File]::WriteAllText((Join-Path $Crlf 'apphvsi.admx'), "<a>`r`n<b/>`r`n</a>`r`n")
            Get-PSGPOAdmxSetHash -File (Get-ChildItem -LiteralPath $Crlf -File) | Should -Be (Get-PSGPOAdmxSetHash -File (Get-ChildItem -LiteralPath $Lf -File))
            [System.IO.File]::WriteAllText((Join-Path $Crlf 'apphvsi.admx'), "<a>`r`n<c/>`r`n</a>`r`n")
            Get-PSGPOAdmxSetHash -File (Get-ChildItem -LiteralPath $Crlf -File) | Should -Not -Be (Get-PSGPOAdmxSetHash -File (Get-ChildItem -LiteralPath $Lf -File))
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

    Describe 'Install-PSGPOAdmx' {
        BeforeAll {
            Mock Get-PSGPOAdmxCatalog { $script:Catalog }
            Mock Invoke-WebRequest { Copy-Item -LiteralPath $script:Download -Destination $OutFile }
            $script:Download = $script:Archive
        }
        BeforeEach { $script:Download = $script:Archive }

        It 'Installs the .admx files and the languages asked for, from the tag of the version' {
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            $Result = Install-PSGPOAdmx -Path $Path -UICulture fr-FR -Confirm:$false
            $Result.Path | Should -Be ([System.IO.Path]::GetFullPath($Path))
            $Result.Languages | Should -Be @('fr-FR')
            $Result.Files | Should -Be 4
            $Result.Ref | Should -BeLike 'v*-alpha'
            @(Get-ChildItem -LiteralPath $Path -File -Filter '*.admx').Name | Sort-Object | Should -Be @('One.admx', 'Two.admx')
            Test-Path -LiteralPath (Join-Path $Path 'fr-FR' 'One.adml') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $Path 'en-US') | Should -BeFalse -Because 'only the languages asked for'
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://github.com/JM2K69/PSGPOTools/archive/$($Result.Ref).zip" }
        }

        It 'Installs every language with -AllLanguages, from the ref given' {
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            $Result = Install-PSGPOAdmx -Path $Path -AllLanguages -Ref master -Confirm:$false
            $Result.Languages | Should -Be @('en-US', 'fr-FR')
            $Result.Files | Should -Be 6
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://github.com/JM2K69/PSGPOTools/archive/master.zip' }
        }

        It 'Refuses a download that is not the files pinned, and installs nothing' {
            $Tampered = Join-Path $TestDrive 'tampered'
            New-TestPolicyDefinitions -Path $Tampered
            [System.IO.File]::WriteAllText((Join-Path $Tampered 'Two.admx'), "<policyDefinitions>changed</policyDefinitions>`n")
            $script:Download = New-TestArchive -PolicyDefinitions $Tampered -Path (Join-Path $TestDrive 'tampered.zip')
            $Path = Join-Path $TestDrive "folder-$([guid]::NewGuid().ToString('N'))"
            { Install-PSGPOAdmx -Path $Path -UICulture en-US -Confirm:$false } | Should -Throw '*not the ADMX files of this version*.admx files differ*nothing is installed*'
            Test-Path -LiteralPath $Path | Should -BeFalse
        }

        It 'Refuses a download without a language asked for' {
            $Partial = Join-Path $TestDrive 'partial'
            New-TestPolicyDefinitions -Path $Partial
            Remove-Item -LiteralPath (Join-Path $Partial 'fr-FR') -Recurse
            $script:Download = New-TestArchive -PolicyDefinitions $Partial -Path (Join-Path $TestDrive 'partial.zip')
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

        It 'Says to give a branch when the tag of the version cannot be downloaded' {
            Mock Invoke-WebRequest { throw 'Response status code does not indicate success: 404 (Not Found).' }
            { Install-PSGPOAdmx -Path (Join-Path $TestDrive 'never') -Confirm:$false } | Should -Throw '*404*-Ref master*'
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
            Should -Invoke Write-PSGPOAuditEntry -Times 1 -Exactly -ParameterFilter { $Action -eq 'InstallAdmx' -and $Details.Files -eq 6 }
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
