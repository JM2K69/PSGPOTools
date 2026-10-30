# Audit on the domain controllers

HGPM writes each change it makes to its [audit log](../features/audit-log.md), and to the log of
the system for a SIEM. A change made with another tool (GPMC, `samba-tool`, a script, an LDAP
client) is not in it: the [drift](../workflows/drift.md) shows what changed in a GPO, not who
changed it. The domain controllers know who: configure them to say it.

| What changes | Where | Windows | Samba |
|---|---|---|---|
| A GPO created, changed (its version, its extensions, its folder, its WMI filter, its permissions) or deleted | its container in `CN=Policies,CN=System` | events 5137, 5136, 5141 | `dsdb_json_audit` |
| A link, a block of the inheritance | `gPLink` and `gPOptions` of the domain, of an OU, of a site | event 5136 | `dsdb_json_audit` |
| The files of a GPO, their permissions | its folder in `SYSVOL\<domain>\Policies` | event 4663 | `vfs_full_audit` |

Send them to the SIEM with the events of HGPM: a change of a GPO without its event of HGPM was made
with another tool.

## Windows (Active Directory)

### 1. The audit policy of the domain controllers

In the **Default Domain Controllers Policy** (the editor of HGPM has it, [advanced audit
policy](../features/policy-editor.md)): **Computer Configuration > Policies > Windows Settings >
Security Settings > Advanced Audit Policy Configuration > Audit Policies**:

| Subcategory | Setting |
|---|---|
| DS Access > **Audit Directory Service Changes** | Success |
| Object Access > **Audit File System** | Success |

On a domain controller, once applied:

```powershell
auditpol /get /subcategory:"Directory Service Changes","File System"
```

### 2. What the directory audits: the SACLs

An event is written only for the objects whose SACL audits the change. As a Domain Admin, with
the ActiveDirectory module (RSAT), the GPOs and their links:

```powershell
Import-Module ActiveDirectory
$domain = (Get-ADDomain).DistinguishedName
$everyone = [System.Security.Principal.SecurityIdentifier]'S-1-1-0'
$all = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All

# The GPOs: created, changed, deleted, their permissions and owner.
$path = "AD:\CN=Policies,CN=System,$domain"
$acl = Get-Acl -Path $path -Audit
$rights = [System.DirectoryServices.ActiveDirectoryRights]'WriteProperty, CreateChild, DeleteChild, Delete, DeleteTree, WriteDacl, WriteOwner'
$acl.AddAuditRule([System.DirectoryServices.ActiveDirectoryAuditRule]::new($everyone, $rights, 'Success', $all))
Set-Acl -Path $path -AclObject $acl

# The links (gPLink) and the block of the inheritance (gPOptions) of the domain and of every OU.
$path = "AD:\$domain"
$acl = Get-Acl -Path $path -Audit
foreach ($attribute in 'f30e3bbe-9ff0-11d1-b603-0000f80367c1', 'f30e3bbf-9ff0-11d1-b603-0000f80367c1') {
    $acl.AddAuditRule([System.DirectoryServices.ActiveDirectoryAuditRule]::new($everyone, 'WriteProperty', 'Success', [guid]$attribute, $all))
}
Set-Acl -Path $path -AclObject $acl
```

The links of the sites are in the configuration of the forest: the same rule for `gPLink` on
`CN=Sites,CN=Configuration,<forest>`, as an Enterprise Admin.

### 3. What SYSVOL audits

The SACL of the `Policies` folder, on each domain controller (SYSVOL is local to each of them):

```powershell
$path = "$env:SystemRoot\SYSVOL\domain\Policies"
$acl = Get-Acl -Path $path -Audit
$rights = [System.Security.AccessControl.FileSystemRights]'CreateFiles, AppendData, WriteAttributes, WriteExtendedAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
$acl.AddAuditRule([System.Security.AccessControl.FileSystemAuditRule]::new('Everyone', $rights, 'ContainerInherit, ObjectInherit', 'None', 'Success'))
Set-Acl -Path $path -AclObject $acl
```

### The events

In the **Security** log of the domain controller where the change was made:

| Event | Says |
|---|---|
| 5137 | an object was created: a GPO (`groupPolicyContainer`) and its `User` and `Machine` containers |
| 5136 | an object was modified: the account, the object, the attribute (`versionNumber`, `gPLink`, `nTSecurityDescriptor`...) and its value added or deleted |
| 5141 | an object was deleted |
| 5139 | an object was moved |
| 4663 | a file or a folder of SYSVOL written, deleted, or its permissions changed (`WRITE_DAC`), by whom |

```powershell
Get-WinEvent -ComputerName dc1 -FilterHashtable @{ LogName = 'Security'; Id = 5136, 5137, 5141 } -MaxEvents 20 |
    Format-List TimeCreated, Id, Message
```

## Samba AD

