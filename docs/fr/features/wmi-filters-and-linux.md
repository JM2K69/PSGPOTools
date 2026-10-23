# Filtres WMI et clients Linux

Un filtre WMI est évalué par l'ordinateur qui applique la GPO, ni par le contrôleur de domaine ni
par la console. Un ordinateur Windows l'évalue ; un ordinateur Linux joint avec Samba, non. Cette
page explique les deux, et ce qu'un client Linux applique d'une GPO.

## Comment fonctionne un filtre WMI

Un filtre WMI est un objet du domaine (`msWMI-Som` dans `CN=SOM,CN=WMIPolicy,CN=System`) avec une
ou plusieurs requêtes WQL, chacune dans un espace de noms WMI (`root\CIMv2` par défaut). Une GPO
nomme son filtre dans `gPCWQLFilter` ; une GPO a au plus un filtre, un filtre sert à autant de GPO
que voulu.

Quand un ordinateur **Windows** traite les stratégies de groupe, pour chaque GPO qui s'applique à
lui (ses liens, l'héritage, le filtrage de sécurité) et qui a un filtre WMI :

1. il exécute chaque requête du filtre sur lui-même, par WMI ;
2. le filtre est **vrai quand chaque requête renvoie au moins une instance** (les requêtes sont
   liées par un ET ; un OU s'écrit dans une seule requête, `WHERE ProductType = 1 OR ProductType = 3`) ;
3. un filtre faux : la GPO n'est pas appliquée (`gpresult` l'indique *Refusé (filtre WMI)*) ; un
   filtre que le domaine n'a plus : la GPO n'est pas appliquée non plus.

Le filtre est évalué à chaque actualisation des stratégies, pour l'ordinateur et pour
l'utilisateur : gardez des requêtes légères (`Win32_OperatingSystem`, `Win32_ComputerSystem`), car
une requête lente ralentit chaque ouverture de session.

| Exemple | Requête |
|---|---|
| Postes de travail | `SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1` |
| Serveurs | `SELECT * FROM Win32_OperatingSystem WHERE ProductType = 3` |
| Windows 11 | `SELECT * FROM Win32_OperatingSystem WHERE Version LIKE '10.0.2%' AND ProductType = 1` |
| Portables | `SELECT * FROM Win32_Battery` |

Samba AD, comme contrôleur de domaine, ne fait que conserver les filtres : les ordinateurs Windows
d'un domaine Samba les évaluent comme dans un domaine Windows. La console les crée, les modifie, les
exporte et les délègue ([filtres WMI](gpo-management.md#les-filtres-wmi)).

## Clients Linux : ce qu'applique samba-gpupdate

Un ordinateur Linux joint au domaine avec Samba (winbind) applique les stratégies de groupe avec
`samba-gpupdate`, quand son `smb.conf` contient `apply group policies = yes` (à chaque actualisation
de winbind, ou à la main : `samba-gpupdate --force` ; `samba-gpupdate --rsop` montre ce qu'il
appliquerait). Il construit la liste des GPO comme Windows, mais vérifie moins de choses, et
n'applique que les paramètres pour lesquels il a une extension côté client.

Ce qui suit a été lu dans le code de Samba 4.22 (Debian 13, `samba/gp/gpclass.py` et les extensions
de `samba/gp/`) ; une autre version de Samba peut différer.

| D'une GPO | Windows | Linux (samba-gpupdate) |
|---|---|---|
| Liens, liens désactivés, liens appliqués, héritage bloqué | oui | oui |
| Filtrage de sécurité : lire la GPO | oui | oui : une GPO que l'ordinateur ne peut pas lire est ignorée |
| Filtrage de sécurité : *Appliquer la stratégie de groupe* (accordé ou refusé) | oui | **non** : une GPO que l'ordinateur lit est appliquée |
| Filtre WMI | oui | **non** : `gPCWQLFilter` est lu, jamais évalué |
| État de la GPO (configuration utilisateur ou ordinateur désactivée) | oui | **non** : `flags` est lu, jamais utilisé |
| Paramètres | les extensions côté client de Windows | **seulement les extensions de Samba** (ci-dessous) |

### Les paramètres qu'applique un client Linux

Les autres paramètres d'une GPO (la plupart des modèles d'administration, les paramètres de
sécurité de Windows, les préférences, les scripts de Windows, la stratégie d'audit avancée...) sont
ignorés par un client Linux.

| Extension de Samba | Lu dans la GPO | Fait |
|---|---|---|
| Droits sudo | `Machine\Registry.pol`, `Software\Policies\Samba\Unix Settings\Sudo Rights` | règles sudoers |
| Scripts | `Software\Policies\Samba\Unix Settings\Daily Scripts` (Hourly, Weekly, Monthly) | scripts dans `/etc/cron.*` ; aussi pour les utilisateurs (`User\Registry.pol`) |
| Messages | `Software\Policies\Samba\Unix Settings\Messages` | `/etc/motd`, `/etc/issue` |
| smb.conf | `Software\Policies\Samba\smb_conf` | options `[global]` de `smb.conf` |
| firewalld | `Software\Policies\Samba\Unix Settings\Firewalld` | zones et règles |
| Firefox | `Software\Policies\Mozilla\Firefox` | les stratégies de Firefox |
| Chromium, Chrome | `Software\Policies\Google\Chrome` | les stratégies gérées et recommandées |
| GNOME | `GNOME Settings\Lock Down Settings` | paramètres dconf et verrous |
| Inscription automatique des certificats | `Software\Policies\Microsoft\Cryptography\AutoEnrollment` | certificats de l'autorité d'entreprise (certmonger) |
| Centrify | `Software\Policies\Centrify\UnixSettings` (SuDo, CrontabEntries) | règles sudo, entrées crontab |
| Lecteurs mappés | `User\Preferences\Drives\Drives.xml` | les lecteurs des utilisateurs |
| VGP (Vintela) | `Machine\VGP\VTLA\...\manifest.xml` | sudoers, fichiers, liens symboliques, OpenSSH, motd, issue, scripts de démarrage, accès à l'hôte |
| Kerberos et accès système | `GptTmpl.inf`, `[Kerberos Policy]` et `[System Access]` | sur un contrôleur de domaine Samba seulement |

`samba-tool gpo manage` écrit ces paramètres (`samba-tool gpo manage sudoers add`, `motd set`,
`scripts startup add`, `symlink add`...), et `samba-tool gpo admxload` met les modèles
d'administration de Samba dans le magasin central, pour l'éditeur de stratégies de la console.

## Pourquoi un test sur un client Linux échoue, et que faire

Une GPO liée à l'OU d'un ordinateur Linux avec un filtre WMI, ou avec des paramètres de Windows
seulement, ne fait pas sous Linux ce qu'elle fait sous Windows. Ce n'est pas un défaut de la
console : le client ne le fait pas.

- **Ciblez les ordinateurs Linux par leur OU**, pas par un filtre WMI : une OU des ordinateurs Linux,
  où sont liées les GPO qui leur sont destinées.
- **Tenez une GPO à l'écart des ordinateurs Linux** en leur refusant la **lecture** de la GPO (un
  groupe des ordinateurs Linux, avec Lire refusé), pas seulement *Appliquer la stratégie de groupe* :
  un groupe de refus créé par la console (`DENY_<GPO>`) refuse *Appliquer la stratégie de groupe*,
  qu'un client Linux ne vérifie pas. Refuser la lecture à un groupe d'ordinateurs Linux seulement ne
  change rien pour les ordinateurs Windows (MS16-072 : ils doivent lire les GPO qu'ils appliquent).
- **L'état de la GPO ne retire pas sa partie utilisateur ou ordinateur à un client Linux** : mettez
  les paramètres pour Linux dans leur propre GPO.
- **Utilisez les paramètres de Samba** pour les ordinateurs Linux (le tableau ci-dessus) : les
  stratégies de Windows ne sont pas traduites. Une requête WQL ne peut pas l'être non plus : Linux
  n'a pas de WMI.
