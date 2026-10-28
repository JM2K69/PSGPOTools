# The lab

The screenshots and the tests of this documentation come from two domains built the same way, one
on Linux with Samba AD, one on Windows with Active Directory: the same tiers, groups, delegation,
approval workflow and central shares.

| | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| Domain controller | `dc.hardenbox.labo`, Debian 13, Samba 4.22 | `ADDS.powershell.labo`, Windows Server |
| Console | on the domain controller itself, Linux, PowerShell 7 | `CLI`, Windows 11 member of the domain, PowerShell 7, RSAT Group Policy Management tools |
| Account of the console | a Kerberos ticket of `administrator` (Tier 0) or of `tiers1` (Tier 1): `kinit` changes it | the session of `Administrator` (Tier 0), or of `tiers1` |
| OUs | `Tier 1` (`Servers`, `Groups`), `Tier 2` (`Workstations`, `Users`, `Groups`), `Test`, `Groupes`, `Domain Controllers` | `Tier 1` (`Servers`, `Groups`), `Tier 2` (`Workstations`, `Users`, `Groups`), `azertyuiop`, `Domain Controllers` |
| Groups | `GPO-Tier1-Admins` (member `tiers1`), `GPO-Tier2-Admins` (member `tiers2`) | `GPO-Tier1-Admins` (member `Tiers1`), `GPO-Tier2-Admins` (member `Tiers2`) |
| Delegation | each group links GPOs to its own OU (write `gPLink` and `gPOptions`) | the same |
| GPOs | Default Domain Policy, Default Domain Controllers Policy, `T1 - Servers - Baseline`, `T2 - Workstations - Baseline`... | Default Domain Policy, Default Domain Controllers Policy, `TEST` |
| Approval workflow | enabled: approvers `Domain Admins`, creators `GPO-Tier1-Admins`, `GPO-Tier2-Admins` | the same |
| Central audit log | `\\dc.hardenbox.labo\gpo-audit` (Samba share on the domain controller) | `\\CLI.powershell.labo\gpo-audit` (`C:\Shares\gpo-audit`) |
| Central backups | `\\dc.hardenbox.labo\gpo-backups`, mounted on `/mnt/gpo-backups` | `\\CLI.powershell.labo\gpo-backups` (`C:\Shares\gpo-backups`) |
| Log of the system | journald (`journalctl -t hgpm`) | the event log Application, source HGPM |

=== "hardenbox.labo (Samba AD)"

    ![The console on hardenbox.labo](../assets/screenshots/01-console-domain.png)

    ![The audit log of hardenbox.labo](../assets/screenshots/63-audit-log.png)

=== "powershell.labo (Active Directory)"

    ![The console on powershell.labo](../assets/screenshots/65-console-active-directory.png)

    ![The audit log of powershell.labo](../assets/screenshots/66-audit-log-active-directory.png)

    ![The events of HGPM in the Event Viewer](../assets/screenshots/67-event-viewer.png)

## Make your own

A lab that shows everything needs a domain (Samba AD or Active Directory), a computer with the
console (a member, or the domain controller), and the tiering of hardenbox.labo: two scripts
create it in any domain, whose distinguished name they read from the domain controller. Both can
run again (what is there is kept), and `-WhatIf` shows what they would change.

- **Windows**: LDAP with the identity of the session (System.DirectoryServices, part of Windows,
  no RSAT), Active Directory or Samba AD, in a session of a domain administrator (a logon with its
  password: a key-based SSH session has no Kerberos ticket to give the domain controller).
- **Linux**: `samba-tool`, with a Kerberos ticket of a domain administrator
  (`kinit administrator`); no password is asked.

!!! warning "A test domain only"
    The accounts `tiers1` and `tiers2` get the password of the lab, `H@rdenB0x!` (`-Password` gives
    another one).

### 1. The tiers, their groups and their technicians

`New-PSGPOTierLab.ps1` creates `OU=Tier 1` (`Servers`, `Groups`) and `OU=Tier 2`
(`Workstations`, `Users`, `Groups`), the groups `GPO-Tier1-Admins` and `GPO-Tier2-Admins` in the
`Groups` OU of their tier, and the accounts `tiers1` and `tiers2` in `CN=Users`, each a member of
the group of its tier.

=== "Windows"

    [Download windows/New-PSGPOTierLab.ps1](../assets/scripts/windows/New-PSGPOTierLab.ps1){ download }

    ```powershell
    .\New-PSGPOTierLab.ps1           # the domain of the computer
    .\New-PSGPOTierLab.ps1 -WhatIf
    ```

    ??? example "windows/New-PSGPOTierLab.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/windows/New-PSGPOTierLab.ps1"
        ```

=== "Linux"

    [Download linux/New-PSGPOTierLab.ps1](../assets/scripts/linux/New-PSGPOTierLab.ps1){ download }

    ```powershell
    ./New-PSGPOTierLab.ps1 -Server dc.hardenbox.labo
    ./New-PSGPOTierLab.ps1 -Server dc.hardenbox.labo -WhatIf
    ```

    ??? example "linux/New-PSGPOTierLab.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/linux/New-PSGPOTierLab.ps1"
        ```

