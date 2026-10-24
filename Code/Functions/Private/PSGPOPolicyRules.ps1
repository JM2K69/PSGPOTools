<#
    The Policy Analyzer of the Microsoft Security Compliance Toolkit, on any platform: the
    settings of GPOs as rule sets (.PolicyRules, GPOToolsPolicyRuleSet), from the files of GPOs
    (of the domain, of backups of HGPM or GPMC), and their comparison setting by setting.

    A rule set holds the settings of any number of GPOs. Compared, each setting is a row with a
    cell per set: absent, set, set several times to the same value (in several GPOs), or set to
    different values (***CONFLICT***, as Policy Analyzer shows it). A row is a conflict when two
    sets, or two GPOs of a set, give the setting different values; a difference when it is a
    conflict or a set does not configure it. As Policy Analyzer, the precedence of the GPOs of a
    set is not taken into account.
#>

# Names of the registry types in a .PolicyRules file.
$script:PSGPOPolicyRuleTypeName = @{
    None = 'REG_NONE'; String = 'REG_SZ'; ExpandString = 'REG_EXPAND_SZ'; Binary = 'REG_BINARY'; DWord = 'REG_DWORD'
    DWordBigEndian = 'REG_DWORD_BIG_ENDIAN'; Link = 'REG_LINK'; MultiString = 'REG_MULTI_SZ'; QWord = 'REG_QWORD'
}

# Names of the client-side extensions, as Policy Analyzer writes them (the preferences come from
# their catalog).
$script:PSGPOPolicyRuleExtensionName = @{
    '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}' = 'Registry Policy'
    '{827D319E-6EAC-11D2-A4EA-00C04F79F83A}' = 'Security'
    '{F3CCC681-B74C-4060-9F26-CD84525DCA2A}' = 'Audit Policy Configuration'
    '{42B5FAAE-6536-11D2-AE5A-0000F87571E3}' = 'Scripts'
    '{25537BA6-77A8-11D2-9B6C-0000F8080861}' = 'Folder Redirection'
    '{C6DC5466-785A-11D2-84D0-00C04FB169F7}' = 'Software Installation'
    '{B1BE8D72-6EAC-11D2-A4EA-00C04F79F83A}' = 'EFS Recovery'
    '{E437BC1C-AA7D-11D2-A382-00C04F991E27}' = 'IP Security'
    '{0ACDD40C-75AC-47AB-BAA0-BF6DE7E7FE63}' = 'Wireless Group Policy'
    '{2A8FDC61-2347-4C87-92F6-B05EB91A201A}' = 'Group Policy Mitigation Options'
    '{7933F41E-56F8-41D6-A31C-4148A711EE93}' = 'Windows Search Group Policy Extension'
    '{D76B9641-3288-4F75-942D-087DE603E3EA}' = 'Local Administrator Password Solution (LAPS)'
    '{F312195E-3D9D-447A-A3F5-08DFFA24735E}' = 'Device Guard'
    '{4CFB60C1-FAA6-47F1-89AA-0B18730C9FD3}' = 'Internet Explorer Zonemapping'
    '{FB2CA36D-0B40-4307-821B-A13B252DE56C}' = 'Enterprise QoS'
    '{3060E8D0-7020-11D2-842D-00C04FA372D4}' = 'Remote Installation Services'
}

# The nodes of the editor of the sections "name",mode,"SDDL", and what their mode means.
$script:PSGPOPolicyRuleListPath = @{ 'Service General Setting' = 'System Services'; 'Registry Keys' = 'Registry'; 'File Security' = 'File System' }
$script:PSGPOPolicyRuleServiceMode = @{ '2' = 'Automatic'; '3' = 'Manual'; '4' = 'Disabled' }
$script:PSGPOPolicyRulePermissionMode = @{ '0' = 'Propagate inheritable permissions'; '1' = 'Do not allow permissions to be replaced'; '2' = 'Replace existing permissions' }

# Name of a client-side extension: the one of the table, of a preference type, else its GUID.
function Get-PSGPOPolicyRuleExtensionName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Guid)

    foreach ($known in $script:PSGPOPolicyRuleExtensionName.Keys) {
        if ([string]::Equals($known, $Guid, [System.StringComparison]::OrdinalIgnoreCase)) { return $script:PSGPOPolicyRuleExtensionName[$known] }
    }
    foreach ($extension in @(Get-PSGPOPreferenceExtension)) {
        if ([string]::Equals($extension.Cse, $Guid, [System.StringComparison]::OrdinalIgnoreCase)) { return "Group Policy $($extension.Name)" }
    }
    $Guid
}

