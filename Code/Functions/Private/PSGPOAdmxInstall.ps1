<#
    The ADMX files of Windows, neither shipped with the module nor kept in its repository: the
    files of Microsoft are not ours to publish. Install-PSGPOAdmx downloads the package of
    Microsoft (Administrative Templates (.admx) for Windows 11, an .msi) and extracts its
    PolicyDefinitions folder. Resources/PolicyDefinitions.json pins that package (its address,
    size and SHA-256) and each set of files it holds (the .admx files, then each language folder
    of .adml files: its number of files and a SHA-256 of their names and contents). A package or
    files that are not those pinned are refused, nothing installed.
#>

# The SHA-256 of a set of files: one line per file, "<name><tab><SHA-256 of its content>", in the
# ordinal order of the names (in lower case: the package names a few files in lower case, a
# copy may change their case), joined with line feeds, hashed as UTF-8. The content is hashed
# as it is, bytes only: on Windows a file read as a string is scanned by AMSI (a minute for the
# 5000 files of the package).
function Get-PSGPOAdmxSetHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [System.IO.FileInfo[]]$File)

    [string[]]$lines = foreach ($item in $File) {
        "$($item.Name.ToLowerInvariant())`t$([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($item.FullName))))"
    }
    [Array]::Sort($lines, [System.StringComparer]::Ordinal)
    [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))
}

# The sets of a PolicyDefinitions folder, as the catalog pins them: '.' for the .admx files, the
# name of each language folder for its .adml files.
function Get-PSGPOAdmxSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    $admx = @(Get-ChildItem -LiteralPath $Path -File -Filter '*.admx')
    if ($admx.Count) { [pscustomobject]@{ Name = '.'; Files = $admx.Count; Sha256 = Get-PSGPOAdmxSetHash -File $admx } }
    foreach ($folder in @(Get-ChildItem -LiteralPath $Path -Directory | Sort-Object Name)) {
        $adml = @(Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.adml')
        # The name of the culture (fr-FR), whatever the case of the folder.
        $name = try { [cultureinfo]::GetCultureInfo($folder.Name).Name } catch { $folder.Name }
        if ($adml.Count) { [pscustomobject]@{ Name = $name; Files = $adml.Count; Sha256 = Get-PSGPOAdmxSetHash -File $adml } }
    }
}

# The sets pinned by the module (Resources/PolicyDefinitions.json).
function Get-PSGPOAdmxCatalog {
    [CmdletBinding()]
    param()

    @((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Resources' 'PolicyDefinitions.json') -Raw | ConvertFrom-Json).Sets)
}

# The package of Microsoft pinned by the module (Resources/PolicyDefinitions.json): Name, Page,
# Uri, FileName, Size, Sha256.
function Get-PSGPOAdmxPackage {
    [CmdletBinding()]
    param()

    (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Resources' 'PolicyDefinitions.json') -Raw | ConvertFrom-Json).Package
}

# The package of Microsoft into $Path: downloaded, or copied from $Source (a copy downloaded on
# another computer). Throws when it is not the package pinned (its size, its SHA-256).
function Save-PSGPOAdmxPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$Source,
        [object]$Package = (Get-PSGPOAdmxPackage)
    )

    if ($Source) {
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "No file '$Source': give the path of '$($Package.FileName)'." }
        Copy-Item -LiteralPath $Source -Destination $Path -Force -ErrorAction Stop
    } else {
        try { Invoke-WebRequest -Uri $Package.Uri -OutFile $Path -UseBasicParsing -ErrorAction Stop }
        catch { throw "Cannot download $($Package.Uri) ($($_.Exception.Message)): download '$($Package.FileName)' on another computer ($($Package.Page)) and give it with -MsiPath." }
    }
    $size = (Get-Item -LiteralPath $Path).Length
    $sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($size -ne $Package.Size -or $sha256 -ne $Package.Sha256) {
        $from = if ($Source) { "'$Source'" } else { "The download of $($Package.Uri)" }
        throw "$from is not the package HGPM pins, $($Package.Name) (SHA-256 $sha256, $($Package.Sha256) expected; $size bytes, $($Package.Size) expected): nothing is installed."
    }
}

