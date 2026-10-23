# Gérer les GPO

Tout est dans le menu contextuel de l'arbre ; le menu ne propose que ce que votre compte a le
droit de faire dans le domaine (voir [délégation](delegation.md)).

## Créer une GPO

**Create a GPO in this domain, and Link it here...** sur le domaine ou une OU, ou **New GPO...**
sur Group Policy Objects :

![Le formulaire New GPO](../assets/screenshots/05-new-gpo.fr.png)

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

![Lier une GPO existante](../assets/screenshots/06-link-existing-gpo.fr.png)

**Delete link...** sur un lien le supprime, après confirmation ; la GPO elle-même reste dans Group
Policy Objects avec ses autres liens, et les liens suivants remontent d'un rang.

Les liens sont écrits dans l'attribut `gPLink` en LDAP : l'ancienne valeur est retirée et la
nouvelle ajoutée dans une seule requête, si bien qu'un lien ajouté par quelqu'un d'autre entre-temps
n'est jamais perdu.

## Liens et héritage

Le menu contextuel d'un lien a les éléments de GPMC :

| Élément | Fait |
|---|---|
| **Enforced** | la GPO s'applique même sous une OU qui bloque l'héritage, et l'emporte sur les GPO liées en dessous |
| **Link Enabled** | décoché, la GPO ne s'applique plus là ; le lien reste, pour le réactiver |
| **Move link up** / **Move link down** | change son ordre de lien : 1 est appliqué en dernier, il l'emporte donc sur les autres |

et le menu contextuel du domaine ou d'une OU, **Block Inheritance** : les GPO liées au-dessus ne
s'y appliquent plus, sauf les liens appliqués (Enforced). L'arbre les montre comme GPMC : un cadenas
pour un lien appliqué, un lien barré pour un lien désactivé, un dossier barré pour une OU qui bloque
l'héritage.

