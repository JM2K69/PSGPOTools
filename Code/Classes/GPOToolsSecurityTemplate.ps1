<#
    GptTmpl.inf, the security settings of a GPO (MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf):
    a security template ([MS-GPSB] 2.2), read and written on any platform.

    An INF file in UTF-16LE with a byte order mark: [Unicode] Unicode=yes, [Version]
    signature="$CHICAGO$" Revision=1, then sections of "key = value" lines ([System Access],
    [Kerberos Policy], [Event Audit], [Privilege Rights], [Registry Values], [System Log]...).
    A setting absent from its section is not defined. The sections and keys this module does
    not know are kept as they are, in their order, and every line not changed (comments
    included) is written back as it was read: an unchanged template is rewritten byte for byte.
#>

class GPOToolsSecurityTemplate {
    # Section name -> ordered list of @{ Key; Value; Line } (keys and section names
    # case-insensitive). Line: the line as read, written back while the value is unchanged;
    # a comment or blank line has no Key.
    hidden [System.Collections.Specialized.OrderedDictionary]$Sections
    # Lines before the first section, and how each section header was written.
    hidden [System.Collections.Generic.List[string]]$Preamble
    hidden [hashtable]$Headers

    GPOToolsSecurityTemplate() {
        $this.Sections = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
        $this.Preamble = [System.Collections.Generic.List[string]]::new()
        $this.Headers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $this.SetValue('Unicode', 'Unicode', 'yes')
        $this.SetValue('Version', 'signature', '"$CHICAGO$"')
        $this.SetValue('Version', 'Revision', '1')
    }