# Extracts every file of an .msi into $Folder, without installing it: an administrative install
# (msiexec /a) on Windows, msiextract (msitools) elsewhere.
function Expand-PSGPOAdmxMsi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Package,
        [Parameter(Mandatory)] [string]$Folder
    )

    $null = New-Item -ItemType Directory -Path $Folder -Force
    if ($IsWindows) {
        $log = Join-Path ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Folder))) 'msiexec.log'
        # One command line: msiexec reads TARGETDIR="<folder>", not a quoted "TARGETDIR=<folder>".
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/a `"$Package`" /qn TARGETDIR=`"$Folder`" /l*v `"$log`"" -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            $detail = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error|failed' } | Select-Object -Last 3) -join ' '
            throw "msiexec /a could not extract '$Package' (exit code $($process.ExitCode)). $detail"
        }
        return
    }
    $msiextract = Get-Command -Name 'msiextract' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $msiextract) {
        throw 'msiextract reads the package of Microsoft (an .msi) on Linux and macOS: install msitools (sudo apt install msitools on Debian and Ubuntu, sudo dnf install msitools on Fedora and RHEL, brew install msitools on macOS).'
    }
    $result = Invoke-PSGPONativeCommand -FilePath $msiextract.Source -ArgumentList '-C', $Folder, $Package -TimeoutSeconds 600
    if ($result.ExitCode -ne 0) { throw "msiextract could not extract '$Package' (exit code $($result.ExitCode)): $($result.Error)" }
}

# The PolicyDefinitions folder of an extracted package: <Program Files>/Microsoft Group
# Policy/<version of Windows>/PolicyDefinitions, the folder of .admx files.
function Get-PSGPOAdmxPackageFolder {
    [CmdletBinding()]
    [OutputType([System.IO.DirectoryInfo])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        # The .msi, for the error.
        [string]$Package
    )

    $found = Get-ChildItem -LiteralPath $Path -Directory -Recurse -Filter 'PolicyDefinitions' |
        Where-Object { Get-ChildItem -LiteralPath $_.FullName -File -Filter '*.admx' | Select-Object -First 1 } | Select-Object -First 1
    if (-not $found) { throw "No PolicyDefinitions folder of .admx files in '$Package': nothing is installed." }
    $found
}

