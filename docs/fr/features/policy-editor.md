# Éditeur de stratégies

**Edit** sur une GPO l'ouvre dans l'éditeur de stratégies. Le bandeau dit quelle GPO est modifiée ;
chaque paramètre est lu dans la GPO, et **Apply** l'y enregistre.

![L'éditeur de stratégies](../assets/screenshots/10-editor-policy.png)

L'arbre a les deux étendues d'une GPO, **Machine** (Configuration ordinateur) et **User**
(Configuration utilisateur), avec chacune :

- **Windows Settings > Security Settings** (ordinateur) : les paramètres de sécurité de
  `GptTmpl.inf` ;
- **les modèles d'administration** des fichiers ADMX chargés, par catégorie ;
- **Preferences** : les [préférences de stratégie de groupe](preferences.md).

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

![Les paramètres de sécurité](../assets/screenshots/12-editor-security.png)

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

## Recherche et copie

Le champ de recherche trouve les stratégies dont le nom contient le texte saisi (avec
**Configured settings only**, parmi celles que la GPO configure). Le menu contextuel d'une
stratégie copie son nom, son chemin de registre, ou la commande `Get-ItemProperty` qui lit sa
valeur sur un ordinateur.
