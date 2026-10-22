# Policy editor

**Edit** on a GPO opens it in the policy editor. The banner says which GPO is edited; each setting
is read from the GPO, and **Apply** saves it there.

![The policy editor](../assets/screenshots/10-editor-policy.png)

The tree is that of the Group Policy editor: **Computer Configuration** and **User
Configuration**, each with:

- **Policies**:
    - **Windows Settings > Security Settings** (computer): the security settings of `GptTmpl.inf`;
    - **Administrative Templates**: the policies of the ADMX files loaded, by category;
- **Preferences**: the [Group Policy Preferences](preferences.md).

**Configured settings only** keeps only what the GPO configures: the quickest way to read a GPO.

## Administrative templates

A policy has three states, as in the Group Policy editor of Windows: **Not configured**,
**Enabled**, **Disabled**. Its options come from its ADMX presentation, in the order of the ADML:

| ADMX element | Form |
|---|---|
| `boolean` | check box |
| `enum` | drop-down list (the ADML default when nothing is chosen) |
| `decimal`, `longDecimal` | number, with its bounds |
| `text` | text, required or not, with its maximum length |
| `multiText` | several lines (REG_MULTI_SZ) |
| `list` | name/value list, with `valuePrefix`, `additive` and `explicitValue` |

The **Registry Preview** shows what Apply writes: the key, the value, its type and its data. The
**Details** tab shows the explanation of the policy, its supported platforms and its ADMX file.

**Apply** writes `Machine\Registry.pol` or `User\Registry.pol` in SYSVOL, then:

- increases the version of the GPO for that scope, in `GPT.INI` and in the `versionNumber` of its
  container, so that the computers apply it again;
- declares the client-side extension of the administrative templates (and its tool) in
  `gPCMachineExtensionNames` / `gPCUserExtensionNames`, without which the computers would ignore
  the file.

The values no policy of the loaded ADMX explains are kept, and shown as **Extra Registry
Settings** in the Settings tab.

!!! warning "A GPO changed since the console read it"
    Apply writes the whole file, from the copy read with the GPO. If the version of the GPO in the
    domain is no longer the one the console read (another console, GPMC, a script changed it),
    nothing is written: the other changes would be lost without a word. Refresh (F5) to read the
    GPO as it is, then make the change again. GPMC overwrites the file in that case.

## Security settings

![The security settings](../assets/screenshots/12-editor-security.png)

189 settings of `Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf`, as the Windows editor groups
them:

| Group | Section of GptTmpl.inf | Settings |
|---|---|---|
| Account Policies > Password Policy, Account Lockout Policy | `[System Access]` | 15 |
| Account Policies > Kerberos Policy | `[Kerberos Policy]` | 5 |
| Local Policies > Audit Policy | `[Event Audit]` | 9 |
| Local Policies > User Rights Assignment | `[Privilege Rights]` | 45 |
| Local Policies > Security Options | `[Registry Values]` | 103 |
| Event Log | `[Application Log]`, `[Security Log]`, `[System Log]` | 12 |

Each has its kind (number with its bounds and unit, choice, text, accounts for the user rights),
and a link to its Microsoft documentation. Apply writes `GptTmpl.inf` (UTF-16, as Windows writes
it), increases the computer version and declares the security extension.

### Restricted groups

**Security Settings > Restricted Groups** lists the groups of `[Group Membership]` in
`GptTmpl.inf`. **Add group** gives the group (`DOMAIN\name`, or a SID such as `*S-1-5-32-544` for
the local Administrators), then:

- **Members of this group**: the computers give the group these members only, and remove the
  others; an empty list removes every member. Unchecked, its members do not change (no
  `__Members` key);
- **This group is a member of**: the groups the computers add it to.

**Edit** and **Delete** change or remove a group; a deleted group keeps the members it has. The
Settings tab lists them (Members, Member of). Checked on a Windows member: the local Remote Desktop
Users received exactly the members defined.

### Advanced audit policy

**Security Settings > Advanced Audit Policy Configuration > Audit Policies** has the 60
subcategories of Windows (as `auditpol /list /subcategory:*` gives them), in their 9 categories
(Account Logon, Account Management, Detailed Tracking, DS Access, Logon/Logoff, Object Access,
Policy Change, Privilege Use, System). Each one is not defined, or audits its successes, its
failures, both, or nothing (No Auditing). Apply writes `Machine\Microsoft\Windows NT\Audit\audit.csv`
as the Group Policy editor does, increases the computer version and declares the extension of
the advanced audit policy (Audit Policy Configuration): Windows applies it at the next refresh
(checked with `auditpol /get` on a Windows member). The lines of `audit.csv` the console does not
edit (audit options, global object access auditing) are kept as they are.

Do not mix it with **Local Policies > Audit Policy** in the same domain: as Microsoft documents
it, a computer then applies one or the other.

## Search and copy

The search box finds the policies whose name holds the text typed (with **Configured settings
only**, among those the GPO configures). The context menu of a policy copies its name, its
registry path, or the `Get-ItemProperty` command that reads its value on a computer.