# Adds to a set the client-side extensions of gPCMachineExtensionNames / gPCUserExtensionNames
# ([{CSE}{tool}...][...]): the first GUID of each pair of brackets.
function Add-PSGPOPolicyRuleExtension {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicyRuleSet]$RuleSet,
        [AllowEmptyString()] [AllowNull()] [string]$MachineExtensionNames,
        [AllowEmptyString()] [AllowNull()] [string]$UserExtensionNames
    )

    foreach ($scope in 'Machine', 'User') {
        $names = if ($scope -eq 'Machine') { $MachineExtensionNames } else { $UserExtensionNames }
        foreach ($pair in [regex]::Matches("$names", '\[(\{[0-9A-Fa-f-]{36}\})')) {
            $guid = $pair.Groups[1].Value.ToUpperInvariant()
            $RuleSet.AddExtension($scope, $guid, (Get-PSGPOPolicyRuleExtensionName -Guid $guid))
        }
    }
    # Sorted by GUID, as Policy Analyzer lists them.
    $sorted = @($RuleSet.Extensions | Sort-Object Scope, Guid)
    $RuleSet.Extensions.Clear()
    foreach ($extension in $sorted) { $RuleSet.Extensions.Add($extension) }
}

# The data of a Registry.pol entry as GPO2PolicyRules writes it in RegData.
function ConvertTo-PSGPOPolicyRuleData {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [GPOToolsPolEntry]$Entry)

    $data = $Entry.Data
    switch ($Entry.Type) {
        { $_ -in 'String', 'ExpandString', 'Link' } { return [GPOToolsPolEntry]::DecodeString($data) }
        'MultiString' {
            $text = [System.Text.Encoding]::Unicode.GetString($data)
            # Ordinal: a culture comparison ignores the null characters ("x".EndsWith("`0`0")).
            if ($text.EndsWith("`0`0", [System.StringComparison]::Ordinal)) { $text = $text.Substring(0, $text.Length - 2) }
            return $text.Replace("`0", '\0')
        }
        'DWord' { if ($data.Length -ge 4) { return "$([BitConverter]::ToUInt32($data, 0))" } }
        'QWord' { if ($data.Length -ge 8) { return "$([BitConverter]::ToUInt64($data, 0))" } }
        'DWordBigEndian' { return "(data not shown; size = $($data.Length))" }
    }
    (@($data) | ForEach-Object { $_.ToString('x2') }) -join ','
}

# The type and bytes of a registry setting of a rule ($null data: not given by the file, as the
# REG_DWORD_BIG_ENDIAN Policy Analyzer does not show).
function ConvertFrom-PSGPOPolicyRuleData {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsPolicyRule]$Rule)

    $type = $null
    foreach ($name in $script:PSGPOPolicyRuleTypeName.Keys) { if ($script:PSGPOPolicyRuleTypeName[$name] -eq $Rule.RegType) { $type = [GPOToolsPolType]$name } }
    if ($null -eq $type) { throw "Unknown registry type '$($Rule.RegType)' for $($Rule.Key)\$($Rule.ValueName)." }
    $text = "$($Rule.RegData)"
    $data = switch ($type) {
        { $_ -in 'String', 'ExpandString', 'Link' } { , [GPOToolsPolEntry]::EncodeString($text) }
        'MultiString' {
            $items = if ($text -eq '\0') { '' } else { $text.Replace('\0', "`0") + "`0" }
            , [System.Text.Encoding]::Unicode.GetBytes($items + "`0")
        }
        'DWord' { , [BitConverter]::GetBytes([uint32]$text) }
        'QWord' { , [BitConverter]::GetBytes([uint64]$text) }
        'DWordBigEndian' { $null }
        default {
            if ($text -eq '') { , [byte[]]::new(0) }
            else { , [byte[]]@($text -split ',' | ForEach-Object { [Convert]::ToByte($_.Trim(), 16) }) }
        }
    }
    [pscustomobject]@{ Type = $type; Data = $data }
}

