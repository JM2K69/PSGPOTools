<#
    Registry.pol, the registry settings of a GPO for one scope (Machine\Registry.pol for HKLM,
    User\Registry.pol for HKCU), read and written byte for byte on any platform.

    Format ("Registry Policy File Format", Microsoft Learn): the header 'PReg' and version 1
    (two little-endian DWORDs), then entries in UTF-16LE:
        [key;value name;type;size;data]
    key and value name end with a null character; type and size are little-endian DWORDs;
    data is size bytes. Special value names: **del.<name> deletes a value, **delvals. deletes
    all the values of the key, **DeleteValues / **DeleteKeys / **SecureKey / **soft.<name>.
#>

# Types of registry values (REG_*), as stored in Registry.pol.
enum GPOToolsPolType {
    None = 0
    String = 1
    ExpandString = 2
    Binary = 3
    DWord = 4
    DWordBigEndian = 5
    Link = 6
    MultiString = 7
    QWord = 11
}

class GPOToolsPolEntry {
    [string]$Key
    [string]$ValueName
    [GPOToolsPolType]$Type
    [byte[]]$Data

    GPOToolsPolEntry() {
        $this.Data = [byte[]]::new(0)
    }

    GPOToolsPolEntry([string]$Key, [string]$ValueName, [GPOToolsPolType]$Type, [byte[]]$Data) {
        $this.Key = $Key
        $this.ValueName = $ValueName
        $this.Type = $Type
        $this.Data = if ($null -eq $Data) { [byte[]]::new(0) } else { $Data }
    }

    # Value name without its **del. prefix, and whether the entry deletes it.
    [bool] IsDelete() { return $this.ValueName -like '`*`*del.*' }
    [bool] IsDeleteAllValues() { return $this.ValueName -like '`*`*delvals.*' }
    [string] GetTargetValueName() {
        if ($this.IsDelete()) { return $this.ValueName.Substring(6) }
        return $this.ValueName
    }

    # Data decoded by type: string, string[], uint32, uint64 or the bytes.
    [object] GetValue() {
        switch ($this.Type) {
            { $_ -in [GPOToolsPolType]::String, [GPOToolsPolType]::ExpandString, [GPOToolsPolType]::Link } {
                return [GPOToolsPolEntry]::DecodeString($this.Data)
            }
            ([GPOToolsPolType]::MultiString) {
                $Text = [System.Text.Encoding]::Unicode.GetString($this.Data)
                return [string[]]@($Text.Split([char]0) | Where-Object { $_ -ne '' })
            }
            ([GPOToolsPolType]::DWord) {
                if ($this.Data.Length -ge 4) { return [BitConverter]::ToUInt32($this.Data, 0) }
            }
            ([GPOToolsPolType]::DWordBigEndian) {
                if ($this.Data.Length -ge 4) { return ([uint32]$this.Data[0] -shl 24) -bor ([uint32]$this.Data[1] -shl 16) -bor ([uint32]$this.Data[2] -shl 8) -bor [uint32]$this.Data[3] }
            }
            ([GPOToolsPolType]::QWord) {
                if ($this.Data.Length -ge 8) { return [BitConverter]::ToUInt64($this.Data, 0) }
            }
        }
        return $this.Data
    }

    static [string] DecodeString([byte[]]$Data) {
        $Text = [System.Text.Encoding]::Unicode.GetString($Data)
        $End = $Text.IndexOf([char]0)
        if ($End -ge 0) { return $Text.Substring(0, $End) }
        return $Text
    }

    static [byte[]] EncodeString([string]$Text) {
        return [System.Text.Encoding]::Unicode.GetBytes("$Text" + [char]0)
    }

