<#
    Security settings of a GPO as the Group Policy editor shows them under Computer
    Configuration > Policies > Windows Settings > Security Settings, each one a key of a section
    of GptTmpl.inf (GPOToolsSecurityTemplate). The catalog of the settings is in
    Resources/SecuritySettings.json (Get-PSGPOSecuritySetting).

    Kinds and their GptTmpl.inf value:
      Number         an integer ("42"); Min / Max, special values in Choices (-1: never...)
      Boolean        0 or 1 (Disabled / Enabled)
      Text           a quoted string (NewAdministratorName = "Admin")
      Choice         an integer among Choices
      Audit          0 none, 1 success, 2 failure, 3 success and failure ([Event Audit])
      Accounts       comma-separated accounts, a SID prefixed with * ([Privilege Rights])
      RegistryValue  "<type>,<data>" for the registry value Key ([Registry Values]); its
                     RegistryType (1 REG_SZ, 2 REG_EXPAND_SZ, 3 REG_BINARY, 4 REG_DWORD,
                     7 REG_MULTI_SZ) and how it is shown (Display: Boolean, Number, Text,
                     Choice, MultiText, Bitmask)
#>

class GPOToolsSecurityChoice {
    [string]$Value
    [string]$Text
}

class GPOToolsSecuritySetting {
    # Unique in the catalog: the section and key
    [string]$Id
    [string]$Name
    # Categories under Security Settings ('Account Policies', 'Password Policy')
    [string[]]$Path
    [string]$Section
    [string]$Key
    [string]$Kind
    # RegistryValue: the registry type and how the value is shown
    [int]$RegistryType
    [string]$Display
    [Nullable[long]]$Min
    [Nullable[long]]$Max
    [string]$Unit
    [GPOToolsSecurityChoice[]]$Choices
    # Page of the setting on Microsoft Learn
    [string]$Reference

    [string] ToString() { return $this.Name }

