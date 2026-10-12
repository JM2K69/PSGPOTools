<#
    Security descriptors of the directory and of SYSVOL ([MS-DTYP] 2.4.6, self-relative form),
    read and written without the ACL classes of .NET: they are only supported on Windows, and the
    console also runs on Linux. Used for the security filtering of a GPO: the access control
    entries "Apply Group Policy" of its group policy container, and the ACL of its SYSVOL folder
    derived from it as samba-tool and GPMC do.

    The access control entries the console does not edit (audit, callback, conditional...) are
    kept byte for byte.
#>

class GPOToolsAce {
    # 0 access allowed, 1 access denied, 5 access allowed object, 6 access denied object
    [byte]$Type
    # 0x01 object inherit, 0x02 container inherit, 0x04 no propagate, 0x08 inherit only, 0x10 inherited
    [byte]$Flags
    [uint32]$Mask
    # Object ACEs: the property, property set or extended right; [guid]::Empty when absent
    [guid]$ObjectType
    [guid]$InheritedObjectType
    [string]$Sid
    # Other ACE types: the ACE as read
    hidden [byte[]]$Raw

    static [byte] $AccessAllowed = 0
    static [byte] $AccessDenied = 1
    static [byte] $AccessAllowedObject = 5
    static [byte] $AccessDeniedObject = 6
    static [byte] $ObjectInherit = 0x01
    static [byte] $ContainerInherit = 0x02
    static [byte] $InheritOnly = 0x08
    static [byte] $Inherited = 0x10

    GPOToolsAce() {}

    GPOToolsAce([byte]$Type, [byte]$Flags, [uint32]$Mask, [string]$Sid, [guid]$ObjectType) {
        $this.Type = $Type
        $this.Flags = $Flags
        $this.Mask = $Mask
        $this.Sid = $Sid
        $this.ObjectType = $ObjectType
    }

    [bool] IsObjectAce() {
        return $this.Type -eq [GPOToolsAce]::AccessAllowedObject -or $this.Type -eq [GPOToolsAce]::AccessDeniedObject
    }

    [bool] IsKnown() { return $null -eq $this.Raw }

    [bool] IsDeny() {
        return $this.Type -eq [GPOToolsAce]::AccessDenied -or $this.Type -eq [GPOToolsAce]::AccessDeniedObject
    }

    static [GPOToolsAce] Parse([byte[]]$Bytes, [int]$Offset) {
        $Ace = [GPOToolsAce]::new()
        $Ace.Type = $Bytes[$Offset]
        $Ace.Flags = $Bytes[$Offset + 1]
        $Size = [BitConverter]::ToUInt16($Bytes, $Offset + 2)
        if ($Ace.Type -notin 0, 1, 5, 6) {
            $Ace.Raw = [byte[]]::new($Size)
            [Array]::Copy($Bytes, $Offset, $Ace.Raw, 0, $Size)
            return $Ace
        }
        $Ace.Mask = [BitConverter]::ToUInt32($Bytes, $Offset + 4)
        $Position = $Offset + 8
        if ($Ace.IsObjectAce()) {
            $Present = [BitConverter]::ToUInt32($Bytes, $Position)
            $Position += 4
            if ($Present -band 1) { $Ace.ObjectType = [GPOToolsAce]::ReadGuid($Bytes, $Position); $Position += 16 }
            if ($Present -band 2) { $Ace.InheritedObjectType = [GPOToolsAce]::ReadGuid($Bytes, $Position); $Position += 16 }
        }
        $Ace.Sid = [GPOToolsSecurityDescriptor]::ConvertSidToString($Bytes, $Position)
        return $Ace
    }

    static [guid] ReadGuid([byte[]]$Bytes, [int]$Offset) {
        $Guid = [byte[]]::new(16)
        [Array]::Copy($Bytes, $Offset, $Guid, 0, 16)
        return [guid]::new($Guid)
    }

