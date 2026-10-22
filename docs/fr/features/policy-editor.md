# Éditeur de stratégies

**Edit** sur une GPO l'ouvre dans l'éditeur de stratégies. Le bandeau dit quelle GPO est modifiée ;
chaque paramètre est lu dans la GPO, et **Apply** l'y enregistre.

![L'éditeur de stratégies](../assets/screenshots/10-editor-policy.fr.png)

L'arbre est celui de l'éditeur de stratégie de groupe : **Configuration ordinateur** et
**Configuration utilisateur**, avec chacune :

- **Stratégies** :
    - **Paramètres Windows > Paramètres de sécurité** (ordinateur) : les paramètres de sécurité de
      `GptTmpl.inf` ;
    - **Modèles d'administration** : les stratégies des fichiers ADMX chargés, par catégorie ;
- **Préférences** : les [préférences de stratégie de groupe](preferences.md).

**Configured settings only** ne garde que ce que la GPO configure : le moyen le plus rapide de lire
une GPO.

## Modèles d'administration

Une stratégie a trois états, comme dans l'éditeur de stratégie de groupe de Windows : **Not
configured**, **Enabled**, **Disabled**. Ses options viennent de sa présentation ADMX, dans l'ordre
de l'ADML :

| Élément ADMX | Formulaire |
|---|---|
| `boolean` | case à cocher |
| `enum` | liste déroulante (la valeur par défaut de l'ADML quand rien n'est choisi) |
| `decimal`, `longDecimal` | nombre, avec ses bornes |
| `text` | texte, obligatoire ou non, avec sa longueur maximale |
| `multiText` | plusieurs lignes (REG_MULTI_SZ) |
| `list` | liste nom/valeur, avec `valuePrefix`, `additive` et `explicitValue` |

L'aperçu **Registry Preview** montre ce qu'Apply écrit : la clé, la valeur, son type et sa donnée.
L'onglet **Details** montre l'explication de la stratégie, ses plateformes prises en charge et son
fichier ADMX.

**Apply** écrit `Machine\Registry.pol` ou `User\Registry.pol` dans SYSVOL, puis :

- augmente la version de la GPO pour cette étendue, dans `GPT.INI` et dans le `versionNumber` de
  son conteneur, pour que les ordinateurs l'appliquent de nouveau ;
- déclare l'extension côté client des modèles d'administration (et son outil) dans
  `gPCMachineExtensionNames` / `gPCUserExtensionNames`, sans quoi les ordinateurs ignoreraient le
  fichier.

Les valeurs qu'aucune stratégie des ADMX chargés n'explique sont conservées, et montrées comme
**Extra Registry Settings** dans l'onglet Settings.

!!! warning "Une GPO modifiée depuis que la console l'a lue"
    Apply écrit le fichier entier, à partir de la copie lue avec la GPO. Si la version de la GPO
    dans le domaine n'est plus celle que la console a lue (une autre console, GPMC, un script l'a
    modifiée), rien n'est écrit : les autres modifications seraient perdues sans un mot. Rafraîchissez
    (F5) pour relire la GPO telle qu'elle est, puis refaites la modification. GPMC, lui, écrase
    le fichier dans ce cas.

## Paramètres de sécurité

![Les paramètres de sécurité](../assets/screenshots/12-editor-security.fr.png)

189 paramètres de `Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf`, groupés comme dans
l'éditeur de Windows :

| Groupe | Section de GptTmpl.inf | Paramètres |
|---|---|---|
| Stratégies de comptes > mot de passe, verrouillage du compte | `[System Access]` | 15 |
| Stratégies de comptes > Kerberos | `[Kerberos Policy]` | 5 |
| Stratégies locales > audit | `[Event Audit]` | 9 |
| Stratégies locales > attribution des droits utilisateur | `[Privilege Rights]` | 45 |
| Stratégies locales > options de sécurité | `[Registry Values]` | 103 |
| Journal des événements | `[Application Log]`, `[Security Log]`, `[System Log]` | 12 |

