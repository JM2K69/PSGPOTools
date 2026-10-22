<#
    Public key policies of a GPO, as the Group Policy editor shows them under Policies > Windows
    Settings > Security Settings > Public Key Policies: certificate stores of the Registry.pol of
    the scope, each certificate a value Blob under

      Software\Policies\Microsoft\SystemCertificates\<store>\Certificates\<SHA-1 thumbprint>

    applied by the Registry extension; the Windows certificate stores add them (Group Policy
    physical store). The Blob is the certificate with its properties ([MS-GPEF] 2.2.1.1.1): a
    property is its id, 1, its length, its value; the encoded certificate is the property 0x20.

    The recovery agents of EFS (store EFS) also need the value EFSBlob of
    Software\Policies\Microsoft\SystemCertificates\EFS ([MS-GPEF] 2.2.1.2): every agent
    certificate, rebuilt at each change. BitLocker takes its data recovery agents from the store
    FVE, and the certificate of its network unlock from FVE_NKP.
#>

$script:PSGPOCertificateRoot = 'Software\Policies\Microsoft\SystemCertificates'

# The stores of the Group Policy editor, in its order: their store name and their scopes.
$script:PSGPOCertificateStores = @(
    [pscustomobject]@{ Store = 'EFS'; Name = 'Encrypting File System'; Scopes = @('Machine') }
    [pscustomobject]@{ Store = 'FVE'; Name = 'BitLocker Drive Encryption'; Scopes = @('Machine') }
    [pscustomobject]@{ Store = 'FVE_NKP'; Name = 'BitLocker Drive Encryption Network Unlock Certificate'; Scopes = @('Machine') }
    [pscustomobject]@{ Store = 'Root'; Name = 'Trusted Root Certification Authorities'; Scopes = @('Machine') }
    [pscustomobject]@{ Store = 'Trust'; Name = 'Enterprise Trust'; Scopes = @('Machine', 'User') }
    [pscustomobject]@{ Store = 'CA'; Name = 'Intermediate Certification Authorities'; Scopes = @('Machine') }
    [pscustomobject]@{ Store = 'TrustedPublisher'; Name = 'Trusted Publishers'; Scopes = @('Machine') }
    [pscustomobject]@{ Store = 'Disallowed'; Name = 'Untrusted Certificates'; Scopes = @('Machine') }
    [pscustomobject]@{ Store = 'AuthRoot'; Name = 'Third-Party Root Certification Authorities'; Scopes = @('Machine') }
    [pscustomobject]@{ Store = 'TrustedPeople'; Name = 'Trusted People'; Scopes = @('Machine', 'User') }
)

# The certificate stores of the public key policies of a scope.
function Get-PSGPOCertificateStore {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope)

    $script:PSGPOCertificateStores | Where-Object { $_.Scopes -contains $Scope }
}

# The Blob of a certificate as the Group Policy editor writes it: its SHA-1 hash (property 3),
# then the encoded certificate (property 0x20).
function ConvertTo-PSGPOCertificateBlob {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)] [byte[]]$Certificate)

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $hash = [System.Security.Cryptography.SHA1]::HashData($Certificate)
        foreach ($property in @(@(3, $hash), @(0x20, $Certificate))) {
            $writer.Write([uint32]$property[0])
            $writer.Write([uint32]1)
            $writer.Write([uint32]$property[1].Length)
            $writer.Write([byte[]]$property[1])
        }
        $writer.Flush()
        , $stream.ToArray()
    } finally {
        $writer.Dispose()
    }
}

# The encoded certificate of a Blob (its property 0x20), $null when it has none.
function ConvertFrom-PSGPOCertificateBlob {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Blob)

    $position = 0
    while ($position + 12 -le $Blob.Length) {
        $id = [BitConverter]::ToUInt32($Blob, $position)
        $length = [int][BitConverter]::ToUInt32($Blob, $position + 8)
        if ($position + 12 + $length -gt $Blob.Length) { break }
        if ($id -eq 0x20) { return , [byte[]]$Blob[($position + 12)..($position + 11 + $length)] }
        $position += 12 + $length
    }
    $null
}