    # Entry written for a registry value of a policy setting (Get-PSGPOPolicyRegistryChange).
    static [GPOToolsPolEntry] FromRegistryValue([GPOToolsRegistryValue]$Value) {
        # Deletions as the Group Policy editor writes them: REG_SZ with a space.
        $Space = [GPOToolsPolEntry]::EncodeString(' ')
        switch ($Value.Type) {
            ([GPOToolsRegistryValueType]::Delete) {
                return [GPOToolsPolEntry]::new($Value.Key, "**del.$($Value.ValueName)", [GPOToolsPolType]::String, $Space)
            }
            ([GPOToolsRegistryValueType]::DeleteAllValues) {
                return [GPOToolsPolEntry]::new($Value.Key, '**delvals.', [GPOToolsPolType]::String, $Space)
            }
            ([GPOToolsRegistryValueType]::String) {
                return [GPOToolsPolEntry]::new($Value.Key, $Value.ValueName, [GPOToolsPolType]::String, [GPOToolsPolEntry]::EncodeString("$($Value.Value)"))
            }
            ([GPOToolsRegistryValueType]::ExpandString) {
                return [GPOToolsPolEntry]::new($Value.Key, $Value.ValueName, [GPOToolsPolType]::ExpandString, [GPOToolsPolEntry]::EncodeString("$($Value.Value)"))
            }
            ([GPOToolsRegistryValueType]::MultiString) {
                $Text = (@($Value.Value) | ForEach-Object { "$_" + [char]0 }) -join ''
                return [GPOToolsPolEntry]::new($Value.Key, $Value.ValueName, [GPOToolsPolType]::MultiString, [System.Text.Encoding]::Unicode.GetBytes($Text + [char]0))
            }
            ([GPOToolsRegistryValueType]::DWord) {
                return [GPOToolsPolEntry]::new($Value.Key, $Value.ValueName, [GPOToolsPolType]::DWord, [BitConverter]::GetBytes([uint32]$Value.Value))
            }
            ([GPOToolsRegistryValueType]::QWord) {
                return [GPOToolsPolEntry]::new($Value.Key, $Value.ValueName, [GPOToolsPolType]::QWord, [BitConverter]::GetBytes([uint64]$Value.Value))
            }
        }
        throw "Registry value type not written to Registry.pol: $($Value.Type)"
    }

    [string] ToString() {
        $Shown = $this.GetValue()
        if ($Shown -is [byte[]]) { $Shown = ($Shown | ForEach-Object { $_.ToString('X2') }) -join ' ' }
        elseif ($Shown -is [array]) { $Shown = $Shown -join '|' }
        return '[{0};{1};{2};{3}]' -f $this.Key, $this.ValueName, $this.Type, $Shown
    }
}

class GPOToolsRegistryPol {
    [System.Collections.Generic.List[GPOToolsPolEntry]]$Entries

    GPOToolsRegistryPol() {
        $this.Entries = [System.Collections.Generic.List[GPOToolsPolEntry]]::new()
    }

    static [GPOToolsRegistryPol] Parse([byte[]]$Bytes) {
        $Pol = [GPOToolsRegistryPol]::new()
        # An empty file holds no setting.
        if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $Pol }
        if ($Bytes.Length -lt 8 -or [BitConverter]::ToUInt32($Bytes, 0) -ne 0x67655250) {
            throw 'Not a Registry.pol file: the PReg signature is missing.'
        }
        $Version = [BitConverter]::ToUInt32($Bytes, 4)
        if ($Version -ne 1) { throw "Registry.pol version $Version is not supported (version 1 only)." }