    [byte[]] ToBytes() {
        if ($this.Raw) { return $this.Raw }
        $Body = [System.IO.MemoryStream]::new()
        $Body.Write([BitConverter]::GetBytes($this.Mask), 0, 4)
        if ($this.IsObjectAce()) {
            $Present = [uint32]0
            if ($this.ObjectType -ne [guid]::Empty) { $Present = $Present -bor 1 }
            if ($this.InheritedObjectType -ne [guid]::Empty) { $Present = $Present -bor 2 }
            $Body.Write([BitConverter]::GetBytes($Present), 0, 4)
            if ($Present -band 1) { $Body.Write($this.ObjectType.ToByteArray(), 0, 16) }
            if ($Present -band 2) { $Body.Write($this.InheritedObjectType.ToByteArray(), 0, 16) }
        }
        $SidBytes = [GPOToolsSecurityDescriptor]::ConvertSidToBytes($this.Sid)
        $Body.Write($SidBytes, 0, $SidBytes.Length)
        $Size = 4 + $Body.Length
        $Ace = [byte[]]::new($Size)
        $Ace[0] = $this.Type
        $Ace[1] = $this.Flags
        [Array]::Copy([BitConverter]::GetBytes([uint16]$Size), 0, $Ace, 2, 2)
        [Array]::Copy($Body.ToArray(), 0, $Ace, 4, $Body.Length)
        return $Ace
    }

    # SDDL form of the ACE, with SID strings and the access mask in hexadecimal.
    [string] ToSddl() {
        if ($this.Raw) { throw "An access control entry of type $($this.Type) has no SDDL form here." }
        $TypeText = @{ 0 = 'A'; 1 = 'D'; 5 = 'OA'; 6 = 'OD' }[[int]$this.Type]
        $FlagText = [System.Text.StringBuilder]::new()
        foreach ($Pair in @(@(0x01, 'OI'), @(0x02, 'CI'), @(0x04, 'NP'), @(0x08, 'IO'), @(0x10, 'ID'), @(0x40, 'SA'), @(0x80, 'FA'))) {
            if ($this.Flags -band $Pair[0]) { [void]$FlagText.Append($Pair[1]) }
        }
        $Object = if ($this.ObjectType -ne [guid]::Empty) { $this.ObjectType.ToString() } else { '' }
        $InheritedText = if ($this.InheritedObjectType -ne [guid]::Empty) { $this.InheritedObjectType.ToString() } else { '' }
        return '({0};{1};0x{2:x8};{3};{4};{5})' -f $TypeText, $FlagText, $this.Mask, $Object, $InheritedText, $this.Sid
    }
}

class GPOToolsSecurityDescriptor {
    # SE_* control flags; the descriptor is always written self-relative
    [uint16]$Control
    [string]$Owner
    [string]$Group
    # $null: no DACL
    [System.Collections.Generic.List[GPOToolsAce]]$Dacl
    # The SACL as read, kept byte for byte
    hidden [byte[]]$Sacl

    static [uint16] $DaclPresent = 0x0004
    static [uint16] $SaclPresent = 0x0010
    static [uint16] $DaclAutoInherited = 0x0400
    static [uint16] $DaclProtected = 0x1000
    static [uint16] $SelfRelative = 0x8000

    # Rights of the directory ([MS-ADTS] 5.1.3.2) and the extended right "Apply Group Policy".
    static [uint32] $ReadMask = 0x00020094   # READ_CONTROL | LIST_CHILDREN | READ_PROPERTY | LIST_OBJECT
    static [uint32] $ControlAccess = 0x00000100
    static [guid] $ApplyGroupPolicy = 'edacfd8f-ffb3-11d1-b41d-00a0c968f939'
    static [string] $AuthenticatedUsers = 'S-1-5-11'
    static [string] $CreatorOwner = 'S-1-3-0'
    static [string] $PreWindows2000 = 'S-1-5-32-554'

