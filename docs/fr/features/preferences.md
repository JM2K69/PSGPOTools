# Préférences de stratégie de groupe

Le nœud **Preferences** de chaque étendue a les 21 types de préférences de
[MS-GPPREF](https://learn.microsoft.com/fr-fr/openspecs/windows_protocols/ms-gppref/), sous
**Windows Settings** et **Control Panel Settings**, comme l'éditeur de Windows les montre.

![Les préférences Registry d'une GPO](../assets/screenshots/11-editor-preferences.fr.png)

| Windows Settings | Control Panel Settings |
|---|---|
| Applications (utilisateur), Drive Maps (utilisateur), Environment, Files, Folders, Ini Files, Registry, Network Shares (ordinateur), Shortcuts | Data Sources, Devices, Folder Options, Internet Settings (utilisateur), Local Users and Groups, Network Options, Power Options, Printers, Regional Options (utilisateur), Scheduled Tasks, Services (ordinateur), Start Menu (utilisateur) |

## Les éléments

Les éléments d'un type sont listés dans leur ordre. **New**, **Edit**, **Move up / down** et
**Delete** les modifient, avec un formulaire généré d'après le type (schéma [MS-GPPREF]) : les 35
types d'éléments des 21 types de préférences (une imprimante TCP/IP, partagée ou locale ; un groupe
et ses membres ; une tâche planifiée ou immédiate…).

Les options communes de chaque élément sont là aussi : description, arrêter le traitement en cas
d'erreur, exécuter dans le contexte de sécurité de l'utilisateur, supprimer l'élément quand il
n'est plus appliqué.

Ce qu'un élément contient en XML se modifie en XML, vérifié avant d'être écrit : la définition du
Planificateur de tâches d'une tâche (une tâche valide est proposée pour commencer), les valeurs de
registre d'Internet Settings, le contenu d'une application.

## Comment c'est écrit

Le fichier XML du type (`Machine\Preferences\Registry\Registry.xml`…) est lu et écrit avec
`System.Xml`, comme GPMC l'écrit : `clsid` de chaque élément, `uid`, `changed` en UTC, l'image de
l'action. **Ce que la console ne modifie pas est conservé** : le ciblage au niveau de l'élément
(`Filters`), les attributs inconnus.

Ensuite la version de l'étendue augmente, et l'extension côté client du type est déclarée avec son
outil, ainsi que l'outil sous l'extension nulle `{00000000-0000-0000-0000-000000000000}`, comme le
fait GPMC.

!!! danger "Les mots de passe ne sont jamais écrits"
    Les préférences peuvent stocker un mot de passe (`cpassword`), chiffré avec une clé publiée par
    Microsoft : n'importe quel utilisateur du domaine peut le lire (MS14-025). La console n'en écrit
    jamais ; un élément qui en stocke un est signalé, et son mot de passe laissé tel quel.

L'onglet Settings, les sauvegardes et l'historique montrent les éléments de préférences, comparés
élément par élément par leur `uid` (le XML qu'ils contiennent, par son empreinte).