# The settings of the files of a GPO (Machine|User\Registry.pol, GptTmpl.inf, audit.csv) as
# rules of $PolicyName; their SourceFile: $SourceRoot\<path in the GPO>.
function ConvertTo-PSGPOPolicyRule {
    [CmdletBinding()]
    [OutputType([GPOToolsPolicyRule])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [string]$PolicyName,
        [string]$SourceRoot
    )

    $source = { param($Path) if ($SourceRoot) { "$($SourceRoot.TrimEnd('\', '/'))\$Path" } else { $Path } }
    $find = { param($Path) @($Files.Keys | Where-Object { $_ -ieq $Path }) | Select-Object -First 1 }

    foreach ($scope in 'Machine', 'User') {
        $path = & $find "$scope\Registry.pol"
        if (-not $path) { continue }
        foreach ($entry in ([GPOToolsRegistryPol]::Parse([byte[]]$Files[$path])).Entries) {
            $rule = [GPOToolsPolicyRule]::new()
            $rule.Kind = 'Registry'
            $rule.Scope = if ($scope -eq 'Machine') { 'Computer' } else { 'User' }
            $rule.Key = $entry.Key
            $rule.ValueName = $entry.ValueName
            $rule.RegType = $script:PSGPOPolicyRuleTypeName["$($entry.Type)"]
            if (-not $rule.RegType) { $rule.RegType = "REG_TYPE_$([int]$entry.Type)" }
            $rule.RegData = ConvertTo-PSGPOPolicyRuleData -Entry $entry
            $rule.SourceFile = & $source $path
            $rule.PolicyName = $PolicyName
            $rule
        }
    }

    $path = & $find ([GPOToolsDirectory]::SecurityTemplatePath)
    if ($path) {
        $template = [GPOToolsSecurityTemplate]::Parse([byte[]]$Files[$path])
        foreach ($section in $template.GetSectionNames()) {
            if ($section -in 'Unicode', 'Version') { continue }
            foreach ($line in $template.GetEntries($section)) {
                $rule = [GPOToolsPolicyRule]::new()
                $rule.Kind = 'SecurityTemplate'
                $rule.Section = $section
                $rule.LineItem = if ($null -eq $line.Value) { $line.Key } else { "$($line.Key)=$($line.Value)" }
                $rule.SourceFile = & $source $path
                $rule.PolicyName = $PolicyName
                $rule
            }
        }
    }

    $path = & $find ([GPOToolsDirectory]::AuditPolicyPath)
    if ($path) {
        foreach ($line in ([GPOToolsAuditPolicyFile]::Parse([byte[]]$Files[$path])).Lines) {
            $rule = [GPOToolsPolicyRule]::new()
            $rule.SourceFile = & $source $path
            $rule.PolicyName = $PolicyName
            if ($line -isnot [string]) {
                $rule.Kind = 'AuditSubcategory'
                $rule.Guid = $line.Guid
                $rule.Name = $line.Name
                $rule.Setting = "$($line.Value)"
                $rule
                continue
            }
            # The other lines: audit options and global object access auditing (Setting Value).
            $fields = $line.Split(',')
            if ($fields.Count -lt 7) { continue }
            if ($fields[2] -like 'Option:*') {
                $rule.Kind = 'AuditOption'
                $rule.Option = $fields[2]
                $rule.Setting = $fields[6]
                $rule
            } elseif ($fields[2] -like '*GlobalSacl') {
                $rule.Kind = 'GlobalAudit'
                $rule.GlobalType = $fields[2]
                $rule.Sacl = ($fields[6..($fields.Count - 1)]) -join ','
                $rule
            }
        }
    }
}

# The rule set of GPOs of the domain, as they are now: named $SetName, else after the GPO when
# there is one, else after the domain.
function New-PSGPOPolicyRuleSetFromGpo {
    [CmdletBinding()]
    [OutputType([GPOToolsPolicyRuleSet])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo[]]$Gpo,
        [string]$SetName
    )

    $set = [GPOToolsPolicyRuleSet]::new($(if ($SetName) { $SetName } elseif ($Gpo.Count -eq 1) { $Gpo[0].DisplayName } else { $Directory.DomainName }))
    $set.Path = "\\$($Directory.DomainName)\SYSVOL\$($Directory.DomainName)\Policies"
    foreach ($item in $Gpo) {
        $Directory.RefreshGpo($item)
        $root = "$($set.Path)\{$($item.Id.ToString().ToUpperInvariant())}"
        foreach ($rule in @(ConvertTo-PSGPOPolicyRule -Files $Directory.ReadGpoFolder($item) -PolicyName $item.DisplayName -SourceRoot $root)) { $set.Rules.Add($rule) }
        Add-PSGPOPolicyRuleExtension -RuleSet $set -MachineExtensionNames $item.MachineExtensionNames -UserExtensionNames $item.UserExtensionNames
    }
    $set
}

