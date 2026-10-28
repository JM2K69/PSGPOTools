#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The supply chain of a release: the build reproducible (the same bytes from the same sources,
# whatever the computer and its culture), the package of a release (CI/05_Package.ps1): its files,
# its archive and SHA256SUMS, its Authenticode signature and catalog (Windows), and the workflows
# that test and publish it.
BeforeAll {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $Sha256 = { param([byte[]]$Bytes) [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant() }
}

Describe 'Build of the module' {
    BeforeAll {
        # A copy of what the build reads: the sources, the build scripts, the manifest.
        $Copy = Join-Path $TestDrive 'repository'
        $null = New-Item -ItemType Directory -Path (Join-Path $Copy 'CI'), (Join-Path $Copy 'HGPM') -Force
        Copy-Item -LiteralPath (Join-Path $Root 'CI' '03_Build.ps1'), (Join-Path $Root 'CI' '03_postContent.ps1') -Destination (Join-Path $Copy 'CI')
        Copy-Item -LiteralPath (Join-Path $Root 'Code') -Destination $Copy -Recurse
        Copy-Item -LiteralPath (Join-Path $Root 'HGPM' 'HGPM.psd1') -Destination (Join-Path $Copy 'HGPM')
        $Build = {
            param([string]$Culture)
            $null = & pwsh -NoProfile -Command "[cultureinfo]::CurrentCulture = '$Culture'; & '$(Join-Path $Copy 'CI' '03_Build.ps1')'" 2>&1
            , [System.IO.File]::ReadAllBytes((Join-Path $Copy 'HGPM' 'HGPM.psm1'))
        }
        $First = & $Build 'en-US'
        $Text = [System.Text.Encoding]::UTF8.GetString($First)
    }

    It 'Gives the same bytes from the same sources, whatever the culture of the computer' {
        & $Sha256 (& $Build 'tr-TR') | Should -Be (& $Sha256 $First)
    }

    It 'Gives the module of the repository, built from them' {
        & $Sha256 ([System.IO.File]::ReadAllBytes((Join-Path $Root 'HGPM' 'HGPM.psm1'))) | Should -Be (& $Sha256 $First)
    }

    It 'Writes no date, LF line endings and no BOM, the sources in the order of their names' {
        ($Text -split "`n")[0] | Should -Be '# Generated from Code/ by CI/03_Build.ps1 (build of Nicolas BAUDIN): edit Code/, not this file.'
        $Text.Contains("`r") | Should -BeFalse
        $First[0] | Should -Not -Be 0xEF
        # Classes, then the private functions, then the public ones, each by name.
        $Text.IndexOf('class GPOToolsDirectory') | Should -BeLessThan $Text.IndexOf('function Get-PSGPOHealthData')
        $Text.IndexOf('function Get-PSGPOHealthData') | Should -BeLessThan $Text.IndexOf('function Get-PSGPOSysvolLocation')
        $Text.IndexOf('function Get-PSGPOSysvolLocation') | Should -BeLessThan $Text.IndexOf('function Approve-PSGPO')
        $Text.IndexOf('function Approve-PSGPO') | Should -BeLessThan $Text.IndexOf('function Test-PSGPOHealth')
    }
}

Describe 'Package of a release' {
    BeforeAll {
        $Data = Import-PowerShellDataFile -Path (Join-Path $Root 'HGPM' 'HGPM.psd1')
        $Version = "$($Data.ModuleVersion)$(if ($Data.PrivateData.PSData.Prerelease) { "-$($Data.PrivateData.PSData.Prerelease)" })"
        $Release = Join-Path $TestDrive 'release'
        $Result = & (Join-Path $Root 'CI' '05_Package.ps1') -OutputPath $Release -Rid @() 6>$null
        $Sums = @(Get-Content -LiteralPath (Join-Path $Release 'SHA256SUMS'))
    }

    It 'Makes the package of the PowerShell Gallery: the module without the Avalonia runtime, with its license' {
        $Result.Package | Should -Be (Join-Path $Release 'HGPM')
        foreach ($Name in 'HGPM.psm1', 'HGPM.psd1', 'LICENSE', 'NOTICE', 'Avalonia/Get-AvaloniaBinaries.ps1', 'Resources/AvaloniaPackages.json') {
            Test-Path -LiteralPath (Join-Path $Result.Package $Name) | Should -BeTrue -Because "$Name is part of the package"
        }
        Test-Path -LiteralPath (Join-Path $Result.Package 'Avalonia' 'bin') | Should -BeFalse
        (Get-FileHash -LiteralPath (Join-Path $Result.Package 'HGPM.psm1')).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $Root 'HGPM' 'HGPM.psm1')).Hash
    }

    It 'Archives the package in a folder of its name' {
        $Result.Archives | Should -Be @(Join-Path $Release "HGPM-$Version.zip")
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $Zip = [System.IO.Compression.ZipFile]::OpenRead($Result.Archives[0])
        try { $Entries = @($Zip.Entries | Where-Object { $_.Name } | ForEach-Object FullName) } finally { $Zip.Dispose() }
        $Files = @(Get-ChildItem -LiteralPath $Result.Package -Recurse -File | ForEach-Object { 'HGPM/' + ($_.FullName.Substring($Result.Package.Length + 1) -replace '\\', '/') })
        @($Entries | Sort-Object) | Should -Be @($Files | Sort-Object)
    }

    It 'Writes the SHA-256 of each file of the package and of the archive, as sha256sum does' {
        $Sums | Should -Contain "$(& $Sha256 ([System.IO.File]::ReadAllBytes((Join-Path $Result.Package 'HGPM.psm1'))))  HGPM/HGPM.psm1"
        $Sums[-1] | Should -Be "$(& $Sha256 ([System.IO.File]::ReadAllBytes($Result.Archives[0])))  HGPM-$Version.zip"
        foreach ($Line in $Sums) {
            $Line | Should -Match '^[0-9a-f]{64}  [^ ].*$'
            $Hash, $Name = $Line -split '  ', 2
            & $Sha256 ([System.IO.File]::ReadAllBytes((Join-Path $Release $Name))) | Should -Be $Hash -Because $Name
        }
        $Sums.Count | Should -Be (@(Get-ChildItem -LiteralPath $Result.Package -Recurse -File).Count + 1)
    }

    It 'Refuses a folder that is not empty' {
        { & (Join-Path $Root 'CI' '05_Package.ps1') -OutputPath $Release -Rid @() } | Should -Throw "$Release is not empty*"
    }

    It 'Signs the scripts of the package, and the catalog of all its files, with the certificate given' -Skip:(-not $IsWindows) {
        # A self-signed code signing certificate, for the test only: not trusted, but signing.
        $Key = [System.Security.Cryptography.RSA]::Create(3072)
        $Request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=HGPM test signing', $Key, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $Usages = [System.Security.Cryptography.OidCollection]::new()
        $null = $Usages.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
        $Request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($Usages, $false))
        $Certificate = $Request.CreateSelfSigned([datetimeoffset]::Now.AddDays(-1), [datetimeoffset]::Now.AddDays(1))
        $Pfx = Join-Path $TestDrive 'signing.pfx'
        [System.IO.File]::WriteAllBytes($Pfx, $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, 'test'))
        $Signed = Join-Path $TestDrive 'signed'
        $Package = (& (Join-Path $Root 'CI' '05_Package.ps1') -OutputPath $Signed -Rid @() -CertificatePath $Pfx -CertificatePassword (ConvertTo-SecureString 'test' -AsPlainText -Force) -TimestampServer '' 6>$null).Package
        foreach ($Name in 'HGPM.psm1', 'HGPM.psd1', 'Avalonia/Get-AvaloniaBinaries.ps1') {
            (Get-AuthenticodeSignature -LiteralPath (Join-Path $Package $Name)).SignerCertificate.Thumbprint | Should -Be $Certificate.Thumbprint -Because "$Name is signed"
        }
        $Catalog = Join-Path $Package 'HGPM.cat'
        (Get-AuthenticodeSignature -LiteralPath $Catalog).SignerCertificate.Thumbprint | Should -Be $Certificate.Thumbprint
        Test-FileCatalog -Path $Package -CatalogFilePath $Catalog | Should -Be 'Valid'
        @(Get-Content -LiteralPath (Join-Path $Signed 'SHA256SUMS')) | Should -Contain "$(& $Sha256 ([System.IO.File]::ReadAllBytes($Catalog)))  HGPM/HGPM.cat"
        # A file of the package changed: the catalog says it.
        Add-Content -LiteralPath (Join-Path $Package 'Resources' 'WmiFilters.json') -Value ' '
        Test-FileCatalog -Path $Package -CatalogFilePath $Catalog | Should -Be 'ValidationFailed'
    }

    It 'Signs only on Windows' -Skip:$IsWindows {
        { & (Join-Path $Root 'CI' '05_Package.ps1') -OutputPath (Join-Path $TestDrive 'linux') -Rid @() -CertificatePath (Join-Path $TestDrive 'none.pfx') } |
            Should -Throw 'Authenticode signatures and catalogs are made on Windows.'
    }
}

