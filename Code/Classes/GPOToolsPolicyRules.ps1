<#
    Rule sets of the Policy Analyzer of the Microsoft Security Compliance Toolkit (.PolicyRules):
    the settings of one or more GPOs in one XML file, read and written as PolicyAnalyzer.exe and
    GPO2PolicyRules.exe do (UTF-8 with a byte order mark, one element per line, CRLF):

      <PolicyRules>
      <ComputerConfig><Key>Software\Policies\..</Key><Value>Name</Value><RegType>REG_DWORD</RegType><RegData>1</RegData><SourceFile>..\Machine\registry.pol</SourceFile><PolicyName>GPO</PolicyName></ComputerConfig>
      <UserConfig>... the same, from User\registry.pol ...</UserConfig>
      <SecurityTemplate Section="Privilege Rights"><LineItem>SeBackupPrivilege=*S-1-5-32-544</LineItem><SourceFile>..</SourceFile><PolicyName>..</PolicyName></SecurityTemplate>
      <AuditSubcategory><GUID>{0cce923f-..}</GUID><Name>Audit Credential Validation</Name><Setting>3</Setting><SourceFile>..</SourceFile><PolicyName>..</PolicyName></AuditSubcategory>
      <AuditOption><Option>Option:CrashOnAuditFail</Option><Setting>1</Setting>...</AuditOption>
      <GlobalAudit><Type>FileGlobalSacl</Type><SACL>..</SACL>...</GlobalAudit>
      <CSE-Machine><GUID>{35378EAC-..}</GUID><Name>Registry Policy</Name></CSE-Machine>
      <CSE-User>...</CSE-User>
      </PolicyRules>

    The registry settings first, then the security template, the audit policy and the client-side
    extensions of all the GPOs. RegData as GPO2PolicyRules writes it: the strings of a REG_MULTI_SZ
    joined by the two characters \0, the bytes of a REG_BINARY in lower-case hex separated by
    commas, numbers in decimal. Text is escaped with &amp; &lt; &gt; &quot; &apos;, and control
    characters as &#xHH;.
#>

class GPOToolsPolicyRule {
    # Registry, SecurityTemplate, AuditSubcategory, AuditOption or GlobalAudit
    [string]$Kind
    # Computer or User: only registry settings are of the user
    [string]$Scope = 'Computer'
    # The GPO the setting comes from, and its file
    [string]$PolicyName
    [string]$SourceFile
    # Registry: key, value name (**del.<name>, **delvals.), type (REG_DWORD...) and data as written
    [string]$Key
    [string]$ValueName
    [string]$RegType
    [string]$RegData
    # SecurityTemplate: the section and the line of the setting (key=value)
    [string]$Section
    [string]$LineItem
    # AuditSubcategory: GUID, name and setting (0 to 3); AuditOption: option and setting;
    # GlobalAudit: type and SACL
    [string]$Guid
    [string]$Name
    [string]$Setting
    [string]$Option
    [string]$GlobalType
    [string]$Sacl
    # The precedence of its GPO where it applies (1 wins, as the Group Policy Inheritance tab of
    # GPMC numbers them); 0 in a set without order (a file, GPOs chosen). Not in the file.
    [int]$Precedence

    # Sections whose lines are "name",mode,"value" rather than key=value.
    static [string[]] $ListSections = @('Service General Setting', 'Registry Keys', 'File Security')
    # Sections whose values are lists of accounts, compared in any order.
    static [string[]] $AccountSections = @('Privilege Rights', 'Group Membership')

    [bool] IsDelete() { return $this.Kind -eq 'Registry' -and $this.ValueName.StartsWith('**del.', [System.StringComparison]::OrdinalIgnoreCase) }
    [bool] IsDeleteAllValues() { return $this.Kind -eq 'Registry' -and $this.ValueName.StartsWith('**delvals.', [System.StringComparison]::OrdinalIgnoreCase) }

