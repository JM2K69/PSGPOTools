#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Test-PSGPOUpdate: the version loaded compared with those of the PowerShell Gallery, as semantic
# versions; the Gallery (Find-PSResource, Get-InstalledPSResource) is mocked.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    Describe 'Semantic versions' {
        It 'Puts a prerelease before its release, and sorts the prereleases by their label' {
            $alpha = ConvertTo-PSGPOSemanticVersion -Version '0.1.4' -Prerelease 'alpha'
            $alpha.ToString() | Should -Be '0.1.4-alpha'
            $alpha -lt (ConvertTo-PSGPOSemanticVersion -Version '0.1.4' -Prerelease 'beta') | Should -BeTrue
            (ConvertTo-PSGPOSemanticVersion -Version '0.1.4' -Prerelease 'beta') -lt (ConvertTo-PSGPOSemanticVersion -Version '0.1.4') | Should -BeTrue
            (ConvertTo-PSGPOSemanticVersion -Version '0.1.3') -lt $alpha | Should -BeTrue
            (ConvertTo-PSGPOSemanticVersion -Version '1.2' -Prerelease '').ToString() | Should -Be '1.2.0'
        }

        It 'Reads the version of the module loaded, with its prerelease label' {
            $Manifest = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1')
            $Expected = $Manifest.ModuleVersion + $(if ($Manifest.PrivateData.PSData.Prerelease) { "-$($Manifest.PrivateData.PSData.Prerelease)" })
            (Get-PSGPOModuleVersion).Version.ToString() | Should -Be $Expected
        }
    }

    Describe 'Test-PSGPOUpdate' {
        BeforeEach {
            # The version loaded, and what the Gallery publishes.
            $script:Installed = '0.1.4-alpha'
            $script:Published = @([pscustomobject]@{ Version = [version]'0.1.4'; Prerelease = 'beta'; PublishedDate = [datetime]'2026-11-02'; ReleaseNotes = 'https://jm2k69.github.io/PSGPOTools/en/changelog/' })
            Mock Get-PSGPOModuleVersion { [pscustomobject]@{ Version = [semver]$script:Installed; Path = 'C:\Users\me\Documents\PowerShell\Modules\HGPM\0.1.4' } }
            Mock Find-PSResource { $script:Published | Where-Object { $Prerelease -or -not $_.Prerelease } }
            Mock Get-InstalledPSResource { [pscustomobject]@{ Name = 'HGPM'; InstalledLocation = 'C:\Users\me\Documents\PowerShell\Modules' } }
        }

        It 'Finds a newer prerelease, and gives the command that updates the module' {
            $Result = Test-PSGPOUpdate
            $Result.PSObject.TypeNames[0] | Should -Be 'PSGPOTools.Update'
            $Result.InstalledVersion | Should -Be '0.1.4-alpha'
            $Result.LatestVersion | Should -Be '0.1.4-beta'
            $Result.UpdateAvailable | Should -BeTrue
            $Result.UpdateCommand | Should -Be 'Update-PSResource -Name HGPM -Prerelease'
            $Result.Published | Should -Be ([datetime]'2026-11-02')
            Should -Invoke Find-PSResource -Times 1 -Exactly -ParameterFilter { $Name -eq 'HGPM' -and $Repository -eq 'PSGallery' -and $Prerelease }
            Test-PSGPOUpdate -Quiet | Should -BeTrue
        }

        It 'Says when the version loaded is the latest, or newer than the Gallery' {
            $script:Installed = '0.1.4-beta'
            $Result = Test-PSGPOUpdate
            $Result.UpdateAvailable | Should -BeFalse
            $Result.UpdateCommand | Should -BeNullOrEmpty
            $script:Installed = '0.2.0-alpha'
            Test-PSGPOUpdate -Quiet | Should -BeFalse
        }

        It 'Compares a stable version with the stable ones only, unless -Prerelease' {
            $script:Installed = '0.1.3'
            $script:Published += [pscustomobject]@{ Version = [version]'0.1.3'; Prerelease = $null; PublishedDate = [datetime]'2026-10-01'; ReleaseNotes = '' }
            (Test-PSGPOUpdate).LatestVersion | Should -Be '0.1.3'
            Test-PSGPOUpdate -Quiet | Should -BeFalse
            $Result = Test-PSGPOUpdate -Prerelease
            $Result.LatestVersion | Should -Be '0.1.4-beta'
            $Result.UpdateAvailable | Should -BeTrue
        }

        It 'Installs from the Gallery a module that was not installed from it' {
            Mock Get-InstalledPSResource { }
            (Test-PSGPOUpdate).UpdateCommand | Should -Be 'Install-PSResource -Name HGPM -Prerelease'
            Mock Get-InstalledPSResource { throw 'no store' }
            (Test-PSGPOUpdate -Repository Internal).UpdateCommand | Should -Be 'Install-PSResource -Name HGPM -Prerelease -Repository Internal'
        }

        It 'Says why the Gallery cannot be read' {
            Mock Find-PSResource { throw 'No such host is known.' }
            { Test-PSGPOUpdate } | Should -Throw -ExpectedMessage 'The repository PSGallery cannot be read*No such host is known.'
            Mock Find-PSResource { }
            { Test-PSGPOUpdate } | Should -Throw -ExpectedMessage 'HGPM is not published in the repository PSGallery.'
        }
    }

    Describe 'At the import of the module' {
        BeforeEach {
            $script:Cache = Join-Path $TestDrive 'UpdateCheck.json'
            Remove-Item -LiteralPath $script:Cache -ErrorAction SilentlyContinue
            $script:Skip = $env:PSGPOTOOLS_SKIP_UPDATE_CHECK
            $env:PSGPOTOOLS_SKIP_UPDATE_CHECK = $null
            $script:Installed = '0.1.5-alpha'
            $script:Gallery = @([semver]'0.1.4-alpha', [semver]'0.1.6-alpha', [semver]'0.1.3')
            Mock Get-PSGPOUpdateCheckPath { $script:Cache }
            Mock Get-PSGPOModuleVersion { [pscustomobject]@{ Version = [semver]$script:Installed; Path = 'C:\Users\me\Documents\PowerShell\Modules\HGPM\0.1.5' } }
            Mock Get-PSGPOGalleryVersion { $script:Gallery }
            Mock Get-InstalledPSResource { [pscustomobject]@{ Name = 'HGPM'; InstalledLocation = 'C:\Users\me\Documents\PowerShell\Modules' } }
            Mock Test-PSGPOUpdateCheckSkipped { $false }
        }
        AfterEach { $env:PSGPOTOOLS_SKIP_UPDATE_CHECK = $script:Skip }

        It 'Gives the version, and the command that installs a newer one' {
            $Message = @(Write-PSGPOImportBanner 6>&1).MessageData -join "`n"
            $Message | Should -BeLike "HGPM 0.1.5-alpha`nHGPM 0.1.6-alpha is available on the PowerShell Gallery: Update-PSResource -Name HGPM -Prerelease, then open a new PowerShell session.*"
        }

        It 'Reads the Gallery once a day, and keeps its answer' {
            $null = Write-PSGPOImportBanner 6>&1
            $null = Write-PSGPOImportBanner 6>&1
            Should -Invoke Get-PSGPOGalleryVersion -Times 1 -Exactly
            $Kept = Get-Content -LiteralPath $script:Cache -Raw | ConvertFrom-Json
            $Kept.Latest | Should -Be '0.1.6-alpha'
            $Kept.LatestStable | Should -Be '0.1.3'
            # A day later, the Gallery is read again.
            $Kept.Checked = [datetime]::UtcNow.AddDays(-2).ToString('o')
            Set-Content -LiteralPath $script:Cache -Value ($Kept | ConvertTo-Json)
            $null = Write-PSGPOImportBanner 6>&1
            Should -Invoke Get-PSGPOGalleryVersion -Times 2 -Exactly
        }

        It 'Compares a stable version with the stable ones only' {
            $script:Installed = '0.1.3'
            @(Write-PSGPOImportBanner 6>&1).MessageData | Should -Be 'HGPM 0.1.3'
        }

        It 'Gives the version only when the Gallery cannot be read, or the check is skipped' {
            Mock Get-PSGPOGalleryVersion { throw 'No such host is known.' }
            @(Write-PSGPOImportBanner 6>&1).MessageData | Should -Be 'HGPM 0.1.5-alpha'
            Mock Get-PSGPOGalleryVersion { $script:Gallery }
            Mock Test-PSGPOUpdateCheckSkipped { $true }
            @(Write-PSGPOImportBanner 6>&1).MessageData | Should -Be 'HGPM 0.1.5-alpha'
            Should -Invoke Get-PSGPOGalleryVersion -Times 1 -Exactly -Because 'only the read that failed, none once skipped'
        }

        It 'Never fails the import' {
            Mock Get-PSGPOModuleVersion { throw 'unreadable manifest' }
            { Write-PSGPOImportBanner 6>$null } | Should -Not -Throw
        }
    }

    Describe 'When the import reads the Gallery' {
        BeforeEach { $script:Skip = $env:PSGPOTOOLS_SKIP_UPDATE_CHECK }
        AfterEach { $env:PSGPOTOOLS_SKIP_UPDATE_CHECK = $script:Skip }

        It 'Skips the check with PSGPOTOOLS_SKIP_UPDATE_CHECK=1, and in a CI' {
            $env:PSGPOTOOLS_SKIP_UPDATE_CHECK = '1'
            Test-PSGPOUpdateCheckSkipped | Should -BeTrue
            $env:PSGPOTOOLS_SKIP_UPDATE_CHECK = $null
            $ci = $env:CI
            try { $env:CI = 'true'; Test-PSGPOUpdateCheckSkipped | Should -BeTrue } finally { $env:CI = $ci }
        }
    }
}