# Throws unless the sets $Name of the PolicyDefinitions folder $Path are those of the catalog.
function Assert-PSGPOAdmxSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string[]]$Name,
        [object[]]$Catalog = (Get-PSGPOAdmxCatalog)
    )

    $sets = @(Get-PSGPOAdmxSet -Path $Path)
    foreach ($item in $Name) {
        $pinned = $Catalog | Where-Object { [string]::Equals($_.Name, $item, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        $got = $sets | Where-Object { [string]::Equals($_.Name, $item, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        $label = if ($item -eq '.') { 'the .admx files' } else { "the $item .adml files" }
        if (-not $pinned) { throw "No '$item' set in the catalog of the ADMX files." }
        if (-not $got) { throw "The package has none of ${label}: nothing is installed." }
        if ($got.Files -ne $pinned.Files -or $got.Sha256 -ne $pinned.Sha256) {
            throw "The package does not hold the ADMX files HGPM pins ($label differ: $($got.Files) files, $($pinned.Files) expected): nothing is installed."
        }
    }
}

# Where Install-PSGPOAdmx puts the files: next to the module, else the data folder of the user.
# Get-PSGPOAdmxCandidate looks in both.
function Get-PSGPOAdmxInstallFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path $PSScriptRoot 'sources' 'PolicyDefinitions'
    $data = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $data) { $data = Join-Path $HOME '.local' 'share' }
    Join-Path $data 'PSGPOTools' 'PolicyDefinitions'
}

# The languages to install by default: en-US, and the language of the session when the catalog has it.
function Resolve-PSGPOAdmxLanguage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string[]]$Available,
        [string[]]$Language,
        [switch]$All,
        [cultureinfo]$Current = [cultureinfo]::CurrentUICulture
    )

    $pick = {
        param([string]$Name)
        $Available | Where-Object { [string]::Equals($_, $Name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    }
    if ($All) { return $Available }
    if ($Language) {
        foreach ($name in $Language) {
            $found = & $pick $name
            if (-not $found) { throw "No '$name' language in the ADMX files of Windows: $($Available -join ', ')." }
            $found
        }
        return
    }
    & $pick 'en-US'
    if ($Current -and $Current.Name) {
        $found = & $pick $Current.Name
        if (-not $found) { $found = $Available | Where-Object { ([cultureinfo]::GetCultureInfo($_)).TwoLetterISOLanguageName -eq $Current.TwoLetterISOLanguageName } | Select-Object -First 1 }
        if ($found -and $found -ne 'en-US') { $found }
    }
}


# Extracts the sets asked for from the package of Microsoft (an .msi) into $Folder, each language
# folder named after its culture (the package names them in lower case, fr-fr), and checks each
# set against the catalog: throws when one differs.
function Expand-PSGPOAdmxPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Package,
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Language,
        [object[]]$Catalog = (Get-PSGPOAdmxCatalog)
    )

    $wanted = @('.') + $Language
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-Msi-$([guid]::NewGuid().ToString('N'))"
    try {
        $expanded = Join-Path $work 'msi'
        Expand-PSGPOAdmxMsi -Package $Package -Folder $expanded
        $source = Get-PSGPOAdmxPackageFolder -Path $expanded -Package $Package

        $null = New-Item -ItemType Directory -Path $Folder -Force
        Copy-Item -Path (Join-Path $source.FullName '*.admx') -Destination $Folder -Force -ErrorAction Stop
        # $languageFolder, not $folder: PowerShell would take it for the parameter $Folder.
        foreach ($languageFolder in @(Get-ChildItem -LiteralPath $source.FullName -Directory)) {
            $culture = try { [cultureinfo]::GetCultureInfo($languageFolder.Name).Name } catch { continue }
            if (-not ($Language | Where-Object { [string]::Equals($_, $culture, [System.StringComparison]::OrdinalIgnoreCase) })) { continue }
            $target = Join-Path $Folder $culture
            $null = New-Item -ItemType Directory -Path $target -Force
            Copy-Item -Path (Join-Path $languageFolder.FullName '*.adml') -Destination $target -Force -ErrorAction Stop
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Nothing is installed from files that are not those pinned.
    Assert-PSGPOAdmxSet -Path $Folder -Name $wanted -Catalog $Catalog
}

# The central store of the domain (SYSVOL\<domain>\Policies\PolicyDefinitions) on the domain
# controller the directory was read from: is there an .admx file in it?
function Test-PSGPOAdmxCentralStore {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory)

    if ($IsWindows) {
        Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL'
        return [bool](Get-ChildItem -LiteralPath "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\PolicyDefinitions" -File -Filter '*.admx' -ErrorAction SilentlyContinue | Select-Object -First 1)
    }
    Assert-PSGPOKerberosOnly -Directory $Directory
    $result = Invoke-PSGPOSmbClient -Server $Directory.Server -Share 'SYSVOL' -AllowMissing -IgnoreStatus 'NT_STATUS_NO_SUCH_FILE' `
        -Command ('ls "{0}\Policies\PolicyDefinitions\*.admx"' -f $Directory.DomainName)
    [bool]@($result | Where-Object { $_ -match '\.admx\s' }).Count
}

# Copies a PolicyDefinitions folder into the central store of the domain, the files there kept
# (the ADMX files of other products) or replaced when they have the same name.
function Copy-PSGPOAdmxCentralStore {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Source,
        # The folder in Policies (another than the central store for the tests).
        [string]$Folder = 'PolicyDefinitions'
    )

    if ($IsWindows) {
        Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL'
        $store = "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\$Folder"
        $null = New-Item -ItemType Directory -Path $store -Force -ErrorAction Stop
        Copy-Item -Path (Join-Path $Source '*') -Destination $store -Recurse -Force -ErrorAction Stop
        return $store
    }
    Assert-PSGPOKerberosOnly -Directory $Directory
    # One smbclient for every file: mput with recurse creates the language folders.
    $null = Invoke-PSGPOSmbClient -Server $Directory.Server -Share 'SYSVOL' -TimeoutSeconds 1800 -IgnoreStatus 'NT_STATUS_OBJECT_NAME_COLLISION' `
        -Command ('prompt OFF; recurse ON; lcd "{0}"; cd "{1}\Policies"; mkdir "{2}"; cd "{2}"; mput *' -f $Source, $Directory.DomainName, $Folder)
    "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\$Folder"
}
