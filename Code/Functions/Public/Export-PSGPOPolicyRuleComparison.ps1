function Export-PSGPOPolicyRuleComparison {
    <#
    .SYNOPSIS
        Saves a comparison of rule sets as an Excel workbook, as Policy Analyzer exports it.
    .DESCRIPTION
        Writes a .xlsx file (without Excel nor any module, on any platform) from the rows of
        Compare-PSGPOPolicyRuleSet: a sheet Comparison with a row per setting and a column per
        set, with the colours of Policy Analyzer (yellow: the sets, or two GPOs of a set, give the
        setting different values; grey: the set does not configure it; light grey: it is set
        several times to the same value, or by GPOs of an OU whose precedence decides), and a sheet
        GPOs with the GPOs of each set.

        By default the table as the Policy Viewer shows it ("Export table to Excel"); with -All,
        also the value of each GPO, the explanation and the reference of each setting
        ("Export all data to Excel").
    .PARAMETER InputObject
        The rows of Compare-PSGPOPolicyRuleSet.
    .PARAMETER Path
        The .xlsx file.
    .PARAMETER All
        Adds the details of each setting.
    .PARAMETER Force
        Replaces a file that exists.
    .EXAMPLE
        Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain | Export-PSGPOPolicyRuleComparison -Path ./Comparison.xlsx
    .EXAMPLE
        Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain -DifferenceOnly | Export-PSGPOPolicyRuleComparison -Path ./Differences.xlsx -All
    .OUTPUTS
        System.IO.FileInfo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/export-psgpopolicyrulecomparison/
    .LINK
        Compare-PSGPOPolicyRuleSet
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [PSTypeName('PSGPOTools.PolicyRuleComparison')] [object[]]$InputObject,
        [Parameter(Mandatory)] [string]$Path,
        [switch]$All,
        [switch]$Force
    )

    begin {
        $rows = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($item in $InputObject) { $rows.Add($item) }
    }
    end {
        $file = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if ((Test-Path -LiteralPath $file) -and -not $Force) { throw "$file exists (-Force replaces it)." }
        $sets = if ($rows.Count) { @($rows[0].Cells | ForEach-Object Set) } else { @() }

        $columns = @('Scope', 'Path', 'Name', 'Option') + $sets + @('Policy type', 'Registry key or group', 'Setting')
        $widths = @(10, 50, 45, 30) + @($sets | ForEach-Object { 28 }) + @(16, 50, 30)
        if ($All) {
            $columns += @($sets | ForEach-Object { "$_ - GPOs" }) + @('Explanation', 'Reference')
            $widths += @($sets | ForEach-Object { 45 }) + @(80, 40)
        }
        $comparison = foreach ($row in $rows) {
            $cells = @(
                New-PSGPOXlsxCell $row.Scope
                New-PSGPOXlsxCell $row.Path
                New-PSGPOXlsxCell $row.Name
                New-PSGPOXlsxCell $row.Option
                foreach ($cell in $row.Cells) {
                    $style = if ($cell.State -eq 'Absent') { 'Absent' } elseif ($row.Conflict) { 'Conflict' } elseif ($cell.State -in 'Duplicate', 'Overridden') { 'Duplicate' } else { 'Normal' }
                    New-PSGPOXlsxCell $cell.Value $style
                }
                New-PSGPOXlsxCell $row.PolicyType
                New-PSGPOXlsxCell $row.Group
                New-PSGPOXlsxCell $row.Setting
                if ($All) {
                    # By precedence (the GPOs of an OU): the precedence of each GPO, the one applied.
                    foreach ($cell in $row.Cells) {
                        New-PSGPOXlsxCell ((@($cell.Values) | ForEach-Object {
                                    if ($_.Precedence -gt 0) { '{0} ({1}{2}): {3}' -f $_.PolicyName, $_.Precedence, $(if ($_.Applied) { ', applied' } else { '' }), $_.Value }
                                    else { "$($_.PolicyName): $($_.Value)" }
                                }) -join [Environment]::NewLine)
                    }
                    New-PSGPOXlsxCell $row.Explain
                    New-PSGPOXlsxCell $row.Reference
                }
            )
            , $cells
        }
        $gpos = foreach ($set in $sets) {
            $names = @($rows | ForEach-Object { $_.Cells | Where-Object Set -EQ $set } | ForEach-Object { $_.Values } | ForEach-Object PolicyName | Group-Object | Sort-Object Name)
            foreach ($group in $names) { , @((New-PSGPOXlsxCell $set), (New-PSGPOXlsxCell $group.Name), (New-PSGPOXlsxCell "$($group.Count)")) }
        }
        $sheets = @(
            [pscustomobject]@{ Name = 'Comparison'; Columns = $columns; Widths = $widths; Rows = @($comparison) }
            [pscustomobject]@{ Name = 'GPOs'; Columns = @('Rule set', 'GPO', 'Settings'); Widths = @(35, 60, 10); Rows = @($gpos) }
        )
        if (-not $PSCmdlet.ShouldProcess($file, "Save the comparison of $($rows.Count) settings")) { return }
        $folder = [System.IO.Path]::GetDirectoryName($file)
        if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop }
        Write-PSGPOXlsxWorkbook -Path $file -Sheets $sheets
        Get-Item -LiteralPath $file
    }
}
