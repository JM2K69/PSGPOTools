# Le labo

Les captures et les tests de cette documentation viennent de deux domaines.

## hardenbox.labo (Samba AD)

| | |
|---|---|
| Contrôleur de domaine | `dc.hardenbox.labo`, Debian 13, Samba 4.22 |
| OU | `Tier 1` (`Servers`, `Groups`), `Tier 2` (`Workstations`, `Users`, `Groups`), `Test`, `Groupes`, `Domain Controllers` |
| Groupes | `GPO-Tier1-Admins` (membre `tiers1`), `GPO-Tier2-Admins` (membre `tiers2`) |
| Délégation | chaque groupe lie des GPO à son OU (écriture de `gPLink` et `gPOptions`) |
| GPO | Default Domain Policy, Default Domain Controllers Policy, `T1 - Servers - Baseline`, `T2 - Workstations - Baseline`… |
| Workflow d'approbation | activé : approbateurs `Domain Admins`, créateurs `GPO-Tier1-Admins`, `GPO-Tier2-Admins` |

La console tourne sur le contrôleur de domaine lui-même, avec un ticket Kerberos d'`administrator`
(Tier 0) ou de `tiers1` (Tier 1) : `kinit` change le compte qu'utilise la console.

## powershell.labo (Active Directory)

| | |
|---|---|
| Contrôleur de domaine | `ADDS.powershell.labo`, Windows Server |
| Client | Windows 11 membre du domaine, outils RSAT de gestion des stratégies de groupe |

## Monter le vôtre

Un labo qui montre tout demande un domaine (Samba AD ou Active Directory), un ordinateur avec la
console (un membre, ou le contrôleur de domaine), et le tiering de hardenbox.labo : deux scripts le
créent dans n'importe quel domaine, dont ils lisent le nom distinctif (DN) sur le contrôleur de
domaine. Les deux peuvent être relancés (ce qui existe est gardé), et `-WhatIf` montre ce qu'ils
changeraient.

- **Windows** : LDAP avec l'identité de la session (System.DirectoryServices, intégré à Windows,
  sans RSAT), Active Directory ou Samba AD, dans une session d'un administrateur du domaine (ouverte
  avec son mot de passe : une session SSH par clé n'a pas de ticket Kerberos à présenter au
  contrôleur de domaine).
- **Linux** : `samba-tool`, avec un ticket Kerberos d'un administrateur du domaine
  (`kinit administrator`) ; aucun mot de passe n'est demandé.

!!! warning "Un domaine de test seulement"
    Les comptes `tiers1` et `tiers2` reçoivent le mot de passe du labo, `H@rdenB0x!` (`-Password` en
    donne un autre).

### 1. Les tiers, leurs groupes et leurs techniciens

`New-PSGPOTierLab.ps1` crée `OU=Tier 1` (`Servers`, `Groups`) et `OU=Tier 2`
(`Workstations`, `Users`, `Groups`), les groupes `GPO-Tier1-Admins` et `GPO-Tier2-Admins` dans l'OU
`Groups` de leur tier, et les comptes `tiers1` et `tiers2` dans `CN=Users`, chacun membre du groupe
de son tier.

=== "Windows"

    [Télécharger windows/New-PSGPOTierLab.ps1](../assets/scripts/windows/New-PSGPOTierLab.ps1){ download }

    ```powershell
    .\New-PSGPOTierLab.ps1           # le domaine de l'ordinateur
    .\New-PSGPOTierLab.ps1 -WhatIf
    ```

    ??? example "windows/New-PSGPOTierLab.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/windows/New-PSGPOTierLab.ps1"
        ```

=== "Linux"

    [Télécharger linux/New-PSGPOTierLab.ps1](../assets/scripts/linux/New-PSGPOTierLab.ps1){ download }

    ```powershell
    ./New-PSGPOTierLab.ps1 -Server dc.hardenbox.labo
    ./New-PSGPOTierLab.ps1 -Server dc.hardenbox.labo -WhatIf
    ```

    ??? example "linux/New-PSGPOTierLab.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/linux/New-PSGPOTierLab.ps1"
        ```

### 2. Leurs droits sur les GPO

`Grant-PSGPOTierDelegation.ps1` donne à chaque groupe :

- **Lier des GPO** à l'OU de son tier et aux OU en dessous, comme l'onglet Délégation de GPMC :
  lecture et écriture de `gPLink` et `gPOptions` ;
- **la création de GPO**, par le [workflow d'approbation](../workflows/approval.md) : une délégation
  fine, jamais Group Policy Creator Owners, dont les membres créent des GPO hors du workflow.
  `Initialize-PSGPOWorkflow -Apply` leur donne le droit de créer des objets `groupPolicyContainer`
  dans `CN=Policies,CN=System` et leur dossier dans le dossier `Policies` de SYSVOL ; leurs GPO
  attendent l'approbation d'un administrateur du domaine.

D'abord, activez le workflow du domaine avec les deux groupes comme créateurs : dans la console, en
administrateur du domaine, **Paramètres** : `Workflow.Enabled` = `True`, `Workflow.Creators` =
`GPO-Tier1-Admins, GPO-Tier2-Admins`, **Enregistrer** (pas à pas dans
[Workflow d'approbation](../workflows/approval.md#1-configurer-le-workflow-tier-0-une-fois)). Sans cela,
le script s'arrête avant de rien changer, et dit ce qu'il a lu.

![Workflow.Creators avec les groupes des scripts](../assets/screenshots/28-settings-workflow-creators.fr.png)

=== "Windows"

    [Télécharger windows/Grant-PSGPOTierDelegation.ps1](../assets/scripts/windows/Grant-PSGPOTierDelegation.ps1){ download }

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

    [Télécharger linux/Grant-PSGPOTierDelegation.ps1](../assets/scripts/linux/Grant-PSGPOTierDelegation.ps1){ download }

    ```powershell
    Import-Module HGPM
    ./Grant-PSGPOTierDelegation.ps1 -Server dc.hardenbox.labo -WhatIf
    ./Grant-PSGPOTierDelegation.ps1 -Server dc.hardenbox.labo
    ```

    ??? example "linux/Grant-PSGPOTierDelegation.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/linux/Grant-PSGPOTierDelegation.ps1"
        ```

### 3. La console en technicien

Connectez-vous en `tiers1` (Linux : `kinit tiers1`), puis `Show-GPOManagerAvalonia` : la console
montre les OU de Tier 1, et les GPO que `tiers1` crée attendent une approbation.

Les tests d'intégration du module tournent sur un tel contrôleur de domaine, ces scripts compris
(sur le domaine de la CI) : voir [Tests](../technical/tests.md).
