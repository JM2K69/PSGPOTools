# Modèle de sécurité

HGPM est une console du Tier 0 que les techniciens du Tier 1 et du Tier 2 utilisent aussi. Il
n'ajoute ni service ni compte à lui : ce qu'un compte peut faire, c'est ce que le domaine le laisse
faire. Cette page dit ce que HGPM protège, ce sur quoi il s'appuie, et ce que les administrateurs
du domaine doivent protéger ; le [durcissement](hardening.md) dit ce qui a été testé, et
[SECURITY.md](https://github.com/JM2K69/PSGPOTools/blob/master/SECURITY.md) comment signaler une
faille.

## Les tiers

| Tier | Qui | Fait avec HGPM |
|---|---|---|
| **Tier 0** | les administrateurs du domaine, les approbateurs (`Workflow.Approvers`), le propriétaire des GPO approuvées, les purgeurs du journal d'audit (`Audit.Purgers`) | configure HGPM pour le domaine, approuve les GPO, en est propriétaire une fois approuvées, garde les sauvegardes et les archives |
| **Tier 1, Tier 2** | les créateurs (`Workflow.Creators`), les groupes de `Audit.Tiers` | créent des GPO qui attendent une approbation, les lient aux UO de leur tier, lisent le journal d'audit de leur tier |
| **Lecteurs** | les auditeurs (`Audit.Readers`) | lisent tout le journal d'audit |
| **Sans tier** | tout autre utilisateur du domaine | lit ce que le domaine le laisse lire ; écrit ses modifications, s'il en fait, dans `Unassigned` |

La frontière, c'est l'approbation : une GPO d'un technicien ne s'applique à personne tant que le
Tier 0 ne l'a pas approuvée, et elle est au Tier 0 ensuite.

## Les actifs

| Actif | Qui l'écrit | La menace | Ce que fait HGPM | Ce que protègent les administrateurs |
|---|---|---|---|---|
| Une GPO en attente d'approbation | son créateur (il en est propriétaire) | elle s'applique avant son approbation ; elle pointe vers un autre dossier ; elle change après son examen | retire « Apply Group Policy » ; refuse une GPO redirigée vers un autre dossier ; approuve ce qui a été examiné, ou rien ([durcissement](hardening.md#approval)) | ne donnez aux créateurs le droit de lier que là où leurs GPO peuvent s'appliquer |
| Une GPO approuvée | le Tier 0 ; les créateurs en `EditSettings` | le créateur la reprend | la donne, elle et son dossier SYSVOL, au Tier 0, reconstruit ses permissions, refuse `gPCFileSysPath` aux créateurs | choisissez `ReadOnly` sauf si les créateurs doivent garder la main ; surveillez la dérive |
| Les groupes de filtrage (`APPLY_`, `DENY_`) | qui gère leurs membres | un technicien les crée avant l'approbation, ou y ajoute ses serveurs | ne propose que des groupes dont le Tier 0 est propriétaire | gérez leurs membres au Tier 0, ou déléguez-les en connaissance de cause |
| La configuration (`SYSVOL\<domaine>\PSGPOTools`) | les administrateurs du domaine | une autre console, une autre version, une copie manquante (Samba ne réplique pas SYSVOL) | la lit comme des données ; échoue en sécurité quand il ne peut pas l'utiliser ([durcissement](hardening.md#configuration-fails-closed)) ; vérifie les rôles | seul le Tier 0 écrit le dossier ; chaque contrôleur de domaine l'a ; `Console.MinimumVersion` une fois les consoles à jour |
| La délégation de la création de GPO | `Initialize-PSGPOWorkflow -Apply` | Group Policy Creator Owners, dont les GPO contournent le circuit | n'utilise jamais Group Policy Creator Owners | gardez Group Policy Creator Owners vide |
| Le journal d'audit (`Audit.Path`) | chaque compte, son propre fichier | un technicien réécrit ses lignes, écrit au nom d'un autre, un partage injoignable les perd | ajout seul, lignes chaînées vérifiées à la lecture, le journal du système d'abord, une file locale ([durcissement](hardening.md#audit-log)) | envoyez le journal du système à un SIEM ; les purgeurs au Tier 0 |
| Les sauvegardes (`Backup.Path`) | le Tier 0 | une sauvegarde modifiée, puis restaurée | vérifie leur SHA-256 et leurs chemins ; Tier 0 seulement | seul le Tier 0 écrit le partage |
| Le poste d'administration | son utilisateur | un module malveillant, un ticket volé | un LDAP signé, un SMB signé sous Linux, aucun mot de passe en LDAP en clair ; le runtime Avalonia vérifié par son SHA-512 | un poste d'administration par tier, le module depuis la Gallery |

## Ce sur quoi HGPM s'appuie

- **Le domaine calcule les droits.** La console montre ce que le domaine dit que le compte peut
  faire (`allowedAttributesEffective`, `tokenGroups`) et le contrôleur de domaine refuse le reste.
  HGPM n'est pas une barrière à lui seul : un compte qui peut écrire une GPO avec un autre outil
  peut le faire sans HGPM. HGPM rend le circuit sûr pour qui le suit, et visible pour qui ne le suit
  pas (l'approbation reconstruit, la dérive et le journal d'audit montrent).
- **SYSVOL, les partages et leurs permissions** sont aux serveurs de fichiers. HGPM écrit les
  permissions dont il a besoin (`Initialize-PSGPOWorkflow`, `Initialize-PSGPOAuditShare`,
  `Initialize-PSGPOBackupShare`) et les vérifie là où il le peut.
- **Kerberos** : les tickets des comptes, sous Linux aussi (`kinit`). HGPM ne garde aucun mot de
  passe.

## Non couvert

- **Le propriétaire d'une GPO en attente** peut encore rendre « Apply Group Policy » avec un autre
  outil : HGPM le dit en rouge et l'approbation le retire, mais ne l'empêche pas.
- **Les créateurs en `EditSettings`** modifient une GPO approuvée sans nouvelle approbation : la
  dérive le montre.
- **Sous Samba**, le propriétaire d'un fichier du journal d'audit peut encore y écrire avec un outil
  qui l'ouvre en ajout : la chaîne montre une ligne modifiée, le journal du système en garde une
  copie.
- **Un Domain Admin** peut tout faire, HGPM compris : protégez le Tier 0 comme le domaine l'exige.
- **Le module lui-même** n'est pas encore signé ; installez-le depuis la PowerShell Gallery, sur
  les postes d'administration seulement.
