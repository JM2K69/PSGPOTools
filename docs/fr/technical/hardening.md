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
| le contenu de sa GPO jusqu'à l'approbation | l'approbation [approuve ce qui a été examiné](#approval), ou rien ; elle sauvegarde la version approuvée, et la dérive montre tout changement ensuite |
| des paramètres que la console ne peut pas montrer (une extension côté client qu'elle ne lit pas, un fichier, un script de démarrage) | [listés là où la GPO est examinée](#what-the-approver-sees), et vérifiés avant son approbation |
| les groupes qu'il peut créer (`APPLY_<sa GPO>`) | un groupe qu'aucun compte du Tier 0 n'a créé [n'est pas proposé](#approval) à l'approbation |
| la configuration des rôles | [des rôles qui se chevauchent, ou un groupe de tous les comptes](#approval), arrêtent le circuit |
| une sauvegarde sur un partage qu'il peut écrire | les [chemins des fichiers](#other-guards) d'une sauvegarde sont vérifiés |
| une console plus ancienne, un contrôleur de domaine sans la configuration | la [configuration échoue en sécurité](#configuration-fails-closed) |
| son propre fichier du journal d'audit central | [ajout seul, chaîné, vérifié à la lecture](#audit-log) ; rien de perdu quand le partage est injoignable |

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

## L'approbation { #approval }

### La menace

- **Ce qui est approuvé n'est pas ce qui a été examiné** : le créateur est propriétaire de sa GPO
  en attente jusqu'à la fin de l'approbation, et pourrait changer ses paramètres, fichiers ou
  attributs entre l'examen et le clic : le Tier 0 approuverait ce que personne n'a vu.
- **Un groupe créé d'avance** : un technicien qui peut créer des groupes crée `APPLY_<sa GPO>`
  avant l'approbation ; l'approbation le proposait, et ses membres (que le technicien choisit)
  décideraient où la GPO approuvée s'applique.
- **Des rôles qui se chevauchent** : un compte à la fois dans `Workflow.Creators` et
  `Workflow.Approvers` est un approbateur, donc les GPO qu'il crée sont approuvées d'emblée ; un
  groupe de tous les comptes (Domain Users, Authenticated Users) comme créateurs ou approbateurs ;
  un propriétaire des GPO approuvées du Tier 1, qui pourrait alors changer les permissions de
  toutes les GPO approuvées.

### Ce que fait la console

- **Le contenu examiné est le contenu approuvé** : le formulaire d'approbation prend un SHA-256 de
  la GPO à son ouverture (`Get-PSGPOReviewStamp`) : les attributs qui la font appliquer
  (`versionNumber`, `flags`, les extensions côté client, le filtre WMI, `gPCFileSysPath`), relus
  dans le domaine, et chaque fichier de son dossier SYSVOL. `Approve-PSGPO` le prend avant sa
  confirmation. L'approbation donne d'abord le dossier SYSVOL au Tier 0, pour que le créateur ne
  puisse plus l'écrire, puis le reprend : s'il diffère, *la GPO a changé depuis son examen*, elle
  n'est pas approuvée et reste en attente, son dossier donné au Tier 0. L'approbateur l'examine
  à nouveau.
- **Les groupes proposés** : `APPLY_<GPO>` et `DENY_<GPO>` ne sont proposés que si un approbateur
  ou un administrateur du domaine en est propriétaire. Sinon le formulaire dit à qui il
  appartient, ne propose personne (pas Authenticated Users à sa place) et ne les crée pas ;
  `Approve-PSGPO` refuse sans `-ApplyTo`.
- **Les rôles** : la configuration refuse un groupe dans les deux rôles, et un groupe de tous les
  comptes (par son nom) ; le circuit les vérifie à nouveau par SID une fois trouvés dans le
  domaine, avec le propriétaire des GPO approuvées, qui doit être un approbateur ou un
  administrateur du domaine. Des rôles faux arrêtent le circuit : personne n'approuve, les comptes
  qui ne sont pas administrateurs ne créent aucune GPO.

### Testé

`PSGPOTools.Hardening.tests.ps1`, `PSGPOTools.Workflow.tests.ps1` et
`PSGPOTools.Configuration.tests.ps1` :

- une GPO modifiée depuis son examen n'est pas approuvée, rien n'est écrit dans l'annuaire une fois
  SYSVOL donné au Tier 0 ; le même contenu est approuvé ;
- l'empreinte change avec la version, le filtre WMI, un fichier de la GPO ;
- un groupe dont un approbateur est propriétaire est proposé ; un groupe d'un technicien ne l'est
  pas, et le formulaire dit pourquoi ;
- le circuit s'arrête sur : un compte dans les deux rôles, Domain Users comme créateurs,
  Authenticated Users comme approbateurs, les créateurs comme propriétaire des GPO approuvées ; la
  configuration refuse un groupe dans les deux rôles, et Domain Users comme créateurs.

La CI lance l'approbation avec les deux comptes à chaque modification, contre son contrôleur Samba
(*Approval written to a domain controller*, [tests](tests.md#face-a-un-controleur-de-domaine)). Sur
les deux labs, `tiers1` (créateur) et l'administrateur (approbateur) :

| Étape | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| `tiers1` crée une GPO, l'administrateur ouvre son approbation (l'empreinte) | oui | oui |
| `tiers1` la modifie ensuite (son Registry.pol) | permis | permis |
| L'administrateur l'approuve avec l'empreinte de son examen | **refusé** : *a changé depuis son examen*, toujours en attente | **refusé** : *a changé depuis son examen*, toujours en attente |
| Un groupe `APPLY_<GPO>` dont `tiers1` est propriétaire | pas proposé, `Approve-PSGPO` refuse | pas proposé, `Approve-PSGPO` refuse |
| Le groupe supprimé, la GPO examinée à nouveau et approuvée | approuvée, propriété de Domain Admins | approuvée, propriété de Domain Admins |
| `GPO-Tier1-Admins` dans les deux rôles : `tiers1` | *le circuit d'approbation est inconnu* : aucune GPO créée | *le circuit d'approbation est inconnu* : aucune GPO créée |
| La configuration restaurée | les mêmes octets | les mêmes octets |

## Ce que voit l'approbateur { #what-the-approver-sees }

### La menace

- **Un paramètre que la console ne montre pas** : les ordinateurs appliquent chaque extension côté
  client qu'une GPO déclare, chacune avec ses propres fichiers ou objets (Redirection de dossiers,
  Installation de logiciels, Sécurité IP, une extension d'un éditeur...). Un technicien en ajoute
  une à sa GPO en attente ; l'approbateur examine les paramètres que la console liste, et approuve
  les autres sans les avoir vus.
- **Un script de démarrage** : il s'exécute en tant que SYSTEM sur chaque ordinateur auquel la GPO
  s'applique. Sa liste (`scripts.ini`, `psscripts.ini`) n'était pas lue, et son fichier pouvait
  changer entre deux versions sans qu'aucun changement n'apparaisse.

### Ce que fait la console

- **Ce qu'elle n'interprète pas est listé** : une extension côté client dont elle ne lit pas les
  paramètres (par son nom quand elle la connaît, par son GUID sinon), et chaque fichier du dossier
  de la GPO qu'aucun de ses lecteurs ne lit (par sa taille et son SHA-256 ; ni ses commentaires ni
  les modèles ADM copiés là, qui n'appliquent rien). Dans l'onglet **Paramètres**, dans un cadre à
  part ; dans les détails de la GPO (*Non interprété*, d'après ses extensions, sans lire SYSVOL) ;
  dans son rapport (`Get-PSGPOReport`, *Enregistrer le rapport...*) ; dans une comparaison de deux
  sauvegardes, pour les extensions.
- **L'approbation le demande** : le formulaire d'approbation les liste, et n'approuve qu'une fois
  *J'ai vérifié ces paramètres avec GPMC, ou dans les fichiers de la GPO* cochée ; `Approve-PSGPO`
  les cite dans un avertissement et dans sa confirmation. Ils viennent de la même lecture du
  dossier que l'empreinte de l'examen ([l'approbation](#approval)).
- **Les scripts sont lus** : chaque script de démarrage, d'arrêt, d'ouverture et de fermeture de
  session avec ses paramètres, si les scripts PowerShell s'exécutent en premier, et le fichier
  qu'il exécute dans la GPO avec sa taille et son SHA-256 : un changement de son contenu apparaît
  quand deux sauvegardes sont comparées, et l'éditeur montre son contenu avant qu'il soit approuvé.
  Un fichier des dossiers des scripts qu'aucun script n'exécute est listé aussi.

### Testé

`PSGPOTools.Report.tests.ps1` et `PSGPOTools.Gui.tests.ps1` : `scripts.ini` et `psscripts.ini`
lus et écrits comme l'éditeur de stratégie de groupe les écrit (UTF-16, numérotés depuis 0, les
autres clés gardées) ; un script hors de la GPO (`\\serveur\partage`, un lecteur, `%`, `..`)
n'y est pas cherché ; un changement du fichier d'un script apparaît dans une comparaison ; les
extensions et fichiers non interprétés listés dans leur ordre, les fichiers qui n'appliquent rien
laissés de côté ; le formulaire d'approbation refuse tant que la case n'est pas cochée ; le
rapport en objet, XML et HTML.

Sur les deux labs, l'administrateur écrit une GPO avec des scripts, `tiers1` ajoute la
Redirection de dossiers à sa GPO en attente, l'administrateur l'approuve :

| Étape | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| Un script de démarrage, un script PowerShell de démarrage exécuté en premier, un script d'ouverture de session hors de la GPO | écrits dans SYSVOL en UTF-16, une seule hausse de version par configuration, l'extension des scripts déclarée | de même |
| Relus depuis le domaine, le rapport (objet, HTML, XML) | les 4 scripts, leurs fichiers et SHA-256 | de même |
| `gpupdate` sur l'ordinateur membre | (pas de membre Windows) | l'ordinateur enregistre les deux scripts de démarrage, le PowerShell en premier (`PSScriptOrder=2`) |
| `Get-GPOReport` de GPMC | | l'extension *Scripts* des deux configurations, les 3 scripts, `RunPSFirst` |
| Le fichier d'un script changé entre deux sauvegardes | `Compare-PSGPOBackup` : *Changed*, sa taille et son SHA-256 | de même |
| `tiers1` ajoute la Redirection de dossiers (`fdeploy1.ini`) à sa GPO en attente | listés : l'extension et le fichier | de même |
| `Approve-PSGPO -WhatIf`, puis l'approbation | l'avertissement et la confirmation citent les deux ; approuvée | de même |
| Nettoyé | les deux GPO supprimées | les deux GPO supprimées, `gpupdate` : plus aucun script de démarrage |

`Approve-PSGPO -WhatIf` sous Linux ne lisait pas la GPO avant (le dossier temporaire de sa copie
n'était pas créé sous `-WhatIf`) : corrigé, avec un test.

## Le journal d'audit { #audit-log }

### La menace

Le journal d'audit est une preuve, écrite par les comptes qu'il surveille. Jusqu'à 0.1.14 :

- le propriétaire d'un fichier pouvait l'écraser (`FILE_WRITE_DATA`) : un technicien réécrivait ou
  vidait ses propres lignes ;
- `Account`, `Tier` et `Computer` sont ce que la console a écrit : un technicien du Tier 2 pouvait
  écrire dans son fichier une ligne « Tier 0, Administrator », que le lecteur montrait telle quelle ;
- n'importe quel compte du domaine, ordinateurs compris, créait des fichiers dans `Unassigned` ;
- un technicien du même tier pouvait créer d'avance le fichier d'un autre compte (son nom est
  connu) : ce compte recevait *accès refusé*, et ses modifications étaient perdues ;
- un partage injoignable perdait la modification, pour le journal central comme pour le SIEM (le
  journal du système était écrit après le partage) ;
- sous Linux, chaque ligne copiait tout le fichier (`smbclient get`, puis `put`).

### Ce que fait la console

[Un journal fiable](../features/audit-log.md#un-journal-fiable) dit tout : ajout seul
(`0x12019d`), des lignes chaînées (`Seq`, `PrevHash`), une **Vérification** de chaque entrée à la
lecture (*Vérifiée*, *Altérée*, *Tier différent*, *Propriétaire différent*, *Non chaînée*), le
journal du système d'abord, les modifications qui attendent dans `audit-waiting.jsonl`, un fichier
d'un nouveau nom quand son nom est pris, `Unassigned` pour Domain Users seulement, et les lignes
importées marquées `ImportedBy`.

### Testé

`PSGPOTools.Audit.tests.ps1` :

- la modification qui ne peut pas être écrite attend, et elle est écrite avant la suivante, dans
  son ordre ; une ligne dont le dossier a disparu n'arrête pas les autres ;
- la modification part au journal du système même quand le partage ne peut pas être écrit ;
- chaque ligne est chaînée ; une ligne modifiée ou retirée au milieu rend la suivante *Altérée* ;
- une ligne du Tier 0 dans le dossier du Tier 1 est *Tier différent* ; un fichier qui appartient à
  un autre compte est *Propriétaire différent*, sauf si ce compte l'a importée ; un fichier
  d'Administrators ne convient qu'à une ligne du Tier 0 ;
- sous Linux, les lignes partent en un appel aux bindings Python, le fichier ouvert en ajout ; un
  fichier de son nom créé par quelqu'un d'autre : un fichier d'un nouveau nom (sous Windows aussi) ;
- le propriétaire d'un fichier ne fait qu'ajouter (`0x12019d`), `Unassigned` est pour Domain Users.

Sur les deux labs, après `Initialize-PSGPOAuditShare` (les fichiers déjà là passés en ajout seul
aussi), `tiers1` sur son propre fichier du mois :

| Étape | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| Une modification (une GPO créée puis supprimée) : ses 3 lignes | chaînées, *Vérifiées* | chaînées, *Vérifiées* |
| Son fichier écrasé (`smbclient put` ; `WriteAllText`) | **refusé** | **refusé** |
| Son fichier supprimé | **refusé** | **refusé** |
| Un octet écrit au milieu avec un handle ouvert en ajout | **écrit** : la ligne suivante est *Altérée* | ajouté à la fin du fichier à la place |
| Le fichier restauré par l'administrateur | à nouveau *Vérifiée* | (l'octet retiré) |
| Les lignes écrites avant 0.1.15 | *Non chaînées* | *Non chaînées* |

Samba laisse un handle ouvert avec `FILE_APPEND_DATA` écrire n'importe où dans le fichier ; Windows
ajoute à la fin quel que soit l'offset donné. La chaîne montre ce que Samba permet.

=== "hardenbox.labo (Samba AD)"

    ![Le journal d'audit, sa colonne Vérification](../assets/screenshots/63-audit-log.fr.png)

=== "powershell.labo (Active Directory)"

    ![Le journal d'audit, sa colonne Vérification](../assets/screenshots/66-audit-log-active-directory.fr.png)

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

- pendant l'attente, le créateur est propriétaire de sa GPO, et peut rendre « Apply Group Policy »
  avec un autre outil : la console le dit en rouge, et l'approbation le retire, mais ne l'empêche
  pas (une ACE pour OWNER RIGHTS le ferait ; le support de Samba est à vérifier d'abord) ;
- les créateurs qui gardent la modification d'une GPO approuvée (`EditSettings`) la changent sans
  nouvelle approbation : la dérive montre chaque changement ;
- sous Samba, le propriétaire d'un fichier du journal d'audit central peut encore y écrire avec un
  outil qui l'ouvre en ajout : la chaîne montre une ligne modifiée, pas un fichier entier réécrit
  avec une nouvelle chaîne. Le journal du système (SIEM) garde une copie de chaque modification.