    static [GPOToolsSecurityDescriptor] Parse([byte[]]$Bytes) {
        if (-not $Bytes -or $Bytes.Length -lt 20 -or $Bytes[0] -ne 1) { throw 'Not a self-relative security descriptor.' }
        $Descriptor = [GPOToolsSecurityDescriptor]::new()
        $Descriptor.Control = [BitConverter]::ToUInt16($Bytes, 2)
        $OwnerOffset = [BitConverter]::ToInt32($Bytes, 4)
        $GroupOffset = [BitConverter]::ToInt32($Bytes, 8)
        $SaclOffset = [BitConverter]::ToInt32($Bytes, 12)
        $DaclOffset = [BitConverter]::ToInt32($Bytes, 16)
        if ($OwnerOffset) { $Descriptor.Owner = [GPOToolsSecurityDescriptor]::ConvertSidToString($Bytes, $OwnerOffset) }
        if ($GroupOffset) { $Descriptor.Group = [GPOToolsSecurityDescriptor]::ConvertSidToString($Bytes, $GroupOffset) }
        if ($SaclOffset) {
            $Size = [BitConverter]::ToUInt16($Bytes, $SaclOffset + 2)
            $Descriptor.Sacl = [byte[]]::new($Size)
            [Array]::Copy($Bytes, $SaclOffset, $Descriptor.Sacl, 0, $Size)
        }
        if ($DaclOffset) {
            $Descriptor.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
            $Count = [BitConverter]::ToUInt16($Bytes, $DaclOffset + 4)
            $Position = $DaclOffset + 8
            for ($i = 0; $i -lt $Count; $i++) {
                $Descriptor.Dacl.Add([GPOToolsAce]::Parse($Bytes, $Position))
                $Position += [BitConverter]::ToUInt16($Bytes, $Position + 2)
            }
        }
        return $Descriptor
    }

