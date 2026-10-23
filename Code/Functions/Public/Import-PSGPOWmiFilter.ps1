function Import-PSGPOWmiFilter {
    <#
    .SYNOPSIS
        Creates WMI filters in the domain from .mof files, as GPMC "Import" does.
    .DESCRIPTION
        Reads the .mof files GPMC exports (Export in the context menu of a WMI filter), and those of
        Export-PSGPOWmiFilter: an instance of MSFT_SomFilter with its WQL rules. Each filter is
        created in the domain with the name, description and queries of the file; it gets a new
        Id, so that a file exported from this domain is imported again beside its filter. A filter
        whose name the domain has already is not imported: -Name gives it another one.
    .PARAMETER Path
        The .mof files.
    .PARAMETER Name
        Name of the imported filter, instead of the one of the file: one filter only.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Import-PSGPOWmiFilter -Path C:\Exports\Workstations.mof
    .EXAMPLE
        Get-ChildItem /srv/wmi-filters -Filter *.mof | Import-PSGPOWmiFilter
    .OUTPUTS
        PSGPOTools.WmiFilter
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/import-psgpowmifilter/
    .LINK
        Export-PSGPOWmiFilter
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.WmiFilter')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)] [Alias('FullName')] [string[]]$Path,
        [string]$Name,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    begin {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
        $imported = @{ Count = 0 }
    }
    process {
        foreach ($item in $Path) {
            $file = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($item)
            try {
                $read = @(ConvertFrom-PSGPOWmiFilterMof -Bytes ([System.IO.File]::ReadAllBytes($file)))
            } catch {
                Write-Error "$file is not imported: $($_.Exception.GetBaseException().Message)"
                continue
            }
            foreach ($source in $read) {
                if ($Name -and ++$imported.Count -gt 1) { Write-Error "-Name renames one WMI filter: '$($source.Name)' of $file is not imported."; continue }
                $target = if ($Name) { "$Name".Trim() } else { $source.Name }
                if (-not $PSCmdlet.ShouldProcess("WMI filter '$target' of $($Directory.DomainName)", "Create it from $file")) { continue }
                try {
                    $filter = $Directory.NewWmiFilter($target, $source.Description, $source.Queries)
                } catch {
                    $why = $_.Exception.GetBaseException().Message
                    if ($Directory.FindWmiFilter($target)) { $why += ' Give it another name with -Name.' }
                    Write-Error "The WMI filter '$target' of $file is not imported: $why"
                    continue
                }
                Get-PSGPOWmiFilter -Directory $Directory -Name $filter.Name
            }
        }
    }
}
