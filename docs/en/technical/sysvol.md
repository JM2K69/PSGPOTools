# SYSVOL

The files of a GPO are in its SYSVOL folder, `gPCFileSysPath` (`\\domain\SysVol\domain\Policies\{GUID}`),
read and written **on the domain controller the directory was read from**: Samba does not
replicate SYSVOL between domain controllers.

## Files

| | Windows | Linux |
|---|---|---|
| Read a file | `\\<dc>\<share>\<path>` | `smbclient //<dc>/<share> --use-kerberos=required -c 'get ...'` |
| Read a folder (backups) | `Get-ChildItem -Recurse` on the UNC path | `smbclient ... 'recurse ON; mget *'` into a temporary folder |
| Write a file | `[IO.File]::WriteAllBytes` | `smbclient ... 'mkdir ...; put ...'`, one folder level at a time |

`smbclient` never asks for a password: no standard input, Kerberos only (not `--no-pass`, with
which it would not use the ticket). Its `NT_STATUS_*` errors are reported as they are; a missing
file is not an error where it may be missing.

## Saving a setting

Writing `Registry.pol`, `GptTmpl.inf` or a preference file also:

1. increases the version of the scope in `GPT.INI` (`Version=`, user version in the high word,
   computer version in the low word);
2. increases `versionNumber` in the directory, from the value the directory has, refused if it
   changed meanwhile;
3. declares the client-side extension and its tool in `gPCMachineExtensionNames` /
   `gPCUserExtensionNames` (sorted GUID pairs, as GPMC writes them).

Without 1 and 2 the computers would not apply the change; without 3 they would ignore the file.

## Permissions

The ACL of a GPO folder is derived from the DACL of its container, as Samba (`dsacl2fsacl`) and
GPMC do: the allow ACEs, inherited by the files and folders, the rights of the directory turned
into file rights.

| | Windows | Linux |
|---|---|---|
| Read a descriptor | `GetAccessControl(...).GetSecurityDescriptorBinaryForm()` | Python: `libsmb.Conn.get_acl` (owner, group, DACL) |
| Write it | `SetSecurityDescriptorBinaryForm` + `SetAccessControl` | Python: `libsmb.Conn.set_acl` with its `SECINFO_*` flags |
| What a folder holds | Windows propagates the ACL of the folder | the console gives each file and folder the ACL of the folder, as `samba-tool ntacl sysvolreset` |

The ACEs of extended rights ("Apply Group Policy") mean nothing to a file: Windows leaves them
out, as GPMC; Samba keeps them as `samba-tool` writes them. `smbcacls` is not used: it sorts the
ACEs and removes duplicates, and `samba-tool gpo aclcheck` compares the ACLs as written.

!!! warning "Samba checks two ACLs"
    With `vfs objects = acl_xattr`, Samba checks the NT ACL of a file (an extended attribute)
    **and** its POSIX ACL, and only changes the POSIX ACL of a file for its owner. An
    administrator changing the ACL of a file it does not own changes its NT ACL only. The
    [approval workflow](../workflows/approval.md) sets the rights of the creators while they own
    the files, so that both ACLs give them.

## The configuration of the domain

`SYSVOL\<domain>\PSGPOTools\Configuration.psd1`, read and written the same way, by its path from
the root of the share ([configuration](../features/configuration.md)).
