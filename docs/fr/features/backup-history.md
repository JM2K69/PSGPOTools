# Sauvegardes et historique

HGPM garde l'historique de chaque GPO sous forme de sauvegardes, dans un dossier de votre
choix (par défaut `PSGPOTools Backups` dans vos documents). L'onglet **History** d'une GPO les
montre en frise.

![L'onglet History](../assets/screenshots/04-history.fr.png)

## Les sauvegardes

```text
<racine>/<nom de la GPO> {<GUID>}/<dernière modification de la GPO, UTC : yyyy-MM-dd_HH-mm-ss>/
    manifest.json       la GPO et le SHA-256 de chaque fichier
    notes.json          son commentaire et ses étiquettes, quand elle en a
    Files/              les fichiers de son dossier SYSVOL, tels quels
```

- **Le GUID** garde l'historique d'une GPO renommée.
- **Une sauvegarde n'est écrite que si la GPO a changé** depuis la précédente (ses fichiers ou ses
  propriétés : nom, statut, filtrage de sécurité, liens), comme `Backup-GPO` de GPMC par date de
  modification. `-Force` sauvegarde quand même.
- Ce ne sont pas des sauvegardes GPMC : `Restore-GPO` et `Import-GPO` ne les lisent pas.

**Back up now** (une GPO) et **Back up all GPOs** (celles que vous voyez) prennent le commentaire
saisi au-dessus de la frise. La même chose en ligne de commande, pour une tâche planifiée :

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Comment 'CHG-1024 : signature SMB'
```

## La frise

La plus ancienne d'abord, comme la branche d'un graphe git. Chaque nœud est une sauvegarde, avec
sa date, ses versions (`ordinateur 3, utilisateur 0`) et ce qui a changé depuis le nœud précédent
(`+ajoutés ~modifiés -retirés`) ; **Now** est la GPO telle qu'elle est, quand elle a changé depuis
sa dernière sauvegarde. Sélectionnez un nœud pour voir ses changements paramètre par paramètre,
avec la valeur avant (barrée) et après.

Les changements sont ceux de l'onglet Settings : les stratégies par chemin de catégorie, les
paramètres de sécurité, les éléments de préférences (par leur `uid`), les autres fichiers par leur
empreinte, et le nom, le statut, le filtrage de sécurité et les liens de la GPO.

```powershell
$Backups = Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy'
Compare-PSGPOBackup -ReferenceBackup $Backups[1] -DifferenceBackup $Backups[0]
```

## Restaurer

**Restore this version...** remet la GPO comme la sauvegarde la contient, comme `Restore-GPO` de
GPMC :

1. Les fichiers de la sauvegarde sont vérifiés par leur SHA-256 : un fichier manquant ou modifié
   depuis arrête la restauration.
2. La GPO telle qu'elle est **est d'abord sauvegardée**, son commentaire le disant.
3. Ses fichiers sont remplacés (ceux que la sauvegarde n'a pas sont supprimés), son statut et ses
   extensions côté client sont ceux de la sauvegarde.
4. Sa version augmente dans les deux étendues, pour que les ordinateurs l'appliquent de nouveau.

Ses liens et ses droits ne changent pas ; son filtre WMI est celui de la sauvegarde, si ce filtre est encore dans le domaine.

Une sauvegarde n'est jamais restaurée dans un autre domaine, même sur une GPO qui a son GUID : la
Default Domain Policy et la Default Domain Controllers Policy ont le même GUID dans tous les
domaines. Utilisez-la plutôt comme [modèle](gpo-management.md#les-modeles) d'une nouvelle GPO.

Chaque chemin du manifeste doit être un fichier du dossier de la GPO (pas de `..`, pas de chemin
absolu) : une sauvegarde dont le manifeste en nomme un autre est ignorée, avec un avertissement,
comme un manifeste abîmé ; les autres sauvegardes sont listées.

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'T1 - Servers - Baseline' |
    Where-Object { $_.Modified.Date -eq [datetime]'2026-10-15' } | Select-Object -First 1 | Restore-PSGPO
```