# A Registry.pol of the registry rules given (of one GPO and scope), and the rule of each entry.
function ConvertTo-PSGPOPolicyRulePol {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [GPOToolsPolicyRule[]]$Rules)

    $pol = [GPOToolsRegistryPol]::new()
    $ruleOf = [System.Collections.Generic.Dictionary[object, object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
    foreach ($rule in $Rules) {
        try { $value = ConvertFrom-PSGPOPolicyRuleData -Rule $rule } catch { continue }
        $data = if ($null -eq $value.Data) { [byte[]]::new(0) } else { [byte[]]$value.Data }
        $entry = [GPOToolsPolEntry]::new($rule.Key, $rule.ValueName, $value.Type, $data)
        $pol.Entries.Add($entry)
        $ruleOf[$entry] = $rule
    }
    [pscustomobject]@{ Pol = $pol; RuleOf = $ruleOf }
}

# The category path of a policy, as the Settings tab shows it.
function Get-PSGPOPolicyRulePolicyPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [GPOToolsPolicy]$Policy)

    $path = [System.Collections.Generic.List[string]]::new()
    for ($category = $Policy.Category; $category; $category = $category.ParentCategory) { $path.Insert(0, $category.DisplayName) }
    $path.Insert(0, 'Administrative Templates')
    $path.Insert(0, 'Policies')
    $path -join ' > '
}

