# Gérer les GPO

Tout est dans le menu contextuel de l'arbre ; le menu ne propose que ce que votre compte a le
droit de faire dans le domaine (voir [délégation](delegation.md)).

## Créer une GPO

**Create a GPO in this domain, and Link it here...** sur le domaine ou une OU, ou **New GPO...**
sur Group Policy Objects :

![Le formulaire New GPO](../assets/screenshots/05-new-gpo.png)

| Champ | |
|---|---|
| Nom | proposé par la configuration (`NewGpo.DefaultName`) |
| GPO status | activée, paramètres ordinateur seuls (configuration utilisateur désactivée), paramètres utilisateur seuls |
| Start from | une GPO vide, ou un [modèle](#les-modeles) |
| Create the security filtering groups | `APPLY_<GPO>` (seuls ses membres l'appliquent) et `DENY_<GPO>` (ses membres ne l'appliquent jamais), dans le conteneur choisi |

La GPO est créée sur le contrôleur de domaine que lit la console, avec **New-GPO** (RSAT) sous
Windows et **samba-tool gpo create** sous Linux : les deux créent son conteneur dans l'annuaire et
son dossier dans SYSVOL avec ses droits, comme GPMC. Viennent ensuite son statut, son modèle, ses
groupes de filtrage et son lien, dans cet ordre. **Elle n'est pas liée si son filtrage de sécurité
a échoué** : elle s'appliquerait à tous les ordinateurs et utilisateurs.

La ligne de commande fait de même :

```powershell
New-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
```

### Les groupes de filtrage de sécurité

**Create the security filtering groups** donne à la nouvelle GPO deux groupes de sécurité à elle,
pour qu'elle ne s'applique que là où vous le décidez :

| Groupe | Membres | Droit sur la GPO |
|---|---|---|
| `APPLY_<GPO>` | les ordinateurs ou utilisateurs qui l'appliquent | lecture et « Appliquer la stratégie de groupe » |
| `DENY_<GPO>` | les ordinateurs ou utilisateurs qui ne l'appliquent jamais | « Appliquer la stratégie de groupe » refusé |

- Leurs noms, leur étendue (globale, domaine local, universelle), leurs descriptions et leur
  conteneur viennent de la [configuration](configuration.md) (`NewGpo.SecurityFilteringGroups`) ;
  le formulaire propose d'abord le conteneur de la configuration, puis le conteneur des
  utilisateurs et les OU.
- **Authenticated Users** n'applique plus la GPO mais garde la lecture : les ordinateurs doivent
  lire chaque GPO (MS16-072).
- Les groupes appartiennent au compte qui les crée, qui gère leurs membres.
- Les groupes sont créés **avant le lien** : s'ils ne peuvent pas l'être (pas de droit dans le
  conteneur, nom déjà pris, nom de plus de 64 caractères…), la GPO est créée mais pas liée, et la
  console dit pourquoi.

Avec le [workflow d'approbation](../workflows/approval.md), un créateur Tier 1 ne se voit pas
proposer les groupes : une GPO en attente ne s'applique à personne, et son filtrage de sécurité est
posé **à l'approbation**, où l'approbateur peut créer les mêmes groupes.

## Lier une GPO

**Link an Existing GPO...** sur le domaine ou une OU liste les GPO qui n'y sont pas encore liées,
avec une recherche par nom ; le lien prend la plus faible priorité (le dernier ordre de lien),
comme dans GPMC.

![Lier une GPO existante](../assets/screenshots/06-link-existing-gpo.png)

**Delete link...** sur un lien le supprime, après confirmation ; la GPO elle-même reste dans Group
Policy Objects avec ses autres liens, et les liens suivants remontent d'un rang.

Les liens sont écrits dans l'attribut `gPLink` en LDAP : l'ancienne valeur est retirée et la
nouvelle ajoutée dans une seule requête, si bien qu'un lien ajouté par quelqu'un d'autre entre-temps
n'est jamais perdu.

## Statut et filtrage de sécurité

Les détails d'une GPO montrent son **statut** et son **filtrage de sécurité**, comme l'onglet
Étendue de GPMC : qui l'applique (« Appliquer la stratégie de groupe ») et à qui elle est refusée.
Les groupes de filtrage d'une nouvelle GPO sont créés avec les préfixes, l'étendue et les
descriptions de la [configuration](configuration.md) ; Authenticated Users garde la lecture de la
GPO, comme les ordinateurs en ont besoin (MS16-072).

## Supprimer une GPO

**Delete GPO...** sur une GPO de Group Policy Objects, après confirmation :

![Supprimer une GPO](../assets/screenshots/08-delete-gpo.png)

1. La GPO est d'abord **sauvegardée**, dans le dossier de l'onglet History ; sa dernière
   sauvegarde dit quand et par qui elle a été supprimée.
2. Ses **liens** dans le domaine sont supprimés. Si votre compte ne peut pas en supprimer un, rien
   n'est supprimé.
3. La GPO, son conteneur et son dossier SYSVOL sont supprimés (**Remove-GPO** sous Windows,
   **samba-tool gpo del** sous Linux), et la console vérifie qu'elle a bien disparu.

La Default Domain Policy et la Default Domain Controllers Policy ne sont jamais supprimées.

```powershell
Remove-PSGPO -Name 'U - Lyon - Printers' -BackupPath /srv/gpo-backups
```

!!! note
    Les liens des sites (dans la partition de configuration) ne sont pas lus par la console : un
    lien d'un site vers une GPO supprimée y reste.

## La corbeille

**Deleted GPOs** liste les GPO du domaine qui n'y sont plus et qui ont une sauvegarde (la plus
récente). **Restore...** recrée la GPO à partir de celle-ci :

![Restaurer une GPO supprimée](../assets/screenshots/07-deleted-gpo.png)

- une **nouvelle GPO**, avec un nouveau GUID donné par le domaine (ni New-GPO ni samba-tool ne
  permettent de le choisir), avec le nom, les paramètres, le statut et les extensions côté client
  de la sauvegarde ;
- **Link it again where it was** : à ses conteneurs qui existent encore, seulement si son filtrage
  de sécurité était Authenticated Users et ses liens activés. Son filtrage de sécurité n'est pas
  restauré : une GPO filtrée sur un groupe n'est donc pas reliée (elle s'appliquerait à tout le
  monde) ;
- la nouvelle GPO est sauvegardée aussitôt, en disant d'où elle vient, et quitte la corbeille.

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted | Restore-PSGPO -RestoreLink
```

## Les modèles

Une sauvegarde étiquetée **Template** (la case de ses notes, onglet History) est proposée dans
**Start from** du formulaire New GPO, quel que soit le domaine d'où elle vient : la nouvelle GPO
part de ses paramètres, vérifiés d'abord par leur SHA-256.

```powershell
$Template = Get-PSGPOBackup -Path /srv/gpo-backups -Template -Name 'Template - Servers' | Select-Object -First 1
New-PSGPO -Name 'C - Servers - Lyon' -Template $Template
```
