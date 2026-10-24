function Get-PSGPOWmiQueryTemplate {
    <#
    .SYNOPSIS
        Gets the ready-made WQL queries of the WMI filter creator, their parameters given.
    .DESCRIPTION
        The library of Show-WmiFilterCreatorAvalonia: more than sixty queries for WMI filters, by
        category (operating system, edition and language, domain and name, hardware, virtual
        machines, security, network and location, software and services, files, time and state),
        each with its namespace, its note (the pitfalls of the query) and its source.

        A query with parameters ({Build}, {Memory}...) is given with their default values, or those
        of -Value; Parameters lists them (Name, Label, Kind Text, Number or Choice, Default,
        Choices). The query goes to New-PSGPOWmiFilter, Set-PSGPOWmiFilter or Test-PSGPOWmiFilter.
    .PARAMETER Id
        Identifiers of the queries (* and ? make a pattern): Windows11, Laptops, Subnet...
    .PARAMETER Category
        Categories of the queries (* and ? make a pattern).
    .PARAMETER Value
        Values of the parameters, by name: @{ Memory = 16 } for the query Memory.
    .EXAMPLE
        Get-PSGPOWmiQueryTemplate | Format-Table Category, Id, Query
    .EXAMPLE
        $Query = Get-PSGPOWmiQueryTemplate -Id Memory -Value @{ Memory = 16 }
        New-PSGPOWmiFilter -Name '16 GB' -Query $Query.Query -Namespace $Query.Namespace
    .EXAMPLE
        Get-PSGPOWmiQueryTemplate -Category 'Virtual machines'
    .OUTPUTS
        PSGPOTools.WmiQueryTemplate
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpowmiquerytemplate/
    .LINK
        Show-WmiFilterCreatorAvalonia
    .LINK
        Test-PSGPOWmiFilter
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.WmiQueryTemplate')]
    param(
        [Parameter(Position = 0)] [string[]]$Id,
        [string[]]$Category,
        [hashtable]$Value = @{}
    )

    $templates = @((Get-PSGPOWmiCatalog).Templates | Where-Object {
            $template = $_
            (-not $Id -or @($Id | Where-Object { Test-PSGPONameMatch -Name $template.Id -Pattern $_ }).Count) -and
            (-not $Category -or @($Category | Where-Object { Test-PSGPONameMatch -Name $template.Category -Pattern $_ }).Count)
        })
    if ($Id -and -not $templates.Count) { throw "No ready-made WMI query '$($Id -join "', '")': $(@((Get-PSGPOWmiCatalog).Templates.Id) -join ', ')." }
    foreach ($template in $templates) {
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.WmiQueryTemplate'
            Id = $template.Id
            Category = $template.Category
            Name = $template.Name
            Description = $template.Description
            Namespace = $template.Namespace
            Query = New-PSGPOWmiTemplateQuery -Template $template -Values $Value
            QueryTemplate = $template.Query
            Parameters = @($template.Parameters | Where-Object { $_ })
            Note = $template.Note
            Source = $template.Source
        }
    }
}