Chacun a sa nature (nombre avec ses bornes et son unité, choix, texte, comptes pour les droits
utilisateur), et un lien vers sa documentation Microsoft. Apply écrit `GptTmpl.inf` (en UTF-16,
comme Windows l'écrit), augmente la version ordinateur et déclare l'extension de sécurité.

### Groupes restreints

![Les groupes restreints d'un GPO](../assets/screenshots/38-restricted-groups.fr.png)

**Paramètres de sécurité > Groupes restreints** liste les groupes de `[Group Membership]` dans
`GptTmpl.inf`. **Ajouter un groupe** demande le groupe (`DOMAINE\nom`, ou un SID comme
`*S-1-5-32-544` pour les Administrateurs locaux), puis :

- **Membres de ce groupe** : les ordinateurs ne donnent au groupe que ces membres et retirent les
  autres ; une liste vide retire tous les membres. Décochée, ses membres ne changent pas (pas de
  clé `__Members`) ;
- **Ce groupe est membre de** : les groupes auxquels les ordinateurs l'ajoutent.

**Modifier** et **Supprimer** changent ou retirent un groupe ; un groupe supprimé garde les membres
qu'il a. L'onglet Paramètres les liste (Membres, Membre de). Vérifié sur un membre Windows : les
Utilisateurs du Bureau à distance locaux ont reçu exactement les membres définis.

!!! warning "Un écart avec la GPMC"
    Pour un groupe restreint, la GPMC écrit toujours la liste de ses membres : une liste vide retire
    alors tous les membres du groupe. Dans la console, **Membres de ce groupe** est coché par
    défaut : même comportement. Décochée, la clé `__Members` n'est pas écrite et les membres
    actuels du groupe ne sont pas touchés ; seul **Ce groupe est membre de** s'applique.

### Stratégies de clé publique

![Les autorités de certification racines de confiance d'un GPO](../assets/screenshots/40-public-key-policies.fr.png)

**Paramètres de sécurité > Stratégies de clé publique** a les magasins de certificats de l'éditeur
de stratégie de groupe : pour les ordinateurs, Système de fichiers EFS, Chiffrement de lecteur
BitLocker, Certificat de déverrouillage réseau du chiffrement de lecteur BitLocker, Autorités de
certification racines de confiance, Confiance de l'entreprise, Autorités de certification
intermédiaires, Éditeurs approuvés, Certificats non autorisés, Autorités de certification racines
tierces et Personnes autorisées ; pour les utilisateurs, Confiance de l'entreprise et Personnes
autorisées.

Un magasin liste ses certificats (sujet, émetteur, expiration, empreinte). **Importer** ajoute un
fichier de certificat (`.cer`, `.crt` ou `.pem`, DER ou Base-64), **Supprimer** en retire un. Ce sont
des valeurs du `Registry.pol` de l'étendue
(`Software\Policies\Microsoft\SystemCertificates\<magasin>\Certificates\<empreinte>`, valeur
`Blob`), telles que [MS-GPEF] les décrit ; l'extension Registre les applique, déclarée avec l'outil
des certificats comme le fait la GPMC. Les agents de récupération du **Système de fichiers EFS**
forment aussi l'`EFSBlob` d'EFS, reconstruit à chaque modification ([MS-GPEF] 2.2.1.2). BitLocker
prend ses agents de récupération de données dans **Chiffrement de lecteur BitLocker** (avec la
stratégie qui donne les identificateurs de l'organisation).

Vérifié sur un membre Windows : l'autorité de certification racine est dans le magasin de stratégie
de groupe de l'ordinateur (`certutil -grouppolicy -store Root`), l'agent de récupération EFS dans
son magasin EFS, et l'`EFSBlob` du registre est celui écrit.

Les formats viennent de la spécification de Microsoft :
[\[MS-GPEF\] Message Syntax](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gpef/2816eba2-0079-4650-a152-276334c0745e)
(EFS Recovery Policy, Certificate BLOB, EfsBlob, EfsKey).

### Stratégie d'audit avancée

![Une sous-catégorie de la stratégie d'audit avancée](../assets/screenshots/39-advanced-audit.fr.png)

**Paramètres de sécurité > Configuration avancée de la stratégie d'audit > Stratégies d'audit** a
les 60 sous-catégories de Windows (telles que `auditpol /list /subcategory:*` les donne), dans
leurs 9 catégories (Connexion de compte, Gestion des comptes, Suivi détaillé, Accès DS,
Ouvrir/fermer la session, Accès à l'objet, Changement de stratégie, Utilisation de privilège,
Système). Chacune est non définie, ou audite ses réussites, ses échecs, les deux, ou rien (Pas
d'audit). Appliquer écrit `Machine\Microsoft\Windows NT\Audit\audit.csv` comme l'éditeur de
stratégie de groupe, augmente la version ordinateur et déclare l'extension de la stratégie d'audit
avancée (Audit Policy Configuration) : Windows l'applique à l'actualisation suivante (vérifié avec
`auditpol /get` sur un membre Windows). Les lignes de `audit.csv` que la console ne modifie pas
(options d'audit, audit de l'accès global aux objets) sont gardées telles quelles.

Ne la mélangez pas avec **Stratégies locales > Stratégie d'audit** dans le même domaine : comme
Microsoft le documente, un ordinateur applique alors l'une ou l'autre.

## Recherche et copie

Le champ de recherche trouve les stratégies dont le nom contient le texte saisi (avec
**Configured settings only**, parmi celles que la GPO configure). Le menu contextuel d'une
stratégie copie son nom, son chemin de registre, ou la commande `Get-ItemProperty` qui lit sa
valeur sur un ordinateur.
