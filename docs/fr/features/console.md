# La console

![La tuile Gestion de stratégie de groupe](../assets/screenshots/57-tile-group-policy.fr.png){ align=right width="170" }

`Show-GPOManagerAvalonia` ouvre une fenêtre à trois vues, qu'on choisit depuis sa barre d'outils.

## Group Policy Management

La vue sur laquelle elle s'ouvre, comme GPMC :

![La vue Group Policy Management](../assets/screenshots/01-console-domain.fr.png)

- **Le domaine et ses OU**, triées par nom, chacune avec ses liens de GPO par ordre de lien
  (l'ordre 1 d'abord, la plus haute priorité). Une OU qui bloque l'héritage le dit, et a sa propre
  icône. Un lien dit quand il est **appliqué** (enforced) ou **désactivé**.
- **Group Policy Objects** : toutes les GPO du domaine que votre compte peut voir.
- **WMI Filters** : les filtres WMI du domaine ([filtres WMI](gpo-management.md#les-filtres-wmi)).
- **Deleted GPOs** : les GPO supprimées du domaine qui ont une sauvegarde, pour les restaurer
  ([corbeille](gpo-management.md#la-corbeille)).

Les détails d'un nœud dépendent de ce qu'il est :

| Nœud | Détails |
|---|---|
| Domaine | nom distinctif, contrôleur de domaine et service d'annuaire, le compte connecté, sa délégation, son rôle dans le workflow d'approbation, les GPO liées |
| OU | nom distinctif, blocage de l'héritage, vos droits à cet endroit, les GPO liées |
| GPO, lien | identifiant unique, statut, état d'approbation et propriétaire, vos droits, filtrage de sécurité, filtre WMI, versions, nom distinctif, chemin SYSVOL, tous les liens de la GPO |
| Filtre WMI | description, requêtes, les GPO qui l'utilisent, identifiant unique, nom distinctif |
| GPO supprimée | sa dernière sauvegarde, par qui, son commentaire, statut, filtrage de sécurité, où elle était liée |

Une GPO a aussi deux onglets :

- **Settings** : ses paramètres configurés, comme le rapport de GPMC : les stratégies par chemin de
  catégorie, les paramètres de sécurité, les préférences, les valeurs de registre qu'aucun ADMX
  n'explique.
- **History** : ses sauvegardes en frise ([sauvegardes et historique](backup-history.md)).

![L'onglet Settings](../assets/screenshots/03-gpo-settings.fr.png)

**Actualiser** (ou F5) relit le domaine, sur le même contrôleur de domaine avec le même compte, comme
GPMC : les modifications des autres consoles et de GPMC apparaissent, l'arbre gardant ce qui est
déplié et sélectionné. Sinon la console lit le domaine une fois ; une GPO modifiée depuis sa
lecture n'est pas écrasée ([éditeur de stratégies](policy-editor.md)) : rafraîchissez, puis refaites
la modification.

## Éditeur de stratégies

**Edit** (clic droit, ou double clic sur une GPO) ouvre la GPO dans
l'[éditeur de stratégies](policy-editor.md) : les modèles d'administration, les paramètres de
sécurité et les préférences, lus dans la GPO et enregistrés dedans.

## Navigateur ADMX

**Browse the ADMX policies** montre les stratégies des fichiers ADMX chargés, sans GPO : chercher
une stratégie par son nom, lire son explication et la valeur de registre qu'elle pose, copier son
nom, son chemin de registre ou la commande `Get-ItemProperty` qui la lit.

![Le navigateur ADMX](../assets/screenshots/13-admx-browser.fr.png)

## La barre d'état

En bas : cet ordinateur (nom, système, adresses), son domaine, le contrôleur de domaine depuis
lequel l'annuaire a été lu et son service d'annuaire (`Samba AD` ou `Active Directory`), le
compte connecté, et la version de HGPM avec une pastille :

- **verte** : la dernière version de la PowerShell Gallery ;
- **orange** : une version plus récente est sur la Gallery (`HGPM 0.1.6-alpha : 0.1.7-alpha
  disponible`) ; son info-bulle donne la commande qui l'installe (`Update-PSResource -Name HGPM
  -Prerelease`, ou `Install-PSResource` pour un module qui n'a pas été installé depuis la Gallery,
  une copie du dépôt par exemple), puis ouvrez une nouvelle session PowerShell ;
- **grise** : la Gallery n'a pas été lue (pas de réseau, ou vérification désactivée), les mises à
  jour sont inconnues.

![Une version plus récente sur la PowerShell Gallery](../assets/screenshots/43-update-available.fr.png)

La Gallery est lue comme à l'import du module (voir [Mises à jour](../getting-started/installation.md#mises-a-jour)) :
au plus une fois par jour, 8 secondes au plus : une version publiée depuis la dernière lecture
apparaît le lendemain, ou tout de suite après avoir supprimé `UpdateCheck.json` du dossier de
données local de l'utilisateur (`~/.local/share/PSGPOTools` sous Linux, `%LOCALAPPDATA%\PSGPOTools`
sous Windows). La console des paramètres de mot de passe a la même barre d'état.

## Thèmes et réglages

La barre d'outils bascule entre les thèmes clair et sombre, et ouvre la fenêtre **Settings** : la
[configuration du domaine](configuration.md).

## Langue

La console est dans la langue de la session PowerShell : en français sur un système français, en
anglais sinon, et `-Language` la choisit. Les textes viennent de `Resources/Strings/<langue>.psd1`
du module (`fr-FR.psd1`, avec les termes de la GPMC française) ; un texte qu'il ne traduit pas reste
en anglais. Les noms des paramètres de sécurité, des préférences et les descriptions de la
configuration viennent de `Resources/Strings/Catalogs/<langue>.psd1`, avec les noms de l'éditeur de
stratégie de groupe français ; les onglets Paramètres et Historique montrent leurs rapports dans la
même langue. Les commandes, leurs messages et leurs erreurs restent en anglais, comme ceux de
PowerShell, ainsi que leurs rapports (`Compare-PSGPOBackup`, `Get-PSGPODrift`).

```powershell
Show-GPOManagerAvalonia -Language fr-FR
Show-GPOManagerAvalonia -Language en-US   # en anglais sur un système français
```

## Environnement de démonstration

Sans domaine, la fenêtre montre `Samples/Directory.sample.json` sous un bandeau : un domaine fictif
avec des OU, des liens et des GPO, pour découvrir la console. Ses modifications restent en mémoire.

```powershell
$Sample = Join-Path (Split-Path (Get-Module HGPM).Path) 'Samples' 'Directory.sample.json'
Show-GPOManagerAvalonia -Directory (Import-PSGPODirectory -Path $Sample)
```
