# Descripteurs de sécurité

Les classes d'ACL de .NET ne fonctionnent que sous Windows. La console lit et écrit elle-même les
descripteurs de sécurité, sous leur forme auto-relative ([MS-DTYP] 2.4.6), sur toutes les
plateformes : `GPOToolsSecurityDescriptor` et `GPOToolsAce`.

## Le format

| Partie | |
|---|---|
| En-tête | révision 1, drapeaux de contrôle (`SE_DACL_PRESENT`, `SE_DACL_PROTECTED`, `SE_DACL_AUTO_INHERITED`, `SE_SELF_RELATIVE`…), décalages du propriétaire, du groupe, de la SACL, de la DACL |
| Propriétaire, groupe | SID |
| SACL | conservée octet par octet (jamais demandée : elle exige un privilège) |
| DACL | révision 4 (`ACL_REVISION_DS` : elle peut contenir des ACE objet), les ACE |

Une ACE est d'autorisation / de refus (types 0, 1) ou d'autorisation / de refus **objet** (types 5,
6 : avec le GUID d'une propriété, d'un jeu de propriétés, d'une classe ou d'un droit étendu, et de
la classe qui en hérite). Les ACE d'autres types (audit, rappel, conditionnelles) sont conservées
octet par octet. `ToSddl()` écrit la forme SDDL, masques en hexadécimal, pour les journaux et les
tests.

`AddAce` place une ACE là où Windows l'attend : refus explicites, autorisations explicites, puis
les héritées.

## Filtrage de sécurité

[MS-GPOL] 3.2.5.1.6 : un ordinateur ou un utilisateur applique une GPO quand il peut la **lire** et
qu'il a le droit étendu **Appliquer la stratégie de groupe** (`edacfd8f-ffb3-11d1-b41d-00a0c968f939`).

- `GetSecurityFiltering()` : qui l'applique (ACE d'autorisation avec ce droit, ou tous les droits
  étendus), à qui elle est refusée ;
- `SetSecurityFiltering(apply, deny)` : Authenticated Users ne l'applique plus mais garde la lecture
  (MS16-072 : les ordinateurs doivent lire la GPO), le groupe l'applique, l'autre groupe se la voit
  refuser.

## De l'annuaire à SYSVOL

`ConvertToFileSystem()` dérive l'ACL du dossier de la GPO de la DACL de son conteneur, comme
`dsacl2fsacl` de Samba : les ACE d'autorisation, héritées par fichiers et dossiers (`OI CI`),
CREATOR OWNER en héritage seul, les droits de l'annuaire traduits en droits de fichiers
(`ldapmask2filemask`) :

| Annuaire | Fichiers |
|---|---|
| lecture des propriétés + liste (`RP LC`) | lecture et exécution (`0x1000A9` ; `0x1200A9` avec le contrôle de lecture de l'ACE) |
| écriture des propriétés (`WP`) | écriture (`0x100116`) |
| création d'enfants (`CC`) | ajout de fichier, ajout de sous-dossier |
| suppression d'enfants (`DC`) | suppression d'enfant |
| droits standard | conservés (`0x1F0000`) |

## Le workflow d'approbation

| Fonction | Fait |
|---|---|
| `ConvertTo-PSGPOPendingDescriptor` | retire « Appliquer la stratégie de groupe » de chaque ACE (une ACE qui donne d'autres droits les garde), donne aux groupes de créateurs *Edit settings* (`RP WP CC DC LC LO RC`, `0x200B7`) |
| `ConvertTo-PSGPOApprovedDescriptor` | pose le propriétaire, retire les ACE explicites du créateur et des créateurs (les héritées suivent leur parent), et sur la GPO : *Edit settings* pour les créateurs (EditSettings), le filtrage de sécurité choisi |
| `Get-PSGPOExplicitDescriptor` | écarte les ACE héritées avant une écriture : l'annuaire les recalcule depuis le parent |

Le propriétaire compte : un propriétaire peut toujours lire et changer la DACL (`READ_CONTROL`,
`WRITE_DAC` implicites). L'approbation donne la GPO, les objets qu'elle contient et chaque fichier
de son dossier au propriétaire des GPO approuvées.