    # The value name a registry setting is about: without **del.
    [string] GetTargetValueName() {
        if ($this.IsDelete()) { return $this.ValueName.Substring(6) }
        return $this.ValueName
    }

    # Key and value of the line of a security setting.
    [string] GetLineKey() {
        $Line = "$($this.LineItem)".Trim()
        if ($this.Section -in [GPOToolsPolicyRule]::ListSections) {
            $Comma = [GPOToolsPolicyRule]::FindFieldEnd($Line)
            return [GPOToolsPolicyRule]::Unquote($Line.Substring(0, $Comma))
        }
        $Equal = $Line.IndexOf('=')
        if ($Equal -lt 0) { return $Line }
        return $Line.Substring(0, $Equal).Trim()
    }

    [string] GetLineValue() {
        $Line = "$($this.LineItem)".Trim()
        if ($this.Section -in [GPOToolsPolicyRule]::ListSections) {
            $Comma = [GPOToolsPolicyRule]::FindFieldEnd($Line)
            if ($Comma -ge $Line.Length) { return '' }
            return $Line.Substring($Comma + 1).Trim()
        }
        $Equal = $Line.IndexOf('=')
        if ($Equal -lt 0) { return '' }
        return $Line.Substring($Equal + 1).Trim()
    }

    # What the setting is, the same in every set and GPO (lower case): two rules with the same
    # identity configure the same thing.
    [string] GetIdentity() {
        $Text = switch ($this.Kind) {
            'Registry' { '{0}|Registry|{1}|{2}' -f $this.Scope, $this.Key, $this.GetTargetValueName() }
            'SecurityTemplate' { 'Computer|SecurityTemplate|{0}|{1}' -f $this.Section, $this.GetLineKey() }
            'AuditSubcategory' { "Computer|AuditSubcategory|$($this.Guid)" }
            'AuditOption' { "Computer|AuditOption|$($this.Option)" }
            'GlobalAudit' { "Computer|GlobalAudit|$($this.GlobalType)" }
            default { "$($this.Scope)|$($this.Kind)" }
        }
        return "$Text".ToLowerInvariant()
    }

    # The value of the setting to compare with the same setting elsewhere, as Policy Analyzer
    # compares them: the type of a registry value counts (REG_DWORD 1 is not REG_SZ 1), and lists
    # whose order does not matter (accounts, REG_MULTI_SZ) are sorted.
    [string] GetComparable() {
        switch ($this.Kind) {
            'Registry' {
                if ($this.IsDeleteAllValues()) { return '[[[Delete all values]]]' }
                if ($this.IsDelete()) { return '[[[delete]]]' }
                if ($this.RegType -eq 'REG_MULTI_SZ') { return 'REG_MULTI_SZ|' + [GPOToolsPolicyRule]::SortList(($this.RegData -split '\\0'), $false) }
                return "$($this.RegType)|$($this.RegData)"
            }
            'SecurityTemplate' {
                $Value = $this.GetLineValue()
                if ($this.Section -in [GPOToolsPolicyRule]::AccountSections) { return [GPOToolsPolicyRule]::SortList(($Value -split ','), $true) }
                if ($this.Section -eq 'Registry Values') {
                    $Comma = $Value.IndexOf(',')
                    if ($Comma -lt 0) { return $Value }
                    $Type = $Value.Substring(0, $Comma).Trim()
                    $Data = $Value.Substring($Comma + 1).Trim()
                    if ($Type -eq '7') { return '7,' + [GPOToolsPolicyRule]::SortList(($Data -split ','), $false) }
                    return "$Type,$([GPOToolsPolicyRule]::Unquote($Data))"
                }
                if ($this.Section -in [GPOToolsPolicyRule]::ListSections) { return $Value }
                return [GPOToolsPolicyRule]::Unquote($Value)
            }
            'AuditSubcategory' { return "$($this.Setting)".Trim() }
            'AuditOption' { return "$($this.Setting)".Trim() }
            'GlobalAudit' { return "$($this.Sacl)".Trim() }
        }
        return ''
    }