![Les liens d'une OU : l'un appliqué, l'autre désactivé](../assets/screenshots/19-links-enforced.fr.png)

![Une OU qui bloque l'héritage](../assets/screenshots/20-block-inheritance.fr.png)

Chaque modification est écrite tout de suite dans le domaine, et seulement ce qui change : la
console relit le `gPLink` (ou le `gPOptions`), modifie son lien, et l'écrit dans une seule requête
qui retire aussi la valeur lue. Une modification faite entre-temps par une autre console est
conservée ; un ordre de lien changé entre la lecture et l'écriture est refusé plutôt que perdu. Il
faut la même délégation que pour lier des GPO (« Link GPOs » de GPMC : écrire `gPLink` et
`gPOptions`).

```powershell
New-PSGPOLink -Name 'C - Servers - Baseline' -Target 'OU=Servers,DC=contoso,DC=com' -Enforced
Set-PSGPOLink -Name 'U - Lyon - Printers' -Target Lyon -Enabled $false
Set-PSGPOLink -Name 'C - Servers - Baseline' -Target Servers -Order 1
Set-PSGPOInheritance -Target 'OU=Kiosks,DC=contoso,DC=com' -Blocked $true
Remove-PSGPOLink -Name 'U - Lyon - Printers' -Target Lyon
```

`-Target` est un nom distinctif, le nom du domaine, ou le nom d'une OU quand une seule OU le porte.

## Statut et filtrage de sécurité

**GPO Status**, dans le menu contextuel d'une GPO, règle quelle partie les ordinateurs en
appliquent, comme dans GPMC : tous ses paramètres, ceux des ordinateurs seulement (User
Configuration Settings Disabled), ceux des utilisateurs seulement, ou aucun (`Set-PSGPO -Status`).

La partie d'une GPO que son statut désactive reste modifiable, comme dans GPMC : ses paramètres
sont enregistrés, mais personne ne les applique. L'éditeur le dit au-dessus des stratégies :

![L'éditeur d'une GPO dont la configuration utilisateur est désactivée](../assets/screenshots/47-editor-status.fr.png)

Les détails d'une GPO montrent son **statut** et son **filtrage de sécurité**, comme l'onglet
Étendue de GPMC : qui l'applique (« Appliquer la stratégie de groupe ») et à qui elle est refusée.
Les groupes de filtrage d'une nouvelle GPO sont créés avec les préfixes, l'étendue et les
descriptions de la [configuration](configuration.md) ; Authenticated Users garde la lecture de la
GPO, comme les ordinateurs en ont besoin (MS16-072).

## Les autorisations d'une GPO (onglet Délégation)

L'onglet **Délégation** d'une GPO montre et modifie ses autorisations, comme les onglets Étendue
et Délégation de GPMC.

![L'onglet Délégation d'une GPO](../assets/screenshots/25-delegation.fr.png)

- **Filtrage de sécurité** : les groupes, utilisateurs et ordinateurs qui appliquent la GPO.
  **Ajouter** un compte (son nom, `DOMAINE\nom`, un ordinateur sous la forme `PC01$`) : il lit et
  applique la GPO, un refus qui le nommait est retiré. **Supprimer** un compte : il n'applique plus
  la GPO, et ne la lit plus quand c'était tout ce qu'il faisait. Utilisateurs authentifiés garde
  la lecture : les ordinateurs doivent lire chaque GPO (MS16-072).
- **Délégation** : chaque compte des autorisations de la GPO avec son niveau : **Lecture**,
  **Lecture et application**, **Modifier les paramètres**, **Modifier les paramètres, supprimer,
  modifier la sécurité**, ou **Personnalisé** (d'autres droits, ou un refus). Choisissez un niveau
  et **Définir l'autorisation** pour un compte, ou **Supprimer** le compte. **Lecture et
  application** lit et applique la GPO (Appliquer la stratégie de groupe), comme un compte ajouté
  au filtrage de sécurité ; GPMC le nomme Lecture (à partir du filtrage de sécurité). Un niveau
  remplace celui du compte : pour garder un éditeur et lui faire appliquer la GPO, **Ajoutez**-le
  plutôt au filtrage de sécurité. Un éditeur qui appliquait la GPO continue de l'appliquer. La
  pastille **S'applique** marque chaque compte qui applique la GPO, quel que soit son niveau. Les
  autorisations héritées viennent du conteneur Policies du domaine : elles sont affichées, pas
  modifiées.

Une modification est écrite sur la GPO dans l'annuaire (sa DACL relue d'abord : la modification
d'une autre console est gardée), puis sur son dossier SYSVOL et tout ce qu'il contient, avec l'ACL
dérivée de l'annuaire comme le font GPMC et `samba-tool`. L'onglet signale quand plus aucun
ordinateur ne peut lire la GPO. Une GPO en attente d'approbation n'est pas modifiée : ses
autorisations sont fixées à son approbation. Chaque modification va dans le
[journal d'audit](backup-history.md).

```powershell
Get-PSGPOPermission -Name 'C - Workstations - BitLocker'
Set-PSGPOPermission -Name 'C - Workstations - BitLocker' -Account 'GPO-Tier2-Admins' -Permission GpoEdit
Set-PSGPOPermission -Name 'C - Workstations - BitLocker' -Account 'Paris-Workstations' -SecurityFiltering Add
Set-PSGPOPermission -Name 'C - Workstations - BitLocker' -Account 'Authenticated Users' -SecurityFiltering Remove
```

## Les filtres WMI

Un filtre WMI fait appliquer une GPO par les ordinateurs seulement quand l'une de ses requêtes WQL
renvoie quelque chose (les postes de travail seulement, une version de Windows, les portables…),
comme le filtrage WMI de l'onglet Étendue de GPMC. Les filtres sont des objets du domaine
(`msWMI-Som` dans `CN=SOM,CN=WMIPolicy,CN=System`), que Samba AD conserve pour les ordinateurs
Windows ; une GPO désigne son filtre dans `gPCWQLFilter`.

**WMI Filters**, dans l'arbre sous Group Policy Objects, liste les filtres du domaine avec leurs
requêtes, comme GPMC. Un filtre montre sa description, ses requêtes, les GPO qui l'utilisent et son
nom distinctif :

![Les filtres WMI du domaine](../assets/screenshots/23-wmi-filter-details.fr.png)

**New WMI Filter...**, dans le menu contextuel de WMI Filters, en crée un : son nom, une
description, l'espace de noms WMI (`root\CIMv2`) et ses requêtes WQL, une par ligne.
**Delete WMI filter...**, dans le menu contextuel d'un filtre, le supprime quand plus aucune GPO ne
l'utilise.

![Un nouveau filtre WMI](../assets/screenshots/24-new-wmi-filter.fr.png)

**Modifier le filtre WMI...**, dans le menu contextuel d'un filtre, ou **Modifier ce filtre WMI**
dans ses détails, le modifie dans le même formulaire : son nom, sa description, ses requêtes.
**Renommer...** (ou F2) ne change que son nom. Le filtre garde son identité (`msWMI-ID`) : les
GPO qui y sont liées le gardent et les ordinateurs les appliquent avec ses nouvelles requêtes, comme
quand GPMC modifie un filtre. Une requête d'un autre espace de noms que celui du formulaire est une
ligne `espace de noms: requête` (`root\WMI: SELECT * FROM BatteryStatus`). La modification est
refusée si le filtre a changé dans le domaine depuis que la console l'a lu.

![Un filtre WMI modifié](../assets/screenshots/41-edit-wmi-filter.fr.png)

**WMI Filter**, dans le menu contextuel d'une GPO, liste les filtres du domaine : celui qui est
coché est le filtre de la GPO, **(none)** la délie. Les détails de la GPO offrent le même choix
dans leur liste **Filtre WMI**, comme l'onglet Étendue de GPMC, et montrent le filtre et ses
requêtes, ou disent que le filtre d'une GPO n'est plus dans le domaine (les ordinateurs ignorent
alors la GPO).

![Une GPO liée à un filtre WMI](../assets/screenshots/21-wmi-filter.fr.png)

Depuis le filtre, **L'utiliser dans un GPO...** liste les GPO que votre compte modifie et qui ne
l'utilisent pas encore (cherchez-en une par son nom) : la GPO choisie est liée au filtre, son
ancien filtre remplacé.

![Utiliser un filtre WMI dans une GPO](../assets/screenshots/50-use-wmi-filter.fr.png)

### Exporter et importer un filtre WMI

**Exporter...**, dans le menu contextuel d'un filtre, l'écrit dans un fichier `.mof`, comme GPMC :
le même format (UTF-16, une instance de `MSFT_SomFilter` avec ses règles), que GPMC importe donc
dans un autre domaine. Le fichier est proposé dans le dossier `WMI filters` du dossier des
sauvegardes ; **Parcourir...** en choisit un autre, et un fichier déjà là est remplacé après
confirmation.

![Exporter un filtre WMI](../assets/screenshots/48-export-wmi-filter.fr.png)

**Importer...**, dans le menu contextuel de Filtres WMI, lit un fichier `.mof` exporté par GPMC ou
par HGPM : **Lire le fichier** montre son filtre (son domaine, sa description et ses requêtes), puis
**Importer** le crée dans le domaine, sous son nom ou un autre. Il reçoit un nouvel Id : un fichier
de ce domaine est donc importé à côté de son filtre ; un nom que le domaine a déjà est refusé. Comme
dans GPMC, la console importe un fichier d'un seul filtre ; `Import-PSGPOWmiFilter` les importe
tous.

![Importer un filtre WMI](../assets/screenshots/49-import-wmi-filter.fr.png)

Les fichiers ont été vérifiés sur un domaine Windows : un filtre exporté par HGPM est recréé par
Windows à partir de son fichier (le fournisseur `root\policy` des filtres, comme GPMC), et un
fichier de Windows est importé par HGPM, puis lu par GPMC.

```powershell
Export-PSGPOWmiFilter -Name '*' -Path C:\Exports
Get-ChildItem C:\Exports -Filter *.mof | Import-PSGPOWmiFilter -Server dc.fabrikam.com
Import-PSGPOWmiFilter -Path C:\Exports\Workstations.mof -Name 'Workstations (lab)'
```

```powershell
New-PSGPOWmiFilter -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1' -Description 'Les postes Windows, pas les serveurs'
Set-PSGPO -Name 'T2 - Workstations - Baseline' -WmiFilter 'Workstations'
Get-PSGPOWmiFilter | Format-Table Name, Queries, Gpos
Set-PSGPOWmiFilter -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1 AND Version LIKE ''10.0.2%''' -Description 'Les postes Windows 11'
Set-PSGPO -Name 'T2 - Workstations - Baseline' -NoWmiFilter
Remove-PSGPOWmiFilter -Name 'Workstations'
```

Un filtre qu'utilise une GPO n'est pas supprimé, y compris les GPO que votre compte ne voit pas.
Les sauvegardes gardent le filtre d'une GPO (son nom et ses requêtes) : l'écart montre quand il a
changé, et une restauration relie la GPO à son filtre s'il est encore dans le domaine, ou dit qu'il
n'y est plus.

## Renommer une GPO

**Renommer...**, dans le menu contextuel d'une GPO ou d'un lien vers elle, ou **F2** dans
l'arborescence, lui donne un nouveau nom, comme GPMC. Seul son nom d'affichage change : son GUID,
donc son dossier SYSVOL, ses liens, ses paramètres, ses sauvegardes (l'onglet Historique) et ses
groupes de filtrage de sécurité sont conservés. Le nom d'une autre GPO du domaine est refusé, tout
comme une GPO renommée dans le domaine depuis que la console l'a lue. Le renommage va dans le
[journal d'audit](backup-history.md) (`RenameGpo`).

![Renommer une GPO](../assets/screenshots/45-rename-gpo.fr.png)

```powershell
Set-PSGPO -Name 'U - Lyon - Printers' -NewName 'U - Lyon - Color printers'
```

## Supprimer une GPO

**Delete GPO...** sur une GPO de Group Policy Objects, après confirmation :

![Supprimer une GPO](../assets/screenshots/08-delete-gpo.fr.png)

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

![Restaurer une GPO supprimée](../assets/screenshots/07-deleted-gpo.fr.png)

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

**Supprimer définitivement...** vide la corbeille d'une GPO, après confirmation : chacune de ses
sauvegardes dans le dossier de l'onglet Historique est supprimée, les modèles faits à partir d'elle
aussi (la confirmation les compte). Elle ne peut plus être restaurée ensuite. Les sauvegardes d'une
GPO encore dans le domaine sont son historique : elles ne sont jamais supprimées ainsi.

![Supprimer définitivement une GPO de la corbeille](../assets/screenshots/46-delete-for-good.fr.png)

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Deleted -Name 'U - Lyon - Printers' | Remove-PSGPOBackup
```

## Les modèles

Une sauvegarde étiquetée **Template** (la case de ses notes, onglet History) est proposée dans
**Start from** du formulaire New GPO, quel que soit le domaine d'où elle vient : la nouvelle GPO
part de ses paramètres, vérifiés d'abord par leur SHA-256.

```powershell
$Template = Get-PSGPOBackup -Path /srv/gpo-backups -Template -Name 'Template - Servers' | Select-Object -First 1
New-PSGPO -Name 'C - Servers - Lyon' -Template $Template
```