# A certificate read from a file: DER, or Base-64 (PEM, with or without its header lines).
function Read-PSGPOCertificateFile {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)] [string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -and $bytes[0] -eq 0x30) { return , $bytes }
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    $base64 = ($text -replace '-----[A-Z ]+-----', '' -replace '\s', '')
    try { $der = [Convert]::FromBase64String($base64) } catch { throw (Get-PSGPOText "'{0}' is not a certificate: DER or Base-64 (.cer, .crt, .pem)." $Path) }
    , $der
}

# A certificate as the editor lists it: its subject, issuer, expiry and thumbprint.
function Get-PSGPOCertificateInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [byte[]]$Certificate)

    $x509 = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($Certificate)
    try {
        $simple = [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName
        [pscustomobject]@{
            Thumbprint = $x509.Thumbprint.ToUpperInvariant()
            Subject = $x509.GetNameInfo($simple, $false)
            Issuer = $x509.GetNameInfo($simple, $true)
            NotAfter = $x509.NotAfter
            SubjectDistinguishedName = $x509.Subject
        }
    } finally {
        $x509.Dispose()
    }
}

# The certificates of a store in a Registry.pol: Store, Thumbprint, Subject, Issuer, NotAfter,
# Certificate (encoded) and Entry; a Blob that is not a certificate with Certificate $null.
function Get-PSGPOPolicyCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol,
        [Parameter(Mandatory)] [string]$Store
    )

    $prefix = "$script:PSGPOCertificateRoot\$Store\Certificates\"
    foreach ($entry in @($Pol.Entries)) {
        if (-not $entry.Key.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or $entry.ValueName -ne 'Blob' -or $entry.Type -ne [GPOToolsPolType]::Binary) { continue }
        $thumbprint = $entry.Key.Substring($prefix.Length).ToUpperInvariant()
        $certificate = ConvertFrom-PSGPOCertificateBlob -Blob $entry.Data
        $info = $null
        if ($certificate) { try { $info = Get-PSGPOCertificateInfo -Certificate $certificate } catch { $info = $null } }
        [pscustomobject]@{
            Store = $Store
            Thumbprint = $thumbprint
            Subject = if ($info) { $info.Subject } else { $thumbprint }
            Issuer = if ($info) { $info.Issuer }
            NotAfter = if ($info) { $info.NotAfter }
            SubjectDistinguishedName = if ($info) { $info.SubjectDistinguishedName }
            Certificate = if ($info) { $certificate }
            Entry = $entry
        }
    }
}

# Adds a certificate to a store of the Registry.pol (in place of the same certificate); the
# EFSBlob follows the recovery agents of EFS.
function Add-PSGPOPolicyCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol,
        [Parameter(Mandatory)] [string]$Store,
        [Parameter(Mandatory)] [byte[]]$Certificate
    )

    try { $info = Get-PSGPOCertificateInfo -Certificate $Certificate } catch { throw (Get-PSGPOText 'This file is not an X.509 certificate: {0}' $_.Exception.GetBaseException().Message) }
    Remove-PSGPOPolicyCertificate -Pol $Pol -Store $Store -Thumbprint $info.Thumbprint
    $Pol.Entries.Add([GPOToolsPolEntry]::new("$script:PSGPOCertificateRoot\$Store\Certificates\$($info.Thumbprint)", 'Blob', [GPOToolsPolType]::Binary, (ConvertTo-PSGPOCertificateBlob -Certificate $Certificate)))
    if ($Store -eq 'EFS') { Update-PSGPOEfsBlob -Pol $Pol }
    $info
}

# Removes a certificate from a store of the Registry.pol.
function Remove-PSGPOPolicyCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol,
        [Parameter(Mandatory)] [string]$Store,
        [Parameter(Mandatory)] [string]$Thumbprint
    )

    $key = "$script:PSGPOCertificateRoot\$Store\Certificates\$Thumbprint"
    for ($i = $Pol.Entries.Count - 1; $i -ge 0; $i--) {
        if ([string]::Equals($Pol.Entries[$i].Key, $key, [System.StringComparison]::OrdinalIgnoreCase)) { $Pol.Entries.RemoveAt($i) }
    }
    if ($Store -eq 'EFS') { Update-PSGPOEfsBlob -Pol $Pol }
}