# The option of a policy an entry writes: the label of its element, '' for the value of the
# policy itself.
function Get-PSGPOPolicyRuleOption {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [GPOToolsPolicy]$Policy, [Parameter(Mandatory)] [GPOToolsPolEntry]$Entry)

    $target = $Entry.GetTargetValueName()
    foreach ($element in $Policy.Elements) {
        $key = if ($element.Key) { $element.Key } else { $Policy.RegistryKey }
        if (-not [string]::Equals($key, $Entry.Key, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($element.Type -eq 'List' -or [string]::Equals($element.ValueName, $target, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($element.Label) { return $element.Label.TrimEnd(':', ' ') }
            return $element.Id
        }
    }
    ''
}

# What each setting of the sets is, by identity (GetIdentity): Kind, Scope, PolicyType, Group and
# Setting (as Policy Analyzer lists them: HKLM / HKCU / Security Template / Audit Policy, the key
# or section, the value name or key), Path, Name and Option (as the Settings tab of GPMC: the
# policy of the loaded ADMX, the security setting of the catalog), Explain and Reference.
function Get-PSGPOPolicyRuleDescription {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [GPOToolsPolicyRuleSet[]]$RuleSet)

    $described = [System.Collections.Generic.Dictionary[string, object]]::new()
    $catalog = @{}
    foreach ($setting in @(Get-PSGPOSecuritySetting)) { $catalog["$($setting.Section)|$($setting.Key)".ToLowerInvariant()] = $setting }
    $securityPath = 'Policies > Windows Settings > Security Settings'

    # The policies of the ADMX: per set, GPO and scope, the policies GPMC would show.
    $policyOf = [System.Collections.Generic.Dictionary[string, object]]::new()
    if (@([GPOToolsUtility]::Policies).Count) {
        foreach ($set in $RuleSet) {
            foreach ($group in @($set.Rules | Where-Object Kind -EQ 'Registry' | Group-Object PolicyName, Scope)) {
                $scope = if ($group.Group[0].Scope -eq 'User') { 'User' } else { 'Machine' }
                $converted = ConvertTo-PSGPOPolicyRulePol -Rules @($group.Group)
                foreach ($configured in @(Get-PSGPOConfiguredPolicy -Pol $converted.Pol -Scope $scope)) {
                    foreach ($entry in $configured.Entries) {
                        $identity = $converted.RuleOf[$entry].GetIdentity()
                        if ($policyOf.ContainsKey($identity)) { continue }
                        $policyOf[$identity] = [pscustomobject]@{ Policy = $configured.Policy; Option = Get-PSGPOPolicyRuleOption -Policy $configured.Policy -Entry $entry }
                    }
                }
            }
        }
    }

    foreach ($set in $RuleSet) {
        foreach ($rule in $set.Rules) {
            $identity = $rule.GetIdentity()
            if ($described.ContainsKey($identity)) { continue }
            $item = [pscustomobject]@{
                Identity = $identity; Kind = $rule.Kind; Scope = $rule.Scope; PolicyType = ''; Group = ''; Setting = ''
                Path = ''; Name = ''; Option = ''; Explain = ''; Reference = ''; CatalogSetting = $null
            }
            switch ($rule.Kind) {
                'Registry' {
                    $item.PolicyType = if ($rule.Scope -eq 'User') { 'HKCU' } else { 'HKLM' }
                    $item.Group = $rule.Key
                    $item.Setting = if ($rule.IsDeleteAllValues()) { '*' } else { $rule.GetTargetValueName() }
                    $known = $null
                    if ($policyOf.TryGetValue($identity, [ref]$known)) {
                        $item.Path = Get-PSGPOPolicyRulePolicyPath -Policy $known.Policy
                        $item.Name = $known.Policy.DisplayName
                        $item.Option = $known.Option
                        $item.Explain = $known.Policy.Description
                    } else {
                        $item.Path = 'Extra Registry Settings'
                        $item.Name = "$($item.PolicyType)\$($rule.Key)$(if ($item.Setting) { "\$($item.Setting)" })"
                    }
                }
                'SecurityTemplate' {
                    $item.PolicyType = 'Security Template'
                    $item.Group = $rule.Section
                    $item.Setting = $rule.GetLineKey()
                    $setting = $catalog["$($rule.Section)|$($item.Setting)".ToLowerInvariant()]
                    if ($setting) {
                        $item.Path = (@($securityPath) + $setting.Path) -join ' > '
                        $item.Name = $setting.Name
                        $item.Reference = $setting.Reference
                        $item.CatalogSetting = $setting
                    } elseif ($script:PSGPOPolicyRuleListPath.ContainsKey($rule.Section)) {
                        $item.Path = "$securityPath > $($script:PSGPOPolicyRuleListPath[$rule.Section])"
                        $item.Name = $item.Setting
                    } elseif ($rule.Section -eq 'Group Membership' -and $item.Setting -match '^(.+)__(Members|Memberof)$') {
                        $item.Path = "$securityPath > Restricted Groups"
                        $item.Name = '{0} ({1})' -f [GPOToolsSecuritySetting]::FormatAccount($Matches[1]), $(if ($Matches[2] -eq 'Members') { 'Members' } else { 'Member of' })
                    } else {
                        $item.Path = "$securityPath > [$($rule.Section)]"
                        $item.Name = $item.Setting
                    }
                }
                'AuditSubcategory' {
                    $item.PolicyType = 'Audit Policy'
                    $item.Group = 'Advanced Audit Policy Configuration'
                    $item.Setting = $rule.Guid
                    $setting = $catalog["$([GPOToolsAuditPolicyFile]::Section)|$($rule.Guid)".ToLowerInvariant()]
                    $item.Path = (@($securityPath) + $(if ($setting) { $setting.Path } else { 'Advanced Audit Policy Configuration', 'Audit Policies' })) -join ' > '
                    $item.Name = if ($setting) { $setting.Name } else { $rule.Name }
                    if ($setting) { $item.Reference = $setting.Reference }
                }
                'AuditOption' {
                    $item.PolicyType = 'Audit Policy'
                    $item.Group = 'Audit Options'
                    $item.Setting = $rule.Option
                    $item.Path = "$securityPath > Advanced Audit Policy Configuration > Audit Policies > Audit Options"
                    $item.Name = $rule.Option -replace '^Option:', ''
                }
                'GlobalAudit' {
                    $item.PolicyType = 'Audit Policy'
                    $item.Group = 'Global Object Access Auditing'
                    $item.Setting = $rule.GlobalType
                    $item.Path = "$securityPath > Advanced Audit Policy Configuration > Audit Policies > Global Object Access Auditing"
                    $item.Name = $rule.GlobalType
                }
            }
            $described[$identity] = $item
        }
    }
    , $described
}

# The value of a rule as a cell shows it: the security settings and audit as the editor shows
# them (accounts by name), the registry data as Policy Analyzer ([[[delete]]]...).
function Format-PSGPOPolicyRuleValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicyRule]$Rule,
        [GPOToolsSecuritySetting]$Setting
    )

    switch ($Rule.Kind) {
        'Registry' {
            if ($Rule.IsDeleteAllValues()) { return '[[[Delete all values]]]' }
            if ($Rule.IsDelete()) { return '[[[delete]]]' }
            if ($Rule.RegType -eq 'REG_MULTI_SZ') { return (@($Rule.RegData -split '\\0') | Where-Object { $_ -ne '' }) -join '; ' }
            # A key created without value: not an empty cell, which is a setting not configured.
            if ($Rule.RegType -eq 'REG_NONE' -and -not $Rule.RegData) { return '(REG_NONE)' }
            return $Rule.RegData
        }
        'SecurityTemplate' {
            $raw = $Rule.GetLineValue()
            if ($Setting) {
                try { return $Setting.FormatValue($Setting.ConvertFromRaw($raw)) } catch { return $raw }
            }
            if ($Rule.Section -in [GPOToolsPolicyRule]::ListSections) {
                # mode,"SDDL": the startup of a service, how the permissions of a key or file apply.
                $comma = $raw.IndexOf(',')
                $mode = if ($comma -ge 0) { $raw.Substring(0, $comma).Trim() } else { $raw.Trim() }
                $sddl = if ($comma -ge 0) { [GPOToolsPolicyRule]::Unquote($raw.Substring($comma + 1)) } else { '' }
                $modes = if ($Rule.Section -eq 'Service General Setting') { $script:PSGPOPolicyRuleServiceMode } else { $script:PSGPOPolicyRulePermissionMode }
                $text = if ($modes.ContainsKey($mode)) { $modes[$mode] } else { $mode }
                if ($sddl) { return "$text; $sddl" }
                return $text
            }
            if ($Rule.Section -in [GPOToolsPolicyRule]::AccountSections) {
                $accounts = @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                if (-not $accounts.Count) { return '(no one)' }
                return ($accounts | ForEach-Object { [GPOToolsSecuritySetting]::FormatAccount($_) }) -join ', '
            }
            return $raw
        }
        'AuditSubcategory' {
            $number = 0
            if ([int]::TryParse($Rule.Setting, [ref]$number) -and $number -ge 0 -and $number -le 3) { return [GPOToolsAuditPolicyFile]::Inclusion[$number] }
            return $Rule.Setting
        }
        'AuditOption' {
            switch ("$($Rule.Setting)".Trim()) { '1' { return 'Enabled' } '0' { return 'Disabled' } }
            return $Rule.Setting
        }
        'GlobalAudit' { return $Rule.Sacl }
    }
    ''
}

