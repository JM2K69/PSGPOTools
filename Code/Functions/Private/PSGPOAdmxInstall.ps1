<#
    The ADMX files of the repository (sources/PolicyDefinitions), downloaded from GitHub rather
    than shipped with the module: Install-PSGPOAdmx. Resources/PolicyDefinitions.json pins each
    set of files (the .admx files, then each language folder of .adml files): its number of files
    and a SHA-256 of their names and contents. A download that is not the set pinned is refused,
    nothing installed.
#>

# The SHA-256 of a set of files: one line per file, "<name><tab><SHA-256 of its content>", in the
# ordinal order of the names (in lower case: a checkout on Windows may change their case), joined
# with line feeds, hashed as UTF-8. The content is hashed with its line endings as Git stores
# them (CR LF as LF): a checkout on Windows (CR LF) and the archive of GitHub (LF) have one hash.
function Get-PSGPOAdmxSetHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [System.IO.FileInfo[]]$File)

    $latin1 = [System.Text.Encoding]::Latin1
    [string[]]$lines = foreach ($item in $File) {
        $content = $latin1.GetBytes($latin1.GetString([System.IO.File]::ReadAllBytes($item.FullName)).Replace("`r`n", "`n"))
        "$($item.Name.ToLowerInvariant())`t$([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($content)))"
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
            if (-not $found) { throw "No '$name' language in the ADMX files of HGPM: $($Available -join ', ')." }
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


# Extracts the sets asked for from an archive of the repository (GitHub: <repository>-<ref>/...)
# into $Folder, and checks each one against the catalog: throws when one differs.
function Expand-PSGPOAdmxArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Archive,
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Language,
        [object[]]$Catalog = (Get-PSGPOAdmxCatalog)
    )

    $wanted = @('.') + $Language
    $null = New-Item -ItemType Directory -Path $Folder -Force
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $match = [regex]::Match($entry.FullName, '^[^/]+/sources/PolicyDefinitions/(?:([^/]+)/)?([^/]+\.(admx|adml))$', 'IgnoreCase')
            if (-not $match.Success) { continue }
            $set = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { '.' }
            if ($set -eq '.' -and $match.Groups[3].Value -ne 'admx') { continue }
            if (-not ($wanted | Where-Object { [string]::Equals($_, $set, [System.StringComparison]::OrdinalIgnoreCase) })) { continue }
            $target = if ($set -eq '.') { $Folder } else { Join-Path $Folder $set }
            $null = New-Item -ItemType Directory -Path $target -Force
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $target $match.Groups[2].Value), $true)
        }
    } finally { $zip.Dispose() }

    # Nothing is installed from a download that is not the files pinned.
    $sets = @(Get-PSGPOAdmxSet -Path $Folder)
    foreach ($name in $wanted) {
        $pinned = $Catalog | Where-Object { [string]::Equals($_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        $got = $sets | Where-Object { [string]::Equals($_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        $label = if ($name -eq '.') { 'the .admx files' } else { "the $name .adml files" }
        if (-not $pinned) { throw "No '$name' set in the catalog of the ADMX files." }
        if (-not $got) { throw "The download has none of ${label}: nothing is installed." }
        if ($got.Files -ne $pinned.Files -or $got.Sha256 -ne $pinned.Sha256) {
            throw "The download is not the ADMX files of this version of HGPM ($label differ: $($got.Files) files, $($pinned.Files) expected): nothing is installed."
        }
    }
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
