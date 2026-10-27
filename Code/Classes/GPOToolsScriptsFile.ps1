<#
    Scripts of a GPO ([MS-GPSCR] 2.2.2): scripts.ini (the scripts) and psscripts.ini (the Windows
    PowerShell scripts) in Machine\Scripts (startup, shutdown) or User\Scripts (logon, logoff), as
    the Group Policy editor writes them, in UTF-16 with a byte order mark:

      [Startup]
      0CmdLine=Install-Agent.ps1
      0Parameters=-Quiet

    A script is a command line and its parameters, numbered from 0 in the order they run; a command
    line without a folder is a file of the folder of its kind in the GPO (Machine\Scripts\Startup).
    psscripts.ini may say whether the PowerShell scripts run before the others or after them
    ([ScriptsConfig]: StartExecutePSFirst for startup and logon, EndExecutePSFirst for shutdown and
    logoff, true or false). The other sections and keys are kept as they are.
#>

class GPOToolsScriptsFile {
    static [string] $ConfigSection = 'ScriptsConfig'

    # The sections in their order, by name (any case): the list of their lines, @{ Key; Value }
    # each, or a line that is no key as its text.
    hidden [System.Collections.Specialized.OrderedDictionary] $Sections = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)

    static [GPOToolsScriptsFile] Parse([byte[]]$Bytes) {
        $File = [GPOToolsScriptsFile]::new()
        if (-not $Bytes -or $Bytes.Length -eq 0) { return $File }
        $Lines = $null
        $Text = [GPOToolsScriptsFile]::Decode($Bytes)
        foreach ($Line in ($Text -split '\r?\n')) {
            if ($Line -match '^\s*\[(.+)\]\s*$') {
                $Name = $Matches[1].Trim()
                if (-not $File.Sections.Contains($Name)) { $File.Sections[$Name] = [System.Collections.Generic.List[object]]::new() }
                $Lines = $File.Sections[$Name]
                continue
            }
            if ($null -eq $Lines -or -not $Line.Trim()) { continue }
            $Equal = $Line.IndexOf('=')
            if ($Equal -gt 0) { $Lines.Add([pscustomobject]@{ Key = $Line.Substring(0, $Equal).Trim(); Value = $Line.Substring($Equal + 1) }) }
            else { $Lines.Add($Line) }
        }
        return $File
    }

    # UTF-16 with its byte order mark, else UTF-8 (with or without one).
    hidden static [string] Decode([byte[]]$Bytes) {
        if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3) }
        return [System.Text.Encoding]::UTF8.GetString($Bytes)
    }

    # The scripts of a kind (Startup, Shutdown, Logon, Logoff) in their order: CmdLine, Parameters.
    [object[]] GetScripts([string]$Kind) {
        if (-not $this.Sections.Contains($Kind)) { return @() }
        $Found = @{}
        foreach ($Line in $this.Sections[$Kind]) {
            if ($Line -is [string] -or $Line.Key -notmatch '^(\d+)(CmdLine|Parameters)$') { continue }
            $Index = [int]$Matches[1]
            if (-not $Found.ContainsKey($Index)) { $Found[$Index] = [pscustomobject]@{ CmdLine = ''; Parameters = '' } }
            if ($Matches[2] -eq 'CmdLine') { $Found[$Index].CmdLine = $Line.Value } else { $Found[$Index].Parameters = $Line.Value }
        }
        return @(foreach ($Index in @($Found.Keys | Sort-Object)) { if ($Found[$Index].CmdLine) { $Found[$Index] } })
    }

    # The scripts of a kind, numbered again from 0 in this order; the section goes when it has nothing left.
    [void] SetScripts([string]$Kind, [object[]]$Scripts) {
        if (-not $this.Sections.Contains($Kind)) { $this.Sections[$Kind] = [System.Collections.Generic.List[object]]::new() }
        $Lines = $this.Sections[$Kind]
        foreach ($Line in @($Lines)) {
            if ($Line -isnot [string] -and $Line.Key -match '^\d+(CmdLine|Parameters)$') { [void]$Lines.Remove($Line) }
        }
        $Index = 0
        foreach ($Script in @($Scripts)) {
            $CmdLine = "$($Script.CmdLine)".Trim()
            if (-not $CmdLine) { continue }
            if ($CmdLine -match '[\r\n]' -or "$($Script.Parameters)" -match '[\r\n]') { throw "A script is one line: '$CmdLine'." }
            $Lines.Add([pscustomobject]@{ Key = "$($Index)CmdLine"; Value = $CmdLine })
            $Lines.Add([pscustomobject]@{ Key = "$($Index)Parameters"; Value = "$($Script.Parameters)".Trim() })
            $Index++
        }
        if (-not $Lines.Count) { $this.Sections.Remove($Kind) }
    }

    # A key of [ScriptsConfig] (StartExecutePSFirst, EndExecutePSFirst), $null when it is not there.
    [string] GetConfig([string]$Key) {
        if (-not $this.Sections.Contains([GPOToolsScriptsFile]::ConfigSection)) { return $null }
        foreach ($Line in $this.Sections[[GPOToolsScriptsFile]::ConfigSection]) {
            if ($Line -isnot [string] -and $Line.Key -ieq $Key) { return $Line.Value.Trim() }
        }
        return $null
    }

    # Sets a key of [ScriptsConfig]; $null removes it.
    [void] SetConfig([string]$Key, [string]$Value) {
        $Name = [GPOToolsScriptsFile]::ConfigSection
        if (-not $this.Sections.Contains($Name)) { $this.Sections[$Name] = [System.Collections.Generic.List[object]]::new() }
        $Lines = $this.Sections[$Name]
        foreach ($Line in @($Lines)) { if ($Line -isnot [string] -and $Line.Key -ieq $Key) { [void]$Lines.Remove($Line) } }
        if ($Value) { $Lines.Add([pscustomobject]@{ Key = $Key; Value = $Value }) }
        if (-not $Lines.Count) { $this.Sections.Remove($Name) }
    }

    [bool] IsEmpty() { return $this.Sections.Count -eq 0 }

    # The file as the Group Policy editor writes it: UTF-16 with its byte order mark, CRLF, an
    # empty line first.
    [byte[]] ToBytes() {
        $Text = [System.Text.StringBuilder]::new()
        [void]$Text.Append("`r`n")
        foreach ($Name in $this.Sections.Keys) {
            [void]$Text.Append("[$Name]`r`n")
            foreach ($Line in $this.Sections[$Name]) {
                if ($Line -is [string]) { [void]$Text.Append("$Line`r`n") } else { [void]$Text.Append("$($Line.Key)=$($Line.Value)`r`n") }
            }
        }
        return [byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($Text.ToString())
    }
}
