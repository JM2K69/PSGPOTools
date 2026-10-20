# The lab

The screenshots and the tests of this documentation come from two domains.

## hardenbox.labo (Samba AD)

| | |
|---|---|
| Domain controller | `dc.hardenbox.labo`, Debian 13, Samba 4.22 |
| OUs | `Tier 1` (`Servers`, `Groups`), `Tier 2` (`Workstations`, `Users`, `Groups`), `Test`, `Groupes`, `Domain Controllers` |
| Groups | `GPO-Tier1-Admins` (member `tiers1`), `GPO-Tier2-Admins` (member `tiers2`) |
| Delegation | each group links GPOs to its own OU (write `gPLink` and `gPOptions`) |
| GPOs | Default Domain Policy, Default Domain Controllers Policy, `T1 - Servers - Baseline`, `T2 - Workstations - Baseline`... |
| Approval workflow | enabled: approvers `Domain Admins`, creators `GPO-Tier1-Admins`, `GPO-Tier2-Admins` |

The console runs on the domain controller itself, with a Kerberos ticket of `administrator`
(Tier 0) or of `tiers1` (Tier 1): `kinit` changes the account the console uses.

## powershell.labo (Active Directory)

| | |
|---|---|
| Domain controller | `ADDS.powershell.labo`, Windows Server |
| Client | Windows 11 member of the domain, RSAT Group Policy Management tools |

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
- **the creation of GPOs**, by `-CreationRight`:
    - `Workflow` (by default, as in the lab): the [approval workflow](../workflows/approval.md).
      First, in the console, **Settings**, **Workflow**: enabled, with `GPO-Tier1-Admins, GPO-Tier2-Admins`
      as its creators; the script then runs `Initialize-PSGPOWorkflow -Apply`, which gives them the
      right to create GPOs in the directory and in SYSVOL. Their GPOs wait for the approval of a
      domain administrator.
    - `GroupPolicyCreatorOwners`: both groups in Group Policy Creator Owners, as GPMC delegates
      the creation of GPOs, without approval.

=== "Windows"

    [Download windows/Grant-PSGPOTierDelegation.ps1](../assets/scripts/windows/Grant-PSGPOTierDelegation.ps1){ download }

    ```powershell
    Import-Module PSGPOTools
    .\Grant-PSGPOTierDelegation.ps1
    .\Grant-PSGPOTierDelegation.ps1 -CreationRight GroupPolicyCreatorOwners
    ```

    ??? example "windows/Grant-PSGPOTierDelegation.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/windows/Grant-PSGPOTierDelegation.ps1"
        ```

=== "Linux"

    [Download linux/Grant-PSGPOTierDelegation.ps1](../assets/scripts/linux/Grant-PSGPOTierDelegation.ps1){ download }

    ```powershell
    Import-Module PSGPOTools
    ./Grant-PSGPOTierDelegation.ps1 -Server dc.hardenbox.labo
    ./Grant-PSGPOTierDelegation.ps1 -Server dc.hardenbox.labo -CreationRight GroupPolicyCreatorOwners
    ```

    ??? example "linux/Grant-PSGPOTierDelegation.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/linux/Grant-PSGPOTierDelegation.ps1"
        ```

### 3. The console as a technician

Log on as `tiers1` (Linux: `kinit tiers1`), then `Show-GPOManagerAvalonia`: the console shows
the OUs of Tier 1, and the GPOs `tiers1` creates wait for an approval.

The integration tests of the module run against such a domain controller, these scripts included
(on the domain of the CI): see [Tests](../technical/tests.md).
