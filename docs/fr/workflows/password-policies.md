# Stratégies de mot de passe des tiers

Objectif : les administrateurs des tiers ont des mots de passe plus robustes que les autres
utilisateurs, grâce aux stratégies de mot de passe affinées (PSO), et vous vérifiez celle qui
s'applique à chaque compte. Tel que dans le [labo](../getting-started/lab.md) : les groupes
`GPO-Tier1-Admins` (utilisateur `tiers1`) et `GPO-Tier2-Admins` (utilisateur `tiers2`) de ses
scripts, sur le domaine Samba AD `hardenbox.labo`.

| PSO | Priorité | S'applique à | Paramètres |
|---|---|---|---|
| PSO - Tier 1 Admins | 10 | `GPO-Tier1-Admins` | 16 caractères, expire après 180 jours, verrouillé 30 minutes après 10 tentatives |
| PSO - Tier 2 Admins | 20 | `GPO-Tier2-Admins` | 14 caractères, expire après 90 jours, verrouillé jusqu'au déverrouillage après 10 tentatives |
| PSO - Domain Users | 50 | `Domain Users` | 12 caractères, historique 12 |

`tiers1` est dans `GPO-Tier1-Admins` et dans `Domain Users` (son groupe principal) : deux PSO le
concernent, celui de priorité 10 s'applique.

```mermaid
flowchart LR
    open[Ouvrir la console] --> new[Nouveau PSO]
    new --> apply[S'applique directement à]
    apply --> list[Ordre de priorité]
    list --> resultant[Paramètres résultants d'un compte]
    resultant --> check{Le PSO attendu ?}
    check -- non --> list
```

## 1. Ouvrir la console

En administrateur du domaine (par défaut, eux seuls lisent et modifient les PSO) :

```powershell
kinit administrator@HARDENBOX.LABO     # Linux ; Windows : la session de l'administrateur
Show-PSOManagerAvalonia -Server dc.hardenbox.labo -Language fr-FR
```

Le domaine n'a encore aucun PSO : chaque utilisateur reçoit la **stratégie de mot de passe par
défaut du domaine**, affichée sous la liste.

![La console avant tout PSO](../assets/screenshots/32-pso-empty.fr.png)

## 2. Créer le PSO du Tier 1

**Nouveau...** ouvre la fenêtre d'un nouveau PSO, avec les paramètres du Centre d'administration
(7 caractères, 24 mots de passe mémorisés, complexité, ancienneté minimale 1 jour et maximale
42 jours, protégé contre la suppression accidentelle) :

1. **Nom** `PSO - Tier 1 Admins`, **Priorité** `10`.
2. **Longueur minimale du mot de passe** `16`.
3. **L'utilisateur doit changer le mot de passe après (jours)** `180`.
4. Cochez **Appliquer la stratégie de verrouillage de compte** : `10` échecs, compteur réinitialisé
   après `30` minutes, verrouillé `30` minutes.
5. **Description** `Administrators of the servers (Tier 1)`.

![Un nouveau PSO](../assets/screenshots/33-pso-new.fr.png)

Sous **S'applique directement à**, recherchez `GPO-Tier`, sélectionnez `GPO-Tier1-Admins`,
**Ajouter** : le PSO s'applique aux membres du groupe. La fenêtre rappelle quels groupes
transmettent un PSO : avec Samba AD, tous les groupes de sécurité sauf les groupes intégrés ; avec
Windows, les groupes de sécurité globaux seulement.

![S'applique directement à](../assets/screenshots/34-pso-applies-to.fr.png)

**OK** vérifie les paramètres, crée le PSO et le sélectionne dans la liste.

## 3. Les autres PSO, en ligne de commande

La même chose, avec les commandes du module :

```powershell
$Server = 'dc.hardenbox.labo'
New-PSGPOFineGrainedPasswordPolicy -Server $Server -Name 'PSO - Tier 2 Admins' -Precedence 20 `
    -MinPasswordLength 14 -MaxPasswordAge 90.00:00:00 -LockoutThreshold 10 -LockoutDuration 0 `
    -AppliesTo 'GPO-Tier2-Admins' -Description 'Administrators of the workstations (Tier 2)'
New-PSGPOFineGrainedPasswordPolicy -Server $Server -Name 'PSO - Domain Users' -Precedence 50 `
    -MinPasswordLength 12 -PasswordHistoryCount 12 -AppliesTo 'Domain Users' `
    -Description 'Every user of the domain' -ProtectedFromAccidentalDeletion $false
```

`-LockoutDuration 0` : verrouillé jusqu'à ce qu'un administrateur déverrouille le compte.
**Actualiser** (F5) les affiche dans la console, par ordre de priorité :

![Les PSO par ordre de priorité](../assets/screenshots/29-pso-list.fr.png)

**Propriétés...** rouvre un PSO ; OK sans modification ne change rien.

![Les propriétés d'un PSO](../assets/screenshots/30-pso-editor.fr.png)

## 4. Quel PSO s'applique à tiers1 ?

**Paramètres de mot de passe résultants**, recherchez `tiers`, sélectionnez `Tiers1` :

![Les paramètres résultants de tiers1](../assets/screenshots/31-pso-resultant.fr.png)

- **PSO - Tier 1 Admins** s'applique, par `GPO-Tier1-Admins` : priorité 10.
- **PSO - Domain Users** le concerne aussi, par son groupe principal, mais passe après (priorité 50).
- La **stratégie de mot de passe par défaut du domaine** ne s'applique pas : un PSO s'applique.

Le PSO de l'encadré est la réponse du contrôleur de domaine (`msDS-ResultantPSO`) ; l'ordre de la
liste est celui des règles, et la console le signale si jamais ils diffèrent.

Sélectionné, un groupe montre ce que ses membres reçoivent par lui :

![Le PSO que transmet GPO-Tier2-Admins](../assets/screenshots/36-pso-resultant-group.fr.png)

En ligne de commande :

```powershell
Get-PSGPOResultantPasswordPolicy -Server dc.hardenbox.labo -Identity tiers1 |
    Select-Object -ExpandProperty Candidates | Format-Table Order, Name, Precedence, AppliesThrough, Status, Reason
```

## 5. Modifier, puis supprimer

Passer la priorité de `PSO - Domain Users` à 5 l'appliquerait aussi à `tiers1` : la vue des
paramètres résultants le montre aussitôt, avant tout autre changement dans le domaine. Pour
supprimer un PSO, **Supprimer** ; un PSO protégé contre la suppression accidentelle est gardé :

![Un PSO protégé n'est pas supprimé](../assets/screenshots/35-pso-delete-protected.fr.png)

Décochez d'abord **Protéger contre la suppression accidentelle** dans ses propriétés, ou :

```powershell
Set-PSGPOFineGrainedPasswordPolicy -Server dc.hardenbox.labo -Name 'PSO - Tier 1 Admins' -ProtectedFromAccidentalDeletion $false
Remove-PSGPOFineGrainedPasswordPolicy -Server dc.hardenbox.labo -Name 'PSO - Tier 1 Admins'
```

Chaque modification est dans le journal d'audit de HGPM :

```powershell
Get-PSGPOAuditLog -Action '*PasswordPolicy' | Format-Table Time, Account, Action, Target
```