# The EFSBlob of the recovery agents of EFS ([MS-GPEF] 2.2.1.2.1): 01 00 01 00, the count of
# keys, then each key (EfsKey): Length1, Length2, SID offset (0: no SID), 2, the length and
# offset of the certificate, 8 reserved bytes, the certificate. No agent: no EFSBlob.
function ConvertTo-PSGPOEfsBlob {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Certificate)

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([byte[]](1, 0, 1, 0))
        $writer.Write([uint32]$Certificate.Count)
        foreach ($der in $Certificate) {
            $length2 = 28 + $der.Length
            $writer.Write([uint32]($length2 + 4))
            $writer.Write([uint32]$length2)
            $writer.Write([uint32]0)
            $writer.Write([uint32]2)
            $writer.Write([uint32]$der.Length)
            $writer.Write([uint32]28)
            $writer.Write([uint64]0)
            $writer.Write([byte[]]$der)
        }
        $writer.Flush()
        , $stream.ToArray()
    } finally {
        $writer.Dispose()
    }
}

# The certificates of an EFSBlob, in their order.
function ConvertFrom-PSGPOEfsBlob {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Blob)

    if ($Blob.Length -lt 8) { return }
    $count = [BitConverter]::ToUInt32($Blob, 4)
    $position = 8
    for ($i = 0; $i -lt $count -and $position + 28 -le $Blob.Length; $i++) {
        $length1 = [int][BitConverter]::ToUInt32($Blob, $position)
        $start = $position + 4
        $length = [int][BitConverter]::ToUInt32($Blob, $start + 12)
        $offset = [int][BitConverter]::ToUInt32($Blob, $start + 16)
        if ($start + $offset + $length -gt $Blob.Length) { break }
        , [byte[]]$Blob[($start + $offset)..($start + $offset + $length - 1)]
        $position += $length1
    }
}

# Writes the EFSBlob from the recovery agents of the store EFS (none: the EFSBlob is removed).
function Update-PSGPOEfsBlob {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol)

    $key = "$script:PSGPOCertificateRoot\EFS"
    for ($i = $Pol.Entries.Count - 1; $i -ge 0; $i--) {
        if ([string]::Equals($Pol.Entries[$i].Key, $key, [System.StringComparison]::OrdinalIgnoreCase) -and $Pol.Entries[$i].ValueName -ieq 'EFSBlob') { $Pol.Entries.RemoveAt($i) }
    }
    $agents = @(Get-PSGPOPolicyCertificate -Pol $Pol -Store 'EFS' | Where-Object Certificate | ForEach-Object { , $_.Certificate })
    if ($agents.Count) { $Pol.Entries.Add([GPOToolsPolEntry]::new($key, 'EFSBlob', [GPOToolsPolType]::Binary, (ConvertTo-PSGPOEfsBlob -Certificate $agents))) }
}

# The certificates of the public key policies as the Settings tab of GPMC lists them, and the
# entries of the Registry.pol they explain (not listed as extra registry settings).
function Get-PSGPOConfiguredPublicKeyPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsRegistryPol]$Pol,
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope
    )

    $explained = [System.Collections.Generic.List[object]]::new()
    $rows = foreach ($store in @(Get-PSGPOCertificateStore -Scope $Scope)) {
        foreach ($certificate in @(Get-PSGPOPolicyCertificate -Pol $Pol -Store $store.Store)) {
            $explained.Add($certificate.Entry)
            $row = [AvaloniaSettingRow]::new()
            $row.Path = "Policies > Windows Settings > Security Settings > Public Key Policies > $($store.Name)"
            $row.Name = $certificate.Subject
            $row.State = if ($certificate.Certificate) { "Issued by: $($certificate.Issuer)" } else { 'Unreadable certificate' }
            $row.Options = (@(
                    if ($certificate.NotAfter) { "Expires: $($certificate.NotAfter.ToString('yyyy-MM-dd'))" }
                    "Thumbprint: $($certificate.Thumbprint)") -join [Environment]::NewLine)
            $row
        }
    }
    foreach ($entry in @($Pol.Entries)) {
        if ([string]::Equals($entry.Key, "$script:PSGPOCertificateRoot\EFS", [System.StringComparison]::OrdinalIgnoreCase) -and $entry.ValueName -ieq 'EFSBlob') { $explained.Add($entry) }
    }
    [pscustomobject]@{ Rows = @($rows); Entries = $explained }
}
