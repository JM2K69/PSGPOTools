<#
    The GPOs that apply to a domain or an OU, in their order of precedence, as the Group Policy
    Inheritance tab of GPMC lists them: first the enforced links, from the domain down to the OU
    (the one nearest the domain wins), then the other links, from the OU up to the domain, until
    an OU that blocks the inheritance (its own links included). The links disabled, and the GPOs
    whose settings are all disabled, do not apply. Precedence 1 wins.

    The security filtering, the WMI filters and the loopback processing are those of each computer
    or user: not taken into account. The links of the sites neither.
#>

# The GPOs that apply to $Som, by precedence: Precedence, Gpo, Som (where it is linked), Enforced.
function Get-PSGPOSomPrecedence {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsSom]$Som)

    $chain = [System.Collections.Generic.List[GPOToolsSom]]::new()
    for ($node = $Som; $node; $node = $node.Parent) { $chain.Add($node) }
    $applies = { param($Link) $Link.Enabled -and $Link.Gpo -and ($Link.Gpo.Flags -band 3) -ne 3 }

    $ordered = [System.Collections.Generic.List[object]]::new()
    # The enforced links, from the domain down.
    for ($index = $chain.Count - 1; $index -ge 0; $index--) {
        foreach ($link in @($chain[$index].Links | Where-Object { $_.Enforced -and (& $applies $_) } | Sort-Object Order)) {
            $ordered.Add([pscustomobject]@{ Gpo = $link.Gpo; Som = $chain[$index]; Enforced = $true })
        }
    }
    # The other links, from the OU up, until an OU that blocks the inheritance.
    foreach ($node in $chain) {
        foreach ($link in @($node.Links | Where-Object { -not $_.Enforced -and (& $applies $_) } | Sort-Object Order)) {
            $ordered.Add([pscustomobject]@{ Gpo = $link.Gpo; Som = $node; Enforced = $false })
        }
        if ($node.BlockInheritance) { break }
    }
    $precedence = 0
    foreach ($item in $ordered) {
        $precedence++
        [pscustomobject]@{ PSTypeName = 'PSGPOTools.GpoPrecedence'; Precedence = $precedence; Gpo = $item.Gpo; Som = $item.Som; Enforced = $item.Enforced }
    }
}

# The rule set of the GPOs that apply to a domain or an OU, each rule with the precedence of its
# GPO; the computer or user part a GPO disables (its status) left out.
function New-PSGPOPolicyRuleSetFromSom {
    [CmdletBinding()]
    [OutputType([GPOToolsPolicyRuleSet])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsSom]$Som,
        [string]$SetName
    )

    $set = [GPOToolsPolicyRuleSet]::new($(if ($SetName) { $SetName } else { "$($Som.Name) (precedence)" }))
    $set.Path = $Som.DistinguishedName
    $read = @{}
    foreach ($item in @(Get-PSGPOSomPrecedence -Som $Som)) {
        $gpo = $item.Gpo
        if (-not $read.ContainsKey($gpo.Id)) {
            $Directory.RefreshGpo($gpo)
            $root = "\\$($Directory.DomainName)\SYSVOL\$($Directory.DomainName)\Policies\{$($gpo.Id.ToString().ToUpperInvariant())}"
            $read[$gpo.Id] = @(ConvertTo-PSGPOPolicyRule -Files $Directory.ReadGpoFolder($gpo) -PolicyName $gpo.DisplayName -SourceRoot $root)
            Add-PSGPOPolicyRuleExtension -RuleSet $set -MachineExtensionNames $gpo.MachineExtensionNames -UserExtensionNames $gpo.UserExtensionNames
        }
        # Flags: 1 the user part disabled, 2 the computer part.
        $userOff = ($gpo.Flags -band 1) -ne 0
        $computerOff = ($gpo.Flags -band 2) -ne 0
        foreach ($rule in $read[$gpo.Id]) {
            if (($rule.Scope -eq 'User' -and $userOff) -or ($rule.Scope -eq 'Computer' -and $computerOff)) { continue }
            # A copy per place the GPO applies: the same GPO linked twice is listed twice.
            $copy = [GPOToolsPolicyRule]::new()
            foreach ($property in $rule.PSObject.Properties) { if ($property.IsSettable) { $copy.($property.Name) = $property.Value } }
            $copy.Precedence = $item.Precedence
            $set.Rules.Add($copy)
        }
    }
    $set
}
