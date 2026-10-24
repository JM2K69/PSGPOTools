# Stratégies de mot de passe (PSO)

![La tuile Paramètres de mot de passe](../assets/screenshots/58-tile-password-settings.fr.png){ align=right width="170" }

`Show-PSOManagerAvalonia` ouvre la deuxième console de HGPM : les **stratégies de mot de passe
affinées** du domaine (objets de paramètres de mot de passe, PSO), comme le *Centre
d'administration Active Directory* les gère, pour les **domaines Windows et Samba AD**, depuis
**Windows ou Linux**.

```powershell
# Le domaine de l'ordinateur (session Windows, ou ticket Kerberos sous Linux)
Show-PSOManagerAvalonia

# Linux, Samba AD, en français
kinit administrator@HARDENBOX.LABO
Show-PSOManagerAvalonia -Server dc.hardenbox.labo -Language fr-FR
```

Un PSO remplace, pour les utilisateurs auxquels il s'applique, la stratégie de mot de passe du
domaine (celle que pose la *Default Domain Policy*) : longueur minimale, historique, complexité,
anciennetés, verrouillage. C'est un objet `msDS-PasswordSettings` de
`CN=Password Settings Container,CN=System` du domaine ; Samba AD a le même schéma depuis la 4.9
(niveau fonctionnel 2008 ou plus), la console le lit et l'écrit donc en LDAP, de la même façon sur
les deux. Une utilisation pas à pas, sur les tiers du labo :
[stratégies de mot de passe des tiers](../workflows/password-policies.md).

## Paramètres de mot de passe

La vue d'ouverture : les PSO **par ordre de priorité** (la plus petite priorité d'abord), chacun
avec ses paramètres en bref, le nombre d'utilisateurs et de groupes auxquels il s'applique
directement, et un cadenas quand il est protégé contre la suppression accidentelle. La **stratégie
de mot de passe du domaine** s'affiche sous la liste : elle s'applique à tout compte qu'aucun PSO ne
concerne.

![La vue Paramètres de mot de passe](../assets/screenshots/29-pso-list.fr.png)

Le détail du PSO sélectionné : ses paramètres, sa date de modification, et les utilisateurs et
groupes auxquels il **s'applique directement** (`msDS-PSOAppliesTo`), avec le type et l'étendue de
chaque groupe.

| Bouton | Action |
|---|---|
| **Nouveau...** | crée un PSO dans sa fenêtre (grisé quand le compte ne peut pas créer de PSO) |
| **Propriétés...** (ou un double clic) | modifie le PSO dans sa fenêtre |
| **Supprimer** | supprime le PSO après confirmation ; un PSO protégé contre la suppression accidentelle est gardé |
| **Actualiser** (F5) | relit les PSO sur le contrôleur de domaine |

## La fenêtre d'un PSO

Les champs de *Créer des paramètres de mot de passe* du Centre d'administration :

![La fenêtre d'un PSO](../assets/screenshots/30-pso-editor.fr.png)

| Champ | Stocké dans | |
|---|---|---|
| Nom, Priorité | `cn`, `msDS-PasswordSettingsPrecedence` | entre plusieurs PSO, la plus petite priorité l'emporte |
| Appliquer la longueur minimale du mot de passe | `msDS-MinimumPasswordLength` | décoché : 0 |
| Appliquer l'historique des mots de passe | `msDS-PasswordHistoryLength` | décoché : 0 |
| Le mot de passe doit respecter des exigences de complexité | `msDS-PasswordComplexityEnabled` | |
| Enregistrer le mot de passe en utilisant un chiffrement réversible | `msDS-PasswordReversibleEncryptionEnabled` | à éviter |
| Protéger contre la suppression accidentelle | la DACL du PSO | Tout le monde se voit refuser *Supprimer* et *Supprimer la sous-arborescence* sur lui, *Supprimer tous les objets enfants* sur son conteneur |
| Appliquer l'ancienneté minimale / maximale | `msDS-MinimumPasswordAge`, `msDS-MaximumPasswordAge` | maximale décochée : le mot de passe n'expire jamais |
| Appliquer la stratégie de verrouillage de compte | `msDS-LockoutThreshold`, `msDS-LockoutObservationWindow`, `msDS-LockoutDuration` | *Jusqu'à ce qu'un administrateur déverrouille manuellement le compte* : pas de durée |
| Description | `description` | |
| S'applique directement à | `msDS-PSOAppliesTo` | utilisateurs et groupes, recherchés dans le domaine |

**OK** vérifie les paramètres comme les contrôleurs de domaine (une priorité de 1 ou plus, une
ancienneté minimale plus courte que la maximale, une réinitialisation du compteur des échecs qui ne
dépasse pas la durée de verrouillage...), puis écrit le PSO. Un paramètre n'est modifié que si le
domaine a toujours la valeur lue par la console : un PSO modifié entre-temps par une autre console
est refusé, **Actualiser** puis refaire la modification. Une durée affichée en jours ou en minutes
entiers garde sa valeur exacte quand elle n'est pas modifiée : ouvrir un PSO et cliquer sur OK ne
change rien.

## Paramètres de mot de passe résultants

Recherchez un utilisateur ou un groupe, sélectionnez-le : tous les PSO qui le concernent, par ordre
de priorité, comment chacun l'atteint (**directement**, ou **par** quels groupes, imbriqués
compris), celui qui **s'applique** et pourquoi les autres ne s'appliquent pas.