    # Where the first field of a "name",mode,"value" line ends (its comma, or the end).
    hidden static [int] FindFieldEnd([string]$Line) {
        $Quoted = $false
        for ($Index = 0; $Index -lt $Line.Length; $Index++) {
            if ($Line[$Index] -eq '"') { $Quoted = -not $Quoted }
            elseif ($Line[$Index] -eq ',' -and -not $Quoted) { return $Index }
        }
        return $Line.Length
    }

    static [string] Unquote([string]$Text) {
        $Value = "$Text".Trim()
        if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) { $Value = $Value.Substring(1, $Value.Length - 2).Replace('""', '"') }
        return $Value
    }

    hidden static [string] SortList([string[]]$Items, [bool]$IgnoreCase) {
        $List = [System.Collections.Generic.List[string]]::new()
        foreach ($Item in $Items) { if ($Item.Trim()) { $List.Add($Item.Trim()) } }
        if ($IgnoreCase) { $List.Sort([System.StringComparer]::OrdinalIgnoreCase) } else { $List.Sort([System.StringComparer]::Ordinal) }
        return $List -join ','
    }

    [string] ToString() {
        switch ($this.Kind) {
            'Registry' { return '{0}: {1}\{2} = {3} {4}' -f $this.Scope, $this.Key, $this.ValueName, $this.RegType, $this.RegData }
            'SecurityTemplate' { return "[$($this.Section)] $($this.LineItem)" }
            'AuditSubcategory' { return "$($this.Name) = $($this.Setting)" }
            'AuditOption' { return "$($this.Option) = $($this.Setting)" }
            'GlobalAudit' { return "$($this.GlobalType) = $($this.Sacl)" }
        }
        return $this.Kind
    }
}

# A client-side extension a rule set lists (CSE-Machine, CSE-User).
class GPOToolsPolicyRuleExtension {
    # Machine or User
    [string]$Scope
    [string]$Guid
    [string]$Name

    [string] ToString() { return "$($this.Scope) $($this.Guid) $($this.Name)" }
}

class GPOToolsPolicyRuleSet {
    # The name of the set: the name of its file without .PolicyRules, or the one it was given
    [string]$Name
    # The .PolicyRules file it was read from, or where its settings were read
    [string]$Path
    [System.Collections.Generic.List[GPOToolsPolicyRule]]$Rules
    [System.Collections.Generic.List[GPOToolsPolicyRuleExtension]]$Extensions

    # The order of the elements in the file.
    static [string[]] $KindOrder = @('Registry', 'SecurityTemplate', 'AuditSubcategory', 'AuditOption', 'GlobalAudit')

    GPOToolsPolicyRuleSet() {
        $this.Rules = [System.Collections.Generic.List[GPOToolsPolicyRule]]::new()
        $this.Extensions = [System.Collections.Generic.List[GPOToolsPolicyRuleExtension]]::new()
    }

    GPOToolsPolicyRuleSet([string]$SetName) {
        $this.Name = $SetName
        $this.Rules = [System.Collections.Generic.List[GPOToolsPolicyRule]]::new()
        $this.Extensions = [System.Collections.Generic.List[GPOToolsPolicyRuleExtension]]::new()
    }

    # The GPOs the set holds, in their order.
    [string[]] GetPolicyNames() {
        $Seen = [System.Collections.Generic.List[string]]::new()
        foreach ($Rule in $this.Rules) { if ($Rule.PolicyName -and -not $Seen.Contains($Rule.PolicyName)) { $Seen.Add($Rule.PolicyName) } }
        return $Seen.ToArray()
    }