    # Value of the setting from its raw GptTmpl.inf value ($null: not defined).
    [object] ConvertFromRaw([string]$Raw) {
        if ($null -eq $Raw) { return $null }
        switch ($this.Kind) {
            { $_ -in 'Number', 'Choice', 'Audit' } { return [long]$Raw }
            'Boolean' { return [long]$Raw -ne 0 }
            'Text' { return [GPOToolsSecuritySetting]::Unquote($Raw) }
            'Accounts' { return [string[]]@($Raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            'RegistryValue' {
                $Comma = $Raw.IndexOf(',')
                $Data = if ($Comma -ge 0) { $Raw.Substring($Comma + 1) } else { '' }
                switch ($this.RegistryType) {
                    { $_ -in 1, 2 } { return [GPOToolsSecuritySetting]::Unquote($Data) }
                    7 { return [string[]]@($Data -split ',' | Where-Object { $_ -ne '' }) }
                    # REG_DWORD, or REG_BINARY shown as a boolean (Audit the use of Backup and Restore privilege)
                    { $_ -eq 4 -or ($_ -eq 3 -and $this.Display -eq 'Boolean') } {
                        $Number = [long]$Data
                        if ($this.Display -eq 'Boolean') { return $Number -ne 0 }
                        return $Number
                    }
                }
                return $Data
            }
        }
        return $Raw
    }

    # Raw GptTmpl.inf value of a value of the setting ($null: not defined).
    [string] ConvertToRaw([object]$Value) {
        if ($null -eq $Value) { return $null }
        switch ($this.Kind) {
            { $_ -in 'Number', 'Choice', 'Audit' } {
                $Number = [long]$Value
                $this.AssertRange($Number)
                return "$Number"
            }
            'Boolean' { if ($Value) { return '1' } else { return '0' } }
            'Text' { return [GPOToolsSecuritySetting]::Quote("$Value") }
            'Accounts' { return (@($Value) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ',' }
            'RegistryValue' {
                switch ($this.RegistryType) {
                    { $_ -in 1, 2 } { return "$($this.RegistryType),$([GPOToolsSecuritySetting]::Quote("$Value"))" }
                    7 { return "7,$((@($Value) | Where-Object { "$_" -ne '' }) -join ',')" }
                    { $_ -eq 4 -or ($_ -eq 3 -and $this.Display -eq 'Boolean') } {
                        $Number = if ($Value -is [bool]) { [long][int]$Value } else { [long]$Value }
                        $this.AssertRange($Number)
                        return "$($this.RegistryType),$Number"
                    }
                }
                return "$($this.RegistryType),$Value"
            }
        }
        return "$Value"
    }

    hidden [void] AssertRange([long]$Number) {
        # Special values (-1 never...) are allowed even out of the range.
        if ($this.Choices -and @($this.Choices | Where-Object { $_.Value -eq "$Number" }).Count) { return }
        if ($this.Kind -eq 'Choice' -or $this.Display -eq 'Choice') {
            if ($this.Choices -and -not @($this.Choices | Where-Object { $_.Value -eq "$Number" }).Count) {
                throw "'$($this.Name)': $Number is not one of its choices."
            }
            return
        }
        if ($this.Kind -eq 'Audit' -and ($Number -lt 0 -or $Number -gt 3)) { throw "'$($this.Name)': $Number is not an audit value (0 to 3)." }
        if ($null -ne $this.Min -and $Number -lt $this.Min) { throw "'$($this.Name)' must be at least $($this.Min)$(if ($this.Unit) { " $($this.Unit)" })." }
        if ($null -ne $this.Max -and $Number -gt $this.Max) { throw "'$($this.Name)' must be at most $($this.Max)$(if ($this.Unit) { " $($this.Unit)" })." }
    }

    # Names of the well-known SIDs ([MS-DTYP] 2.4.2.4), as the Group Policy editor shows them.
    static [hashtable] $WellKnownAccounts = @{
        'S-1-1-0' = 'Everyone'; 'S-1-3-0' = 'CREATOR OWNER'; 'S-1-5-2' = 'NT AUTHORITY\NETWORK'
        'S-1-5-3' = 'NT AUTHORITY\BATCH'; 'S-1-5-4' = 'NT AUTHORITY\INTERACTIVE'; 'S-1-5-6' = 'NT AUTHORITY\SERVICE'
        'S-1-5-7' = 'NT AUTHORITY\ANONYMOUS LOGON'; 'S-1-5-9' = 'NT AUTHORITY\ENTERPRISE DOMAIN CONTROLLERS'
        'S-1-5-11' = 'NT AUTHORITY\Authenticated Users'; 'S-1-5-13' = 'NT AUTHORITY\TERMINAL SERVER USER'
        'S-1-5-14' = 'NT AUTHORITY\REMOTE INTERACTIVE LOGON'; 'S-1-5-17' = 'NT AUTHORITY\IUSR'
        'S-1-5-18' = 'NT AUTHORITY\SYSTEM'; 'S-1-5-19' = 'NT AUTHORITY\LOCAL SERVICE'; 'S-1-5-20' = 'NT AUTHORITY\NETWORK SERVICE'
        'S-1-5-113' = 'NT AUTHORITY\Local account'; 'S-1-5-114' = 'NT AUTHORITY\Local account and member of Administrators group'
        'S-1-5-32-544' = 'BUILTIN\Administrators'; 'S-1-5-32-545' = 'BUILTIN\Users'; 'S-1-5-32-546' = 'BUILTIN\Guests'
        'S-1-5-32-547' = 'BUILTIN\Power Users'; 'S-1-5-32-548' = 'BUILTIN\Account Operators'; 'S-1-5-32-549' = 'BUILTIN\Server Operators'
        'S-1-5-32-550' = 'BUILTIN\Print Operators'; 'S-1-5-32-551' = 'BUILTIN\Backup Operators'; 'S-1-5-32-552' = 'BUILTIN\Replicator'
        'S-1-5-32-554' = 'BUILTIN\Pre-Windows 2000 Compatible Access'; 'S-1-5-32-555' = 'BUILTIN\Remote Desktop Users'
        'S-1-5-32-556' = 'BUILTIN\Network Configuration Operators'; 'S-1-5-32-558' = 'BUILTIN\Performance Monitor Users'
        'S-1-5-32-559' = 'BUILTIN\Performance Log Users'; 'S-1-5-32-562' = 'BUILTIN\Distributed COM Users'
        'S-1-5-32-568' = 'BUILTIN\IIS_IUSRS'; 'S-1-5-32-573' = 'BUILTIN\Event Log Readers'; 'S-1-5-32-578' = 'BUILTIN\Hyper-V Administrators'
        'S-1-5-32-580' = 'BUILTIN\Remote Management Users'; 'S-1-5-80-0' = 'NT SERVICE\ALL SERVICES'
        'S-1-5-83-0' = 'NT VIRTUAL MACHINE\Virtual Machines'; 'S-1-15-2-1' = 'APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES'
    }
    # Accounts of a domain by their RID (S-1-5-21-<domain>-<RID>).
    static [hashtable] $DomainAccounts = @{
        '500' = 'Administrator'; '501' = 'Guest'; '502' = 'krbtgt'; '512' = 'Domain Admins'; '513' = 'Domain Users'
        '514' = 'Domain Guests'; '515' = 'Domain Computers'; '516' = 'Domain Controllers'; '517' = 'Cert Publishers'
        '518' = 'Schema Admins'; '519' = 'Enterprise Admins'; '520' = 'Group Policy Creator Owners'
        '521' = 'Read-only Domain Controllers'; '525' = 'Protected Users'
    }

    # Name of an account of a user right ('*S-1-5-32-544' -> 'BUILTIN\Administrators'): a name as
    # written, a SID by its well-known name, else the SID.
    static [string] FormatAccount([string]$Account) {
        if (-not $Account.StartsWith('*')) { return $Account }
        $Sid = $Account.Substring(1)
        if ([GPOToolsSecuritySetting]::WellKnownAccounts.ContainsKey($Sid)) { return [GPOToolsSecuritySetting]::WellKnownAccounts[$Sid] }
        if ($Sid -match '^S-1-5-21-\d+-\d+-\d+-(\d+)$' -and [GPOToolsSecuritySetting]::DomainAccounts.ContainsKey($Matches[1])) {
            return [GPOToolsSecuritySetting]::DomainAccounts[$Matches[1]]
        }
        return $Sid
    }

    hidden static [string] Quote([string]$Text) { return '"' + $Text.Replace('"', '""') + '"' }

    hidden static [string] Unquote([string]$Text) {
        $Value = $Text.Trim()
        if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) { $Value = $Value.Substring(1, $Value.Length - 2).Replace('""', '"') }
        return $Value
    }

    # Text of a value, as the Group Policy editor and the GPMC report show it.
    [string] FormatValue([object]$Value) {
        if ($null -eq $Value) { return 'Not Defined' }
        $Choice = @($this.Choices | Where-Object { $_.Value -eq "$Value" }) | Select-Object -First 1
        switch ($this.Kind) {
            'Boolean' { if ($Value) { return 'Enabled' } else { return 'Disabled' } }
            'Audit' {
                $Number = [long]$Value
                if ($Number -eq 0) { return 'No auditing' }
                return (@(if ($Number -band 1) { 'Success' }) + @(if ($Number -band 2) { 'Failure' })) -join ', '
            }
            'Accounts' {
                if (@($Value).Count) { return (@($Value) | ForEach-Object { [GPOToolsSecuritySetting]::FormatAccount($_) }) -join ', ' }
                return '(no one)'
            }
        }
        if ($this.Display -eq 'Bitmask') {
            $Number = [long]$Value
            $Set = @($this.Choices | Where-Object { ($Number -band [long]$_.Value) -eq [long]$_.Value -and [long]$_.Value -ne 0 } | ForEach-Object Text)
            if ($Set.Count) { return $Set -join ', ' } else { return 'None' }
        }
        if ($Choice) { return $Choice.Text }
        if ($this.Kind -eq 'RegistryValue' -and $this.Display -eq 'Boolean') { if ($Value) { return 'Enabled' } else { return 'Disabled' } }
        if ($Value -is [array]) { return $Value -join '; ' }
        if ($this.Unit) { return "$Value $($this.Unit)" }
        return "$Value"
    }
}