        $Position = 8
        while ($Position -lt $Bytes.Length) {
            $Start = $Position
            [GPOToolsRegistryPol]::Expect($Bytes, [ref]$Position, '[')
            $Entry = [GPOToolsPolEntry]::new()
            $Entry.Key = [GPOToolsRegistryPol]::ReadString($Bytes, [ref]$Position)
            [GPOToolsRegistryPol]::Expect($Bytes, [ref]$Position, ';')
            $Entry.ValueName = [GPOToolsRegistryPol]::ReadString($Bytes, [ref]$Position)
            [GPOToolsRegistryPol]::Expect($Bytes, [ref]$Position, ';')
            $Entry.Type = [GPOToolsPolType][GPOToolsRegistryPol]::ReadDWord($Bytes, [ref]$Position)
            [GPOToolsRegistryPol]::Expect($Bytes, [ref]$Position, ';')
            $Size = [GPOToolsRegistryPol]::ReadDWord($Bytes, [ref]$Position)
            [GPOToolsRegistryPol]::Expect($Bytes, [ref]$Position, ';')
            if ($Position + $Size -gt $Bytes.Length) { throw "Registry.pol entry at byte $Start is truncated." }
            $Entry.Data = [byte[]]::new($Size)
            [Array]::Copy($Bytes, $Position, $Entry.Data, 0, $Size)
            $Position += $Size
            [GPOToolsRegistryPol]::Expect($Bytes, [ref]$Position, ']')
            $Pol.Entries.Add($Entry)
        }
        return $Pol
    }

    hidden static [void] Expect([byte[]]$Bytes, [ref]$Position, [char]$Character) {
        if ($Position.Value + 2 -gt $Bytes.Length -or [BitConverter]::ToChar($Bytes, $Position.Value) -ne $Character) {
            throw "Registry.pol is malformed: '$Character' expected at byte $($Position.Value)."
        }
        $Position.Value += 2
    }

    # UTF-16 string up to its null character (the null is read, not returned).
    hidden static [string] ReadString([byte[]]$Bytes, [ref]$Position) {
        $Text = [System.Text.StringBuilder]::new()
        while ($true) {
            if ($Position.Value + 2 -gt $Bytes.Length) { throw 'Registry.pol is malformed: a string does not end.' }
            $Character = [BitConverter]::ToChar($Bytes, $Position.Value)
            # Some writers omit the null before ';': stop there without reading it.
            if ($Character -eq ';') { break }
            $Position.Value += 2
            if ($Character -eq [char]0) { break }
            [void]$Text.Append($Character)
        }
        return $Text.ToString()
    }

    hidden static [uint32] ReadDWord([byte[]]$Bytes, [ref]$Position) {
        if ($Position.Value + 4 -gt $Bytes.Length) { throw 'Registry.pol is malformed: a number is truncated.' }
        $Value = [BitConverter]::ToUInt32($Bytes, $Position.Value)
        $Position.Value += 4
        return $Value
    }

    [byte[]] ToBytes() {
        $Stream = [System.IO.MemoryStream]::new()
        $Writer = [System.IO.BinaryWriter]::new($Stream)
        try {
            $Writer.Write([uint32]0x67655250)
            $Writer.Write([uint32]1)
            $Unicode = [System.Text.Encoding]::Unicode
            foreach ($Entry in $this.Entries) {
                $Writer.Write($Unicode.GetBytes('['))
                $Writer.Write($Unicode.GetBytes("$($Entry.Key)" + [char]0))
                $Writer.Write($Unicode.GetBytes(';'))
                $Writer.Write($Unicode.GetBytes("$($Entry.ValueName)" + [char]0))
                $Writer.Write($Unicode.GetBytes(';'))
                $Writer.Write([uint32]$Entry.Type)
                $Writer.Write($Unicode.GetBytes(';'))
                $Writer.Write([uint32]$Entry.Data.Length)
                $Writer.Write($Unicode.GetBytes(';'))
                $Writer.Write($Entry.Data)
                $Writer.Write($Unicode.GetBytes(']'))
            }
            $Writer.Flush()
            return $Stream.ToArray()
        } finally {
            $Writer.Dispose()
        }
    }

    # Entries of a key (case-insensitive, as the registry).
    [GPOToolsPolEntry[]] GetEntries([string]$Key) {
        return @($this.Entries | Where-Object { [string]::Equals($_.Key, $Key, [System.StringComparison]::OrdinalIgnoreCase) })
    }

    # The entry of a value, or the **del. entry that deletes it ($null when neither).
    [GPOToolsPolEntry] FindValue([string]$Key, [string]$ValueName) {
        foreach ($Entry in $this.Entries) {
            if (-not [string]::Equals($Entry.Key, $Key, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($Entry.IsDeleteAllValues()) { continue }
            if ([string]::Equals($Entry.GetTargetValueName(), $ValueName, [System.StringComparison]::OrdinalIgnoreCase)) { return $Entry }
        }
        return $null
    }
}
