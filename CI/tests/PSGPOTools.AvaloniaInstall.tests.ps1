#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The Avalonia runtime installed on first use: the pinned packages, where the runtime goes, and
# the checks of a download. nuget.org is not reached: Invoke-WebRequest serves local packages.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'PSGPOTools.psd1'
    Get-Module PSGPOTools | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName PSGPOTools {
    BeforeAll {
        # A package of the test: a zip with the given entries, and its SHA-512 as NuGet gives it.
        function New-TestPackage {
            param([string]$Id, [hashtable]$Entries)
            $Folder = Join-Path $TestDrive "pkg-$Id-$([guid]::NewGuid())"
            foreach ($Name in $Entries.Keys) {
                $Path = Join-Path $Folder $Name
                $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
                Set-Content -LiteralPath $Path -Value $Entries[$Name]
            }
            $Zip = Join-Path $TestDrive "$Id.$([guid]::NewGuid()).nupkg.zip"
            Compress-Archive -Path (Join-Path $Folder '*') -DestinationPath $Zip
            [pscustomobject]@{ Path = $Zip; Sha512 = [Convert]::ToBase64String([System.Security.Cryptography.SHA512]::HashData([System.IO.File]::ReadAllBytes($Zip))) }
        }
    }
    Describe 'Avalonia runtime' {
    AfterEach {
        $script:PSGPOAvaloniaPackages = $null
        $env:PSGPOTOOLS_AVALONIA_NO_DOWNLOAD = $null
    }

    Describe 'Pinned packages of the Avalonia runtime' {
        It 'Has, for each runtime, Avalonia, its windowing backend and its native rendering libraries, each with its SHA-512' {
            $Packages = @(Get-PSGPOAvaloniaPackage)
            foreach ($Package in $Packages) { $Package.Sha512 | Should -Match '^[A-Za-z0-9+/]{86}==$' }
            $Backend = @{ 'win-x64' = 'Avalonia.Win32'; 'win-arm64' = 'Avalonia.Win32'; 'linux-x64' = 'Avalonia.X11'; 'linux-arm64' = 'Avalonia.X11'; osx = 'Avalonia.Native' }
            foreach ($Rid in $Backend.Keys) {
                $Ids = @($Packages | Where-Object { $_.Rids -contains $Rid }).Id
                $Ids | Should -Contain 'Avalonia'
                $Ids | Should -Contain 'Avalonia.Markup.Xaml.Loader'
                $Ids | Should -Contain $Backend[$Rid]
                @($Ids | Where-Object { $_ -like 'SkiaSharp.NativeAssets.*' }).Count | Should -Be 1 -Because "$Rid draws with Skia"
                @($Ids | Where-Object { $_ -like 'HarfBuzzSharp.NativeAssets.*' }).Count | Should -Be 1
            }
        }

        It 'Looks for the runtime in the module, then in the data folder of the user' {
            $Folders = @(Get-PSGPOAvaloniaFolder -Rid linux-x64)
            $Folders[0] | Should -Be (Join-Path $PSScriptRoot '..' '..' 'PSGPOTools' 'Avalonia' 'bin' 'linux-x64' | ForEach-Object { [System.IO.Path]::GetFullPath($_) })
            $Folders[1] | Should -BeLike "*PSGPOTools*Avalonia*11.2.3*linux-x64"
            $Empty = Join-Path $TestDrive 'empty'
            $Full = Join-Path $TestDrive 'full'
            $null = New-Item -ItemType Directory -Path $Empty, $Full -Force
            Set-Content -LiteralPath (Join-Path $Full 'Avalonia.dll') -Value ''
            Mock Get-PSGPOAvaloniaFolder { $Empty; $Full }
            Get-PSGPOAvaloniaPath -Rid linux-x64 | Should -Be $Full
        }
    }

    Describe 'Install of the Avalonia runtime' {
        BeforeEach {
            $Managed = New-TestPackage 'Test.Managed' @{ 'lib/net8.0/Test.Managed.dll' = 'managed'; 'lib/netstandard2.0/Old.dll' = 'old' }
            $Native = New-TestPackage 'Test.Native' @{ 'runtimes/linux-x64/native/libtest.so' = 'native'; 'runtimes/win-x64/native/test.dll' = 'windows' }
            $Served = @{ 'test.managed' = $Managed.Path; 'test.native' = $Native.Path }
            $script:PSGPOAvaloniaPackages = [pscustomobject]@{ Packages = @(
                    [pscustomobject]@{ Id = 'Test.Managed'; Version = '1.0.0'; Assets = 'Managed'; Rids = @('linux-x64'); Sha512 = $Managed.Sha512 }
                    [pscustomobject]@{ Id = 'Test.Native'; Version = '1.0.0'; Assets = 'Native'; Rids = @('linux-x64'); Sha512 = $Native.Sha512 }
                    [pscustomobject]@{ Id = 'Avalonia'; Version = '11.2.3'; Assets = 'Managed'; Rids = @('osx'); Sha512 = 'x' }) }
            Mock Invoke-WebRequest {
                $Id = ([uri]$Uri).Segments[2].TrimEnd('/')
                Copy-Item -LiteralPath $Served[$Id] -Destination $OutFile
            }
        }

        It 'Downloads the packages of the runtime, and puts their .NET 8 assemblies and native libraries in place' {
            $Destination = Join-Path $TestDrive 'runtime' 'linux-x64'
            Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination $Destination | Should -Be $Destination
            @(Get-ChildItem -LiteralPath $Destination -File).Name | Sort-Object | Should -Be @('libtest.so', 'packages.json', 'Test.Managed.dll')
            (Get-Content -LiteralPath (Join-Path $Destination 'packages.json') -Raw | ConvertFrom-Json).Id | Should -Be @('Test.Managed', 'Test.Native')
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Uri -like 'https://api.nuget.org/v3-flatcontainer/test.*/1.0.0/test.*.1.0.0.nupkg' }
            # Already there: nothing is downloaded again.
            $null = Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination $Destination
            Set-Content -LiteralPath (Join-Path $Destination 'Avalonia.dll') -Value ''
            $null = Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination $Destination
            Should -Invoke Invoke-WebRequest -Times 4 -Exactly
        }

        It 'Installs nothing when a package is not the one pinned' {
            $script:PSGPOAvaloniaPackages.Packages[1].Sha512 = $Managed.Sha512
            $Destination = Join-Path $TestDrive 'tampered' 'linux-x64'
            { Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination $Destination } | Should -Throw -ExpectedMessage '*Test.Native 1.0.0*SHA-512 differs*nothing is installed*'
            Test-Path -LiteralPath $Destination | Should -BeFalse
        }

        It 'Downloads nothing when PSGPOTOOLS_AVALONIA_NO_DOWNLOAD is 1, and says how to install it' {
            $env:PSGPOTOOLS_AVALONIA_NO_DOWNLOAD = '1'
            { Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination (Join-Path $TestDrive 'none') } | Should -Throw -ExpectedMessage '*Get-AvaloniaBinaries.ps1 -Rid linux-x64*'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
    }
    }
}
