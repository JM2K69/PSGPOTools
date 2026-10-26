# Durcissement

HGPM donne aux techniciens de Tier 1 et de Tier 2 la création de GPO, et aux approbateurs de
Tier 0 le pouvoir de les faire appliquer. Chaque droit d'un technicien est un moyen de faire agir
le Tier 0 pour lui : cette page liste ce dont la console ne se fie pas, ce qu'elle fait à la place,
et ce qui a été testé, par les tests du module (`CI/tests/PSGPOTools.Hardening.tests.ps1` et
d'autres) et sur les deux labs ([hardenbox.labo, Samba AD et powershell.labo, Active
Directory](../getting-started/lab.md)).

| Ce qu'un technicien contrôle | Ce que fait HGPM |
|---|---|
| le `gPCFileSysPath` de sa GPO (il en est propriétaire pendant l'attente) | [n'utilise que le dossier de la GPO](#redirected-gpo), refuse une GPO redirigée |
| les permissions de sa GPO, hors de la console | l'approbation [les reconstruit](../workflows/approval.md#4-lapprouver-tier-0) à partir de ce qu'une GPO approuvée peut avoir |
| le contenu de sa GPO jusqu'à l'approbation | l'approbation [sauvegarde](../workflows/approval.md#4-lapprouver-tier-0) la version approuvée ; la dérive montre tout changement ensuite |
| une sauvegarde sur un partage qu'il peut écrire | les [chemins des fichiers](#other-guards) d'une sauvegarde sont vérifiés |
| une console plus ancienne, un contrôleur de domaine sans la configuration | la [configuration échoue en sécurité](#configuration-fails-closed) |

## Une GPO redirigée vers un autre dossier { #redirected-gpo }

### La menace

L'attribut `gPCFileSysPath` d'une GPO dit où est son dossier dans SYSVOL
(`\\<domaine>\SysVol\<domaine>\Policies\{GUID}`) : les ordinateurs y lisent les paramètres de la
GPO. Tant qu'une GPO attend son approbation, son créateur en est propriétaire, avec le contrôle
total : il peut écrire cet attribut, hors de la console (`ldapmodify`, ADSI Edit), et le faire
pointer vers n'importe quel dossier :

- la configuration de la console (`SYSVOL\<domaine>\PSGPOTools`), le dossier d'une autre GPO, ou
  un autre partage d'un contrôleur de domaine (`C$`) ;
- à l'approbation, l'approbateur, Tier 0, donne à ce dossier le propriétaire et les permissions
  d'une GPO approuvée, avec ses propres droits : en *Modifier les paramètres*, les groupes de
  créateurs pourraient alors modifier la configuration de la console et se nommer approbateurs ;
- une fois approuvée, les ordinateurs lisent les paramètres de la GPO dans le dossier du créateur,
  jamais approuvé ;
- à la suppression, `samba-tool gpo del` et `Remove-GPO` suppriment le dossier que donne l'attribut.

Jusqu'à 0.1.13, la console utilisait l'attribut tel quel.

### Ce que fait la console

- **Le dossier de la GPO seulement** : la console lit et écrit `SysVol` et
  `<domaine>\Policies\{GUID}` de la GPO, quelle que soit la casse. Une GPO dont le
  `gPCFileSysPath` désigne un autre dossier, partage ou serveur est *redirigée* : la console ne la
  lit, ne l'écrit ni ne l'approuve, le dit en rouge dans l'arbre (*redirigée vers un autre
  dossier*) et dans ses détails (**Redirigée** : où les ordinateurs la lisent).
- **La suppression** : l'attribut est relu, remis sur le dossier de la GPO, puis la GPO est
  supprimée : `samba-tool` et `Remove-GPO` suppriment son propre dossier, pas celui du créateur.
- **Après l'approbation** : en *Modifier les paramètres* (`Workflow.CreatorRights = EditSettings`),
  les groupes de créateurs se voient refuser l'écriture de `gPCFileSysPath`
  (`(OD;;WP;f30e3bc1-9ff0-11d1-b603-0000f80367c1;;<groupe>)`, en tête de la DACL). Ils modifient
  toujours les paramètres : l'onglet Délégation les montre en *Modifier les paramètres*, et le
  refus reste quand un administrateur leur donne un autre niveau.

Une GPO redirigée est supprimée par un administrateur du domaine, ou son `gPCFileSysPath` remis
sur son dossier (ADSI Edit, `ldbedit`) : elle n'a pas été approuvée.

### Testé

`PSGPOTools.Hardening.tests.ps1`, *A GPO redirected to another folder* :

- le dossier de la GPO est utilisé quelle que soit la casse du serveur, du partage, du domaine et
  du GUID, avec ou sans `\` final ;
- 7 redirections sont refusées : la configuration de la console, une autre GPO, `..` dans le
  chemin, un autre partage (`NETLOGON`), `C$` d'un contrôleur de domaine, un autre serveur du
  domaine, un guillemet qui terminerait une commande de `smbclient` ;
- une GPO redirigée n'est pas approuvée, et apparaît en rouge dans l'arbre et dans ses détails ;
- l'approbation en *Modifier les paramètres* ajoute le refus, en tête, gardé quand le niveau
  change ; pas en *Lecture seule* ;
- la suppression remet l'attribut avant `samba-tool gpo del` ou `Remove-GPO`.

Sur les deux labs, avec un dossier leurre `SYSVOL\<domaine>\HGPM-decoy` (un fichier) :

| Étape | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| `tiers1` crée une GPO, qui attend son approbation | oui | oui |
| `tiers1` écrit son `gPCFileSysPath` vers le leurre (la menace) | **permis** | **permis** |
| L'administrateur lit le domaine : la GPO est redirigée, en rouge dans l'arbre | oui | oui |
| Lecture de ses fichiers | refusée | refusée |
| Son approbation | refusée, elle reste en attente | refusée, elle reste en attente |
| Sa suppression | l'attribut remis, puis supprimée | l'attribut remis, puis supprimée |
| Le leurre après la suppression | son fichier et son ACL inchangés | son fichier et son ACL inchangés |
| Une seconde GPO approuvée en *Modifier les paramètres* : le refus | sur le groupe de créateurs | sur le groupe de créateurs |
| L'onglet Délégation | le groupe : *Modifier les paramètres* | le groupe : *Modifier les paramètres* |
| `tiers1` écrit son `gPCFileSysPath` | **refusé** (droits insuffisants) | **refusé** (droits insuffisants) |
| `tiers1` la renomme (un paramètre qu'il modifie) | permis | permis |

## La configuration du domaine échoue en sécurité { #configuration-fails-closed }

### La menace

La configuration du domaine (`SYSVOL\<domaine>\PSGPOTools\Configuration.psd1`) règle le circuit
d'approbation, les rôles, le journal d'audit central et les sauvegardes du Tier 0. Sans elle, les
valeurs par défaut s'appliquent, et celle de `Workflow.Enabled` est `$false` : aucune GPO n'attend
d'approbation. Le domaine délègue pourtant toujours la création de GPO aux créateurs
(`Initialize-PSGPOWorkflow`) : une GPO qu'ils créent s'appliquerait tout de suite. Jusqu'à 0.1.13,
une console retombait sur les valeurs par défaut quand la configuration :

- ne pouvait pas être lue, ou contenait une valeur fausse ;
- contenait un réglage qu'elle ne connaissait pas : une console plus récente l'avait écrit
  (`Audit.Tiers` est arrivé en 0.1.12), et toute la configuration était ignorée ;
- n'était pas sur le contrôleur de domaine qu'elle lit : Samba ne réplique pas SYSVOL.

Un administrateur qui ouvrait la console sur un tel contrôleur de domaine y créait une configuration
vide : le circuit coupé pour toutes les consoles qui le lisent.

### Ce que fait la console

| Cas | Avant (0.1.13) | Maintenant |
|---|---|---|
| Un réglage que la console ne connaît pas | toute la configuration ignorée, circuit coupé | ce réglage ignoré avec un avertissement, les autres utilisés ; gardé quand la console enregistre la configuration |
| La configuration ne peut pas être lue, ou contient une valeur fausse | valeurs par défaut, circuit coupé | non utilisée ; les comptes qui ne sont pas administrateurs du domaine ne créent aucune GPO (*le circuit d'approbation est inconnu*) |
| La console est plus ancienne que `Console.MinimumVersion` | (pas de tel réglage) | non utilisée ; aucune GPO créée par ces comptes, le message dit de mettre à jour |
| Pas de configuration sur le contrôleur de domaine, la création de GPO déléguée | valeurs par défaut, circuit coupé | aucune GPO créée par ces comptes, le message dit de l'y copier |
| Le même cas, pour un administrateur qui ouvre la console | une configuration vide créée | pas créée, un avertissement dit où elle est |
| Pas de configuration, pas de délégation (circuit jamais déployé) | valeurs par défaut | valeurs par défaut |

Les administrateurs du domaine continuent de travailler dans tous les cas : ce sont eux qui
corrigent la configuration. La délégation est lue dans les permissions de `CN=Policies,CN=System` :
le droit de créer des objets `groupPolicyContainer` donné à un groupe autre que Domain Admins,
Enterprise Admins, Group Policy Creator Owners, Administrators ou SYSTEM.

`Console.MinimumVersion` ([référence](../reference/configuration.md#console)) est le moyen
d'arrêter les consoles plus anciennes : réglez-le une fois toutes les consoles mises à jour. Les
consoles antérieures à 0.1.14 ne le connaissent pas : elles ignorent toute la configuration, comme
avant. Mettez-les à jour d'abord.

### Testé

`PSGPOTools.Configuration.tests.ps1` et `PSGPOTools.Workflow.tests.ps1` :

- une configuration qui demande une console plus récente, contient une version minimale fausse, ou
  une table là où une valeur est attendue, n'est pas utilisée, et dit pourquoi ;
- les réglages écrits par une console plus récente sont ignorés avec un avertissement, les autres
  utilisés, et ils sont gardés quand la configuration est enregistrée ; cette console ne les règle
  pas ;
- la création de GPO s'arrête quand la configuration n'est pas utilisée, et quand elle manque alors
  que le domaine délègue la création de GPO ; un administrateur du domaine, et un domaine sans la
  délégation (Group Policy Creator Owners seulement), ne sont pas arrêtés ;
- aucune configuration vide n'est créée sur un contrôleur de domaine qui ne l'a pas quand le
  domaine délègue la création de GPO.

Sur les deux labs, la configuration du domaine sauvegardée d'abord et restaurée à la fin, octet pour
octet ; `tiers1`, un créateur, après chaque changement :

| La configuration du domaine | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| Telle quelle | circuit connu, sa GPO créée en attente d'approbation | circuit connu, sa GPO créée en attente d'approbation |
| Avec `Console.MinimumVersion = '99.0'` | *le circuit d'approbation est inconnu* : aucune GPO créée | *le circuit d'approbation est inconnu* : aucune GPO créée |
| Avec un réglage qu'aucune console ne connaît (`Future.Mode`) | un avertissement ; circuit connu, sa GPO créée en attente d'approbation | un avertissement ; circuit connu, sa GPO créée en attente d'approbation |
| Retirée du contrôleur de domaine | *le domaine délègue la création de GPO, mais dc.hardenbox.labo n'a pas de configuration* : aucune GPO créée | *le domaine délègue la création de GPO, mais ADDS.powershell.labo n'a pas de configuration* : aucune GPO créée |
| L'administrateur ouvre alors la console | la configuration pas créée, un avertissement | la configuration pas créée, un avertissement |
| Restaurée | circuit connu, sa GPO créée en attente d'approbation | les mêmes octets, lus sans avertissement |

## Autres protections { #other-guards }

`PSGPOTools.Hardening.tests.ps1` teste aussi :

| Protection | Pourquoi |
|---|---|
| Les chemins des fichiers d'une sauvegarde restent dans le dossier de la GPO (pas de `..`, pas de chemin absolu, pas de guillemet) | une sauvegarde vient d'un partage que d'autres peuvent écrire : une restauration écrirait ailleurs, un guillemet terminerait une commande de `smbclient` |
| Une sauvegarde d'un autre domaine n'est jamais restaurée sur une GPO de ce domaine de même GUID (les GPO par défaut) | les GUID des GPO par défaut sont les mêmes dans tous les domaines |
| Les jokers dans les noms donnés aux commandes, et deux GPO de même nom | chacune est sauvegardée et comparée, pas la première trouvée |
| Une GPO modifiée depuis sa lecture n'est pas écrasée (`versionNumber`, `gPLink` comparés dans la même requête) | une autre console, ou GPMC, l'a modifiée entre-temps |
| L'approbation écrit SYSVOL, puis les conteneurs de la GPO, puis la GPO ; un échec la laisse en attente | c'est son propriétaire qui la rend approuvée : jamais approuvée avec un dossier encore au créateur |
| Les permissions ajoutées pendant l'attente sont retirées à l'approbation, et listées | le créateur en était propriétaire, et pouvait ajouter n'importe quelle ACE |
| SYSVOL avec `-Credential` sous Windows : le partage atteint une seule fois avec ce compte | la session d'un autre compte n'est jamais utilisée par erreur |
| Lecture d'un grand domaine : 2 000 GPO et 1 000 UO en quelques secondes | la console reste utilisable sur un grand domaine |

Pour les lancer :

```powershell
pwsh -Command "& ./CI/Invoke-Tests.ps1 -Path CI/tests/PSGPOTools.Hardening.tests.ps1"
```

## Limites connues

La même revue les a trouvées, elles ne sont pas encore corrigées :

- pendant qu'un approbateur examine une GPO, son créateur peut encore la modifier : l'approbation
  approuve ce que la GPO contient à ce moment, que la sauvegarde approuvée enregistre, et qui peut
  différer de ce qui a été examiné ;
- un compte à la fois dans `Workflow.Creators` et `Workflow.Approvers` est un approbateur : ses
  GPO n'attendent pas d'approbation. Gardez les groupes séparés ;
- le propriétaire d'un fichier du journal d'audit central peut le réécrire : le journal du système
  (SIEM) garde une copie de chaque modification.
