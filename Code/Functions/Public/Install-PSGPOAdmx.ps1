function Install-PSGPOAdmx {
    <#
    .SYNOPSIS
        Installs the ADMX files of Windows from the package of Microsoft: into a folder, or to create the central store of the domain.
    .DESCRIPTION
        The module does not ship ADMX files: the console reads those of the central store of the
        domain, of Windows (%windir%\PolicyDefinitions) or of the SYSVOL of a Samba domain
        controller. This command downloads the package of Microsoft, Administrative Templates
        (.admx) for Windows 11 (an .msi, from download.microsoft.com), extracts it without
        installing it (msiexec /a on Windows, msiextract of msitools on Linux and macOS) and
        installs its .admx files with their .adml files in the languages asked for (-UICulture)
        or all of them (-AllLanguages, 22 languages). The files are those of Microsoft, under its
        terms.

        The module pins the package (Resources/PolicyDefinitions.json): a download whose size or
        SHA-256 differs is refused, and so are extracted files that are not those pinned, set by
        set (the .admx files, each language), before anything is written.

        - Without -CentralStore, the files go into -Path, by default next to the module when it can
          be written to, else into the data folder of the user (PSGPOTools/PolicyDefinitions),
          where the console and Initialize-PSGPOAdmx find them.
        - With -CentralStore, they go into the central store of the domain,
          SYSVOL\<domain>\Policies\PolicyDefinitions on the domain controller the directory comes
          from (Windows: its share; Linux: smbclient with Kerberos), as an administrator creates it
          for GPMC: every console of the domain then reads them. The files already there (the ADMX
          files of other products) are kept, those of the same name replaced.

        A computer without internet: download the package on another computer (the page of
        Microsoft is in the error of a failed download) and give it with -MsiPath; it is checked as
        a download is.
    .PARAMETER UICulture
        The languages of the .adml files to install (en-US, fr-FR...); by default en-US and the
        language of the session.
    .PARAMETER AllLanguages
        The 22 languages.
    .PARAMETER Path
        The PolicyDefinitions folder to write; next to the module, else the data folder of the user, by default.
    .PARAMETER CentralStore
        Writes the central store of the domain (SYSVOL\<domain>\Policies\PolicyDefinitions).
    .PARAMETER Directory
        With -CentralStore: the domain (from Get-PSGPODirectory); the domain of the computer by default.
    .PARAMETER Server
        With -CentralStore: the domain controller to read the domain from and write to.
    .PARAMETER MsiPath
        The package of Microsoft downloaded beforehand (the .msi file): nothing is downloaded. It
        must be the package the module pins.
    .PARAMETER Force
        Writes even when ADMX files are already there.
    .EXAMPLE
        Install-PSGPOAdmx
        The .admx files, with their en-US .adml files and those of the language of the session,
        next to the module.
    .EXAMPLE
        Install-PSGPOAdmx -CentralStore -Server dc.hardenbox.labo -UICulture en-US, fr-FR
        Creates the central store of the domain, in English and French.
    .EXAMPLE
        Install-PSGPOAdmx -AllLanguages -Path ~/PolicyDefinitions; Initialize-PSGPOAdmx -Path ~/PolicyDefinitions
    .EXAMPLE
        Install-PSGPOAdmx -MsiPath 'D:\Administrative Templates (.admx) for Windows 11 Sep 2026 Update.msi'
        From the package copied to a computer without internet.
    .OUTPUTS
        PSGPOTools.AdmxInstall
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/install-psgpoadmx/
    .LINK
        Initialize-PSGPOAdmx
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Folder')]
    [OutputType('PSGPOTools.AdmxInstall')]
    param(
        [string[]]$UICulture,
        [switch]$AllLanguages,
        [Parameter(ParameterSetName = 'Folder')] [string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'CentralStore')] [switch]$CentralStore,
        [Parameter(ParameterSetName = 'CentralStore')] [GPOToolsDirectory]$Directory,
        [Parameter(ParameterSetName = 'CentralStore')] [string]$Server,
        [string]$MsiPath,
        [switch]$Force
    )

    if ($UICulture -and $AllLanguages) { throw 'Give -UICulture or -AllLanguages, not both.' }
    $catalog = Get-PSGPOAdmxCatalog
    $package = Get-PSGPOAdmxPackage
    $languages = @(Resolve-PSGPOAdmxLanguage -Available @($catalog.Name | Where-Object { $_ -ne '.' }) -Language $UICulture -All:$AllLanguages)
    if ($MsiPath) {
        $MsiPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($MsiPath)
        if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) { throw "No file '$MsiPath': give the path of '$($package.FileName)'." }
    }

    if ($CentralStore) {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        if ($Directory -isnot [GPOToolsLdapDirectory]) { throw 'The central store is in SYSVOL: read the domain from a domain controller (Get-PSGPODirectory).' }
        $target = "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\PolicyDefinitions"
        if ((Test-PSGPOAdmxCentralStore -Directory $Directory) -and -not $Force) {
            throw "The central store of $($Directory.DomainName) has ADMX files ($target): give -Force to add those of Windows, the others kept."
        }
    } else {
        if (-not $Path) {
            foreach ($candidate in @(Get-PSGPOAdmxInstallFolder)) {
                $parent = Split-Path -Parent $candidate
                try {
                    $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
                    $probe = Join-Path $parent ".write-$([guid]::NewGuid())"
                    [System.IO.File]::WriteAllText($probe, '')
                    Remove-Item -LiteralPath $probe -Force
                    $Path = $candidate
                    break
                } catch {
                    Write-Verbose "Not writable: $parent"
                }
            }
            if (-not $Path) { throw 'No folder to install the ADMX files in: neither the module nor the data folder of the user can be written to; give -Path.' }
        }
        $target = [System.IO.Path]::GetFullPath($Path)
        if ((Get-ChildItem -LiteralPath $target -File -Filter '*.admx' -ErrorAction SilentlyContinue | Select-Object -First 1) -and -not $Force) {
            throw "ADMX files are already in '$target': give -Force to write those of Windows, the others kept."
        }
    }
    $from = if ($MsiPath) { $MsiPath } else { $package.Uri }
    if (-not $PSCmdlet.ShouldProcess($target, "install the ADMX files ($($languages -join ', ')) of $($package.Name), from $from")) { return }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-Admx-$([guid]::NewGuid().ToString('N'))"
    $msi = Join-Path $work 'package.msi'
    $staging = Join-Path $work 'PolicyDefinitions'
    $null = New-Item -ItemType Directory -Path $work -Force
    try {
        Write-Progress -Activity 'Installing the ADMX files' -Status $from
        $save = @{ Path = $msi; Package = $package }
        if ($MsiPath) { $save.Source = $MsiPath }
        Save-PSGPOAdmxPackage @save
        Write-Progress -Activity 'Installing the ADMX files' -Status "Extracting $($package.FileName)"
        Expand-PSGPOAdmxPackage -Package $msi -Folder $staging -Language $languages -Catalog $catalog
        $files = @(Get-ChildItem -LiteralPath $staging -File -Recurse).Count
        if ($CentralStore) {
            Write-Progress -Activity 'Installing the ADMX files' -Status $target
            $target = Copy-PSGPOAdmxCentralStore -Directory $Directory -Source $staging
            Write-PSGPOAuditEntry -Directory $Directory -Action 'InstallAdmx' -Target $target -Details @{ Languages = $languages; Files = $files; Package = $package.Name; Sha256 = $package.Sha256 }
        } else {
            $null = New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop
            Copy-Item -Path (Join-Path $staging '*') -Destination $target -Recurse -Force -ErrorAction Stop
        }
        Write-Progress -Activity 'Installing the ADMX files' -Completed
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.AdmxInstall'
            Path       = $target
            Languages  = $languages
            Files      = $files
            Package    = $package.Name
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