### 2. Their rights on GPOs

`Grant-PSGPOTierDelegation.ps1` gives each group:

- **Link GPOs** to the OU of its tier and the OUs below it, as the Delegation tab of GPMC: read
  and write of `gPLink` and `gPOptions`;
- **the creation of GPOs**, through the [approval workflow](../workflows/approval.md): a fine
  delegation, never Group Policy Creator Owners, whose members create GPOs outside the workflow.
  `Initialize-PSGPOWorkflow -Apply` gives them the right to create `groupPolicyContainer` objects
  in `CN=Policies,CN=System` and their folder in the `Policies` folder of SYSVOL; their GPOs wait
  for the approval of a domain administrator.

First, enable the workflow of the domain with both groups as its creators: in the console, as a
domain administrator, **Settings**: `Workflow.Enabled` = `True`, `Workflow.Creators` =
`GPO-Tier1-Admins, GPO-Tier2-Admins`, **Save** (step by step in
[Approval workflow](../workflows/approval.md#1-configure-the-workflow-tier-0-once)). Without it,
the script stops before changing anything, and says what it read.

The central store of the domain must exist too (`Install-PSGPOAdmx -CentralStore`, or a copy of a
`PolicyDefinitions` folder): without it, the creators get no right, as one of them could create it
and own it ([hardening](../technical/hardening.md#posture)).

![Workflow.Creators with the groups of the scripts](../assets/screenshots/28-settings-workflow-creators.png)

=== "Windows"

    [Download windows/Grant-PSGPOTierDelegation.ps1](../assets/scripts/windows/Grant-PSGPOTierDelegation.ps1){ download }

    ```powershell
    Import-Module HGPM
    .\Grant-PSGPOTierDelegation.ps1 -WhatIf
    .\Grant-PSGPOTierDelegation.ps1
    ```

    ??? example "windows/Grant-PSGPOTierDelegation.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/windows/Grant-PSGPOTierDelegation.ps1"
        ```

=== "Linux"

    [Download linux/Grant-PSGPOTierDelegation.ps1](../assets/scripts/linux/Grant-PSGPOTierDelegation.ps1){ download }

    ```powershell
    Import-Module HGPM
    ./Grant-PSGPOTierDelegation.ps1 -Server dc.hardenbox.labo -WhatIf
    ./Grant-PSGPOTierDelegation.ps1 -Server dc.hardenbox.labo
    ```

    ??? example "linux/Grant-PSGPOTierDelegation.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/linux/Grant-PSGPOTierDelegation.ps1"
        ```

### 3. The console as a technician

Log on as `tiers1` or `tiers2` (Linux: `kinit tiers1`; Windows: a session of the account, or
`runas /user:POWERSHELL\Tiers1`), then `Show-GPOManagerAvalonia`: the console shows the whole
domain, greyed but the OUs of its tier, and the GPOs it creates wait for an approval. Settings is
greyed, the History tab and the deleted GPOs are not there (the backups are for Tier 0), and the
audit log shows the changes of its tier only: empty for an account that changed nothing yet.

!!! tip "Only **Link an Existing GPO...** in the menu of its OU"
    The technician does not create GPOs: the rights of the workflow are missing (the script ran
    before `Workflow.Creators` was set, or with `-WhatIf`). As a domain administrator,
    `Initialize-PSGPOWorkflow` says what is missing (`Missing`), `Initialize-PSGPOWorkflow -Apply`
    adds it; the technician opens its console again.

=== "hardenbox.labo (Samba AD)"

    **Tier 1** (`tiers1`)

    ![The console of tiers1](../assets/screenshots/14-tier1-view.png)

    ![A GPO of tiers1: it waits for its approval](../assets/screenshots/15-tier1-new-gpo.png)

    ![The audit log of tiers1: its tier only](../assets/screenshots/68-tier1-audit-log.png)

    **Tier 2** (`tiers2`)

    ![The console of tiers2](../assets/screenshots/69-tier2-view.png)

    ![A GPO of tiers2: it waits for its approval](../assets/screenshots/70-tier2-new-gpo.png)

    ![The audit log of tiers2: its tier only](../assets/screenshots/71-tier2-audit-log.png)

=== "powershell.labo (Active Directory)"

    **Tier 1** (`Tiers1`)

    ![The console of Tiers1](../assets/screenshots/72-tier1-view-active-directory.png)

    ![A GPO of Tiers1: it waits for its approval](../assets/screenshots/73-tier1-new-gpo-active-directory.png)

    ![The audit log of Tiers1: its tier only](../assets/screenshots/74-tier1-audit-log-active-directory.png)

    **Tier 2** (`Tiers2`)

    ![The console of Tiers2](../assets/screenshots/75-tier2-view-active-directory.png)

    ![A GPO of Tiers2: it waits for its approval](../assets/screenshots/76-tier2-new-gpo-active-directory.png)

    ![The audit log of Tiers2: its tier only](../assets/screenshots/77-tier2-audit-log-active-directory.png)


The integration tests of the module run against such a domain controller, these scripts included
(on the domain of the CI): see [Tests](../technical/tests.md).
