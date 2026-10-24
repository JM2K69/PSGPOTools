# Policy Analyzer

The [Security Compliance Toolkit](https://www.microsoft.com/download/details.aspx?id=55319) of
Microsoft comes with Policy Analyzer: it compares sets of GPOs setting by setting, and shows the
settings a set configures twice or with different values. HGPM does the same, on Windows and on
Linux, with the same files: the `.PolicyRules` files of the security baselines of Microsoft, and
those Policy Analyzer or `GPO2PolicyRules.exe` made, are read as they are, and the files HGPM
writes open in Policy Analyzer.

## Rule sets

A rule set is the settings of one or more GPOs, as one unit: the registry settings of their
`Registry.pol` files (computer and user), their security template (`GptTmpl.inf`: account
policies, user rights, security options, services, restricted groups...), their advanced audit
policy (`audit.csv`) and their client-side extensions. Group Policy Preferences and scripts are
not part of it, as in Policy Analyzer.

| Rule set from | Command |
|---|---|
| `.PolicyRules` files, or all those of a folder (`Documents\PolicyAnalyzer` for Policy Analyzer) | `Get-PSGPOPolicyRuleSet -Path` |
| GPOs of the domain, as they are now | `Get-PSGPOPolicyRuleSet -Name` |
| Backups of HGPM | `Get-PSGPOBackup ... \| Get-PSGPOPolicyRuleSet` |
| Backups of GPMC: the `GPOs` folder of a security baseline | `Get-PSGPOPolicyRuleSet -GpmcBackupPath` |

`Export-PSGPOPolicyRuleSet` saves sets as a `.PolicyRules` file, as `GPO2PolicyRules.exe` writes
it: Policy Analyzer opens it, and `LGPO.exe /p` applies it to the local policy of a computer.
Several sets are merged in one file, as `Merge-PolicyRules.ps1` does.

```powershell
# The GPOs of the domain that harden the workstations, saved for Policy Analyzer
Get-PSGPOPolicyRuleSet -Name 'Workstations - *' -SetName 'Workstations' |
    Export-PSGPOPolicyRuleSet -Path "$HOME\Documents\PolicyAnalyzer\Workstations.PolicyRules"

# The baseline of Microsoft, from its GPO backups (what its .PolicyRules file holds)
Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows 11 v25H2 Security Baseline\GPOs'
```

## Comparing rule sets

`Compare-PSGPOPolicyRuleSet` gives a row per setting one of the sets configures, and a column per
set with its value:

| Cell | Meaning | In Excel |
|---|---|---|
| a value | the set configures the setting, once | white, yellow when another set has another value |
| empty | the set does not configure the setting | grey |
| a value, set more than once | two GPOs of the set give the setting the same value | light grey |
| `***CONFLICT***` | two GPOs of the set give the setting different values | yellow |
| `[[[delete]]]` | the GPO deletes the registry value | |
| `[[[Delete all values]]]` | the GPO deletes all the values of the key (before writing a list) | |

A row is a **conflict** when two sets, or two GPOs of a set, give the setting different values; a
**difference** when it is a conflict or a set does not configure it (`-ConflictOnly`,
`-DifferenceOnly`: "Show only Conflicts" and "Show only Differences" of Policy Analyzer). As in
Policy Analyzer:

- lists whose order does not matter are compared in any order: the accounts of a user right or of
  a restricted group, the strings of a `REG_MULTI_SZ`;
- a `REG_DWORD` 5 is not a `REG_SZ` 5: the cells then show the type of each value;
- the precedence of the GPOs of a set is not taken into account: a set shows that its GPOs
  disagree, not which one wins.

Each setting is shown as GPMC shows it: the registry values as the policy and option of the
administrative templates loaded with `Initialize-PSGPOAdmx` (otherwise, and for the values no ADMX
explains, as *Extra Registry Settings*), the security settings and the audit subcategories by
their names, the accounts by name rather than SID. The row also keeps the setting as Policy
Analyzer lists it (`PolicyType`: HKLM, HKCU, Security Template, Audit Policy; `Group`: the key or
the section; `Setting`), its explanation and, in `Cells`, the value each GPO gives it.

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions
$baseline = Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules
$domain = Get-PSGPOPolicyRuleSet -Name 'Workstations - *' -SetName 'Domain'
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain -DifferenceOnly |
    Format-Table Scope, Name, Option, MSFT-Win11-v25H2, Domain
```

One set alone shows its own conflicts and duplicates: the GPOs applied together that set the same
setting.

## Excel workbook

`Export-PSGPOPolicyRuleComparison` saves a comparison as an Excel workbook, written by HGPM
(neither Excel nor any module is needed, on any platform): a sheet *Comparison* with the colours
above, the header frozen and filters on every column, and a sheet *GPOs* with the GPOs of each set.
With `-All`, as "Export all data to Excel", it also has the value of each GPO, the explanation and
the reference of each setting.

```powershell
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domain |
    Export-PSGPOPolicyRuleComparison -Path ./Baseline-vs-domain.xlsx -All
```