# The comparison of rule sets, setting by setting (see the top of the file): one row per
# setting, sorted by scope, path and name, with a cell per set.
function Get-PSGPOPolicyRuleComparison {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsPolicyRuleSet[]]$RuleSet)

    $described = Get-PSGPOPolicyRuleDescription -RuleSet $RuleSet
    # identity -> one list of rules per set
    $byIdentity = [System.Collections.Generic.Dictionary[string, object]]::new()
    for ($index = 0; $index -lt $RuleSet.Count; $index++) {
        foreach ($rule in $RuleSet[$index].Rules) {
            $identity = $rule.GetIdentity()
            $lists = $null
            if (-not $byIdentity.TryGetValue($identity, [ref]$lists)) {
                $lists = [object[]]::new($RuleSet.Count)
                for ($each = 0; $each -lt $RuleSet.Count; $each++) { $lists[$each] = [System.Collections.Generic.List[GPOToolsPolicyRule]]::new() }
                $byIdentity[$identity] = $lists
            }
            $lists[$index].Add($rule)
        }
    }

    # In a set by precedence, a **delvals. clears the values of its key the GPOs of lower precedence
    # write: the highest precedence of a **delvals. by key (scope|key).
    $clearedAt = for ($index = 0; $index -lt $RuleSet.Count; $index++) {
        $keys = @{}
        foreach ($rule in $RuleSet[$index].Rules) {
            if ($rule.Precedence -le 0 -or -not $rule.IsDeleteAllValues()) { continue }
            $key = "$($rule.Scope)|$($rule.Key)".ToLowerInvariant()
            if (-not $keys.ContainsKey($key) -or $rule.Precedence -lt $keys[$key]) { $keys[$key] = $rule.Precedence }
        }
        , $keys
    }
    $clearedAt = @($clearedAt)

    # @(): one name alone comes back as a string, whose [0] is its first letter.
    $columns = @(Get-PSGPOPolicyRuleColumnName -RuleSet $RuleSet)
    $scopeOrder = @{ Computer = 0; User = 1 }
    $rows = foreach ($identity in $byIdentity.Keys) {
        $lists = $byIdentity[$identity]
        $item = $described[$identity]
        # The type shown with the data when the sets do not all use the same one.
        $types = @($lists | ForEach-Object { $_ } | Where-Object { $_.Kind -eq 'Registry' -and -not $_.IsDelete() -and -not $_.IsDeleteAllValues() } | ForEach-Object RegType | Select-Object -Unique)
        $cells = for ($index = 0; $index -lt $RuleSet.Count; $index++) {
            $rules = $lists[$index]
            # By precedence (the GPOs of an OU): the GPO of precedence 1 first, its value wins.
            $ordered = $rules.Count -and -not @($rules | Where-Object Precedence -LE 0).Count
            if ($ordered) { $rules = [System.Collections.Generic.List[GPOToolsPolicyRule]]@($rules | Sort-Object Precedence) }
            $distinct = @($rules | ForEach-Object { $_.GetComparable() } | Select-Object -Unique)
            $winner = if ($rules.Count) { $rules[0] }
            $cleared = $false
            if ($ordered -and $winner.Kind -eq 'Registry' -and -not $winner.IsDeleteAllValues()) {
                $at = $clearedAt[$index]["$($winner.Scope)|$($winner.Key)".ToLowerInvariant()]
                $cleared = $null -ne $at -and $at -lt $winner.Precedence
            }
            $state = if (-not $rules.Count) { 'Absent' }
                elseif ($cleared) { 'Overridden' }
                elseif ($distinct.Count -gt 1) { if ($ordered) { 'Overridden' } else { 'Conflict' } }
                elseif ($rules.Count -gt 1) { 'Duplicate' } else { 'Set' }
            $value = if (-not $rules.Count) { '' }
                elseif ($state -eq 'Conflict') { '***CONFLICT***' }
                elseif ($cleared) { '[[[Delete all values]]]' }
                else {
                    $text = Format-PSGPOPolicyRuleValue -Rule $winner -Setting $item.CatalogSetting
                    if ($types.Count -gt 1 -and $winner.Kind -eq 'Registry' -and -not $winner.IsDelete()) { "$text ($($winner.RegType))" } else { $text }
                }
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.PolicyRuleCell'
                Set = $columns[$index]
                State = $state
                Value = $value
                Comparable = if ($cleared) { '[[[Delete all values]]]' } elseif ($state -in 'Set', 'Duplicate', 'Overridden') { $winner.GetComparable() } else { $null }
                Rules = @($rules)
                # Applied: the value of the GPO that wins in a set by precedence.
                Values = @(for ($each = 0; $each -lt $rules.Count; $each++) {
                        $rule = $rules[$each]
                        [pscustomobject]@{
                            PolicyName = $rule.PolicyName; Value = Format-PSGPOPolicyRuleValue -Rule $rule -Setting $item.CatalogSetting; SourceFile = $rule.SourceFile
                            Precedence = $rule.Precedence; Applied = $ordered -and $each -eq 0 -and -not $cleared
                        }
                    })
            }
        }
        $cells = @($cells)
        $present = @($cells | Where-Object { $_.State -ne 'Absent' })
        $conflict = @($cells | Where-Object State -EQ 'Conflict').Count -gt 0 -or @($present | Where-Object Comparable | ForEach-Object Comparable | Select-Object -Unique).Count -gt 1
        $row = [ordered]@{
            PSTypeName = 'PSGPOTools.PolicyRuleComparison'
            Scope = $item.Scope
            Path = $item.Path
            Name = $item.Name
            Option = $item.Option
        }
        for ($index = 0; $index -lt $RuleSet.Count; $index++) { $row[$columns[$index]] = $cells[$index].Value }
        $row.Conflict = $conflict
        $row.Difference = $conflict -or ($RuleSet.Count -gt 1 -and $present.Count -lt $cells.Count)
        $row.PolicyType = $item.PolicyType
        $row.Group = $item.Group
        $row.Setting = $item.Setting
        $row.Kind = $item.Kind
        $row.Explain = $item.Explain
        $row.Reference = $item.Reference
        $row.Identity = $identity
        $row.Cells = $cells
        [pscustomobject]$row
    }
    @($rows | Sort-Object { $scopeOrder[$_.Scope] }, Path, Name, Option, Group, Setting)
}

