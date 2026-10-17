# The domain or the OU a command names: its distinguished name, the name of the domain, or the
# name of an OU when only one OU has it.
function Resolve-PSGPOSom {
    [CmdletBinding()]
    [OutputType([GPOToolsSom])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Target
    )

    $Target = $Target.Trim()
    if ($Target -match '=') {
        $som = $Directory.FindSom($Target)
        if (-not $som) { throw "No domain or OU '$Target' in $($Directory.DomainName)." }
        return $som
    }
    if ([string]::Equals($Target, $Directory.DomainName, [System.StringComparison]::OrdinalIgnoreCase)) { return $Directory.Domain }
    $found = [System.Collections.Generic.List[GPOToolsSom]]::new()
    $stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
    $stack.Push($Directory.Domain)
    while ($stack.Count) {
        $som = $stack.Pop()
        if ($som.Kind -eq [GPOToolsSomKind]::OrganizationalUnit -and [string]::Equals($som.Name, $Target, [System.StringComparison]::OrdinalIgnoreCase)) { $found.Add($som) }
        foreach ($child in $som.Children) { $stack.Push($child) }
    }
    if (-not $found.Count) { throw "No domain or OU named '$Target' in $($Directory.DomainName)." }
    if ($found.Count -gt 1) { throw "Several OUs are named '$Target', give the distinguished name of one: $(@($found.DistinguishedName) -join '; ')." }
    $found[0]
}

# The link of a GPO to a SOM.
function Get-PSGPOSomLink {
    [CmdletBinding()]
    [OutputType([GPOToolsGpoLink])]
    param(
        [Parameter(Mandatory)] [GPOToolsSom]$Som,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $link = $Som.Links | Where-Object { [object]::ReferenceEquals($_.Gpo, $Gpo) } | Select-Object -First 1
    if (-not $link) { throw "The GPO '$($Gpo.DisplayName)' is not linked to $($Som.Name)." }
    $link
}

# A link as the commands return it.
function ConvertTo-PSGPOLinkOutput {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsSom]$Som, [Parameter(Mandatory)] [GPOToolsGpoLink]$Link)

    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Link'
        DisplayName = $Link.GetDisplayName()
        Target = $Som.DistinguishedName
        Order = $Link.Order
        Enabled = $Link.Enabled
        Enforced = $Link.Enforced
    }
}
