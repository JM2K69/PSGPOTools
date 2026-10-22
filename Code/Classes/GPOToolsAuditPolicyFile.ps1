<#
    Advanced audit policy of a GPO: Machine\Microsoft\Windows NT\Audit\audit.csv, as the Group
    Policy editor writes it under Security Settings > Advanced Audit Policy Configuration > Audit
    Policies ([MS-GPAC]). One line per subcategory configured:

      Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value
      ,System,Audit Credential Validation,{0cce923f-69ae-11d9-bed3-505054503030},Success and Failure,,3

    Setting Value: 0 no auditing, 1 success, 2 failure, 3 success and failure; a subcategory not
    configured has no line. The other lines (audit options, global object access auditing) are
    kept as they are. The settings are those of the catalog Resources/AuditPolicies.json
    (Get-PSGPOSecuritySetting), in the section AdvancedAudit, by the GUID of their subcategory.
#>

class GPOToolsAuditPolicyFile {
    static [string] $Section = 'AdvancedAudit'
    static [string] $Header = 'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value'
    static [string[]] $Inclusion = @('No Auditing', 'Success', 'Failure', 'Success and Failure')

    # The lines of the file but its header: a subcategory as @{ Name; Guid; Value }, any other
    # line as its text.
    [System.Collections.Generic.List[object]] $Lines = [System.Collections.Generic.List[object]]::new()

    static [GPOToolsAuditPolicyFile] Parse([byte[]]$Bytes) {
        $File = [GPOToolsAuditPolicyFile]::new()
        if (-not $Bytes -or $Bytes.Length -eq 0) { return $File }
        $Text = [GPOToolsAuditPolicyFile]::Decode($Bytes)
        foreach ($Line in ($Text -split '\r?\n')) {
            if (-not $Line.Trim() -or $Line.StartsWith('Machine Name,', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $Fields = $Line.Split(',')
            if ($Fields.Count -ge 7 -and $Fields[1] -eq 'System' -and $Fields[3] -match '^\{[0-9a-fA-F-]{36}\}$' -and $Fields[6] -match '^[0-3]$') {
                $File.Lines.Add([pscustomobject]@{ Name = $Fields[2]; Guid = $Fields[3].ToLowerInvariant(); Value = [int]$Fields[6] })
            } else {
                $File.Lines.Add($Line)
            }
        }
        return $File
    }

    # UTF-16 with its byte order mark, else UTF-8 (with or without one).
    hidden static [string] Decode([byte[]]$Bytes) {
        if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3) }
        return [System.Text.Encoding]::UTF8.GetString($Bytes)
    }

    hidden [object] Find([string]$Guid) {
        foreach ($Line in $this.Lines) { if ($Line -isnot [string] -and $Line.Guid -eq $Guid.ToLowerInvariant()) { return $Line } }
        return $null
    }

    # As GPOToolsSecurityTemplate: the value of a subcategory (its Setting Value), $null when not configured.
    [string] GetValue([string]$Section, [string]$Key) {
        $Line = $this.Find($Key)
        if ($Section -ne [GPOToolsAuditPolicyFile]::Section -or -not $Line) { return $null }
        return "$($Line.Value)"
    }

    [bool] HasValue([string]$Section, [string]$Key) {
        return $Section -eq [GPOToolsAuditPolicyFile]::Section -and $null -ne $this.Find($Key)
    }

    # Configures a subcategory (0-3), or removes it ($null: not configured).
    [void] SetSubcategory([string]$Guid, [string]$Name, [object]$Value) {
        $Line = $this.Find($Guid)
        if ($null -eq $Value) {
            if ($Line) { [void]$this.Lines.Remove($Line) }
            return
        }
        $Number = [int]$Value
        if ($Number -lt 0 -or $Number -gt 3) { throw "'$Name': $Number is not an audit setting (0 no auditing, 1 success, 2 failure, 3 success and failure)." }
        if ($Line) { $Line.Value = $Number; $Line.Name = $Name; return }
        $this.Lines.Add([pscustomobject]@{ Name = $Name; Guid = $Guid.ToLowerInvariant(); Value = $Number })
    }

    [bool] IsEmpty() { return $this.Lines.Count -eq 0 }

    # The file as the Group Policy editor writes it: its header, a line per subcategory (CRLF).
    [byte[]] ToBytes() {
        $Text = [System.Text.StringBuilder]::new()
        [void]$Text.Append([GPOToolsAuditPolicyFile]::Header).Append("`r`n")
        foreach ($Line in $this.Lines) {
            if ($Line -is [string]) { [void]$Text.Append($Line).Append("`r`n"); continue }
            [void]$Text.Append((',System,{0},{1},{2},,{3}' -f $Line.Name, $Line.Guid, [GPOToolsAuditPolicyFile]::Inclusion[$Line.Value], $Line.Value)).Append("`r`n")
        }
        return [System.Text.Encoding]::UTF8.GetBytes($Text.ToString())
    }
}