    static [GPOToolsSecurityTemplate] Parse([byte[]]$Bytes) {
        $Template = [GPOToolsSecurityTemplate]::new()
        if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $Template }
        $Template.Sections.Clear()
        $Text = [GPOToolsSecurityTemplate]::Decode($Bytes)
        # The last line break ends the last line: no empty line after it.
        if ($Text.EndsWith("`n")) { $Text = $Text.Substring(0, $Text.Length - 1) }
        if ($Text.EndsWith("`r")) { $Text = $Text.Substring(0, $Text.Length - 1) }
        $Section = $null
        $LineNumber = 0
        foreach ($Line in $Text -split '\r?\n') {
            $LineNumber++
            $Trimmed = $Line.Trim()
            if ($Trimmed -match '^\[(.+)\]$') {
                $Section = $Matches[1].Trim()
                if (-not $Template.Sections.Contains($Section)) {
                    $Template.Sections[$Section] = [System.Collections.Generic.List[object]]::new()
                    $Template.Headers[$Section] = $Line
                }
                continue
            }
            if (-not $Trimmed -or $Trimmed.StartsWith(';')) {
                if ($null -eq $Section) { $Template.Preamble.Add($Line) }
                else { $Template.Sections[$Section].Add(@{ Key = $null; Value = $null; Line = $Line }) }
                continue
            }
            if ($null -eq $Section) { throw "GptTmpl.inf line ${LineNumber}: a setting before any [section]." }
            $Equal = $Trimmed.IndexOf('=')
            if ($Equal -lt 0) {
                # A line without '=' (some sections list values alone): kept as a key without value.
                $Template.Sections[$Section].Add(@{ Key = $Trimmed; Value = $null; Line = $Line })
                continue
            }
            $Template.Sections[$Section].Add(@{ Key = $Trimmed.Substring(0, $Equal).Trim(); Value = $Trimmed.Substring($Equal + 1).Trim(); Line = $Line })
        }
        # samba-tool gpo manage security writes no [Unicode] nor [Version]: a file without
        # sections only is not a security template.
        if (-not $Template.Sections.Count) { throw 'Not a security template: GptTmpl.inf has no [section].' }
        return $Template
    }

    # UTF-16LE with a byte order mark, as secedit writes it; UTF-8 or ANSI files are read too.
    hidden static [string] Decode([byte[]]$Bytes) {
        if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3) }
        if ($Bytes.Length -ge 2 -and $Bytes[1] -eq 0) { return [System.Text.Encoding]::Unicode.GetString($Bytes) }
        return [System.Text.Encoding]::UTF8.GetString($Bytes)
    }

    [byte[]] ToBytes() {
        $Text = [System.Text.StringBuilder]::new()
        foreach ($Line in $this.Preamble) { [void]$Text.Append("$Line`r`n") }
        foreach ($Name in $this.Sections.Keys) {
            $Header = if ($this.Headers.ContainsKey($Name)) { $this.Headers[$Name] } else { "[$Name]" }
            [void]$Text.Append("$Header`r`n")
            foreach ($Entry in $this.Sections[$Name]) {
                if ($null -ne $Entry.Line) { [void]$Text.Append("$($Entry.Line)`r`n") }
                elseif ($null -eq $Entry.Value) { [void]$Text.Append("$($Entry.Key)`r`n") }
                # As secedit writes them: no spaces in [Unicode], [Version] and [Registry Values].
                elseif ($Name -in 'Unicode', 'Version', 'Registry Values') { [void]$Text.Append("$($Entry.Key)=$($Entry.Value)`r`n") }
                else { [void]$Text.Append("$($Entry.Key) = $($Entry.Value)`r`n") }
            }
        }
        return [byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($Text.ToString())
    }

    [string[]] GetSectionNames() { return @($this.Sections.Keys) }

    # [Unicode] and [Version] first when they are missing, as [MS-GPSB] 2.2 requires them.
    [void] AddPreamble() {
        if (-not $this.Sections.Contains('Version')) {
            $Version = [System.Collections.Generic.List[object]]::new()
            $Version.Add(@{ Key = 'signature'; Value = '"$CHICAGO$"'; Line = $null })
            $Version.Add(@{ Key = 'Revision'; Value = '1'; Line = $null })
            $this.Sections.Insert(0, 'Version', $Version)
        }
        if (-not $this.Sections.Contains('Unicode')) {
            $Unicode = [System.Collections.Generic.List[object]]::new()
            $Unicode.Add(@{ Key = 'Unicode'; Value = 'yes'; Line = $null })
            $this.Sections.Insert(0, 'Unicode', $Unicode)
        }
    }

    # Keys of a section, in their order (empty when the section is absent).
    [string[]] GetKeys([string]$Section) {
        if (-not $this.Sections.Contains($Section)) { return @() }
        return @($this.Sections[$Section] | Where-Object { $null -ne $_.Key } | ForEach-Object { $_.Key })
    }

    # The settings of a section as read, in their order: Key and Value ($null for a line without
    # '=', which GetValue returns as '').
    [object[]] GetEntries([string]$Section) {
        if (-not $this.Sections.Contains($Section)) { return @() }
        return @($this.Sections[$Section] | Where-Object { $null -ne $_.Key })
    }

    # A line added at the end of a section, $null value for a line without '=' (the "name",mode,"SDDL"
    # lines of services, files and registry keys); SetValue changes a key in place instead.
    [void] AddEntry([string]$Section, [string]$Key, [object]$Value) {
        if (-not $this.Sections.Contains($Section)) { $this.Sections[$Section] = [System.Collections.Generic.List[object]]::new() }
        $this.Sections[$Section].Add(@{ Key = $Key; Value = $(if ($null -eq $Value) { $null } else { "$Value" }); Line = $null })
    }

    # Raw value of a key ($null when the setting is not defined).
    [string] GetValue([string]$Section, [string]$Key) {
        if (-not $this.Sections.Contains($Section)) { return $null }
        foreach ($Entry in $this.Sections[$Section]) {
            if ([string]::Equals($Entry.Key, $Key, [System.StringComparison]::OrdinalIgnoreCase)) { return $Entry.Value }
        }
        return $null
    }

    [bool] HasValue([string]$Section, [string]$Key) {
        if (-not $this.Sections.Contains($Section)) { return $false }
        foreach ($Entry in $this.Sections[$Section]) {
            if ([string]::Equals($Entry.Key, $Key, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }

    # Sets a raw value, in place when the key exists; $null removes the setting (not defined),
    # and an emptied section is removed.
    # [object] and not [string]: a [string] parameter turns $null into ''.
    [void] SetValue([string]$Section, [string]$Key, [object]$Value) {
        if ($null -eq $Value) {
            if (-not $this.Sections.Contains($Section)) { return }
            $List = $this.Sections[$Section]
            for ($i = $List.Count - 1; $i -ge 0; $i--) {
                if ([string]::Equals($List[$i].Key, $Key, [System.StringComparison]::OrdinalIgnoreCase)) { $List.RemoveAt($i) }
            }
            if (-not @($List | Where-Object { $null -ne $_.Key }).Count -and $Section -notin 'Unicode', 'Version') { $this.Sections.Remove($Section) }
            return
        }
        if (-not $this.Sections.Contains($Section)) { $this.Sections[$Section] = [System.Collections.Generic.List[object]]::new() }
        foreach ($Entry in $this.Sections[$Section]) {
            if ([string]::Equals($Entry.Key, $Key, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($Entry.Value -cne "$Value") {
                    $Entry.Value = "$Value"
                    $Entry.Line = $null
                }
                return
            }
        }
        $this.Sections[$Section].Add(@{ Key = $Key; Value = "$Value"; Line = $null })
    }

    # Whether the template defines any setting (beyond [Unicode] and [Version]).
    [bool] IsEmpty() {
        foreach ($Name in $this.Sections.Keys) {
            if ($Name -notin 'Unicode', 'Version' -and @($this.Sections[$Name] | Where-Object { $null -ne $_.Key }).Count) { return $false }
        }
        return $true
    }
}