    [byte[]] ToBytes() {
        $Stream = [System.IO.MemoryStream]::new()
        $Stream.Write([byte[]]::new(20), 0, 20)
        $Offsets = @{ Owner = 0; Group = 0; Sacl = 0; Dacl = 0 }
        $ControlValue = $this.Control -bor [GPOToolsSecurityDescriptor]::SelfRelative
        # Owner, group, SACL then DACL, as Samba and Windows lay them out.
        if ($this.Owner) {
            $Offsets.Owner = [int]$Stream.Length
            $Sid = [GPOToolsSecurityDescriptor]::ConvertSidToBytes($this.Owner)
            $Stream.Write($Sid, 0, $Sid.Length)
        }
        if ($this.Group) {
            $Offsets.Group = [int]$Stream.Length
            $Sid = [GPOToolsSecurityDescriptor]::ConvertSidToBytes($this.Group)
            $Stream.Write($Sid, 0, $Sid.Length)
        }
        if ($this.Sacl) {
            $Offsets.Sacl = [int]$Stream.Length
            $Stream.Write($this.Sacl, 0, $this.Sacl.Length)
            $ControlValue = $ControlValue -bor [GPOToolsSecurityDescriptor]::SaclPresent
        } else {
            $ControlValue = $ControlValue -band 0xFFEF   # no SACL present
        }
        if ($null -ne $this.Dacl) {
            $Offsets.Dacl = [int]$Stream.Length
            $Aces = [System.IO.MemoryStream]::new()
            foreach ($Ace in $this.Dacl) { $AceBytes = $Ace.ToBytes(); $Aces.Write($AceBytes, 0, $AceBytes.Length) }
            $Header = [byte[]]::new(8)
            $Header[0] = 4   # ACL_REVISION_DS: the ACL may hold object ACEs
            [Array]::Copy([BitConverter]::GetBytes([uint16](8 + $Aces.Length)), 0, $Header, 2, 2)
            [Array]::Copy([BitConverter]::GetBytes([uint16]$this.Dacl.Count), 0, $Header, 4, 2)
            $Stream.Write($Header, 0, 8)
            $Stream.Write($Aces.ToArray(), 0, [int]$Aces.Length)
            $ControlValue = $ControlValue -bor [GPOToolsSecurityDescriptor]::DaclPresent
        }
        $Bytes = $Stream.ToArray()
        $Bytes[0] = 1
        [Array]::Copy([BitConverter]::GetBytes([uint16]$ControlValue), 0, $Bytes, 2, 2)
        [Array]::Copy([BitConverter]::GetBytes([int]$Offsets.Owner), 0, $Bytes, 4, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$Offsets.Group), 0, $Bytes, 8, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$Offsets.Sacl), 0, $Bytes, 12, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$Offsets.Dacl), 0, $Bytes, 16, 4)
        return $Bytes
    }

    # SDDL of the owner, group and DACL (smbcacls --sddl); the SACL is not part of it.
    [string] ToSddl() {
        $Text = [System.Text.StringBuilder]::new()
        if ($this.Owner) { [void]$Text.Append("O:$($this.Owner)") }
        if ($this.Group) { [void]$Text.Append("G:$($this.Group)") }
        if ($null -ne $this.Dacl) {
            [void]$Text.Append('D:')
            if ($this.Control -band [GPOToolsSecurityDescriptor]::DaclProtected) { [void]$Text.Append('P') }
            if ($this.Control -band [GPOToolsSecurityDescriptor]::DaclAutoInherited) { [void]$Text.Append('AI') }
            foreach ($Ace in $this.Dacl) { [void]$Text.Append($Ace.ToSddl()) }
        }
        return $Text.ToString()
    }

    # Places an ACE where Windows expects it: explicit deny ACEs, then explicit allow ACEs, then
    # the inherited ones.
    [void] AddAce([GPOToolsAce]$Ace) {
        $Index = 0
        while ($Index -lt $this.Dacl.Count) {
            $Existing = $this.Dacl[$Index]
            if ($Existing.Flags -band [GPOToolsAce]::Inherited) { break }
            if ($Ace.IsDeny() -and -not $Existing.IsDeny()) { break }
            $Index++
        }
        $this.Dacl.Insert($Index, $Ace)
    }

    # ACL of the SYSVOL folder of a GPO from the ACL of its group policy container, as Samba
    # (dsacl2fsacl) and GPMC derive it: the allow ACEs, inherited by the files and folders, with
    # the rights of the directory turned into file rights.
    [GPOToolsSecurityDescriptor] ConvertToFileSystem() {
        $Files = [GPOToolsSecurityDescriptor]::new()
        $Files.Owner = $this.Owner
        $Files.Group = $this.Group
        $Files.Control = $this.Control -band ([GPOToolsSecurityDescriptor]::DaclProtected -bor [GPOToolsSecurityDescriptor]::DaclAutoInherited)
        $Files.Dacl = [System.Collections.Generic.List[GPOToolsAce]]::new()
        foreach ($Ace in $this.Dacl) {
            if (-not $Ace.IsKnown() -or $Ace.IsDeny() -or $Ace.Sid -eq [GPOToolsSecurityDescriptor]::PreWindows2000) { continue }
            $Copy = [GPOToolsAce]::new($Ace.Type, ($Ace.Flags -bor [GPOToolsAce]::ObjectInherit -bor [GPOToolsAce]::ContainerInherit), [GPOToolsSecurityDescriptor]::ConvertToFileMask($Ace.Mask), $Ace.Sid, $Ace.ObjectType)
            $Copy.InheritedObjectType = $Ace.InheritedObjectType
            if ($Ace.Sid -eq [GPOToolsSecurityDescriptor]::CreatorOwner) { $Copy.Flags = $Copy.Flags -bor [GPOToolsAce]::InheritOnly }
            $Files.Dacl.Add($Copy)
        }
        return $Files
    }

    # File rights of directory rights (Samba ldapmask2filemask).
    static [uint32] ConvertToFileMask([uint32]$Mask) {
        $File = $Mask -band 0x001F0000
        if (($Mask -band 0x10) -and ($Mask -band 0x04)) { $File = $File -bor 0x001000A9 }   # read: SYNCHRONIZE, list, read attributes and EA, execute
        if ($Mask -band 0x20) { $File = $File -bor 0x00100116 }                           # write: SYNCHRONIZE, write data, append, write attributes and EA
        if ($Mask -band 0x01) { $File = $File -bor 0x00000006 }                           # create child: add file and subdirectory
        if ($Mask -band 0x02) { $File = $File -bor 0x00000040 }                           # delete child
        return [uint32]$File
    }

    static [string] ConvertSidToString([byte[]]$Bytes, [int]$Offset) {
        $Count = $Bytes[$Offset + 1]
        $Authority = [uint64]0
        for ($i = 2; $i -lt 8; $i++) { $Authority = ($Authority -shl 8) -bor $Bytes[$Offset + $i] }
        $Text = [System.Text.StringBuilder]::new("S-$($Bytes[$Offset])-$Authority")
        for ($i = 0; $i -lt $Count; $i++) { [void]$Text.Append("-$([BitConverter]::ToUInt32($Bytes, $Offset + 8 + 4 * $i))") }
        return $Text.ToString()
    }

    static [byte[]] ConvertSidToBytes([string]$Sid) {
        $Parts = $Sid.Split('-')
        if ($Parts.Count -lt 3 -or $Parts[0] -ne 'S') { throw "Not a SID: '$Sid'." }
        $SubAuthorities = $Parts.Count - 3
        $Bytes = [byte[]]::new(8 + 4 * $SubAuthorities)
        $Bytes[0] = [byte]$Parts[1]
        $Bytes[1] = [byte]$SubAuthorities
        $Authority = [uint64]$Parts[2]
        for ($i = 7; $i -ge 2; $i--) { $Bytes[$i] = [byte]($Authority -band 0xFF); $Authority = $Authority -shr 8 }
        for ($i = 0; $i -lt $SubAuthorities; $i++) {
            [Array]::Copy([BitConverter]::GetBytes([uint32]$Parts[3 + $i]), 0, $Bytes, 8 + 4 * $i, 4)
        }
        return $Bytes
    }

    # Security filtering of a GPO ([MS-GPOL] 3.2.5.1.6): the members of $ApplySid read and apply
    # it, the members of $DenySid do not apply it, and Authenticated Users only read it (the
    # computers must read the GPO, MS16-072). Both are optional.
    [void] SetSecurityFiltering([string]$ApplySid, [string]$DenySid) {
        $Apply = [GPOToolsSecurityDescriptor]::ApplyGroupPolicy
        $Inherit = [GPOToolsAce]::ContainerInherit
        if ($ApplySid) {
            # Authenticated Users no longer apply it: only the members of the group.
            for ($i = $this.Dacl.Count - 1; $i -ge 0; $i--) {
                $Ace = $this.Dacl[$i]
                if ($Ace.IsKnown() -and -not ($Ace.Flags -band [GPOToolsAce]::Inherited) -and $Ace.Type -eq [GPOToolsAce]::AccessAllowedObject -and
                    $Ace.ObjectType -eq $Apply -and $Ace.Sid -eq [GPOToolsSecurityDescriptor]::AuthenticatedUsers) {
                    $this.Dacl.RemoveAt($i)
                }
            }
            $this.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowed, $Inherit, [GPOToolsSecurityDescriptor]::ReadMask, $ApplySid, [guid]::Empty))
            $this.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessAllowedObject, $Inherit, [GPOToolsSecurityDescriptor]::ControlAccess, $ApplySid, $Apply))
        }
        if ($DenySid) {
            $this.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDeniedObject, $Inherit, [GPOToolsSecurityDescriptor]::ControlAccess, $DenySid, $Apply))
        }
    }
}
