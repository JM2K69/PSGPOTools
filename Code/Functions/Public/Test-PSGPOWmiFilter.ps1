function Test-PSGPOWmiFilter {
    <#
    .SYNOPSIS
        Tests a WMI filter on a computer, as Windows evaluates it before it applies a GPO.
    .DESCRIPTION
        Runs each WQL query of the filter on this computer, or on another one by CIM (WinRM): a
        query is True when it returns at least one instance, False when it returns nothing or
        fails (a namespace or a class the computer does not have); the filter is True, and the
        computer applies the GPOs linked to it, when each query is True. The syntax of each query
        is checked first.

        The queries come from -Query, from a WMI filter of the domain (Get-PSGPOWmiFilter), from
        the .mof file of a filter (-Path) or from Get-PSGPOWmiQueryTemplate. WMI is a service of
        Windows: the test runs on Windows only. The GPOs are evaluated by the system: the queries of the TPM and
        BitLocker classes need an elevated session.
    .PARAMETER Query
        WQL queries.
    .PARAMETER Namespace
        WMI namespace of -Query; root\CIMv2 by default.
    .PARAMETER InputObject
        A WMI filter (Get-PSGPOWmiFilter), or objects with Namespace and Query
        (Get-PSGPOWmiQueryTemplate).
    .PARAMETER Path
        A .mof file of WMI filters, exported by GPMC or HGPM: each filter is tested.
    .PARAMETER ComputerName
        Computer to test the filter on, by CIM (WinRM); this computer by default.
    .PARAMETER Credential
        Account for -ComputerName.
    .EXAMPLE
        Test-PSGPOWmiFilter -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
    .EXAMPLE
        Get-PSGPOWmiFilter -Name 'Windows 11' | Test-PSGPOWmiFilter -ComputerName PC042
    .EXAMPLE
        Get-PSGPOWmiQueryTemplate -Id Laptops, Windows11 | Test-PSGPOWmiFilter
    .EXAMPLE
        Test-PSGPOWmiFilter -Path C:\Exports\Workstations.mof
    .OUTPUTS
        PSGPOTools.WmiFilterTest
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/test-psgpowmifilter/
    .LINK
        Show-WmiFilterCreatorAvalonia
    .LINK
        Get-PSGPOWmiQueryTemplate
    #>
    [CmdletBinding(DefaultParameterSetName = 'Query')]
    [OutputType('PSGPOTools.WmiFilterTest')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Query')] [string[]]$Query,
        [Parameter(ParameterSetName = 'Query')] [string]$Namespace = 'root\CIMv2',
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')] [object[]]$InputObject,
        [Parameter(Mandatory, ParameterSetName = 'Path')] [string]$Path,
        [string]$ComputerName,
        [pscredential]$Credential
    )

    begin {
        if (-not $IsWindows) { throw 'WMI is a service of Windows: test the WMI filter on a Windows computer.' }
        $items = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($item in @($InputObject)) { if ($null -ne $item) { $items.Add($item) } }
    }
    end {
        # The filters to test: a name and its queries.
        $filters = switch ($PSCmdlet.ParameterSetName) {
            'Query' { [pscustomobject]@{ Name = $null; Queries = @($Query | ForEach-Object { [pscustomobject]@{ Namespace = $Namespace; Query = $_ } }) } }
            'Path' {
                $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
                ConvertFrom-PSGPOWmiFilterMof -Bytes ([System.IO.File]::ReadAllBytes($full))
            }
            default {
                # Filters as they are, and loose queries (templates) as one filter.
                $loose = @($items | Where-Object { -not $_.PSObject.Properties['Queries'] })
                $items | Where-Object { $_.PSObject.Properties['Queries'] }
                if ($loose.Count) { [pscustomobject]@{ Name = $null; Queries = @($loose | ForEach-Object { [pscustomobject]@{ Namespace = $_.Namespace; Query = $_.Query } }) } }
            }
        }
        $computer = if ($ComputerName) { $ComputerName } else { [Environment]::MachineName }
        foreach ($filter in @($filters)) {
            $queries = @($filter.Queries)
            foreach ($item in $queries) {
                $check = Test-PSGPOWqlSyntax -Query $item.Query -Namespace $item.Namespace
                if (-not $check.IsValid) { throw "The query '$($item.Query)' is not valid WQL: $($check.Error)" }
                if ($check.Warning) { Write-Warning "$($item.Query): $($check.Warning)" }
            }
            $test = @{ Query = $queries }
            if ($ComputerName) { $test.ComputerName = $ComputerName }
            if ($Credential) { $test.Credential = $Credential }
            $results = @(Invoke-PSGPOWmiQueryTest @test)
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.WmiFilterTest'
                Name = $filter.Name
                ComputerName = $computer
                Applies = $results.Count -gt 0 -and -not @($results | Where-Object Result -NE 'Match').Count
                Queries = $results
            }
        }
    }
}
