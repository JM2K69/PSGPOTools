<#
    The ADMX files of other products than Windows (Office, Firefox, Adobe Acrobat and Reader,
    Edge, Chrome, Google Update), neither shipped with the module nor kept in its repository: the
    files are their publishers' to publish. Install-PSGPOProductAdmx downloads the package of the
    publisher and installs its .admx and .adml files. Resources/AdmxProducts.json pins each
    package (its address, size and SHA-256) and each of its files: its path in a PolicyDefinitions
    folder and the SHA-256 of its content. The files are found in the package by their content,
    whatever the package names them: the package of Office holds the .adml files of its languages
    side by side, as word16.adml, word16.adml0... A package or a file that is not the one pinned is
    refused, nothing installed. CI/Update-AdmxProductCatalog.ps1 pins a new package.
#>

# Every product the module pins (Resources/AdmxProducts.json).
function Read-PSGPOAdmxProductFile {
    [CmdletBinding()]
    param()

    @((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Resources' 'AdmxProducts.json') -Raw | ConvertFrom-Json).Products)
}

# The products pinned by the module, or those named; throws for a name it does not pin.
function Get-PSGPOAdmxProductCatalog {
    [CmdletBinding()]
    param([string[]]$Name)

    $products = @(Read-PSGPOAdmxProductFile)
    if (-not $Name) { return $products }
    foreach ($item in $Name) {
        $found = $products | Where-Object { [string]::Equals($_.Name, $item, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if (-not $found) { throw "HGPM pins no ADMX files of '$item': $(@($products.Name) -join ', ') (Get-PSGPOProductAdmx). Install the ADMX files of another product with -SourcePath." }
        $found
    }
}

# The languages of the .adml files a product pins (fr-FR...).
function Get-PSGPOAdmxProductLanguage {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [object]$Product)

    @($Product.Files | ForEach-Object { $path = "$($_.Path)"; if ($path.Contains('/')) { $path.Substring(0, $path.IndexOf('/')) } } | Sort-Object -Unique)
}

# The names of the .admx files of a product that are its own: those it shares with another
# product pinned (google.admx, of Chrome and of Google Update) aside, as they may be there already.
function Get-PSGPOAdmxProductOwnFile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object]$Product,
        [object[]]$Catalog = (Get-PSGPOAdmxProductCatalog)
    )

    $others = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($other in $Catalog) {
        if ($other.Name -eq $Product.Name) { continue }
        foreach ($file in $other.Files) { [void]$others.Add("$($file.Path)") }
    }
    @($Product.Files | Where-Object { "$($_.Path)" -notmatch '/' -and -not $others.Contains("$($_.Path)") } | ForEach-Object { "$($_.Path)" })
}