Samba has no SACL: it logs what changes, for every object, as JSON, when the class
`dsdb_json_audit` is at level 5; and the files of a share with the module `vfs_full_audit`. Both
are set in `/etc/samba/smb.conf` of each domain controller, then Samba is restarted.

### 1. The changes of the directory

In `[global]`:

```ini
[global]
    log level = 0 dsdb_json_audit:5@/var/log/samba/dsdb_json_audit.log
```

| Part | Does |
|---|---|
| `log level = 0` | the level of the other classes, in `log file`: keep yours (`1`, `2`...) when the line already had one |
| `dsdb_json_audit:5` | each change of the database (add, modify, delete), as one line of JSON: who (`userSid`), from where (`remoteAddress`), what (`operation`, `dn`, `attributes` with their values) |
| `@/var/log/samba/dsdb_json_audit.log` | in a file of its own, not in `log.samba` |

```bash
sudo systemctl restart samba-ad-dc
```

`smbcontrol ... debug` at run time does not turn it on: the processes of LDAP read it when they
start. Other classes, on the same line: `dsdb_group_json_audit:5` (the members of the groups:
the security filtering groups), `auth_json_audit:3` (the logons).

A GPO unlinked from an OU (on one line, shortened here): the value of `gPLink` before
(`delete`) and after (`add`), as the console writes it in one request.

```json
{"timestamp": "2026-10-30T12:51:48.701369+0100", "type": "dsdbChange", "dsdbChange": {
  "status": "Success", "operation": "Modify", "remoteAddress": "ipv4:10.0.0.51:47044",
  "userSid": "S-1-5-21-99285962-3314789183-2679996994-500", "dn": "OU=Test,DC=hardenbox,DC=labo",
  "attributes": {"gPLink": {"actions": [
    {"action": "delete", "values": [{"value": "[LDAP://CN={5D5A49E5-...},CN=Policies,...;0][LDAP://CN={04CF011D-...},...;0]"}]},
    {"action": "add", "values": [{"value": "[LDAP://CN={04CF011D-...},CN=Policies,...;0]"}]}]}}}}
```

The file grows with every change of the domain (logons and computers too): `max log size` (in kB)
rotates it to `.old`, or a rule of `logrotate`; the SIEM reads it as JSON.

### 2. The files of SYSVOL

In `[sysvol]` (and `[netlogon]`), the module `full_audit` after the two modules SYSVOL needs:

```ini
[sysvol]
    vfs objects = dfs_samba4 acl_xattr full_audit
    full_audit:prefix = IP=%I|USER=%u|MACHINE=%m|VOLUME=%S
    full_audit:success = mkdirat renameat unlinkat pwrite pwrite_send fset_nt_acl
    full_audit:failure = none
    full_audit:facility = local7
    full_audit:priority = NOTICE
```

| Line | Does |
|---|---|
| `vfs objects = dfs_samba4 acl_xattr full_audit` | adds the audit; never remove `dfs_samba4` and `acl_xattr` (the ACLs of SYSVOL are in `acl_xattr`) |
| `full_audit:prefix` | the start of each line: the address, the account, the computer, the share |
| `full_audit:success` | the operations logged: a folder created (`mkdirat`), renamed (`renameat`, Samba creates a folder under a temporary name), a file or folder deleted (`unlinkat`), written (`pwrite`; `pwrite_send` for SMB2, as `GPT.INI`), its permissions (`fset_nt_acl`) |
| `full_audit:failure = none` | the operations refused are not logged |
| `full_audit:facility`, `full_audit:priority` | where syslog puts them: `journalctl -t smbd_audit` |

Without `pwrite_send`, `unlinkat` and `fset_nt_acl`, the writes of SMB2, the deletions and the
permissions are not logged: only the folders renamed are.

## Tested

On hardenbox.labo (Samba 4.22), the two settings above in `smb.conf`, Samba restarted, then a GPO
created with the console, linked to an OU, unlinked, a permission changed, and deleted:

| What | `dsdb_json_audit` | `full_audit` |
|---|---|---|
| The GPO created | `Add` of the GPO, of its `User` and `Machine` | `mkdirat`, `renameat` of its folders, `pwrite_send` of `GPT.INI`, `fset_nt_acl` |
| Linked, unlinked | `Modify` of the OU, twice | (nothing: the directory only) |
| A permission changed | `Modify` of the GPO | `fset_nt_acl` of its folder and its files |
| Deleted | `Delete` of `User`, `Machine`, then of the GPO | `unlinkat` of `GPT.INI`, of its folders, of the folder |
| Who | `userSid` of the account (Administrator, RID 500) | `USER=HARDENBOX\Administrator`, its address |

`smbcontrol samba debug` and `smbcontrol ldap_server debug` at run time: nothing logged. With
`full_audit:success = pwrite write renameat` only: the folders renamed only.

The part of Windows gives the settings and the events of Windows Server; it was not run on
powershell.labo.
