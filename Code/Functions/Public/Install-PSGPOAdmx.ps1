function Install-PSGPOAdmx {
    <#
    .SYNOPSIS
        Downloads the ADMX files of HGPM from GitHub: into a folder, or to create the central store of the domain.
    .DESCRIPTION
        The module does not ship ADMX files: the console reads those of the central store of the
        domain, of Windows (%windir%\PolicyDefinitions) or of the SYSVOL of a Samba domain
        controller. This command downloads the copy of the repository (sources/PolicyDefinitions:
        the .admx files and their .adml files in 22 languages) from GitHub, at the tag of the
        version of the module, with the languages asked for (-UICulture) or all of them
        (-AllLanguages).

        Each set of files (the .admx files, each language) is checked against the SHA-256 the
        module pins (Resources/PolicyDefinitions.json) before anything is written: a download that
        differs is refused, nothing installed.

        - Without -CentralStore, the files go into -Path, by default next to the module when it can
          be written to, else into the data folder of the user (PSGPOTools/PolicyDefinitions),
          where the console and Initialize-PSGPOAdmx find them.
        - With -CentralStore, they go into the central store of the domain,
          SYSVOL\<domain>\Policies\PolicyDefinitions on the domain controller the directory comes
          from (Windows: its share; Linux: smbclient with Kerberos), as an administrator creates it
          for GPMC: every console of the domain then reads them. The files already there (the ADMX
          files of other products) are kept, those of the same name replaced.
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
    .PARAMETER Ref
        The tag, branch or commit of the repository to download; the tag of the version of the
        module (v0.1.2-alpha) by default. Its files must be those the module pins.
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
        [string]$Ref,
        [switch]$Force
    )

    if ($UICulture -and $AllLanguages) { throw 'Give -UICulture or -AllLanguages, not both.' }
    $catalog = Get-PSGPOAdmxCatalog
    $languages = @(Resolve-PSGPOAdmxLanguage -Available @($catalog.Name | Where-Object { $_ -ne '.' }) -Language $UICulture -All:$AllLanguages)
    if (-not $Ref) {
        $module = $MyInvocation.MyCommand.Module
        $prerelease = "$($module.PrivateData.PSData.Prerelease)".Trim()
        $Ref = "v$($module.Version)$(if ($prerelease) { "-$prerelease" })"
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
            throw "The central store of $($Directory.DomainName) has ADMX files ($target): give -Force to add those of HGPM, the others kept."
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
            throw "ADMX files are already in '$target': give -Force to write those of HGPM, the others kept."
        }
    }
    $uri = "https://github.com/JM2K69/PSGPOTools/archive/$Ref.zip"
    if (-not $PSCmdlet.ShouldProcess($target, "install the ADMX files ($($languages -join ', ')) of $uri")) { return }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-Admx-$([guid]::NewGuid().ToString('N'))"
    $archive = Join-Path $work 'archive.zip'
    $staging = Join-Path $work 'PolicyDefinitions'
    $null = New-Item -ItemType Directory -Path $work -Force
    try {
        Write-Progress -Activity 'Installing the ADMX files' -Status $uri
        try { Invoke-WebRequest -Uri $uri -OutFile $archive -UseBasicParsing -ErrorAction Stop }
        catch { throw "Cannot download $uri ($($_.Exception.Message)): a version not released has no tag yet, give -Ref with a branch (-Ref master)." }
        Expand-PSGPOAdmxArchive -Archive $archive -Folder $staging -Language $languages -Catalog $catalog
        $files = @(Get-ChildItem -LiteralPath $staging -File -Recurse).Count
        if ($CentralStore) {
            Write-Progress -Activity 'Installing the ADMX files' -Status $target
            $target = Copy-PSGPOAdmxCentralStore -Directory $Directory -Source $staging
            Write-PSGPOAuditEntry -Directory $Directory -Action 'InstallAdmx' -Target $target -Details @{ Languages = $languages; Files = $files; Ref = $Ref }
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
            Ref        = $Ref
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
