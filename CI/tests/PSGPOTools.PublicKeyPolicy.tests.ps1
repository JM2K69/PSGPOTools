#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Public key policies of a GPO: the certificate stores of Registry.pol, their Blob ([MS-GPEF]
# 2.2.1.1.1) and the EFSBlob of the recovery agents of EFS ([MS-GPEF] 2.2.1.2), with certificates
# made for the tests.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        # A self-signed certificate, encoded (DER).
        function New-TestCertificate {
            param([string]$Subject, [int]$Days = 365)
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            try {
                $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=$Subject", $rsa,
                    [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
                $certificate = $request.CreateSelfSigned([datetimeoffset]::Now.AddDays(-1), [datetimeoffset]::Now.AddDays($Days))
                , $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            } finally {
                $rsa.Dispose()
            }
        }
        $Root = New-TestCertificate 'HGPM Test Root CA'
        $Agent = New-TestCertificate 'HGPM EFS Recovery Agent'
        $Agent2 = New-TestCertificate 'HGPM EFS Recovery Agent 2'
        $Thumbprint = [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData($Root))
    }

    Describe 'Certificate Blob' {
        It 'Writes the SHA-1 hash, then the certificate, as properties of id, 1, length, value' {
            $Blob = ConvertTo-PSGPOCertificateBlob -Certificate $Root
            [BitConverter]::ToUInt32($Blob, 0) | Should -Be 3
            [BitConverter]::ToUInt32($Blob, 4) | Should -Be 1
            [BitConverter]::ToUInt32($Blob, 8) | Should -Be 20
            [System.Convert]::ToHexString($Blob[12..31]) | Should -Be $Thumbprint
            [BitConverter]::ToUInt32($Blob, 32) | Should -Be 0x20
            [BitConverter]::ToUInt32($Blob, 40) | Should -Be $Root.Length
            [Linq.Enumerable]::SequenceEqual([byte[]](ConvertFrom-PSGPOCertificateBlob -Blob $Blob), [byte[]]$Root) | Should -BeTrue
            ConvertFrom-PSGPOCertificateBlob -Blob ([byte[]](1, 2, 3)) | Should -BeNullOrEmpty
        }

        It 'Reads a certificate file in DER or in Base-64' {
            $Der = Join-Path $TestDrive 'root.cer'
            [System.IO.File]::WriteAllBytes($Der, $Root)
            $Pem = Join-Path $TestDrive 'root.pem'
            Set-Content -LiteralPath $Pem -Value "-----BEGIN CERTIFICATE-----`n$([Convert]::ToBase64String($Root, 'InsertLineBreaks'))`n-----END CERTIFICATE-----"
            foreach ($Path in $Der, $Pem) { [Linq.Enumerable]::SequenceEqual([byte[]](Read-PSGPOCertificateFile -Path $Path), [byte[]]$Root) | Should -BeTrue -Because $Path }
            $Bad = Join-Path $TestDrive 'bad.txt'
            Set-Content -LiteralPath $Bad -Value 'not a certificate!'
            { Read-PSGPOCertificateFile -Path $Bad } | Should -Throw
        }
    }

    Describe 'Certificate stores of Registry.pol' {
        It 'Has the stores of the Group Policy editor for each scope' {
            @(Get-PSGPOCertificateStore -Scope Machine).Store | Should -Be @('EFS', 'FVE', 'FVE_NKP', 'Root', 'Trust', 'CA', 'TrustedPublisher', 'Disallowed', 'AuthRoot', 'TrustedPeople')
            @(Get-PSGPOCertificateStore -Scope User).Store | Should -Be @('Trust', 'TrustedPeople')
        }

        It 'Adds a certificate under its thumbprint, once, and removes it' {
            $Pol = [GPOToolsRegistryPol]::new()
            $Info = Add-PSGPOPolicyCertificate -Pol $Pol -Store 'Root' -Certificate $Root
            $Info.Subject | Should -Be 'HGPM Test Root CA'
            $null = Add-PSGPOPolicyCertificate -Pol $Pol -Store 'Root' -Certificate $Root
            $Pol.Entries.Count | Should -Be 1
            $Pol.Entries[0].Key | Should -Be "Software\Policies\Microsoft\SystemCertificates\Root\Certificates\$Thumbprint"
            $Pol.Entries[0].ValueName | Should -Be 'Blob'
            $Pol.Entries[0].Type | Should -Be ([GPOToolsPolType]::Binary)
            # Read back from the file.
            $Read = @(Get-PSGPOPolicyCertificate -Pol ([GPOToolsRegistryPol]::Parse($Pol.ToBytes())) -Store 'Root')
            $Read.Count | Should -Be 1
            $Read[0].Thumbprint | Should -Be $Thumbprint
            $Read[0].Issuer | Should -Be 'HGPM Test Root CA'
            Remove-PSGPOPolicyCertificate -Pol $Pol -Store 'Root' -Thumbprint $Thumbprint.ToLowerInvariant()
            $Pol.Entries.Count | Should -Be 0
            { Add-PSGPOPolicyCertificate -Pol $Pol -Store 'Root' -Certificate ([byte[]](0x30, 1, 2)) } | Should -Throw
        }

        It 'Writes the EFSBlob of the recovery agents of EFS, and removes it with the last one' {
            $Pol = [GPOToolsRegistryPol]::new()
            $null = Add-PSGPOPolicyCertificate -Pol $Pol -Store 'EFS' -Certificate $Agent
            $null = Add-PSGPOPolicyCertificate -Pol $Pol -Store 'EFS' -Certificate $Agent2
            $Entry = $Pol.FindValue('Software\Policies\Microsoft\SystemCertificates\EFS', 'EFSBlob')
            $Entry.Type | Should -Be ([GPOToolsPolType]::Binary)
            $Blob = $Entry.Data
            $Blob[0..3] | Should -Be @(1, 0, 1, 0)
            [BitConverter]::ToUInt32($Blob, 4) | Should -Be 2
            # The first EfsKey: Length1 = Length2 + 4, no SID, 2, the certificate after 28 bytes.
            [BitConverter]::ToUInt32($Blob, 8) | Should -Be (32 + $Agent.Length)
            [BitConverter]::ToUInt32($Blob, 12) | Should -Be (28 + $Agent.Length)
            [BitConverter]::ToUInt32($Blob, 16) | Should -Be 0
            [BitConverter]::ToUInt32($Blob, 20) | Should -Be 2
            [BitConverter]::ToUInt32($Blob, 24) | Should -Be $Agent.Length
            [BitConverter]::ToUInt32($Blob, 28) | Should -Be 28
            $Agents = @(ConvertFrom-PSGPOEfsBlob -Blob $Blob)
            $Agents.Count | Should -Be 2
            [Linq.Enumerable]::SequenceEqual([byte[]]$Agents[1], [byte[]]$Agent2) | Should -BeTrue
            foreach ($Certificate in @(Get-PSGPOPolicyCertificate -Pol $Pol -Store 'EFS')) { Remove-PSGPOPolicyCertificate -Pol $Pol -Store 'EFS' -Thumbprint $Certificate.Thumbprint }
            $Pol.Entries.Count | Should -Be 0 -Because 'no agent: no EFSBlob'
        }

        It 'Lists the certificates in the Settings tab instead of extra registry settings' {
            $Pol = [GPOToolsRegistryPol]::new()
            $null = Add-PSGPOPolicyCertificate -Pol $Pol -Store 'Root' -Certificate $Root
            $null = Add-PSGPOPolicyCertificate -Pol $Pol -Store 'EFS' -Certificate $Agent
            $Rows = @(Get-PSGPOConfiguredSetting -Pol $Pol -Scope Machine)
            @($Rows | Where-Object IsExtra) | Should -BeNullOrEmpty -Because 'the Blob and the EFSBlob are explained'
            ($Rows | Where-Object Name -EQ 'HGPM Test Root CA').Path | Should -Be 'Policies > Windows Settings > Security Settings > Public Key Policies > Trusted Root Certification Authorities'
            ($Rows | Where-Object Name -EQ 'HGPM Test Root CA').State | Should -Be 'Issued by: HGPM Test Root CA'
            ($Rows | Where-Object Name -EQ 'HGPM EFS Recovery Agent').Path | Should -BeLike '*> Encrypting File System'
        }

        It 'Saves the Registry.pol with the tool of the certificates, and the extension of EFS with recovery agents' {
            $Directory = Import-PSGPODirectory -Path (Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json')
            $Gpo = $Directory.FindGpo('C - Servers - Security Baseline')
            $Pol = [GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($Gpo, 'Machine'))
            $null = Add-PSGPOPolicyCertificate -Pol $Pol -Store 'EFS' -Certificate $Agent
            $Directory.WritePublicKeyPolicyFile($Gpo, 'Machine', $Pol.ToBytes(), $true)
            $Gpo.MachineExtensionNames | Should -Match ([regex]::Escape('{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'))
            $Gpo.MachineExtensionNames | Should -Match ([regex]::Escape('{53D6AB1D-2488-11D1-A28C-00C04FB94F17}'))
            $Gpo.MachineExtensionNames | Should -Match ([regex]::Escape('[{B1BE8D72-6EAC-11D2-A4EA-00C04F79F83A}{53D6AB1D-2488-11D1-A28C-00C04FB94F17}]'))
            @(Get-PSGPOPolicyCertificate -Pol ([GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($Gpo, 'Machine'))) -Store 'EFS').Count | Should -Be 1
        }
    }
}
