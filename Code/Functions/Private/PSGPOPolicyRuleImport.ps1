<#
    The settings of a rule set written in a GPO of the domain, as LGPO.exe /p applies a .PolicyRules
    file to the local policy of a computer: the registry settings in Machine|User\Registry.pol, the
    security template in GptTmpl.inf, the advanced audit policy in audit.csv, and the client-side
    extensions they need declared in the GPO.

    Merged by default: a setting of the set replaces the same setting of the GPO (a registry value,
    its deletion, the values of a key a **delvals. clears; a key of a section of GptTmpl.inf; a
    subcategory, option or global SACL of audit.csv), the other settings of the GPO stay. With
    Replace, those three files hold the settings of the set alone. The other files of the GPO
    (preferences, scripts...) never change.
#>

# What the GPO files become with the rules: Files (the files of the GPO, changed), Counts by kind,
# Skipped (what cannot be written, and why).
function Set-PSGPOPolicyRuleFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [GPOToolsPolicyRule[]]$Rules,
        [switch]$Replace
    )

    $result = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $Files.Keys) { $result[$name] = $Files[$name] }
    $counts = [ordered]@{ Registry = 0; SecurityTemplate = 0; Audit = 0 }
    $skipped = [System.Collections.Generic.List[string]]::new()
    # The path a file has in the GPO, in its case (GPMC writes machine\microsoft\windows nt...).
    $pathOf = { param($Path) $found = @($result.Keys | Where-Object { $_ -ieq $Path }) | Select-Object -First 1; if ($found) { $found } else { $Path } }

    foreach ($scope in 'Machine', 'User') {
        $ruleScope = if ($scope -eq 'Machine') { 'Computer' } else { 'User' }
        $mine = @($Rules | Where-Object { $_.Kind -eq 'Registry' -and $_.Scope -eq $ruleScope })
        $path = & $pathOf "$scope\Registry.pol"
        if (-not $mine.Count -and -not ($Replace -and $result.Contains($path))) { continue }
        $pol = if ($Replace -or -not $result.Contains($path)) { [GPOToolsRegistryPol]::new() } else { [GPOToolsRegistryPol]::Parse([byte[]]$result[$path]) }
        foreach ($rule in $mine) {
            $value = $null
            try { $value = ConvertFrom-PSGPOPolicyRuleData -Rule $rule } catch { $skipped.Add("$($rule.Key)\$($rule.ValueName): $($_.Exception.Message)"); continue }
            if ($null -eq $value.Data) { $skipped.Add("$($rule.Key)\$($rule.ValueName): $($rule.RegType) without its data in the rule set"); continue }
            $target = $rule.GetTargetValueName()
            for ($index = $pol.Entries.Count - 1; $index -ge 0; $index--) {
                $entry = $pol.Entries[$index]
                if (-not [string]::Equals($entry.Key, $rule.Key, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                # A **delvals. clears the values of the key, the value or its deletion is replaced.
                if ($rule.IsDeleteAllValues() -or [string]::Equals($entry.GetTargetValueName(), $target, [System.StringComparison]::OrdinalIgnoreCase)) { $pol.Entries.RemoveAt($index) }
            }
            $pol.Entries.Add([GPOToolsPolEntry]::new($rule.Key, $rule.ValueName, $value.Type, [byte[]]$value.Data))
            $counts.Registry++
        }
        if ($pol.Entries.Count) { $result[$path] = $pol.ToBytes() } else { $result.Remove($path) }
    }

    $mine = @($Rules | Where-Object Kind -EQ 'SecurityTemplate')
    $path = & $pathOf ([GPOToolsDirectory]::SecurityTemplatePath)
    if ($mine.Count -or ($Replace -and $result.Contains($path))) {
        $template = if ($Replace -or -not $result.Contains($path)) { [GPOToolsSecurityTemplate]::new() } else { [GPOToolsSecurityTemplate]::Parse([byte[]]$result[$path]) }
        foreach ($rule in $mine) {
            if ($rule.Section -in [GPOToolsPolicyRule]::ListSections) {
                # "name",mode,"SDDL": the line of the same service, file or key replaced.
                $name = $rule.GetLineKey()
                foreach ($entry in @($template.GetEntries($rule.Section))) {
                    $probe = [GPOToolsPolicyRule]@{ Kind = 'SecurityTemplate'; Section = $rule.Section; LineItem = $(if ($null -eq $entry.Value) { $entry.Key } else { "$($entry.Key)=$($entry.Value)" }) }
                    if ([string]::Equals($probe.GetLineKey(), $name, [System.StringComparison]::OrdinalIgnoreCase)) { $template.SetValue($rule.Section, $entry.Key, $null) }
                }
                $template.AddEntry($rule.Section, "$($rule.LineItem)".Trim(), $null)
            } else {
                $template.SetValue($rule.Section, $rule.GetLineKey(), $rule.GetLineValue())
            }
            $counts.SecurityTemplate++
        }
        if (@($template.GetSectionNames() | Where-Object { $_ -notin 'Unicode', 'Version' }).Count) {
            $template.AddPreamble()
            $result[$path] = $template.ToBytes()
        } else { $result.Remove($path) }
    }

    $mine = @($Rules | Where-Object Kind -In 'AuditSubcategory', 'AuditOption', 'GlobalAudit')
    $path = & $pathOf ([GPOToolsDirectory]::AuditPolicyPath)
    if ($mine.Count -or ($Replace -and $result.Contains($path))) {
        $audit = if ($Replace -or -not $result.Contains($path)) { [GPOToolsAuditPolicyFile]::new() } else { [GPOToolsAuditPolicyFile]::Parse([byte[]]$result[$path]) }
        foreach ($rule in $mine) {
            if ($rule.Kind -eq 'AuditSubcategory') {
                $number = 0
                if (-not [int]::TryParse("$($rule.Setting)".Trim(), [ref]$number) -or $number -lt 0 -or $number -gt 3) { $skipped.Add("$($rule.Name): the audit setting '$($rule.Setting)' is not 0 to 3"); continue }
                $audit.SetSubcategory($rule.Guid, $rule.Name, $number)
            } else {
                # The other lines (an audit option, a global SACL) by their subcategory column.
                $name = if ($rule.Kind -eq 'AuditOption') { $rule.Option } else { $rule.GlobalType }
                foreach ($line in @($audit.Lines | Where-Object { $_ -is [string] })) {
                    $fields = $line.Split(',')
                    if ($fields.Count -ge 3 -and $fields[2] -ieq $name) { [void]$audit.Lines.Remove($line) }
                }
                $audit.Lines.Add($(if ($rule.Kind -eq 'AuditOption') {
                            ',System,{0},,{1},,{2}' -f $rule.Option, $(if ("$($rule.Setting)".Trim() -eq '1') { 'Enabled' } else { 'Disabled' }), "$($rule.Setting)".Trim()
                        } else { ',System,{0},,,,{1}' -f $rule.GlobalType, $rule.Sacl }))
            }
            $counts.Audit++
        }
        if (-not $audit.IsEmpty()) { $result[$path] = $audit.ToBytes() } else { $result.Remove($path) }
    }

    [pscustomobject]@{ Files = $result; Counts = $counts; Skipped = $skipped.ToArray() }
}

# The client-side extensions of a GPO once the rules are written: those it declares, those of its
# files (registry, security, audit), and those the rule set lists, with the tool of the
# administrative templates (the extensions of registry settings: mitigation options, LAPS...).
function Get-PSGPOPolicyRuleGpoExtension {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [GPOToolsPolicyRuleSet]$RuleSet
    )

    $names = @{}
    foreach ($scope in 'Machine', 'User') {
        $current = if ($scope -eq 'Machine') { "$($Gpo.MachineExtensionNames)" } else { "$($Gpo.UserExtensionNames)" }
        foreach ($pair in [regex]::Matches((Get-PSGPOFileExtensionName -Files $Files -Scope $scope), '\[(\{[^}]+\})(\{[^}]+\})\]')) {
            $current = Add-PSGPOExtensionName -Current $current -Extension $pair.Groups[1].Value -Tool $pair.Groups[2].Value
        }
        if ($scope -eq 'Machine' -and @($Files.Keys | Where-Object { $_ -ieq [GPOToolsDirectory]::AuditPolicyPath }).Count) {
            $current = Add-PSGPOExtensionName -Current $current -Extension ([GPOToolsDirectory]::AuditPolicyExtension) -Tool ([GPOToolsDirectory]::AuditPolicyTool)
        }
        $own = @([GPOToolsDirectory]::RegistryExtension, [GPOToolsDirectory]::SecurityExtension, [GPOToolsDirectory]::AuditPolicyExtension)
        foreach ($extension in @($RuleSet.Extensions | Where-Object Scope -EQ $scope)) {
            if ($extension.Guid -in $own) { continue }
            $current = Add-PSGPOExtensionName -Current $current -Extension $extension.Guid -Tool ([GPOToolsDirectory]::RegistryTool[$scope])
        }
        $names[$scope] = $current
    }
    [pscustomobject]@{ Machine = $names.Machine; User = $names.User }
}

