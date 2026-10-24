function Compare-PSGPOPolicyRuleSet {
    <#
    .SYNOPSIS
        Compares rule sets setting by setting, as the Policy Viewer of Policy Analyzer does.
    .DESCRIPTION
        One row per setting configured by one of the sets, with a property per set (named after
        it) holding its value: empty when the set does not configure the setting, ***CONFLICT***
        when two GPOs of the set give it different values. As Policy Analyzer, [[[delete]]] is a
        registry value deleted, [[[Delete all values]]] the values of a key deleted, lists whose
        order does not matter (accounts of a user right, REG_MULTI_SZ) are compared in any order,
        and a REG_DWORD 5 is not a REG_SZ 5.

        Each row also has Conflict (two sets, or two GPOs of a set, give the setting different
        values), Difference (a conflict, or a set does not configure it), the setting as Policy
        Analyzer lists it (PolicyType, Group, Setting) and as GPMC shows it (Path, Name, Option:
        the policies of the ADMX loaded by Initialize-PSGPOAdmx, the security settings), its
        explanation, and Cells: for each set its state (Absent, Set, Duplicate, Conflict,
        Overridden) and the value of each GPO. Export-PSGPOPolicyRuleComparison saves the rows as
        an Excel workbook.

        One set alone shows its own conflicts and duplicates. The precedence of the GPOs of a set
        is not taken into account, but for the GPOs of a domain or an OU (Get-PSGPOPolicyRuleSet
        -Container): the value of the GPO of precedence 1 is the one of the set (Overridden when
        others give another one), a **delvals. of higher precedence clearing the values of its key.
    .PARAMETER RuleSet
        The sets (Get-PSGPOPolicyRuleSet), in the order of their columns.
    .PARAMETER DifferenceOnly
        Only the rows with a difference, as "Show only Differences" of Policy Analyzer.
    .PARAMETER ConflictOnly
        Only the rows with a conflict, as "Show only Conflicts".
    .EXAMPLE
        $baseline = Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules
        $domain = Get-PSGPOPolicyRuleSet -Name 'Workstations - *' -SetName 'Domain'
        Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain -DifferenceOnly | Format-Table Scope, Name, MSFT-Win11-v25H2, Domain
    .EXAMPLE
        Get-PSGPOPolicyRuleSet -Path .\MyGpos.PolicyRules | Compare-PSGPOPolicyRuleSet -ConflictOnly
    .OUTPUTS
        PSGPOTools.PolicyRuleComparison
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/compare-psgpopolicyruleset/
    .LINK
        Get-PSGPOPolicyRuleSet
    .LINK
        Export-PSGPOPolicyRuleComparison
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.PolicyRuleComparison')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [GPOToolsPolicyRuleSet[]]$RuleSet,
        [switch]$DifferenceOnly,
        [switch]$ConflictOnly
    )

    begin {
        $sets = [System.Collections.Generic.List[GPOToolsPolicyRuleSet]]::new()
    }
    process {
        foreach ($item in $RuleSet) { $sets.Add($item) }
    }
    end {
        if (-not $sets.Count) { return }
        foreach ($row in @(Get-PSGPOPolicyRuleComparison -RuleSet $sets.ToArray())) {
            if ($ConflictOnly -and -not $row.Conflict) { continue }
            if ($DifferenceOnly -and -not $row.Difference) { continue }
            $row
        }
    }
}
