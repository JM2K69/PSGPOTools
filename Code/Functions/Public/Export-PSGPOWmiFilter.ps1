function Export-PSGPOWmiFilter {
    <#
    .SYNOPSIS
        Exports WMI filters of the domain to .mof files, as GPMC "Export" does.
    .DESCRIPTION
        One .mof file for each filter, in the format of GPMC (UTF-16, an instance of
        MSFT_SomFilter with its rules): GPMC imports it in another domain, and so does
        Import-PSGPOWmiFilter. The file keeps the name, description, author, dates and WQL
        queries of the filter.

        With -InputObject, filters that are not in a domain are exported: objects with Name,
        Description and Queries (Namespace and Query), as Show-WmiFilterCreatorAvalonia writes them;
        no domain is read.
    .PARAMETER Name
        Names of the filters (* and ? make a pattern).
    .PARAMETER Path
        Folder of the files, each one named after its filter (<name>.mof); or the .mof file of one
        filter.
    .PARAMETER InputObject
        Filters to export without a domain: objects with Name, Description (optional) and Queries
        (Namespace and Query); Id, Author, CreationDate and ChangeDate are kept when given.
    .PARAMETER Domain
        DNS name of the domain written in the file with -InputObject; the domain of the computer by
        default. GPMC creates the filter in the domain it imports it in, whatever this name is.
    .PARAMETER Force
        Replaces a file that exists.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Export-PSGPOWmiFilter -Name 'Workstations' -Path C:\Exports
    .EXAMPLE
        Export-PSGPOWmiFilter -Name '*' -Path /srv/wmi-filters
    .EXAMPLE
        $Query = Get-PSGPOWmiQueryTemplate -Id Laptops
        [pscustomobject]@{ Name = 'Laptops'; Queries = $Query } | Export-PSGPOWmiFilter -Path C:\Exports
    .OUTPUTS
        System.IO.FileInfo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/export-psgpowmifilter/
    .LINK
        Import-PSGPOWmiFilter
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Domain')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Domain')] [string[]]$Name,
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')] [object[]]$InputObject,
        [Parameter(Mandatory)] [string]$Path,
        [switch]$Force,
        [Parameter(ParameterSetName = 'Domain')] [GPOToolsDirectory]$Directory,
        [Parameter(ParameterSetName = 'Domain')] [string]$Server,
        [Parameter(ParameterSetName = 'InputObject')] [string]$Domain
    )

    begin { $inputs = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($item in @($InputObject)) { if ($null -ne $item) { $inputs.Add($item) } } }
    end {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            if (-not $Domain) {
                $Domain = (Get-PSGPOPlatform).DomainName
                if (-not $Domain) { $Domain = [Environment]::UserDomainName }
            }
            $filters = @(foreach ($item in $inputs) {
                    $filter = [GPOToolsWmiFilter]::new()
                    $filter.Name = "$($item.Name)".Trim()
                    if (-not $filter.Name) { throw 'A WMI filter to export has a Name.' }
                    $filter.Description = "$($item.Description)"
                    $filter.Queries = @($item.Queries | ForEach-Object { [pscustomobject]@{ Namespace = $(if ("$($_.Namespace)".Trim()) { "$($_.Namespace)".Trim() } else { 'root\CIMv2' }); Query = "$($_.Query)".Trim() } })
                    if (-not $filter.Queries.Count) { throw "The WMI filter '$($filter.Name)' has no query." }
                    foreach ($query in $filter.Queries) {
                        $check = Test-PSGPOWqlSyntax -Query $query.Query -Namespace $query.Namespace
                        if (-not $check.IsValid) { throw "The query '$($query.Query)' of the WMI filter '$($filter.Name)' is not valid WQL: $($check.Error)" }
                    }
                    $id = [guid]::Empty
                    $filter.Id = if ($item.PSObject.Properties['Id'] -and [guid]::TryParse("$($item.Id)", [ref]$id) -and $id -ne [guid]::Empty) { $id } else { [guid]::NewGuid() }
                    $filter.Author = if ($item.PSObject.Properties['Author'] -and $item.Author) { $item.Author } else { "$([Environment]::UserDomainName)\$([Environment]::UserName)" }
                    $filter.CreationDate = if ($item.PSObject.Properties['CreationDate'] -and $item.CreationDate) { $item.CreationDate } else { [GPOToolsWmiFilter]::GetDate() }
                    $filter.ChangeDate = if ($item.PSObject.Properties['ChangeDate'] -and $item.ChangeDate) { $item.ChangeDate } else { $filter.CreationDate }
                    $filter
                })
        } else {
            if (-not $Directory) {
                $read = @{}
                if ($Server) { $read.Server = $Server }
                $Directory = Get-PSGPODirectory @read -ErrorAction Stop
            }
            $filters = @($Directory.WmiFilters | Where-Object { $filter = $_; @($Name | Where-Object { Test-PSGPONameMatch -Name $filter.Name -Pattern $_ }).Count })
            if (-not $filters.Count) { throw "No WMI filter named '$($Name -join "', '")' in $($Directory.DomainName): $(@($Directory.WmiFilters.Name) -join ', ')." }
            $Domain = $Directory.DomainName
        }
        $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $toFile = $full.EndsWith('.mof', [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath $full -PathType Container)
        if ($toFile -and $filters.Count -gt 1) { throw "$Path is one file: give a folder for the $($filters.Count) WMI filters ($(@($filters.Name) -join ', '))." }
        foreach ($filter in $filters) {
            $file = if ($toFile) { $full } else { Join-Path $full (Get-PSGPOWmiFilterFileName -Name $filter.Name) }
            if ((Test-Path -LiteralPath $file) -and -not $Force) {
                Write-Error "$file exists: the WMI filter '$($filter.Name)' is not exported (-Force replaces it)."
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($file, "Export the WMI filter '$($filter.Name)'")) { continue }
            $folder = [System.IO.Path]::GetDirectoryName($file)
            if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop }
            [System.IO.File]::WriteAllBytes($file, (ConvertTo-PSGPOWmiFilterMofByte -Filter $filter -Domain $Domain))
            Get-Item -LiteralPath $file
        }
    }
}