# The rules of the GPOs of the set given (* and ? make a pattern; all by default), a warning for the
# settings they give different values: the value of the last one is written.
function Select-PSGPOPolicyRuleToImport {
    [CmdletBinding()]
    [OutputType([GPOToolsPolicyRule])]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicyRuleSet]$RuleSet,
        [AllowNull()] [AllowEmptyCollection()] [string[]]$PolicyName
    )

    $rules = @($RuleSet.Rules | Where-Object { $rule = $_; -not $PolicyName -or @($PolicyName | Where-Object { Test-PSGPONameMatch -Name $rule.PolicyName -Pattern $_ }).Count })
    if (-not $rules.Count) {
        throw "No setting of $(if ($PolicyName) { "the GPOs '$($PolicyName -join "', '")' of " })the rule set '$($RuleSet.Name)': $(@($RuleSet.GetPolicyNames()) -join ', ')."
    }
    $conflicts = @($rules | Group-Object { $_.GetIdentity() } | Where-Object { @($_.Group | ForEach-Object { $_.GetComparable() } | Select-Object -Unique).Count -gt 1 })
    if ($conflicts.Count) {
        $shown = @($conflicts | Select-Object -First 5 | ForEach-Object { "$($_.Group[0])" }) -join '; '
        Write-Warning "$($conflicts.Count) setting(s) given different values by the GPOs of the rule set: the value of the last GPO is written ($shown$(if ($conflicts.Count -gt 5) { '...' }))."
    }
    $rules
}