# The cabinet (.cab) a self-extracting package of Microsoft holds after its program (the package
# of Office), written to $Destination without running the program: it starts where the last
# section of the program ends (its PE headers), with MSCF and its size.
function Save-PSGPOAdmxEmbeddedCabinet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Destination
    )

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = [System.IO.BinaryReader]::new($stream)
        $fail = { throw "'$Path' holds no cabinet after its program: is it the package HGPM pins? Nothing is installed." }
        # MZ, then the PE header where 0x3C says.
        if ($stream.Length -lt 0x40 -or $reader.ReadUInt16() -ne 0x5A4D) { & $fail }
        $stream.Position = 0x3C
        $header = $reader.ReadInt32()
        if ($header -lt 0x40 -or $header + 24 -gt $stream.Length) { & $fail }
        $stream.Position = $header
        if ($reader.ReadUInt32() -ne 0x00004550) { & $fail }
        $stream.Position = $header + 6
        $sections = $reader.ReadUInt16()
        $stream.Position = $header + 20
        $optional = $reader.ReadUInt16()
        $end = [long]0
        for ($index = 0; $index -lt $sections; $index++) {
            # SizeOfRawData, then PointerToRawData, at 16 in each section header of 40 bytes.
            $stream.Position = $header + 24 + $optional + 40 * $index + 16
            $size = $reader.ReadUInt32()
            $pointer = $reader.ReadUInt32()
            $end = [math]::Max($end, [long]$pointer + $size)
        }
        if ($end + 16 -gt $stream.Length) { & $fail }
        $stream.Position = $end
        # MSCF, a reserved field, then the size of the whole cabinet.
        if ($reader.ReadUInt32() -ne 0x4643534D) { & $fail }
        $null = $reader.ReadUInt32()
        $length = [long]$reader.ReadUInt32()
        if ($end + $length -gt $stream.Length) { & $fail }
        $stream.Position = $end
        $out = [System.IO.File]::Create($Destination)
        try {
            $buffer = [byte[]]::new(1MB)
            while ($length -gt 0) {
                $read = $stream.Read($buffer, 0, [int][math]::Min($buffer.Length, $length))
                if ($read -le 0) { & $fail }
                $out.Write($buffer, 0, $read)
                $length -= $read
            }
        } finally {
            $out.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

# Extracts every file of a cabinet (.cab) into $Folder: expand on Windows, cabextract (or 7-Zip)
# on Linux and macOS.
function Expand-PSGPOAdmxCabinet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Folder
    )

    $null = New-Item -ItemType Directory -Path $Folder -Force
    if ($IsWindows) {
        $result = Invoke-PSGPONativeCommand -FilePath (Join-Path ([Environment]::SystemDirectory) 'expand.exe') -ArgumentList $Path, '-F:*', $Folder -TimeoutSeconds 600
        if ($result.ExitCode -ne 0) { throw "expand could not extract '$Path' (exit code $($result.ExitCode)): $($result.Error)" }
        return
    }
    $cabextract = Get-Command -Name 'cabextract' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cabextract) {
        $result = Invoke-PSGPONativeCommand -FilePath $cabextract.Source -ArgumentList '-q', '-d', $Folder, $Path -TimeoutSeconds 600
        if ($result.ExitCode -ne 0) { throw "cabextract could not extract '$Path' (exit code $($result.ExitCode)): $($result.Error)" }
        return
    }
    $sevenZip = Get-Command -Name '7z', '7zz', '7za' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sevenZip) {
        $result = Invoke-PSGPONativeCommand -FilePath $sevenZip.Source -ArgumentList 'x', '-y', "-o$Folder", $Path -TimeoutSeconds 600
        if ($result.ExitCode -ne 0) { throw "$($sevenZip.Name) could not extract '$Path' (exit code $($result.ExitCode)): $($result.Error)" }
        return
    }
    throw 'cabextract reads the packages of Microsoft (a cabinet, .cab) on Linux and macOS: install it (sudo apt install cabextract on Debian and Ubuntu, sudo dnf install cabextract on Fedora and RHEL, brew install cabextract on macOS).'
}

# Is the file a zip archive (PK\x03\x04), whatever its name? expand names the archive a cabinet
# of a single file holds after the cabinet (the templates of Edge).
function Test-PSGPOZipFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $bytes = [byte[]]::new(4)
        $stream.Read($bytes, 0, 4) -eq 4 -and [BitConverter]::ToUInt32($bytes, 0) -eq 0x04034B50
    } finally {
        $stream.Dispose()
    }
}

# Extracts the .admx and .adml files of a zip archive into $Folder, the other files left (the
# templates of other systems). Each one is written under its number in the archive, never at a
# path the archive gives: the files are then found by their content.
function Expand-PSGPOAdmxZipEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Folder
    )

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.ZipFile
    $null = New-Item -ItemType Directory -Path $Folder -Force
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $number = 0
        foreach ($entry in $archive.Entries) {
            $number++
            if ($entry.Name -notmatch '\.adm[lx]$') { continue }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Folder "$number$([System.IO.Path]::GetExtension($entry.Name))"), $true)
        }
    } finally {
        $archive.Dispose()
    }
}

# The files of $Path an ADMX package may hold (.admx, .adml, and the .adml files of Office named
# by language, .adml0...), by the SHA-256 of their content, hashed as bytes (see Get-PSGPOAdmxSetHash).
function Get-PSGPOAdmxFileIndex {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string]$Path)

    $index = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Recurse | Where-Object Name -Match '\.adm[lx]\d*$')) {
        $index[[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($file.FullName)))] = $file.FullName
    }
    $index
}

