function Install-PSGPOProductAdmx {
    <#
    .SYNOPSIS
        Installs the ADMX files of other products than Windows (Office, Firefox, Adobe, Edge, Chrome...) from their publishers, or from a folder: into a folder, or into the central store of the domain.
    .DESCRIPTION
        Install-PSGPOAdmx installs the ADMX files of Windows; this command those of the products
        HGPM pins (Get-PSGPOProductAdmx lists them), downloaded from their publishers:
        - Office: Microsoft 365 Apps, Office LTSC and Office 2016 to 2024 (Microsoft);
        - Firefox (Mozilla);
        - AdobeAcrobat and AdobeReader: Adobe Acrobat and Acrobat Reader (Adobe);
        - Edge (Microsoft);
        - Chrome and GoogleUpdate (Google).
        Their files are those of their publishers, under their terms.

        The module pins each package (Resources/AdmxProducts.json): its address, size and SHA-256,
        and the SHA-256 of each of its .admx and .adml files. A download that differs is refused,
        and so is a package without one of the files pinned, before anything is written. The
        package is read without running anything: a zip archive, a cabinet (expand on Windows,
        cabextract or 7-Zip on Linux and macOS), or the cabinet the program of Office holds. A
        newer version than the one pinned: extract it, and install its folder with -SourcePath.

        -SourcePath installs the ADMX files of any product from a PolicyDefinitions folder: its
        ADMX files, and one folder per language (en-US, fr-FR...) with their ADML files. The folder
        is checked as GPMC reads it: every .admx file has its .adml file in each language
        installed, with the strings and presentations it names. The folders of the languages are named after
        their culture (fr-FR, not fr-fr: the SYSVOL of Samba tells them apart).

        - Without -CentralStore, the files go into -Path, by default the folder of
          Install-PSGPOAdmx that holds the ADMX files of Windows (next to the module, else in the
          data folder of the user), as the console reads one folder.
        - With -CentralStore, they go into the central store of the domain,
          SYSVOL\<domain>\Policies\PolicyDefinitions on the domain controller the directory comes
          from (Windows: its share; Linux: smbclient with Kerberos), with the ADMX files of
          Windows: every console of the domain, GPMC and HGPM, then reads them. The other files
          are kept; the install is written to the audit log.

        The .admx files of the product already there are replaced with -Force only. A file that
        declares the namespace of a file of another name already there is refused: GPMC refuses a
        store where two files declare one namespace. A product whose files use those of Windows
        (windows.admx) is installed with a warning when they are not there.
    .PARAMETER Name
        The products pinned to install (Get-PSGPOProductAdmx): Office, Firefox, AdobeAcrobat,
        AdobeReader, Edge, Chrome, GoogleUpdate.
    .PARAMETER SourcePath
        A PolicyDefinitions folder to install, instead of a product pinned: its .admx files, and
        one folder per language with the .adml files.
    .PARAMETER UICulture
        The languages of the .adml files to install (en-US, fr-FR...); by default en-US and the
        language of the session. A language a product does not have is left with a warning (GPMC
        and HGPM show its policies in en-US).
    .PARAMETER AllLanguages
        Every language of the product.
    .PARAMETER Path
        The PolicyDefinitions folder to write; by default the one that holds the ADMX files of
        Windows installed by Install-PSGPOAdmx.
    .PARAMETER CentralStore
        Writes the central store of the domain (SYSVOL\<domain>\Policies\PolicyDefinitions).
    .PARAMETER Directory
        With -CentralStore: the domain (from Get-PSGPODirectory); the domain of the computer by default.
    .PARAMETER Server
        With -CentralStore: the domain controller to read the domain from and write to.
    .PARAMETER PackagePath
        The package of the product downloaded beforehand (one product, -Name): nothing is
        downloaded. It must be the package the module pins.
    .PARAMETER Force
        Replaces the .admx files of the product already there.
    .EXAMPLE
        Install-PSGPOProductAdmx -Name Office, Firefox -CentralStore -Server dc.hardenbox.labo -UICulture en-US, fr-FR
        Adds the ADMX files of Office and Firefox to the central store of the domain, in English and French.
    .EXAMPLE
        Install-PSGPOProductAdmx -Name Edge, Chrome, GoogleUpdate
        Next to those of Windows installed by Install-PSGPOAdmx, in en-US and the language of the session.
    .EXAMPLE
        Install-PSGPOProductAdmx -SourcePath ~/Downloads/Zoom/PolicyDefinitions -CentralStore -Server dc.hardenbox.labo
        The ADMX files of another product, checked, then added to the central store.
    .EXAMPLE
        Install-PSGPOProductAdmx -Name Office -PackagePath D:\admintemplates_x64_5568_1000_en-us.exe -AllLanguages
        From the package copied to a computer without internet.
    .OUTPUTS
        PSGPOTools.AdmxInstall
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/install-psgpoproductadmx/
    .LINK
        Get-PSGPOProductAdmx
    .LINK
        Install-PSGPOAdmx
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Product')]
    [OutputType('PSGPOTools.AdmxInstall')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Product')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ProductCentralStore')]
        [string[]]$Name,

        [Parameter(Mandatory, ParameterSetName = 'Source')]
        [Parameter(Mandatory, ParameterSetName = 'SourceCentralStore')]
        [string]$SourcePath,

        [string[]]$UICulture,
        [switch]$AllLanguages,

        [Parameter(ParameterSetName = 'Product')]
        [Parameter(ParameterSetName = 'Source')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'ProductCentralStore')]
        [Parameter(Mandatory, ParameterSetName = 'SourceCentralStore')]
        [switch]$CentralStore,

        [Parameter(ParameterSetName = 'ProductCentralStore')]
        [Parameter(ParameterSetName = 'SourceCentralStore')]
        [GPOToolsDirectory]$Directory,

        [Parameter(ParameterSetName = 'ProductCentralStore')]
        [Parameter(ParameterSetName = 'SourceCentralStore')]
        [string]$Server,

        [Parameter(ParameterSetName = 'Product')]
        [Parameter(ParameterSetName = 'ProductCentralStore')]
        [string]$PackagePath,

        [switch]$Force
    )

    if ($UICulture -and $AllLanguages) { throw 'Give -UICulture or -AllLanguages, not both.' }
    $catalog = @(Get-PSGPOAdmxProductCatalog)

    # What to install: the products pinned, or the folder given.
    $items = [System.Collections.Generic.List[object]]::new()
    if ($SourcePath) {
        $SourcePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($SourcePath)
        if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) { throw "No folder '$SourcePath': give a PolicyDefinitions folder (the .admx files, and one folder per language with the .adml files)." }
        $own = @(Get-ChildItem -LiteralPath $SourcePath -File -Filter '*.admx' | ForEach-Object Name)
        if (-not $own.Count) { throw "No .admx file in '$SourcePath': give a PolicyDefinitions folder (the .admx files, and one folder per language with the .adml files)." }
        $sourceLanguages = @(Get-PSGPOAdmxSourceLanguage -Path $SourcePath)
        if (-not $sourceLanguages.Count) { throw "No folder of .adml files named after a language in '$SourcePath' (en-US, fr-FR...)." }
        $items.Add([pscustomobject]@{ Product = $null; Label = "the ADMX files of $SourcePath"; Package = $SourcePath; Available = @($sourceLanguages.Culture); Own = $own; Sources = $sourceLanguages })
    } else {
        if ($PackagePath -and @($Name).Count -ne 1) { throw 'Give -PackagePath with one product (-Name).' }
        foreach ($product in @(Get-PSGPOAdmxProductCatalog -Name $Name)) {
            if (@($items | Where-Object { $_.Product.Name -eq $product.Name }).Count) { continue }
            $items.Add([pscustomobject]@{
                    Product = $product; Label = "$($product.DisplayName) $($product.Version)"; Package = "$($product.DisplayName) $($product.Version)"
                    Available = @(Get-PSGPOAdmxProductLanguage -Product $product); Own = @(Get-PSGPOAdmxProductOwnFile -Product $product -Catalog $catalog); Sources = $null
                })
        }
    }
    if ($PackagePath) {
        $PackagePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($PackagePath)
        if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { throw "No file '$PackagePath': give the path of '$($items[0].Product.FileName)'." }
    }

    # Where: the central store of the domain, or a folder; the .admx files already there.
    if ($CentralStore) {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        if ($Directory -isnot [GPOToolsLdapDirectory]) { throw 'The central store is in SYSVOL: read the domain from a domain controller (Get-PSGPODirectory).' }
        $target = "\\$($Directory.Server)\SYSVOL\$($Directory.DomainName)\Policies\PolicyDefinitions"
        $present = @(Get-PSGPOAdmxCentralStoreFile -Directory $Directory)
        # The namespaces of the files there are read through the share of Windows only.
        $readable = [bool]$IsWindows
    } else {
        if (-not $Path) { $Path = Resolve-PSGPOAdmxInstallPath -PreferExisting }
        $target = [System.IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path))
        $present = @(Get-ChildItem -LiteralPath $target -File -Filter '*.admx' -ErrorAction SilentlyContinue | ForEach-Object Name)
        $readable = $true
    }
    $there = [System.Collections.Generic.HashSet[string]]::new([string[]]$present, [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $items) {
        $already = @($item.Own | Where-Object { $there.Contains($_) })
        if ($already.Count -and -not $Force) {
            throw "The ADMX files of $($item.Label) are already in '$target' ($($already -join ', ')): give -Force to replace them."
        }
    }
    $namespaces = if ($CentralStore) { @(Get-PSGPOAdmxCentralStoreNamespace -Directory $Directory) } else { @(Get-PSGPOAdmxNamespace -Path $target) }

    foreach ($item in $items) {
        # The languages: those asked for that the product has, the others left with a warning.
        $languages = if ($UICulture) {
            $known = @($UICulture | Where-Object { $culture = $_; $item.Available | Where-Object { [string]::Equals($_, $culture, [System.StringComparison]::OrdinalIgnoreCase) } })
            foreach ($culture in @($UICulture | Where-Object { $known -notcontains $_ })) {
                Write-Warning "$($item.Label) has no $culture .adml files ($($item.Available -join ', ')): GPMC and HGPM show its policies in en-US."
            }
            if (-not $known.Count) { throw "None of the languages asked for ($($UICulture -join ', ')) in $($item.Label): $($item.Available -join ', ')." }
            @(Resolve-PSGPOAdmxLanguage -Available $item.Available -Language $known -Product $item.Label)
        } else {
            @(Resolve-PSGPOAdmxLanguage -Available $item.Available -All:$AllLanguages -Product $item.Label)
        }
        if (-not $languages.Count) { throw "$($item.Label) has no en-US .adml files: give -UICulture ($($item.Available -join ', '))." }

        $from = if ($item.Product) { if ($PackagePath) { $PackagePath } else { $item.Product.Uri } } else { $SourcePath }
        if (-not $PSCmdlet.ShouldProcess($target, "install the ADMX files ($($languages -join ', ')) of $($item.Label), from $from")) { continue }

        $work = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-Admx-$([guid]::NewGuid().ToString('N'))"
        $staging = Join-Path $work 'PolicyDefinitions'
        $null = New-Item -ItemType Directory -Path $staging -Force
        try {
            Write-Progress -Activity "Installing the ADMX files of $($item.Label)" -Status $from
            if ($item.Product) {
                $product = $item.Product
                $package = Join-Path $work $product.FileName
                $pin = [pscustomobject]@{ Name = $item.Label; Page = $product.Page; Uri = $product.Uri; FileName = $product.FileName; Size = $product.Size; Sha256 = $product.Sha256 }
                $save = @{ Path = $package; Package = $pin; SourceParameter = 'PackagePath' }
                if ($PackagePath) { $save.Source = $PackagePath }
                Save-PSGPOAdmxPackage @save
                Write-Progress -Activity "Installing the ADMX files of $($item.Label)" -Status "Extracting $($product.FileName)"
                $files = Expand-PSGPOAdmxProductPackage -Package $package -Product $product -Folder $staging -Language $languages
            } else {
                $chosen = @($item.Sources | Where-Object { $languages -contains $_.Culture })
                $problems = @(Test-PSGPOAdmxSourceFolder -Path $SourcePath -Language $chosen)
                if ($problems.Count) {
                    throw "GPMC cannot read the ADMX files of '$SourcePath' ($($problems.Count) problems: $(@($problems | Select-Object -First 3) -join ' ')$(if ($problems.Count -gt 3) { ' ...' })): nothing is installed."
                }
                Copy-Item -Path (Join-Path $SourcePath '*.admx') -Destination $staging -ErrorAction Stop
                foreach ($source in $chosen) {
                    # The folder named after the culture (fr-FR), whatever its case in the source.
                    $folder = Join-Path $staging $source.Culture
                    $null = New-Item -ItemType Directory -Path $folder -Force
                    Copy-Item -Path (Join-Path $source.Folder '*.adml') -Destination $folder -ErrorAction Stop
                }
                $files = @(Get-ChildItem -LiteralPath $staging -File -Recurse).Count
            }

            # GPMC refuses a store where two files declare one namespace; and reads the files of the
            # product only with the files whose namespaces they use.
            $staged = @(Get-PSGPOAdmxNamespace -Path $staging)
            foreach ($file in $staged) {
                $clash = @($namespaces | Where-Object { $_.Target -and $_.Target -eq $file.Target -and -not [string]::Equals($_.Name, $file.Name, [System.StringComparison]::OrdinalIgnoreCase) })
                if ($clash.Count) {
                    throw "$($file.Name) declares the namespace $($file.Target), which $($clash[0].Name) in '$target' declares already: GPMC refuses a store where two files declare one namespace. Remove $($clash[0].Name), or install with its name: nothing is installed."
                }
            }
            $declared = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($staged.Target) + @($namespaces.Target) | Where-Object { $_ }))
            foreach ($namespace in @($staged.Using | Sort-Object -Unique)) {
                if ($declared.Contains($namespace)) { continue }
                if ($namespace -eq 'Microsoft.Policies.Windows') {
                    if (-not $there.Contains('windows.admx')) { Write-Warning "The ADMX files of $($item.Label) use those of Windows (windows.admx), not in '$target': install them too (Install-PSGPOAdmx), else GPMC and HGPM cannot read them." }
                } elseif ($readable) {
                    Write-Warning "The ADMX files of $($item.Label) use the namespace $namespace, which no file in '$target' declares: GPMC and HGPM cannot read them without it."
                }
            }

            if ($CentralStore) {
                Write-Progress -Activity "Installing the ADMX files of $($item.Label)" -Status $target
                $target = Copy-PSGPOAdmxCentralStore -Directory $Directory -Source $staging
                $details = @{ Languages = $languages; Files = $files; Package = $item.Package }
                if ($item.Product) { $details.Product = $item.Product.Name; $details.Version = $item.Product.Version; $details.Sha256 = $item.Product.Sha256 }
                Write-PSGPOAuditEntry -Directory $Directory -Action 'InstallAdmx' -Target $target -Details $details
            } else {
                $null = New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop
                Copy-Item -Path (Join-Path $staging '*') -Destination $target -Recurse -Force -ErrorAction Stop
            }
            foreach ($file in $staged) {
                [void]$there.Add($file.Name)
                $namespaces = @($namespaces | Where-Object { $_.Name -ne $file.Name }) + $file
            }
            Write-Progress -Activity "Installing the ADMX files of $($item.Label)" -Completed
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.AdmxInstall'
                Path       = $target
                Languages  = $languages
                Files      = $files
                Package    = $item.Package
                Product    = if ($item.Product) { $item.Product.Name } else { $null }
            }
        } finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