# Writes the rules of a set in a GPO (Import-PSGPOPolicyRuleSet, the Policy Analyzer window): the
# GPO backed up first, created when needed, and the change audited.
function Invoke-PSGPOPolicyRuleImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsPolicyRuleSet]$RuleSet,
        [Parameter(Mandatory)] [string]$TargetName,
        [string[]]$PolicyName,
        [switch]$Replace,
        [switch]$CreateIfNeeded,
        [string]$BackupPath,
        [switch]$NoBackup
    )

    $rules = @(Select-PSGPOPolicyRuleToImport -RuleSet $RuleSet -PolicyName $PolicyName -WarningAction SilentlyContinue)
    $gpo = $Directory.FindGpo($TargetName)
    if (-not $gpo) {
        if (-not $CreateIfNeeded) { throw "No GPO named '$TargetName' in $($Directory.DomainName)." }
        $gpo = $Directory.NewGpo($TargetName)
    }
    $before = $null
    if (-not $NoBackup -and -not $BackupPath -and -not (Test-PSGPOBackupAllowed -Directory $Directory)) {
        Write-Warning "The backups of $($Directory.DomainName) are for Tier 0: '$($gpo.DisplayName)' is not backed up before the rule set is written."
        $NoBackup = $true
    }
    if (-not $NoBackup) {
        if (-not $BackupPath) { $BackupPath = Get-PSGPODefaultBackupPath }
        $null = New-Item -ItemType Directory -Path $BackupPath -Force -ErrorAction Stop
        $before = Save-PSGPOBackup -Directory $Directory -Gpo $gpo -Path $BackupPath -Comment "Before the settings of the rule set '$($RuleSet.Name)' were written$(if ($Replace) { ' in place of its own' })."
    }
    $Directory.RefreshGpo($gpo)
    $files = $Directory.ReadGpoFolder($gpo)
    $files.Remove('GPT.INI')
    $written = Set-PSGPOPolicyRuleFile -Files $files -Rules $rules -Replace:$Replace
    $extensions = Get-PSGPOPolicyRuleGpoExtension -Gpo $gpo -Files $written.Files -RuleSet $RuleSet
    $Directory.RestoreGpo($gpo, $written.Files, $gpo.Flags, $extensions.Machine, $extensions.User)
    foreach ($item in $written.Skipped) { Write-Warning "Not written: $item" }
    $policies = @($rules | ForEach-Object PolicyName | Select-Object -Unique)
    if ($Directory -is [GPOToolsLdapDirectory]) {
        Write-PSGPOAuditEntry -Directory $Directory -Action 'ImportPolicyRuleSet' -Target $gpo.DistinguishedName -Gpo $gpo -Details ([ordered]@{
                RuleSet = $RuleSet.Name; Path = $RuleSet.Path; Policies = $policies; Replace = [bool]$Replace
                Registry = $written.Counts.Registry; SecurityTemplate = $written.Counts.SecurityTemplate; Audit = $written.Counts.Audit; Skipped = $written.Skipped.Count
            })
    }
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.PolicyRuleImport'
        DisplayName = $gpo.DisplayName
        Id = $gpo.Id
        Version = $gpo.Version
        RuleSet = $RuleSet.Name
        Policies = $policies
        Registry = $written.Counts.Registry
        SecurityTemplate = $written.Counts.SecurityTemplate
        Audit = $written.Counts.Audit
        Skipped = $written.Skipped
        BackupBefore = $before
    }
}
