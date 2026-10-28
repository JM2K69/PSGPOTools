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
| le magasin central, quand le domaine n'en a pas (il crée des dossiers dans `Policies`) | les créateurs n'ont [aucun droit tant qu'il n'existe pas](#posture) ; la posture dit à qui il est |
| un droit donné à côté du circuit (Group Policy Creator Owners, une GPO ou une UO des contrôleurs de domaine) | [trouvé chaque jour](#posture), envoyé au SIEM |

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

## Le contrôleur de domaine et les versions { #domain-controller }

### La menace

- **Deux contrôleurs de domaine, deux versions** : une GPO est un conteneur de l'annuaire et un
  dossier de SYSVOL, chacun avec sa version (`versionNumber`, `Version=` de `GPT.INI`). Une
  modification faite sur un autre contrôleur que l'émulateur PDC, celui de GPMC, entre en
  concurrence avec celles qui y sont faites ; avec Samba, qui ne réplique pas SYSVOL, les fichiers
  restent sur le contrôleur écrit.
- **Une modification coupée en chemin** : les fichiers étaient écrits d'abord, puis la version de
  l'annuaire. Quand l'annuaire la refusait (la GPO modifiée entre-temps, un droit, le serveur
  parti), SYSVOL gardait les nouveaux fichiers et une version en avance sur l'annuaire : les
  ordinateurs appliquaient une modification que la console disait non enregistrée. Un ordinateur
  pouvait aussi lire un fichier en cours d'écriture.
- **Un ticket Kerberos expiré** (Linux) : SYSVOL et l'annuaire refusent avec des erreurs qui ne le
  disent pas, après une partie de la modification.

### Ce que fait la console

- **L'émulateur PDC** : le domaine est lu depuis l'émulateur PDC (le `fSMORoleOwner` du domaine),
  trouvé par le contrôleur de domaine que l'ordinateur atteint ; les modifications y vont.
  `-Server` sur un autre contrôleur avertit, et la barre d'état dit *pas l'émulateur PDC* ;
  **Changer de contrôleur de domaine...** (clic droit sur le domaine) liste les contrôleurs de
  domaine, l'émulateur PDC d'abord, et relit le domaine depuis celui choisi.
- **Un fichier écrit à côté, puis renommé** sur l'ancien (le chemin UNC sous Windows, `put` puis
  `rename -f` avec `smbclient`) : un ordinateur lit l'ancien fichier ou le nouveau.
- **Remis comme ils étaient** : les fichiers de la GPO sont lus avant la modification ; quand un
  fichier ne peut pas être écrit, ou que l'annuaire refuse la nouvelle version, les fichiers écrits
  sont remis (ou supprimés quand il n'y en avait pas), et l'erreur le dit. La restauration d'une
  sauvegarde fait de même.
- **Les versions des deux** sont affichées dans les détails d'une GPO, comme GPMC (*Version
  utilisateur : 2 (AD), 2 (SYSVOL)*), et une ligne dit quand elles diffèrent.
- **Le ticket** est vérifié (`klist -s`) avant d'atteindre SYSVOL ou l'annuaire depuis Linux :
  *lancez kinit*, rien n'est modifié.

### Testé

`PSGPOTools.Hardening.tests.ps1` et `PSGPOTools.Ldap.tests.ps1` : les fichiers remis dans l'ordre
inverse de leur écriture, un fichier qui n'existait pas supprimé, ce qui n'a pas pu être remis
signalé ; une restauration remise ; le `put` et le `rename -f` de `smbclient`, et l'écriture sur le
fichier avec un `smbclient` qui ne renomme pas sur un fichier ; un ticket expiré refusé avant toute
commande ; le domaine lu depuis son émulateur PDC trouvé par un autre contrôleur, `-Server` sur un
autre averti, le contrôleur trouvé utilisé quand l'émulateur PDC est injoignable ; les contrôleurs
listés, l'émulateur PDC d'abord ; les versions des deux dans les détails, lues une fois par version
de la GPO. `PSGPOTools.Gui.tests.ps1` : **Changer de contrôleur de domaine...** sur le domaine
seulement, le domaine relu depuis celui choisi, la barre d'état mise à jour.

Sur les deux labos (un contrôleur de domaine chacun, donc l'émulateur PDC), l'administrateur écrit
un `Registry.pol` dans une nouvelle GPO, puis l'annuaire refuse la version suivante (une ancienne
valeur qui n'est pas celle de l'annuaire) :

| Étape | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| Le domaine lu sans `-Server` | depuis `dc.hardenbox.labo`, l'émulateur PDC ; la barre d'état le dit | depuis `ADDS.powershell.labo`, l'émulateur PDC ; de même |
| Un `Registry.pol` enregistré | aucun fichier laissé à côté (`smbclient`), versions 1 (AD) et 1 (SYSVOL) | aucun fichier laissé à côté (UNC), les mêmes versions |
| Les détails de la GPO | *0 (AD), 0 (SYSVOL)*, *1 (AD), 1 (SYSVOL)* | de même |
| L'annuaire refuse la version suivante | *not saved... the files of the GPO were put back as they were* ; `Registry.pol` et `GPT.INI` aux mêmes octets qu'avant, version 1 des deux côtés | de même |
| Un cache de tickets sans ticket | *The Kerberos ticket of this session... has expired* : rien n'est écrit | (Windows : la session) |
| Nettoyé | la GPO supprimée | la GPO supprimée |

## La santé des GPO et leur réplication { #health }

### La menace

- **Un contrôleur de domaine en retard sur les autres** : Active Directory réplique l'annuaire,
  DFSR le SYSVOL de Windows, chacun à son rythme ; Samba ne réplique pas SYSVOL. Un ordinateur
  applique la GPO du contrôleur qu'il joint : une autre version, ou aucune, jusqu'à ce qu'ils
  concordent, et rien ne le disait.
- **Une GPO qui ne peut pas s'appliquer** : son dossier ou son `GPT.INI` manquant, une version de
  SYSVOL qui n'est pas celle de l'annuaire, un fichier de paramètres dont la GPO ne déclare pas
  l'extension côté client (écrit par un script, une copie, un outil qui ne la déclare pas) : les
  ordinateurs n'arrivent pas à l'appliquer, ou sautent les paramètres, sans un mot dans la console.
- **Ce qui reste derrière** : un dossier de SYSVOL dont la GPO a été supprimée ailleurs (ou un
  conflit de la réplication), une liaison vers une GPO qui n'existe plus.

### Ce que fait la console

- **`Get-PSGPOReplicationStatus`** : chaque contrôleur de domaine du domaine est lu, son annuaire
  et son SYSVOL (une seule liste de `Policies` ; sous Linux, les `GPT.INI` de toutes les GPO en un
  seul `smbclient`), et comparé à la référence, le contrôleur depuis lequel le domaine a été lu
  (son émulateur PDC) : une ligne par GPO et par contrôleur, *InSync*, *DirectoryDiffers*,
  *SysvolDiffers*, *Missing*, *Extra*, *OrphanFolder* ou *Unreachable*, avec ses versions et ce
  qu'elle signifie.
- **`Test-PSGPOHealth`** : sur la référence, une GPO redirigée, sans son dossier ou son `GPT.INI`,
  ou dont les versions diffèrent (erreurs) ; un fichier de paramètres (`Registry.pol` avec des
  entrées, `GptTmpl.inf`, `audit.csv`, `scripts.ini`, les préférences) dont la GPO ne déclare pas
  l'extension, un dossier sans GPO, une liaison vers une GPO du domaine qui n'existe pas ; les
  autres contrôleurs qui diffèrent, ou qui ne peuvent pas être lus (avertissements). Rien de
  renvoyé : aucun problème.
- **L'onglet État du domaine**, comme celui de GPMC : **Détecter maintenant** montre les
  contrôleurs de domaine (*synchronisé*, *réplication en cours*, *ne peut pas être lu*) et les
  problèmes trouvés ; seulement alors, car il lit chaque contrôleur. Les versions montrées dans
  les détails des GPO sont relues.

Elles ne font que lire : rien n'est modifié.

### Testé

`PSGPOTools.Health.tests.ps1` : trois contrôleurs de domaine simulés (leur annuaire, et leur
SYSVOL par `Read-PSGPOSysvolItem` sous Windows et `smbclient` sous Linux) : chaque état de la
réplication avec ses versions, chaque problème de la référence, un contrôleur qui ne peut pas être
lu, une référence illisible refusée, `-Name` et `-DomainController`, rien de renvoyé pour un
domaine sain ; la liste de `smbclient` (les dossiers des GPO et leurs fichiers, un dossier refusé,
`Policies` refusé), les fichiers qui contiennent des paramètres. `PSGPOTools.Gui.tests.ps1` :
l'onglet **État** sur le domaine seulement, rempli par **Détecter maintenant**, et pourquoi il
n'est pas lu.

Sur les deux labos (un contrôleur de domaine chacun), l'administrateur crée des problèmes exprès :
une GPO dont SYSVOL est en avance sur l'annuaire, avec un `Registry.pol` dont l'extension n'est pas
déclarée ; une GPO sans `GPT.INI` ; un dossier de `Policies` sans GPO :

| Étape | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| Le domaine tel qu'il est | 7 GPO *InSync*, aucun problème (0,4 s) | 6 GPO *InSync*, aucun problème (0,7 s) |
| La GPO en avance sur l'annuaire | *Error, Version* : *user 0, computer 0 in the directory, user 0, computer 1 in SYSVOL* | de même |
| Son `Registry.pol` | *Warning, Extension* : *(Registry Policy) for the computers* | de même |
| La GPO sans `GPT.INI` | *Error, Folder* : *the folder of the GPO has no GPT.INI* | de même |
| Le dossier sans GPO | *Warning, OrphanFolder* | de même |
| Autre chose | rien | rien |
| `Get-PSGPOReplicationStatus` | les deux GPO *SysvolDiffers*, le dossier *OrphanFolder* | de même |
| Nettoyé | les GPO et le dossier supprimés, plus aucun problème | de même |

## La posture de sécurité { #posture }

### La menace

- **Des droits donnés à côté du circuit** : le circuit ne tient que si personne d'autre ne crée,
  ne modifie ou ne lie de GPO. Un membre de Group Policy Creator Owners crée des GPO qui
  s'appliquent aussitôt, et en est propriétaire. Un droit sur `CN=Policies`, sur une GPO liée au
  domaine ou aux contrôleurs de domaine, ou sur leur `gPLink`, donné une fois pour une migration ou
  un outil puis oublié, donne les contrôleurs de domaine à un compte hors du Tier 0.
- **Le magasin central pris le premier** : les créateurs créent des dossiers dans le dossier
  `Policies` de SYSVOL (les dossiers de leurs GPO). Là où le domaine n'a pas encore de magasin
  central, un créateur peut créer `Policies\PolicyDefinitions` et en être propriétaire : chaque
  console du domaine lit alors ses fichiers ADMX, qui disent ce qu'écrit chaque stratégie, et où.
- **Personne ne regarde** : ces droits sont dans les descripteurs de l'annuaire et les ACL de
  SYSVOL, que personne ne relit une fois donnés.

### Ce que fait la console

- **`Test-PSGPOSecurityPosture`** lit le propriétaire et la DACL de `CN=Policies`, de chaque GPO,
  du domaine et de chaque UO, les membres de Group Policy Creator Owners, et les ACL du dossier
  `Policies`, du magasin central et de la configuration de HGPM dans SYSVOL. Il dit ce qu'un compte
  hors du Tier 0 peut y faire (*High*) : créer des GPO hors des créateurs, modifier une GPO qui
  s'applique aux contrôleurs de domaine, lier des GPO au domaine ou à leur UO, posséder ou modifier
  ces dossiers ; et ce qu'un groupe de tous les comptes peut faire où que ce soit. *Medium* : pas de
  magasin central alors que les créateurs créent des dossiers. *Low* : le circuit désactivé, pas de
  journal d'audit central, rien dans le journal du système. Le Tier 0, ce sont les groupes que le
  domaine protège (AdminSDHolder), les approbateurs, le propriétaire des GPO approuvées, et les
  comptes de leurs groupes. Les attributs qui comptent (`gPLink`, `gPOptions`, ceux d'une GPO qui
  changent ce qui s'applique) sont lus dans le schéma. Il ne fait que lire : un compte sans groupe
  le lance, un gMSA dans une [tâche quotidienne](../getting-started/production.md#the-posture-each-day).
- **`-SystemLog`** : un résumé (événement 4000) et chaque constat *High* (événement 4001) dans le
  [journal du système](../features/audit-log.md#le-journal-du-systeme-pour-un-siem), pour un SIEM.
- **`Initialize-PSGPOWorkflow`** ne donne rien aux créateurs tant que le magasin central manque :
  il s'arrête, et dit pourquoi (un script qui délègue s'arrête aussi). Il ne le crée pas : un
  magasin central vide cache les modèles d'administration de GPMC
  (`Install-PSGPOAdmx -CentralStore` le remplit). Sa dernière ligne dit si le Tier 0 en est
  propriétaire, et sinon comment le reprendre.

### Testé

`PSGPOTools.Posture.tests.ps1` : un domaine tel que le circuit le laisse, rien de trouvé ; chaque
droit trop large dans l'annuaire et dans SYSVOL trouvé, avec le compte nommé ; un compte d'un
groupe de Domain Admins est du Tier 0 ; un droit sur un autre attribut (le nom d'une GPO,
`msDS-KeyCredentialLink` de Key Admins) ne compte pas, et chaque attribut compte quand le schéma ne
peut pas être lu ; le résumé et chaque constat *High* dans le journal du système.
`PSGPOTools.Workflow.tests.ps1` : sans magasin central, `-Apply` ne change rien et s'arrête, un
script avec lui ; il avertit quand les créateurs créent déjà des dossiers ; le propriétaire du magasin central nommé.
`PSGPOTools.Ldap.tests.ps1`, sur le contrôleur de domaine Samba de la CI : le script du lab refusé
sans magasin central, puis la délégation du lab, et aucun constat *High*.

Sur les deux labs, des problèmes faits exprès, puis défaits :

| Étape | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| Le domaine tel qu'il est | *Medium, CentralStore* : pas de magasin central alors que les créateurs créent des dossiers (0,5 s ; la même chose avec `tiers2`, un compte d'aucun autre groupe) | aucun constat (0,5 s) : le magasin central existe, à Administrators |
| `Initialize-PSGPOWorkflow` | le magasin central *Missing*, et pourquoi | le magasin central *Present* [Administrators] |
| `tiers1` crée le magasin central | *High, CentralStore* [tiers1] ; `Initialize-PSGPOWorkflow` : *Missing* [tiers1], et comment le reprendre | (le magasin central existe : aucun technicien ne peut le créer) |
| Domain Users peut modifier une GPO | *High, GpoEditableByAll* [Domain Users] | la même chose |
| `GPO-Tier1-Admins` peut lier des GPO à l'UO des contrôleurs de domaine | *High, Tier0Link* [GPO-Tier1-Admins] | la même chose |
| `tiers1` dans Group Policy Creator Owners | *High, GroupPolicyCreatorOwners* [tiers1] | la même chose |
| `-SystemLog` | journald : `[4000] ... 4 high, 0 medium, 0 low`, quatre lignes `[4001]` | le journal d'événements : 4000 *Warning* `... 3 high, 0 medium, 0 low`, trois événements 4001 |
| Défait | le seul constat d'avant | aucun constat, comme avant |

## La chaîne de livraison { #supply-chain }

### La menace

- **Un paquet qui n'est pas celui testé** : la release reconstruisait le module, sur une autre
  machine, à un autre moment ; les tests exécutaient une autre construction. Rien ne permettait de
  vérifier qu'un module avait été construit depuis les sources de son tag.
- **Un runtime modifié après son installation** : les assemblies Avalonia, vérifiées au
  téléchargement, étaient ensuite chargées depuis un dossier où l'on peut écrire plus tard (le
  dossier du module, le dossier de données de l'utilisateur). Une bibliothèque remplacée ou ajoutée
  là s'exécute dans la console d'un administrateur du domaine.
- **Les outils de la CI qui changent seuls** : une action déplacée sous son tag, une nouvelle
  version de Pester ou du générateur du site, un jeton des tests qui pouvait écrire dans le dépôt.
- **Les ordinateurs sans internet** : le seul chemin vers le runtime était un dossier copié à la
  main, vérifié par rien.

### Ce que fait la console

- **Une seule construction, reproductible** : pas de date, les sources dans l'ordre de leurs noms,
  des fins de ligne LF : les mêmes octets depuis les mêmes sources, sous Windows et sous Linux. Le
  job `build` de la CI fait le module, les autres jobs testent celui-là, le job Windows le
  reconstruit et compare, et la release publie celui-là ([tests](tests.md#ci)).
- **SHA256SUMS et une attestation** : chaque release liste le SHA-256 de chaque fichier du module et
  de chaque archive, attestés par GitHub (`actions/attest`, Sigstore) : `gh attestation verify` dit
  qu'un fichier a été construit par le workflow de release depuis le commit du tag.
- **Authenticode, quand le certificat est donné** : les scripts du module signés et horodatés, et
  le catalogue `HGPM.cat` de tous ses fichiers (`Test-FileCatalog`) ; le certificat est un secret de
  l'environnement de la release.
- **Des archives hors ligne** : le module avec le runtime Avalonia de chaque plateforme, pour les
  ordinateurs sans internet ([installation hors ligne](../getting-started/offline.md)).
- **Le runtime épinglé fichier par fichier** : le SHA-256 de chaque fichier de chaque runtime est
  dans le module ; la console les vérifie à chaque chargement du runtime, et refuse une bibliothèque
  ajoutée à côté, avant que rien ne soit chargé. Les paquets, de nuget.org, d'un flux interne ou
  d'un dossier (`PSGPOTOOLS_NUGET_SOURCE`), sont vérifiés avec leur SHA-512 comme avant.
- **La CI épinglée et en lecture seule** : chaque action épinglée à un commit (Dependabot propose
  les nouvelles), Pester, PSScriptAnalyzer et le générateur du site à une version ; les jobs des
  tests ne font que lire le dépôt, le job qui publie a les droits dont il a besoin et les secrets de
  son environnement.

### Testé

`PSGPOTools.Release.tests.ps1` : la construction donne les mêmes octets dans deux cultures, et le
module du dépôt ; pas de date, LF, pas de BOM, les sources dans l'ordre de leurs noms ; le paquet
sans le runtime, avec sa licence ; son archive et `SHA256SUMS`, chaque ligne vérifiée ; un dossier
non vide refusé ; sous Windows, les scripts et le catalogue signés avec un certificat fait pour le
test, le catalogue en échec dès qu'un fichier change ; chaque action des workflows épinglée à un
commit, les modules des tests à une version, les droits de chaque workflow, la release qui publie le
module des tests. `PSGPOTools.AvaloniaInstall.tests.ps1` : chaque fichier de chaque runtime épinglé ;
un fichier qui n'est pas celui épinglé n'installe rien ; les paquets depuis un dossier (à plat,
comme un flux, quelle que soit la casse) et depuis un flux (son index lu) ; un téléchargement essayé
trois fois, puis signalé ; un runtime avec un fichier modifié, manquant, ou une bibliothèque ajoutée
refusé.

Sur les deux labos, l'archive hors ligne de la plateforme (faite par `CI/05_Package.ps1`),
installée comme [la page](../getting-started/offline.md) le dit, sans internet :

| Étape | hardenbox.labo (Linux) | powershell.labo (Windows) |
|---|---|---|
| L'archive et chaque fichier du module comparés à `SHA256SUMS` | identiques (61 fichiers) | identiques (61 fichiers) |
| La console ouverte, le runtime de l'archive chargé | oui, depuis `Avalonia/bin/linux-x64` | oui, depuis `Avalonia/bin/win-x64` |
| Un octet de `Avalonia.Base.dll` modifié | *Avalonia.Base.dll differs: nothing of it is loaded*, aucune assembly chargée | de même |
| Une bibliothèque ajoutée à côté du runtime | *libextra.so is not part of it*, aucune assembly chargée | *version.dll is not part of it*, aucune assembly chargée |
| Le runtime depuis un dossier de fichiers `.nupkg` | installé (15 paquets) | (Linux seulement) |
| Un paquet de ce dossier altéré | *SHA-512 differs: nothing is installed* | (Linux seulement) |

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
  avec une nouvelle chaîne. Le journal du système (SIEM) garde une copie de chaque modification ;
- `Test-PSGPOSecurityPosture` lit les groupes d'un compte (`tokenGroups`) : un groupe qu'il ne
  peut pas lire compte comme hors du Tier 0 (un constat à vérifier, jamais un constat manqué). Les
  liens des sites (`CN=Sites`) ne sont pas encore vérifiés ;
- `Test-PSGPOHealth` ne compare pas les permissions du dossier d'une GPO dans SYSVOL avec celles de
  l'annuaire (*les autorisations de cet objet GPO dans le dossier SYSVOL ne sont pas cohérentes*
  de GPMC), et les contrôleurs de domaine sont comparés à la référence, pas répliqués : un
  contrôleur en retard le reste jusqu'à ce que la réplication (ou une copie de SYSVOL avec Samba)
  le rattrape.