![La vue Paramètres de mot de passe résultants](../assets/screenshots/31-pso-resultant.fr.png)

Le PSO qui s'applique à un utilisateur :

1. Les PSO appliqués **directement** à l'utilisateur l'emportent sur ceux de ses groupes.
2. Sans eux, les PSO appliqués à ses **groupes**, imbriqués compris.
3. Entre plusieurs, la **plus petite priorité** l'emporte ; à priorité égale, le plus petit `objectGUID`.
4. Sans aucun PSO, la **stratégie de mot de passe du domaine** s'applique.

Les groupes qui transmettent un PSO à leurs membres diffèrent selon le contrôleur de domaine :

| Contrôleur de domaine | Groupes qui transmettent un PSO |
|---|---|
| Windows | les groupes de **sécurité globaux** seulement (un PSO appliqué à un groupe local de domaine ou universel ne s'applique à personne) |
| Samba AD | tous les groupes de **sécurité**, sauf les groupes intégrés |

!!! warning "Samba AD et Windows n'appliquent pas le même PSO"
    Un PSO appliqué à un groupe de sécurité **local de domaine** ou **universel** s'applique à ses
    membres sur un domaine **Samba AD**, et à **personne** sur un domaine **Windows**. Les mêmes
    groupes et les mêmes PSO peuvent alors donner une autre stratégie de mot de passe au même
    utilisateur, par exemple après une migration de Samba AD vers Windows, ou avec des contrôleurs
    de domaine Windows et Samba côte à côte.

    - Appliquez les PSO à des utilisateurs, ou à des **groupes de sécurité globaux** : les deux
      contrôleurs de domaine les transmettent.
    - Vérifiez le résultat dans **Paramètres de mot de passe résultants** : le PSO de l'encadré est
      celui qu'applique le contrôleur de domaine lu ; un PSO **Ignoré** atteint le compte par un
      groupe qui ne le transmet pas.

    Sur le domaine Windows `powershell.labo` du labo, un PSO de priorité 5 appliqué au groupe local
    de domaine `VPN Users` est ignoré pour `tiers1`, son membre : le PSO de son groupe global
    s'applique.

    ![Un PSO ignoré par un groupe local de domaine, sur un contrôleur de domaine Windows](../assets/screenshots/37-pso-ignored.fr.png)

L'état de chaque PSO le dit : **S'applique**, **Non appliqué** (un autre passe avant, ou un PSO
appliqué directement l'emporte), **Ignoré** (appliqué par un groupe qui ne transmet pas de PSO).
Pour un utilisateur, le contrôleur de domaine a le dernier mot : la console affiche le PSO qu'il
applique (`msDS-ResultantPSO`), et le signale s'il diffère de l'ordre de priorité des PSO que le
compte peut lire.

Pour un groupe, la vue donne le PSO que ses membres reçoivent par lui, quand aucun PSO plus proche
ne les concerne.

![Les PSO qu'un groupe transmet](../assets/screenshots/36-pso-resultant-group.fr.png)

## Droits

Par défaut, seuls les administrateurs du domaine lisent et modifient les PSO : un autre compte voit
un conteneur vide, et **Nouveau...** est grisé. Les modifications vont dans le journal d'audit de
HGPM (`Get-PSGPOAuditLog`) : `NewPasswordPolicy`, `SetPasswordPolicy` (ce qui a changé, les sujets
ajoutés et retirés), `RemovePasswordPolicy`.

## Les commandes

La même chose en ligne de commande :

| Commande | |
|---|---|
| [`Get-PSGPOFineGrainedPasswordPolicy`](../reference/commands/get-psgpofinegrainedpasswordpolicy.md) | les PSO, par ordre de priorité |
| [`Get-PSGPODefaultPasswordPolicy`](../reference/commands/get-psgpodefaultpasswordpolicy.md) | la stratégie de mot de passe du domaine |
| [`New-PSGPOFineGrainedPasswordPolicy`](../reference/commands/new-psgpofinegrainedpasswordpolicy.md) | crée un PSO, avec par défaut les paramètres du Centre d'administration |
| [`Set-PSGPOFineGrainedPasswordPolicy`](../reference/commands/set-psgpofinegrainedpasswordpolicy.md) | modifie, renomme, protège un PSO |
| [`Remove-PSGPOFineGrainedPasswordPolicy`](../reference/commands/remove-psgpofinegrainedpasswordpolicy.md) | supprime un PSO |
| [`Add-PSGPOFineGrainedPasswordPolicySubject`](../reference/commands/add-psgpofinegrainedpasswordpolicysubject.md) | applique un PSO à des utilisateurs et des groupes |
| [`Remove-PSGPOFineGrainedPasswordPolicySubject`](../reference/commands/remove-psgpofinegrainedpasswordpolicysubject.md) | cesse de l'appliquer |
| [`Get-PSGPOResultantPasswordPolicy`](../reference/commands/get-psgporesultantpasswordpolicy.md) | le PSO qui s'applique à un utilisateur, et pourquoi |

Une durée est un `TimeSpan` (`180.00:00:00` vaut 180 jours) ; un `MaxPasswordAge` à zéro signifie
que le mot de passe n'expire jamais, un `LockoutDuration` à zéro que le compte reste verrouillé
jusqu'à ce qu'un administrateur le déverrouille.
