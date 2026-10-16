# Le labo

Les captures et les tests de cette documentation viennent de deux domaines.

## hardenbox.labo (Samba AD)

| | |
|---|---|
| Contrôleur de domaine | `dc.hardenbox.labo`, Debian 13, Samba 4.22 |
| OU | `Tier 1`, `Tier 2` (chacune avec son OU `Groups`), `Test`, `Groupes`, `Domain Controllers` |
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

Un labo qui montre tout demande :

1. Un domaine (Samba AD ou Active Directory) et un ordinateur avec la console (un membre, ou le
   contrôleur de domaine).
2. Deux OU et deux groupes pour les techniciens Tier 1 et Tier 2, chaque groupe autorisé à lier des
   GPO à son OU (Délégation de contrôle : « Gérer les liens de stratégie de groupe »).
3. Pour le [workflow d'approbation](../workflows/approval.md) : la configuration du domaine, et
   `Initialize-PSGPOWorkflow -Apply`.

Les tests d'intégration du module tournent sur un tel contrôleur de domaine : voir
[Tests](../technical/tests.md).
