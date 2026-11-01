# Modeling, results and update

GPMC has three ways to know what applies where: **Group Policy Modeling**, which computes it from
the directory; **Group Policy Results**, which reads what a computer logged; **Group Policy
Update**, which has computers apply their GPOs now. HGPM has them as commands, on Windows and
Linux.

## Group Policy Modeling { #group-policy-modeling }

`Get-PSGPOModeling` gives the GPOs a computer and a user would apply, from the directory alone:
nothing runs on the computer.

- **The order of the links**, as Windows applies them: the site of the computer (`-Site`), the
  domain, the OUs above the account; the enforced links from the site down, the others from the
  OU up to an OU that blocks the inheritance. A GPO linked twice applies once.
- **The token**: the SID of the account and its groups, the nested ones included (`tokenGroups`),
  Everyone and Authenticated Users. In place of an account, the domain or an OU (a container, as
  GPMC allows it): the group of every computer or user of the domain, and the groups given with
  `-ComputerGroup` and `-UserGroup`. A directory in memory (`Import-PSGPODirectory`) has no
  accounts: containers only.
- **Loopback processing** from the computer GPOs applied (*Configure user Group Policy loopback
  processing mode*), or given with `-Loopback`: **Merge** adds the user GPOs of the computer after
  those of the user, **Replace** takes them alone.
- **The WMI filters** are not run: assumed true, but those given with `-FalseWmiFilter`.

Each GPO of each part is applied, with its precedence (1 wins), or denied, with its reason:

| Reason | Why |
|---|---|
| Disabled link | the link is not enabled |
| Disabled GPO | the GPO status disables that part |
| Denied (security) | a deny for one of the SIDs of the token |
| Not applied (security filtering) | no *Apply Group Policy* with *Read* for the token |
| Inaccessible (the computer cannot read it, MS16-072) | a user GPO the computer cannot read: Windows does not apply it, even to its users |
| WMI filter not found | its WMI filter is not in the domain anymore: the computers ignore the GPO |
| WMI filter false | its WMI filter is given false |
| Empty | no settings in that part: its version is 0, or no client-side extension declares it |
| Not found | the link names a GPO not in the domain (another domain of the forest) |

```powershell
$Modeling = Get-PSGPOModeling -Computer 'PC-LYON-042' -User 'CONTOSO\jdoe' -Site 'Lyon-Site'
$Modeling.ComputerGpos | Format-Table Precedence, Name, Link, Enforced, Reason
$Modeling.UserGpos | Where-Object Applied

# An OU in place of a computer, with the groups it would be in.
Get-PSGPOModeling -Computer 'OU=Kiosks,OU=Workstations,DC=contoso,DC=com' -ComputerGroup 'APPLY_C - Kiosks'
```

## Group Policy Results { #group-policy-results }

`Get-PSGPOResult` reads what a computer and a user applied the last time, as the computer logged
it: the GPOs of each part, applied with their precedence or denied with their reason, where they
are linked; with gpresult, the security groups of the computer and the user, their SOM and site,
the status of each client-side extension.

- **Windows**: `gpresult /x`, on this computer or another one (`-ComputerName`, its firewall
  letting RSoP through), for the user given or the one running it; the computer part needs an
  administrator.
- **Linux**, a member of a domain: `samba-gpupdate --rsop`, which reads the policy with the machine
  account: root only (`sudo pwsh`). It also gives the settings of each GPO (`Settings`).
- **`-Path`** reads a file made elsewhere: the XML of `gpresult /x`, or what
  `samba-gpupdate --rsop` printed. On Linux, the way to read it with the Kerberos ticket of a user
  (root has the machine account, not that ticket):

```powershell
Get-PSGPOResult | Select-Object -ExpandProperty ComputerGpos | Format-Table Precedence, Name, Link, Reason
Get-PSGPOResult -ComputerName PC-LYON-042 -User 'CONTOSO\jdoe'

# Linux: the result as root, read as the user.
#   sudo samba-gpupdate --rsop --target=Computer > /tmp/rsop-computer.txt
Get-PSGPOResult -Path /tmp/rsop-computer.txt -Scope Computer
```

## Group Policy Update { #group-policy-update }

`Invoke-PSGPOUpdate` has computers apply their GPOs now; `-Force` applies every setting again.

- **Windows**: `gpupdate` on this computer; on other computers (`-ComputerName`),
  `Invoke-GPUpdate` of RSAT when it is there, as GPMC does (a scheduled task on the computer, for
  it and for each user logged on), else `gpupdate` through PowerShell remoting.
- **Linux**: `samba-gpupdate`, root only; the user part for the user given (`-User`). `-WhatIf`
  needs no root.

```powershell
Invoke-PSGPOUpdate -Target Computer -Force
Invoke-PSGPOUpdate -ComputerName PC-LYON-041, PC-LYON-042
```

## Checked on both labs

On the Windows member of `powershell.labo` and on the Samba domain controller of `hardenbox.labo`,
the modeling of the computer and of the user gives the GPOs the computer applied, in the same
order; the policy update of the Windows member shows in its result read again.