    # An extension once per scope.
    [void] AddExtension([string]$ExtensionScope, [string]$ExtensionGuid, [string]$ExtensionName) {
        foreach ($Known in $this.Extensions) {
            if ($Known.Scope -eq $ExtensionScope -and [string]::Equals($Known.Guid, $ExtensionGuid, [System.StringComparison]::OrdinalIgnoreCase)) { return }
        }
        $this.Extensions.Add([GPOToolsPolicyRuleExtension]@{ Scope = $ExtensionScope; Guid = $ExtensionGuid; Name = $ExtensionName })
    }

    static [GPOToolsPolicyRuleSet] Parse([byte[]]$Bytes, [string]$SetName) {
        $Set = [GPOToolsPolicyRuleSet]::new($SetName)
        $Text = [GPOToolsPolicyRuleSet]::Decode($Bytes)
        $Settings = [System.Xml.XmlReaderSettings]::new()
        $Settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $Settings.XmlResolver = $null
        # Policy Analyzer writes control characters as &#xHH;, which XML 1.0 does not allow.
        $Settings.CheckCharacters = $false
        $Document = [System.Xml.XmlDocument]::new()
        # RegData of a deletion is a space: kept.
        $Document.PreserveWhitespace = $true
        $Reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($Text), $Settings)
        try { $Document.Load($Reader) } finally { $Reader.Dispose() }
        if ($Document.DocumentElement.LocalName -ne 'PolicyRules') { throw "Not a .PolicyRules file: the root element is <$($Document.DocumentElement.LocalName)>, not <PolicyRules>." }