Describe 'Workflows of the CI and of the release' {
    BeforeAll {
        $Workflows = @{}
        foreach ($File in Get-ChildItem -LiteralPath (Join-Path $Root '.github' 'workflows') -Filter '*.yml') { $Workflows[$File.Name] = Get-Content -LiteralPath $File.FullName -Raw }
    }

    It 'Pins each action to a commit' {
        foreach ($Name in $Workflows.Keys) {
            foreach ($Use in [regex]::Matches($Workflows[$Name], '(?m)^\s*-?\s*uses:\s*(\S+)')) {
                $Action = $Use.Groups[1].Value
                if ($Action.StartsWith('./')) { continue }
                $Action | Should -Match '^[\w.-]+/[\w./-]+@[0-9a-f]{40}$' -Because "$Name uses $Action"
            }
        }
        Test-Path -LiteralPath (Join-Path $Root '.github' 'dependabot.yml') | Should -BeTrue -Because 'Dependabot proposes their new versions'
    }

    It 'Pins the modules of the tests to a version' {
        foreach ($Install in [regex]::Matches($Workflows['ci.yml'], 'Install-CIModule\.ps1[^\r\n]*')) {
            $Install.Value | Should -Match '-RequiredVersion \d+\.\d+\.\d+' -Because $Install.Value
        }
    }

    It 'Gives the tests read rights only, and each job of the release its own' {
        $Workflows['ci.yml'] | Should -Match '(?m)^permissions:\r?\n  contents: read\r?$'
        $Workflows['release.yml'] | Should -Match '(?m)^permissions: \{\}\r?$'
    }

    It 'Publishes the module the tests ran, never a build of its own' {
        $Workflows['ci.yml'] | Should -Match 'name: module'
        $Workflows['release.yml'] | Should -Match 'name: module'
        $Workflows['release.yml'] | Should -Not -Match '03_Build'
        $Workflows['release.yml'] | Should -Match '05_Package\.ps1'
        $Workflows['release.yml'] | Should -Match 'subject-checksums: .*SHA256SUMS'
        $Workflows['release.yml'] | Should -Match '04_Publish\.ps1 [^\r\n]*-PackagePath'
    }
}