# Extracts the files of a product the module pins, its .admx files and the .adml files of the
# languages asked for, from its package into the PolicyDefinitions folder $Folder: each one found
# in the package by its SHA-256, written at the path pinned. Throws when one is missing. Returns
# the number of files.
function Expand-PSGPOAdmxProductPackage {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [string]$Package,
        [Parameter(Mandatory)] [object]$Product,
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Language
    )

    $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-Product-$([guid]::NewGuid().ToString('N'))"
    try {
        $expanded = Join-Path $work 'expanded'
        switch ("$($Product.Format)") {
            'Zip' { Expand-PSGPOAdmxZipEntry -Path $Package -Folder $expanded }
            'Cabinet' { Expand-PSGPOAdmxCabinet -Path $Package -Folder $expanded }
            'CabinetExecutable' {
                $null = New-Item -ItemType Directory -Path $work -Force
                $cabinet = Join-Path $work 'package.cab'
                Save-PSGPOAdmxEmbeddedCabinet -Path $Package -Destination $cabinet
                Expand-PSGPOAdmxCabinet -Path $cabinet -Folder $expanded
            }
            default { throw "Unknown format '$($Product.Format)' of the package of $($Product.DisplayName)." }
        }
        # The zip archives a cabinet holds (the templates of Edge).
        $number = 0
        foreach ($archive in @(Get-ChildItem -LiteralPath $expanded -File -Recurse | Where-Object { $_.Name -notmatch '\.adm[lx]\d*$' -and (Test-PSGPOZipFile -Path $_.FullName) })) {
            $number++
            Expand-PSGPOAdmxZipEntry -Path $archive.FullName -Folder (Join-Path $expanded "zip-$number")
        }
        $index = Get-PSGPOAdmxFileIndex -Path $expanded
        $wanted = @($Product.Files | Where-Object { $path = "$($_.Path)"; -not $path.Contains('/') -or $Language -contains $path.Substring(0, $path.IndexOf('/')) })
        $missing = @($wanted | Where-Object { -not $index.ContainsKey("$($_.Sha256)") })
        if ($missing.Count) {
            throw "The package does not hold the ADMX files HGPM pins for $($Product.DisplayName) ($(@($missing | Select-Object -First 3 | ForEach-Object Path) -join ', ')$(if ($missing.Count -gt 3) { '...' }) differ): nothing is installed."
        }
        foreach ($file in $wanted) {
            $target = Join-Path $Folder ("$($file.Path)" -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
            Copy-Item -LiteralPath $index["$($file.Sha256)"] -Destination $target -Force -ErrorAction Stop
        }
        $wanted.Count
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The languages of a PolicyDefinitions folder given with -SourcePath: its folders named after a
# culture (fr-FR, fr-fr) that hold .adml files, by the name of the culture, with their folder.
function Get-PSGPOAdmxSourceLanguage {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    foreach ($folder in @(Get-ChildItem -LiteralPath $Path -Directory | Sort-Object Name)) {
        $culture = try { [cultureinfo]::GetCultureInfo($folder.Name).Name } catch { $null }
        if (-not $culture -or -not (Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.adml' | Select-Object -First 1)) { continue }
        [pscustomobject]@{ Culture = $culture; Folder = $folder.FullName }
    }
}

# The problems GPMC would find in a PolicyDefinitions folder given with -SourcePath, for the
# languages asked for: an .admx or .adml file it cannot read, an .admx file without its .adml file
# in a language, a string or a presentation an .admx file names that its .adml file does not
# have. None: the folder can be installed.
function Test-PSGPOAdmxSourceFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [object[]]$Language
    )

    $read = {
        param([string]$File)
        $document = [System.Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($File)
        $document
    }
    foreach ($admx in @(Get-ChildItem -LiteralPath $Path -File -Filter '*.admx' | Sort-Object Name)) {
        try { $document = & $read $admx.FullName } catch { "$($admx.Name) cannot be read: $($_.Exception.GetBaseException().Message)"; continue }
        if ($document.DocumentElement.LocalName -ne 'policyDefinitions') { "$($admx.Name) is not an ADMX file (its root is $($document.DocumentElement.LocalName))."; continue }
        # The strings and presentations it names: $(string.Id), $(presentation.Id), in attributes.
        $strings = [System.Collections.Generic.HashSet[string]]::new()
        $presentations = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($attribute in @($document.SelectNodes("//@*[contains(., '`$(')]"))) {
            foreach ($match in [regex]::Matches($attribute.Value, '\$\((string|presentation)\.([^)]+)\)')) {
                if ($match.Groups[1].Value -eq 'string') { [void]$strings.Add($match.Groups[2].Value) } else { [void]$presentations.Add($match.Groups[2].Value) }
            }
        }
        foreach ($item in $Language) {
            $file = Join-Path $item.Folder "$($admx.BaseName).adml"
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { "$($admx.Name) has no .adml file in $($item.Culture)."; continue }
            try { $resources = & $read $file } catch { "$($item.Culture)\$($admx.BaseName).adml cannot be read: $($_.Exception.GetBaseException().Message)"; continue }
            $have = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($node in @($resources.SelectNodes("//*[local-name()='stringTable']/*[local-name()='string']/@id"))) { [void]$have.Add($node.Value) }
            $missing = @($strings | Where-Object { -not $have.Contains($_) })
            if ($missing.Count) { "$($item.Culture)\$($admx.BaseName).adml lacks $($missing.Count) strings of $($admx.Name): $(@($missing | Select-Object -First 3) -join ', ')$(if ($missing.Count -gt 3) { '...' })." }
            $have.Clear()
            foreach ($node in @($resources.SelectNodes("//*[local-name()='presentationTable']/*[local-name()='presentation']/@id"))) { [void]$have.Add($node.Value) }
            $missing = @($presentations | Where-Object { -not $have.Contains($_) })
            if ($missing.Count) { "$($item.Culture)\$($admx.BaseName).adml lacks $($missing.Count) presentations of $($admx.Name): $(@($missing | Select-Object -First 3) -join ', ')$(if ($missing.Count -gt 3) { '...' })." }
        }
    }
}

# The namespaces of the .admx files of a folder: their target, and the namespaces they use, by
# the name of the file. Only the start of each file is read, up to its policyNamespaces.
function Get-PSGPOAdmxNamespace {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Filter '*.admx' -ErrorAction SilentlyContinue)) {
        $target = $null
        $using = [System.Collections.Generic.List[string]]::new()
        try {
            $reader = [System.Xml.XmlReader]::Create($file.FullName, $settings)
            try {
                while ($reader.Read()) {
                    if ($reader.NodeType -eq [System.Xml.XmlNodeType]::EndElement -and $reader.LocalName -eq 'policyNamespaces') { break }
                    if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                    if ($reader.LocalName -eq 'target') { $target = $reader.GetAttribute('namespace') }
                    elseif ($reader.LocalName -eq 'using') { $using.Add($reader.GetAttribute('namespace')) }
                }
            } finally {
                $reader.Dispose()
            }
        } catch {
            Write-Verbose "Namespaces of $($file.FullName) not read: $($_.Exception.Message)"
            continue
        }
        [pscustomobject]@{ Name = $file.Name; Target = $target; Using = $using.ToArray() }
    }
}

# The namespaces of the .admx files of the central store of the domain (Get-PSGPOAdmxNamespace):
# read through its share on Windows; none on Linux, where smbclient lists the files without
# reading them.
function Get-PSGPOAdmxCentralStoreNamespace {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory)

    if (-not $IsWindows) { return }
    Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL'
    Get-PSGPOAdmxNamespace -Path "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\PolicyDefinitions"
}

# The names of the .admx files of the central store of the domain (SYSVOL\<domain>\Policies\
# PolicyDefinitions), on the domain controller the directory was read from.
function Get-PSGPOAdmxCentralStoreFile {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory)

    if ($IsWindows) {
        Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL'
        return @(Get-ChildItem -LiteralPath "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\PolicyDefinitions" -File -Filter '*.admx' -ErrorAction SilentlyContinue | ForEach-Object Name)
    }
    Assert-PSGPOKerberosOnly -Directory $Directory
    $result = Invoke-PSGPOSmbClient -Server $Directory.Server -Share 'SYSVOL' -AllowMissing -IgnoreStatus 'NT_STATUS_NO_SUCH_FILE' `
        -Command ('ls "{0}\Policies\PolicyDefinitions\*.admx"' -f $Directory.DomainName)
    # "  windows.admx    A    12345  Mon Nov  2 10:00:00 2026"
    foreach ($line in @($result)) { if ("$line" -match '^\s+(.+?\.admx)\s+[A-Z]*\s+\d+\s') { $Matches[1] } }
}
