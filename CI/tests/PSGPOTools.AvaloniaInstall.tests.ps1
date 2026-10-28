#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The Avalonia runtime installed on first use: the pinned packages and files, where the runtime
# goes, where the packages come from (nuget.org, a feed, a folder), and the checks of a download and
# of a runtime installed. nuget.org is not reached: Invoke-WebRequest serves local packages.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        # A package of the test: a zip with the given entries, its SHA-512 as NuGet gives it, and
        # the SHA-256 of each entry by its name (as the files of a runtime are pinned).
        function New-TestPackage {
            param([string]$Id, [hashtable]$Entries)
            $Folder = Join-Path $TestDrive "pkg-$Id-$([guid]::NewGuid())"
            $Hashes = @{}
            foreach ($Name in $Entries.Keys) {
                $Path = Join-Path $Folder $Name
                $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
                Set-Content -LiteralPath $Path -Value $Entries[$Name]
                $Hashes[(Split-Path -Leaf $Name)] = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path)))
            }
            $Zip = Join-Path $TestDrive "$Id.$([guid]::NewGuid()).nupkg.zip"
            Compress-Archive -Path (Join-Path $Folder '*') -DestinationPath $Zip
            [pscustomobject]@{ Path = $Zip; Sha512 = [Convert]::ToBase64String([System.Security.Cryptography.SHA512]::HashData([System.IO.File]::ReadAllBytes($Zip))); Hashes = $Hashes }
        }
    }
    Describe 'Avalonia runtime' {
    AfterEach {
        $script:PSGPOAvaloniaPackages = $null
        $env:PSGPOTOOLS_AVALONIA_NO_DOWNLOAD = $null
        $env:PSGPOTOOLS_NUGET_SOURCE = $null
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

        It 'Pins each file of each runtime, the libraries the console loads included' {
            $Data = Get-PSGPOAvaloniaPackageData
            foreach ($Rid in 'win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx') {
                $Files = Get-PSGPOAvaloniaFileHash -Rid $Rid
                $Files.Count | Should -BeGreaterThan 20 -Because "$Rid has its runtime pinned"
                foreach ($Hash in $Files.Values) { $Hash | Should -Match '^[0-9A-F]{64}$' }
                $Files.Keys | Should -Contain 'Avalonia.dll'
                $Files.Keys | Should -Contain 'Avalonia.Markup.Xaml.Loader.dll'
            }
            (Get-PSGPOAvaloniaFileHash -Rid 'win-x64').Keys | Should -Contain 'Avalonia.Win32.dll'
            (Get-PSGPOAvaloniaFileHash -Rid 'win-x64').Keys | Should -Contain 'libSkiaSharp.dll'
            (Get-PSGPOAvaloniaFileHash -Rid 'linux-x64').Keys | Should -Contain 'Avalonia.X11.dll'
            (Get-PSGPOAvaloniaFileHash -Rid 'linux-x64').Keys | Should -Contain 'libSkiaSharp.so'
            @($Data.Files.PSObject.Properties.Name) | Should -Be @('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'osx')
        }

        It 'Looks for the runtime in the module, then in the data folder of the user' {
            $Folders = @(Get-PSGPOAvaloniaFolder -Rid linux-x64)
            $Folders[0] | Should -Be (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Avalonia' 'bin' 'linux-x64' | ForEach-Object { [System.IO.Path]::GetFullPath($_) })
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
            $script:PSGPOAvaloniaPackages = [pscustomobject]@{
                Packages = @(
                    [pscustomobject]@{ Id = 'Test.Managed'; Version = '1.0.0'; Assets = 'Managed'; Rids = @('linux-x64'); Sha512 = $Managed.Sha512 }
                    [pscustomobject]@{ Id = 'Test.Native'; Version = '1.0.0'; Assets = 'Native'; Rids = @('linux-x64'); Sha512 = $Native.Sha512 }
                    [pscustomobject]@{ Id = 'Avalonia'; Version = '11.2.3'; Assets = 'Managed'; Rids = @('osx'); Sha512 = 'x' })
                Files = [pscustomobject]@{ 'linux-x64' = [pscustomobject]@{ 'Test.Managed.dll' = $Managed.Hashes['Test.Managed.dll']; 'libtest.so' = $Native.Hashes['libtest.so'] } }
            }
            Mock Invoke-WebRequest {
                $Id = ([uri]$Uri).Segments[-3].TrimEnd('/')
                Copy-Item -LiteralPath $Served[$Id] -Destination $OutFile
            }
            Mock Start-Sleep { }
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
            { Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination (Join-Path $TestDrive 'none') } | Should -Throw -ExpectedMessage '*offline package of the release*Get-AvaloniaBinaries.ps1 -Rid linux-x64*'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'Installs nothing when a file of the runtime is not the one pinned' {
            $script:PSGPOAvaloniaPackages.Files.'linux-x64'.'Test.Managed.dll' = '0' * 64
            $Destination = Join-Path $TestDrive 'files' 'linux-x64'
            { Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination $Destination } | Should -Throw -ExpectedMessage '*not the one HGPM pinned (Test.Managed.dll differs)*'
            Test-Path -LiteralPath $Destination | Should -BeFalse
        }

        It 'Takes the packages from a folder of PSGPOTOOLS_NUGET_SOURCE, flat or as a feed lays them out, whatever their case' {
            $Mirror = Join-Path $TestDrive 'mirror'
            $null = New-Item -ItemType Directory -Path (Join-Path $Mirror 'test.native' '1.0.0') -Force
            Copy-Item -LiteralPath $Managed.Path -Destination (Join-Path $Mirror 'Test.Managed.1.0.0.nupkg')
            Copy-Item -LiteralPath $Native.Path -Destination (Join-Path $Mirror 'test.native' '1.0.0' 'test.native.1.0.0.nupkg')
            $env:PSGPOTOOLS_NUGET_SOURCE = $Mirror
            $Destination = Join-Path $TestDrive 'from-folder' 'linux-x64'
            Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination $Destination | Should -Be $Destination
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            Remove-Item -LiteralPath (Join-Path $Mirror 'Test.Managed.1.0.0.nupkg')
            { Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination (Join-Path $TestDrive 'missing' 'linux-x64') } | Should -Throw -ExpectedMessage "*Test.Managed 1.0.0 is not in $Mirror (test.managed.1.0.0.nupkg)*"
        }

        It 'Takes the packages from the feed of PSGPOTOOLS_NUGET_SOURCE, its base address read from its index' {
            $env:PSGPOTOOLS_NUGET_SOURCE = 'https://nuget.corp.example/v3/index.json'
            Mock Invoke-RestMethod { [pscustomobject]@{ resources = @([pscustomobject]@{ '@id' = 'https://nuget.corp.example/flat/'; '@type' = 'PackageBaseAddress/3.0.0' }) } }
            $null = Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination (Join-Path $TestDrive 'from-feed' 'linux-x64')
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Uri -like 'https://nuget.corp.example/flat/test.*/1.0.0/test.*.1.0.0.nupkg' -and $TimeoutSec -eq 120 }
        }

        It 'Tries a download three times, then says from where it failed' {
            Mock Invoke-WebRequest { throw 'The operation has timed out.' }
            { Install-PSGPOAvaloniaRuntime -Rid linux-x64 -Destination (Join-Path $TestDrive 'timeout' 'linux-x64') } |
                Should -Throw -ExpectedMessage '*Test.Managed 1.0.0 cannot be downloaded from https://api.nuget.org/v3-flatcontainer/: The operation has timed out.*'
            Should -Invoke Invoke-WebRequest -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 2 -Exactly
        }
    }

    Describe 'Runtime checked before it is loaded' {
        BeforeEach {
            $Runtime = Join-Path $TestDrive "runtime-$([guid]::NewGuid())"
            $null = New-Item -ItemType Directory -Path $Runtime
            [System.IO.File]::WriteAllText((Join-Path $Runtime 'Avalonia.dll'), 'assembly')
            [System.IO.File]::WriteAllText((Join-Path $Runtime 'libSkiaSharp.so'), 'native')
            $Hash = { param($Text) [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))) }
            $script:PSGPOAvaloniaPackages = [pscustomobject]@{
                Packages = @()
                Files = [pscustomobject]@{ 'linux-x64' = [pscustomobject]@{ 'Avalonia.dll' = (& $Hash 'assembly'); 'libSkiaSharp.so' = (& $Hash 'native') } }
            }
        }

        It 'Accepts the files pinned, and what is not a library next to them' {
            [System.IO.File]::WriteAllText((Join-Path $Runtime 'packages.json'), '[]')
            { Assert-PSGPOAvaloniaRuntime -Path $Runtime -Rid linux-x64 } | Should -Not -Throw
        }

        It 'Refuses a file changed, a file missing, and another library next to them' {
            [System.IO.File]::WriteAllText((Join-Path $Runtime 'Avalonia.dll'), 'patched')
            Remove-Item -LiteralPath (Join-Path $Runtime 'libSkiaSharp.so')
            [System.IO.File]::WriteAllText((Join-Path $Runtime 'Avalonia.Extra.dll'), 'loaded by probing')
            { Assert-PSGPOAvaloniaRuntime -Path $Runtime -Rid linux-x64 } |
                Should -Throw -ExpectedMessage "The Avalonia runtime in $Runtime is not the one HGPM pinned (Avalonia.dll differs; libSkiaSharp.so is missing; Avalonia.Extra.dll is not part of it): nothing of it is loaded.*"
        }

        It 'Refuses a runtime whose files are not pinned' {
            { Assert-PSGPOAvaloniaRuntime -Path $Runtime -Rid osx } | Should -Throw -ExpectedMessage 'No file of the Avalonia runtime is pinned for osx*'
        }
    }
    }
}
