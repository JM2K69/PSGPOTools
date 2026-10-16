# Policy editor

**Edit** on a GPO opens it in the policy editor. The banner says which GPO is edited; each setting
is read from the GPO, and **Apply** saves it there.

![The policy editor](../assets/screenshots/10-editor-policy.png)

The tree has the two scopes of a GPO, **Machine** (Computer Configuration) and **User** (User
Configuration), each with:

- **Windows Settings > Security Settings** (computer): the security settings of `GptTmpl.inf`;
- **the administrative templates** of the ADMX files loaded, by category;
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

## Search and copy

The search box finds the policies whose name holds the text typed (with **Configured settings
only**, among those the GPO configures). The context menu of a policy copies its name, its
registry path, or the `Get-ItemProperty` command that reads its value on a computer.
