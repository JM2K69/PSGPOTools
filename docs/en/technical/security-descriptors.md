# Security descriptors

The ACL classes of .NET only work on Windows. The console reads and writes the security
descriptors itself, in their self-relative form ([MS-DTYP] 2.4.6), on every platform:
`GPOToolsSecurityDescriptor` and `GPOToolsAce`.

## The format

| Part | |
|---|---|
| Header | revision 1, control flags (`SE_DACL_PRESENT`, `SE_DACL_PROTECTED`, `SE_DACL_AUTO_INHERITED`, `SE_SELF_RELATIVE`...), offsets of the owner, group, SACL, DACL |
| Owner, group | SIDs |
| SACL | kept byte for byte (never asked for: it needs a privilege) |
| DACL | revision 4 (`ACL_REVISION_DS`: it may hold object ACEs), the ACEs |

An ACE is allowed / denied (types 0, 1) or allowed / denied **object** (types 5, 6: with the GUID
of a property, a property set, a class or an extended right, and of the class that inherits it).
The ACEs of other types (audit, callback, conditional) are kept byte for byte. `ToSddl()` writes the
SDDL form, with the masks in hexadecimal, for the logs and the tests.

`AddAce` places an ACE where Windows expects it: explicit deny, explicit allow, then the inherited
ones.

## Security filtering

[MS-GPOL] 3.2.5.1.6: a computer or a user applies a GPO when it can **read** it and has the
extended right **Apply Group Policy** (`edacfd8f-ffb3-11d1-b41d-00a0c968f939`).

- `GetSecurityFiltering()`: who applies it (allow ACEs with that right, or every extended right),
  who is denied it;
- `SetSecurityFiltering(apply, deny)`: Authenticated Users no longer apply it but keep reading it
  (MS16-072: the computers must read the GPO), the group applies it, the other group is denied it.

## From the directory to SYSVOL

`ConvertToFileSystem()` derives the ACL of the GPO folder from the DACL of its container, as Samba
`dsacl2fsacl`: the allow ACEs, inherited by files and folders (`OI CI`), CREATOR OWNER inherit-only,
the rights of the directory turned into file rights (`ldapmask2filemask`):

| Directory | Files |
|---|---|
| read property + list (`RP LC`) | read and execute (`0x1200A9`) |
| write property (`WP`) | write (`0x100116`) |
| create child (`CC`) | add file, add subfolder |
| delete child (`DC`) | delete child |
| standard rights | kept (`0x1F0000`) |

## The approval workflow

| Function | Does |
|---|---|
| `ConvertTo-PSGPOPendingDescriptor` | removes "Apply Group Policy" from every ACE (an ACE that gives other rights keeps them), gives the groups of creators *Edit settings* (`RP WP CC DC LC LO RC`, `0x200B7`) |
| `ConvertTo-PSGPOApprovedDescriptor` | sets the owner, removes the explicit ACEs of the creator and of the creators (the inherited ones follow their parent), and on the GPO: *Edit settings* for the creators (EditSettings), the security filtering chosen |
| `Get-PSGPOExplicitDescriptor` | leaves out the inherited ACEs before a write: the directory computes them again from the parent |

The owner matters: an owner can always read and change the DACL (implicit `READ_CONTROL`,
`WRITE_DAC`). The approval gives the GPO, the objects it holds and every file of its folder to the
owner of the approved GPOs.
