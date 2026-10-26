# Le labo

Les captures et les tests de cette documentation viennent de deux domaines construits de la même
façon, l'un sous Linux avec Samba AD, l'autre sous Windows avec Active Directory : les mêmes tiers,
groupes, délégation, workflow d'approbation et partages centraux.

| | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| Contrôleur de domaine | `dc.hardenbox.labo`, Debian 13, Samba 4.22 | `ADDS.powershell.labo`, Windows Server |
| Console | sur le contrôleur de domaine lui-même, Linux, PowerShell 7 | `CLI`, Windows 11 membre du domaine, PowerShell 7, outils RSAT de gestion des stratégies de groupe |
| Compte de la console | un ticket Kerberos d'`administrator` (Tier 0) ou de `tiers1` (Tier 1) : `kinit` le change | la session d'`Administrator` (Tier 0), ou de `tiers1` |
| OU | `Tier 1` (`Servers`, `Groups`), `Tier 2` (`Workstations`, `Users`, `Groups`), `Test`, `Groupes`, `Domain Controllers` | `Tier 1` (`Servers`, `Groups`), `Tier 2` (`Workstations`, `Users`, `Groups`), `azertyuiop`, `Domain Controllers` |
| Groupes | `GPO-Tier1-Admins` (membre `tiers1`), `GPO-Tier2-Admins` (membre `tiers2`) | `GPO-Tier1-Admins` (membre `Tiers1`), `GPO-Tier2-Admins` (membre `Tiers2`) |
| Délégation | chaque groupe lie des GPO à son OU (écriture de `gPLink` et `gPOptions`) | la même |
| GPO | Default Domain Policy, Default Domain Controllers Policy, `T1 - Servers - Baseline`, `T2 - Workstations - Baseline`… | Default Domain Policy, Default Domain Controllers Policy, `TEST` |
| Workflow d'approbation | activé : approbateurs `Domain Admins`, créateurs `GPO-Tier1-Admins`, `GPO-Tier2-Admins` | le même |
| Journal d'audit central | `\\dc.hardenbox.labo\gpo-audit` (partage Samba du contrôleur de domaine) | `\\CLI.powershell.labo\gpo-audit` (`C:\Shares\gpo-audit`) |
| Sauvegardes centrales | `\\dc.hardenbox.labo\gpo-backups`, monté sur `/mnt/gpo-backups` | `\\CLI.powershell.labo\gpo-backups` (`C:\Shares\gpo-backups`) |
| Journal du système | journald (`journalctl -t hgpm`) | le journal d'événements Application, source HGPM |

=== "hardenbox.labo (Samba AD)"

    ![La console sur hardenbox.labo](../assets/screenshots/01-console-domain.fr.png)

    ![Le journal d'audit de hardenbox.labo](../assets/screenshots/63-audit-log.fr.png)

=== "powershell.labo (Active Directory)"

    ![La console sur powershell.labo](../assets/screenshots/65-console-active-directory.fr.png)

    ![Le journal d'audit de powershell.labo](../assets/screenshots/66-audit-log-active-directory.fr.png)

    ![Les événements de HGPM dans l'Observateur d'événements](../assets/screenshots/67-event-viewer.png)

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

Connectez-vous en `tiers1` ou `tiers2` (Linux : `kinit tiers1` ; Windows : une session du compte, ou
`runas /user:POWERSHELL\Tiers1`), puis `Show-GPOManagerAvalonia` : la console montre tout le
domaine, grisé sauf les OU de son tier, et les GPO qu'il crée attendent une approbation.
Paramètres est grisé, l'onglet Historique et les GPO supprimées n'y sont pas (les sauvegardes sont
pour le Tier 0), et le journal d'audit ne montre que les modifications de son tier : vide pour un
compte qui n'a encore rien modifié.

=== "hardenbox.labo (Samba AD)"

    **Tier 1** (`tiers1`)

    ![La console de tiers1](../assets/screenshots/14-tier1-view.fr.png)

    ![Une GPO de tiers1 : elle attend son approbation](../assets/screenshots/15-tier1-new-gpo.fr.png)

    ![Le journal d'audit de tiers1 : son tier seulement](../assets/screenshots/68-tier1-audit-log.fr.png)

    **Tier 2** (`tiers2`)

    ![La console de tiers2](../assets/screenshots/69-tier2-view.fr.png)

    ![Une GPO de tiers2 : elle attend son approbation](../assets/screenshots/70-tier2-new-gpo.fr.png)

    ![Le journal d'audit de tiers2 : son tier seulement](../assets/screenshots/71-tier2-audit-log.fr.png)

=== "powershell.labo (Active Directory)"

    **Tier 1** (`Tiers1`)

    ![La console de Tiers1](../assets/screenshots/72-tier1-view-active-directory.fr.png)

    ![Une GPO de Tiers1 : elle attend son approbation](../assets/screenshots/73-tier1-new-gpo-active-directory.fr.png)

    ![Le journal d'audit de Tiers1 : son tier seulement](../assets/screenshots/74-tier1-audit-log-active-directory.fr.png)

    **Tier 2** (`Tiers2`)

    ![La console de Tiers2](../assets/screenshots/75-tier2-view-active-directory.fr.png)

    ![Une GPO de Tiers2 : elle attend son approbation](../assets/screenshots/76-tier2-new-gpo-active-directory.fr.png)

    ![Le journal d'audit de Tiers2 : son tier seulement](../assets/screenshots/77-tier2-audit-log-active-directory.fr.png)


Les tests d'intégration du module tournent sur un tel contrôleur de domaine, ces scripts compris
(sur le domaine de la CI) : voir [Tests](../technical/tests.md).