        foreach ($Element in $Document.DocumentElement.ChildNodes) {
            if ($Element -isnot [System.Xml.XmlElement]) { continue }
            $Field = @{}
            foreach ($Child in $Element.ChildNodes) { if ($Child -is [System.Xml.XmlElement]) { $Field[$Child.LocalName] = $Child.InnerText } }
            $Rule = [GPOToolsPolicyRule]::new()
            $Rule.SourceFile = $Field['SourceFile']
            $Rule.PolicyName = $Field['PolicyName']
            switch ($Element.LocalName) {
                { $_ -in 'ComputerConfig', 'UserConfig' } {
                    $Rule.Kind = 'Registry'
                    $Rule.Scope = if ($_ -eq 'UserConfig') { 'User' } else { 'Computer' }
                    $Rule.Key = "$($Field['Key'])"
                    $Rule.ValueName = "$($Field['Value'])"
                    $Rule.RegType = "$($Field['RegType'])"
                    $Rule.RegData = "$($Field['RegData'])"
                }
                'SecurityTemplate' {
                    $Rule.Kind = 'SecurityTemplate'
                    $Rule.Section = $Element.GetAttribute('Section')
                    $Rule.LineItem = "$($Field['LineItem'])"
                }
                'AuditSubcategory' {
                    $Rule.Kind = 'AuditSubcategory'
                    $Rule.Guid = "$($Field['GUID'])"
                    $Rule.Name = $Field['Name']
                    $Rule.Setting = "$($Field['Setting'])"
                }
                'AuditOption' {
                    $Rule.Kind = 'AuditOption'
                    $Rule.Option = "$($Field['Option'])"
                    $Rule.Setting = "$($Field['Setting'])"
                }
                'GlobalAudit' {
                    $Rule.Kind = 'GlobalAudit'
                    $Rule.GlobalType = "$($Field['Type'])"
                    $Rule.Sacl = "$($Field['SACL'])"
                }
                { $_ -in 'CSE-Machine', 'CSE-User' } {
                    $Set.AddExtension($(if ($_ -eq 'CSE-User') { 'User' } else { 'Machine' }), "$($Field['GUID'])", "$($Field['Name'])")
                }
            }
            if ($Rule.Kind) { $Set.Rules.Add($Rule) }
        }
        return $Set
    }

    # UTF-8 with or without its byte order mark, or UTF-16 with one.
    hidden static [string] Decode([byte[]]$Bytes) {
        if ($null -eq $Bytes -or $Bytes.Length -eq 0) { throw 'Not a .PolicyRules file: it is empty.' }
        if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3) }
        return [System.Text.Encoding]::UTF8.GetString($Bytes)
    }

    # The file, as GPO2PolicyRules writes it.
    [byte[]] ToBytes() {
        $Text = [System.Text.StringBuilder]::new()
        [void]$Text.Append("<PolicyRules>`r`n")
        $X = { param([string]$Value) [GPOToolsPolicyRuleSet]::Escape($Value) }
        foreach ($Kind in [GPOToolsPolicyRuleSet]::KindOrder) {
            foreach ($Rule in $this.Rules) {
                if ($Rule.Kind -ne $Kind) { continue }
                $Source = '<SourceFile>{0}</SourceFile><PolicyName>{1}</PolicyName>' -f (& $X $Rule.SourceFile), (& $X $Rule.PolicyName)
                $Line = switch ($Kind) {
                    'Registry' {
                        $Tag = if ($Rule.Scope -eq 'User') { 'UserConfig' } else { 'ComputerConfig' }
                        '<{0}><Key>{1}</Key><Value>{2}</Value><RegType>{3}</RegType><RegData>{4}</RegData>{5}</{0}>' -f $Tag, (& $X $Rule.Key), (& $X $Rule.ValueName), (& $X $Rule.RegType), (& $X $Rule.RegData), $Source
                    }
                    'SecurityTemplate' { '<SecurityTemplate Section="{0}"><LineItem>{1}</LineItem>{2}</SecurityTemplate>' -f (& $X $Rule.Section), (& $X $Rule.LineItem), $Source }
                    'AuditSubcategory' { '<AuditSubcategory><GUID>{0}</GUID><Name>{1}</Name><Setting>{2}</Setting>{3}</AuditSubcategory>' -f (& $X $Rule.Guid), (& $X $Rule.Name), (& $X $Rule.Setting), $Source }
                    'AuditOption' { '<AuditOption><Option>{0}</Option><Setting>{1}</Setting>{2}</AuditOption>' -f (& $X $Rule.Option), (& $X $Rule.Setting), $Source }
                    'GlobalAudit' { '<GlobalAudit><Type>{0}</Type><SACL>{1}</SACL>{2}</GlobalAudit>' -f (& $X $Rule.GlobalType), (& $X $Rule.Sacl), $Source }
                }
                [void]$Text.Append($Line).Append("`r`n")
            }
        }
        foreach ($ExtensionScope in 'Machine', 'User') {
            foreach ($Extension in $this.Extensions) {
                if ($Extension.Scope -ne $ExtensionScope) { continue }
                [void]$Text.Append(('<CSE-{0}><GUID>{1}</GUID><Name>{2}</Name></CSE-{0}>' -f $ExtensionScope, (& $X $Extension.Guid), (& $X $Extension.Name))).Append("`r`n")
            }
        }
        [void]$Text.Append("</PolicyRules>`r`n")
        return [byte[]](0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($Text.ToString())
    }

    static [string] Escape([string]$Value) {
        if ([string]::IsNullOrEmpty($Value)) { return '' }
        $Text = [System.Text.StringBuilder]::new($Value.Length)
        foreach ($Character in $Value.ToCharArray()) {
            switch ($Character) {
                '&' { [void]$Text.Append('&amp;') }
                '<' { [void]$Text.Append('&lt;') }
                '>' { [void]$Text.Append('&gt;') }
                '"' { [void]$Text.Append('&quot;') }
                "'" { [void]$Text.Append('&apos;') }
                default {
                    if ([int]$Character -lt 0x20) { [void]$Text.Append(('&#x{0:X2};' -f [int]$Character)) }
                    else { [void]$Text.Append($Character) }
                }
            }
        }
        return $Text.ToString()
    }

    [string] ToString() { return "$($this.Name) ($($this.Rules.Count) settings)" }
}
