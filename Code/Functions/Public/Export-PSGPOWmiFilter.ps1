function Export-PSGPOWmiFilter {
    <#
    .SYNOPSIS
        Exports WMI filters of the domain to .mof files, as GPMC "Export" does.
    .DESCRIPTION
        One .mof file for each filter, in the format of GPMC (UTF-16, an instance of
        MSFT_SomFilter with its rules): GPMC imports it in another domain, and so does
        Import-PSGPOWmiFilter. The file keeps the name, description, author, dates and WQL
        queries of the filter.
    .PARAMETER Name
        Names of the filters (* and ? make a pattern).
    .PARAMETER Path
        Folder of the files, each one named after its filter (<name>.mof); or the .mof file of one
        filter.
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
    .OUTPUTS
        System.IO.FileInfo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/export-psgpowmifilter/
    .LINK
        Import-PSGPOWmiFilter
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)] [string[]]$Name,
        [Parameter(Mandatory)] [string]$Path,
        [switch]$Force,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    $filters = @($Directory.WmiFilters | Where-Object { $filter = $_; @($Name | Where-Object { Test-PSGPONameMatch -Name $filter.Name -Pattern $_ }).Count })
    if (-not $filters.Count) { throw "No WMI filter named '$($Name -join "', '")' in $($Directory.DomainName): $(@($Directory.WmiFilters.Name) -join ', ')." }
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
        [System.IO.File]::WriteAllBytes($file, (ConvertTo-PSGPOWmiFilterMofByte -Filter $filter -Domain $Directory.DomainName))
        Get-Item -LiteralPath $file
    }
}
