function Export-PSGPOPolicyRuleSet {
    <#
    .SYNOPSIS
        Saves rule sets as a .PolicyRules file of Policy Analyzer.
    .DESCRIPTION
        Writes the file as GPO2PolicyRules.exe does: PolicyAnalyzer.exe opens it, LGPO.exe /p
        applies it to the local policy of a computer, and Get-PSGPOPolicyRuleSet reads it again.
        Several sets are merged in one file, as Merge-PolicyRules.ps1 of Policy Analyzer does: the
        settings of all their GPOs, and their client-side extensions once.
    .PARAMETER RuleSet
        The sets (Get-PSGPOPolicyRuleSet).
    .PARAMETER Path
        The .PolicyRules file.
    .PARAMETER Force
        Replaces a file that exists.
    .EXAMPLE
        Get-PSGPOPolicyRuleSet -Name 'Tier 1 - *' | Export-PSGPOPolicyRuleSet -Path "$HOME\Documents\PolicyAnalyzer\Tier 1.PolicyRules"
    .EXAMPLE
        Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows Server 2025 Security Baseline\GPOs' | Export-PSGPOPolicyRuleSet -Path ./WS2025.PolicyRules
    .OUTPUTS
        System.IO.FileInfo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/export-psgpopolicyruleset/
    .LINK
        Get-PSGPOPolicyRuleSet
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [GPOToolsPolicyRuleSet[]]$RuleSet,
        [Parameter(Mandatory)] [string]$Path,
        [switch]$Force
    )

    begin {
        $sets = [System.Collections.Generic.List[GPOToolsPolicyRuleSet]]::new()
    }
    process {
        foreach ($item in $RuleSet) { $sets.Add($item) }
    }
    end {
        if (-not $sets.Count) { return }
        $file = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if ((Test-Path -LiteralPath $file) -and -not $Force) { throw "$file exists (-Force replaces it)." }
        $merged = if ($sets.Count -eq 1) { $sets[0] } else {
            $all = [GPOToolsPolicyRuleSet]::new([System.IO.Path]::GetFileNameWithoutExtension($file))
            foreach ($set in $sets) {
                foreach ($rule in $set.Rules) { $all.Rules.Add($rule) }
                foreach ($extension in $set.Extensions) { $all.AddExtension($extension.Scope, $extension.Guid, $extension.Name) }
            }
            $all
        }
        if (-not $PSCmdlet.ShouldProcess($file, "Save the settings of $(@($merged.GetPolicyNames()).Count) GPO(s)")) { return }
        $folder = [System.IO.Path]::GetDirectoryName($file)
        if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop }
        [System.IO.File]::WriteAllBytes($file, $merged.ToBytes())
        Get-Item -LiteralPath $file
    }
}