## Les notes : commentaires et étiquettes

Les notes d'une sauvegarde sont rangées à côté d'elle, dans `notes.json` ; son manifest et ses
fichiers ne changent jamais, si bien qu'une restauration les vérifie toujours. Sélectionnez un nœud
pour les modifier : son commentaire, ses étiquettes, et deux cases :

- **Approved version** : l'étiquette des versions approuvées (`Backup.ApprovedLabel` de la
  configuration, `Approved` par défaut) ;
- **Template** : l'étiquette des modèles de nouvelles GPO (`Backup.TemplateLabel`, `Template`).

Sur la frise, les étiquettes sont sous chaque nœud, le commentaire apparaît au survol, et la
version approuvée est en vert.

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy' | Select-Object -First 1 |
    Set-PSGPOBackup -Approve -Comment "Relue avec l'équipe sécurité"
```

## Écart avec la version approuvée

La sauvegarde la plus récente qui porte l'étiquette approuvée est la **version approuvée** de la
GPO. Au-dessus de la frise, la console dit si la GPO l'est toujours, ou ce qui a changé depuis :
dans la console, avec GPMC, `samba-tool`, un script, quel que soit l'auteur du changement.

| État | |
|---|---|
| `InSync` | la GPO est sa version approuvée |
| `Drifted` | elle a changé depuis : **Show the changes** les liste |
| `NotApproved` | aucune sauvegarde ne porte encore l'étiquette approuvée |

```powershell
Get-PSGPODrift -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
```

Voir [le workflow d'écart](../workflows/drift.md) et le [workflow d'approbation](../workflows/approval.md).

## Journal d'audit

Chaque modification acceptée par le domaine, depuis la console ou une commande, est une ligne du
journal d'audit :

| Champ | |
|---|---|
| `Time` | quand (UTC) |
| `Account`, `Computer`, `Server` | qui, depuis quel ordinateur, sur quel contrôleur de domaine |
| `Action` | `NewGpo`, `RenameGpo`, `NewLink`, `SetLink`, `RemoveLink`, `SetBlockInheritance`, `SetGpoStatus`, `SetWmiFilter`, `NewWmiFilter`, `EditWmiFilter`, `RemoveWmiFilter`, `SetGpoPermission`, `SetGpoSecurityFiltering`, `SaveGpoFile`, `RestoreGpo`, `ImportGpo`, `RemoveGpo`, `RemoveDeletedGpoBackup`, `PendingGpo`, `ApproveGpo`, `NewFilteringGroups`, `SaveConfiguration` |
| `Target`, `GpoName`, `GpoId` | sur quoi : la GPO, le domaine ou l'OU, la configuration |
| `Details` | comment : les options de lien changées, le fichier enregistré avec son SHA-256 et la nouvelle version, les droits des créateurs et les permissions retirées à une approbation… |

Les lignes sont seulement ajoutées, jamais réécrites : un fichier par domaine et par mois,
`<domaine>-<aaaa-MM>.jsonl`, dans `Audit.Path` de la [configuration](configuration.md) (un partage
où écrivent les administrateurs des GPO, le même pour toutes les consoles) ; par défaut dans le
dossier `Audit` des sauvegardes du compte, que seule sa console voit. Un journal qui ne peut pas
être écrit n'annule pas la modification, qui est faite : la console le dit.

```powershell
Get-PSGPOAuditLog -After (Get-Date).AddDays(-7) | Format-Table Time, Account, Action, GpoName, Target
Get-PSGPOAuditLog -Name 'C - Servers - Baseline' -Action SaveGpoFile, ApproveGpo
```

!!! note
    Le journal dit ce que les consoles et les commandes de HGPM ont modifié, pas ce que
    GPMC ou un autre outil a modifié. Qui peut écrire dans son dossier peut le modifier : ne donnez
    le partage qu'aux administrateurs des GPO, et gardez-en une copie là où ils n'écrivent pas (un
    SIEM).