# The column of each set: its name, made unique ("Name (2)") and not one of the other properties
# of a row.
function Get-PSGPOPolicyRuleColumnName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [GPOToolsPolicyRuleSet[]]$RuleSet)

    $taken = [System.Collections.Generic.HashSet[string]]::new([string[]]@('PSTypeName', 'Scope', 'Path', 'Name', 'Option', 'Conflict', 'Difference', 'PolicyType', 'Group', 'Setting', 'Kind', 'Explain', 'Reference', 'Identity', 'Cells'), [System.StringComparer]::OrdinalIgnoreCase)
    $names = foreach ($set in $RuleSet) {
        $base = if ($set.Name) { $set.Name } else { 'Rule set' }
        $name = $base
        for ($number = 2; $taken.Contains($name); $number++) { $name = "$base ($number)" }
        [void]$taken.Add($name)
        $name
    }
    [string[]]@($names)
}

# The rule set of the backups of a folder: GPMC backups (a folder of them as Backup-GPO writes it,
# the GPOs folder of a security baseline, or one backup), and those of HGPM (Backup-PSGPO: their
# folder, the newest backup of each GPO; the folder of a GPO, its newest; one backup, or its Files
# folder). As GPO2PolicyRules: the GPOs by name, the newest backup of each.
function New-PSGPOPolicyRuleSetFromBackupFolder {
    [CmdletBinding()]
    [OutputType([GPOToolsPolicyRuleSet])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string[]]$Name,
        [string]$SetName
    )

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "No folder $Path." }
    $same = { param($A, $B) [string]::Equals([System.IO.Path]::GetFullPath($A).TrimEnd('\', '/'), [System.IO.Path]::GetFullPath($B).TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase) }
    # The Files folder of a backup of HGPM: the backup.
    if ([System.IO.Path]::GetFileName($full) -ieq 'Files' -and (Test-Path -LiteralPath (Join-Path ([System.IO.Path]::GetDirectoryName($full)) 'manifest.json'))) { $full = [System.IO.Path]::GetDirectoryName($full) }

    $own = @()
    if (Test-Path -LiteralPath (Join-Path $full 'manifest.json')) {
        # One backup of HGPM: read with the others of its folder of backups.
        $root = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetDirectoryName($full))
        $own = @(Get-PSGPOBackupEntry -Path $root | Where-Object { & $same $_.Path $full })
    } elseif (@(Get-ChildItem -LiteralPath $full -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json') }).Count) {
        # The folder of a GPO of HGPM, its backups by date: the newest.
        $root = [System.IO.Path]::GetDirectoryName($full)
        $own = @(Get-PSGPOBackupEntry -Path $root | Where-Object { & $same ([System.IO.Path]::GetDirectoryName($_.Path)) $full })
    } else {
        $own = @(Get-PSGPOBackupEntry -Path $full -ErrorAction SilentlyContinue)
    }
    $gpmc = @(Get-PSGPOGpmcBackupEntry -Path $full -WarningAction SilentlyContinue)
    $match = { param($DisplayName) -not $Name -or @($Name | Where-Object { Test-PSGPONameMatch -Name $DisplayName -Pattern $_ }).Count }
    $sources = @(@($gpmc) + @($own) | Where-Object { & $match $_.DisplayName } | Sort-Object { if ($_.BackedUp) { $_.BackedUp } else { [datetime]::MinValue } } -Descending | Group-Object Id | ForEach-Object { $_.Group[0] } | Sort-Object DisplayName)
    if (-not $sources.Count) { throw "No backup of GPMC nor of HGPM$(if ($Name) { " of '$($Name -join "', '")'" }) in $Path." }

    $set = [GPOToolsPolicyRuleSet]::new($(if ($SetName) { $SetName } elseif ($sources.Count -eq 1) { $sources[0].DisplayName } else { [System.IO.Path]::GetFileName($full) }))
    $set.Path = $full
    foreach ($source in $sources) {
        if ($source.PSObject.TypeNames -contains 'PSGPOTools.GpmcBackup') {
            $files = Read-PSGPOGpmcBackupFile -Backup $source
            $root = Join-Path $source.Path 'DomainSysvol' 'GPO'
            $machine = $source.MachineExtensionNames
            $user = $source.UserExtensionNames
        } else {
            $files = Read-PSGPOBackupFile -Backup $source
            $root = Join-Path $source.Path 'Files'
            $extensions = Get-PSGPOBackupExtensionName -Backup $source -Files $files
            $machine = $extensions.Machine
            $user = $extensions.User
        }
        foreach ($rule in @(ConvertTo-PSGPOPolicyRule -Files $files -PolicyName $source.DisplayName -SourceRoot $root)) { $set.Rules.Add($rule) }
        Add-PSGPOPolicyRuleExtension -RuleSet $set -MachineExtensionNames $machine -UserExtensionNames $user
    }
    $set
}
