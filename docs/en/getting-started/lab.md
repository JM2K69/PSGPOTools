# The lab

The screenshots and the tests of this documentation come from two domains.

## hardenbox.labo (Samba AD)

| | |
|---|---|
| Domain controller | `dc.hardenbox.labo`, Debian 13, Samba 4.22 |
| OUs | `Tier 1`, `Tier 2` (each with its `Groups` OU), `Test`, `Groupes`, `Domain Controllers` |
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

A lab that shows everything needs:

1. A domain (Samba AD or Active Directory) and a computer with the console (a member, or the
   domain controller).
2. Two OUs and two groups for the Tier 1 and Tier 2 technicians, each group allowed to link GPOs
   to its OU (Delegation of control: "Manage Group Policy links").
3. For the [approval workflow](../workflows/approval.md): the configuration of the domain, and
   `Initialize-PSGPOWorkflow -Apply`.

The integration tests of the module run against such a domain controller: see
[Tests](../technical/tests.md).
