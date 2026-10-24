# Policy Analyzer

![La tuile Policy Analyzer](../assets/screenshots/60-tile-policy-analyzer.fr.png){ align=right width="170" }

Le [Security Compliance Toolkit](https://www.microsoft.com/download/details.aspx?id=55319) de
Microsoft contient Policy Analyzer : il compare des ensembles de GPO paramètre par paramètre, et
montre les paramètres qu'un ensemble configure deux fois ou avec des valeurs différentes. HGPM fait
la même chose, sous Windows et sous Linux, avec les mêmes fichiers : les fichiers `.PolicyRules`
des baselines de sécurité de Microsoft, et ceux faits par Policy Analyzer ou `GPO2PolicyRules.exe`,
sont lus tels quels, et les fichiers qu'écrit HGPM s'ouvrent dans Policy Analyzer.

## La fenêtre

`Show-PolicyAnalyzerAvalonia` ouvre Policy Analyzer dans une fenêtre à part, comme le fait la
tuile **Policy Analyzer** du lanceur (`Start-HGPM`). Il n'a pas besoin de domaine : les GPO du
domaine sont lues la première fois qu'elles sont demandées (`-Server`, sinon le domaine de
l'ordinateur). Les paramètres sont nommés avec les fichiers ADMX chargés, sinon ceux du magasin
central ou de `%windir%\PolicyDefinitions` (`-PolicyDefinitions` ailleurs) ; sans eux, une valeur
de registre est montrée par sa clé.

```powershell
Show-PolicyAnalyzerAvalonia
Show-PolicyAnalyzerAvalonia -Server dc.contoso.com -Path '.\Windows 11 v25H2 Security Baseline\Documentation'
```

À gauche, les jeux de règles : les fichiers `.PolicyRules` du dossier
*Jeux de règles dans* (`Documents\PolicyAnalyzer` par défaut, comme Policy Analyzer : copiez-y les
fichiers des baselines de sécurité de Microsoft), et les jeux ajoutés avec **GPO du domaine...**
(les GPO choisies, telles qu'elles sont) ou **Sauvegardes GPMC...** (le dossier `GPOs` d'une
baseline). Cochez les jeux à comparer, puis **Afficher / Comparer**.

![Des GPO du domaine comme jeu de règles](../assets/screenshots/54-policy-analyzer-gpos.fr.png)

Le tableau a une ligne par paramètre et une colonne par jeu, avec les couleurs de Policy Analyzer
ci-dessous ; ses colonnes se trient, se déplacent et se redimensionnent comme dans Policy Analyzer.
*Seulement les différences* et *Seulement les conflits* gardent les lignes du menu, la recherche
trouve un paramètre, une valeur ou une GPO. Sous le tableau, le paramètre sélectionné : où GPMC le
montre, sa valeur de registre ou la ligne de son modèle de sécurité, la valeur que lui donne chaque
GPO de chaque jeu, et son explication.

![Une baseline de sécurité de Microsoft et des GPO du domaine comparées](../assets/screenshots/53-policy-analyzer.fr.png)

**Exporter vers Excel...** enregistre les lignes affichées dans un classeur Excel (*Toutes les
données* : avec la valeur de chaque GPO et l'explication de chaque paramètre) ; **Enregistrer en
.PolicyRules...** enregistre le jeu sélectionné dans un fichier que lisent Policy Analyzer et
`LGPO.exe`, par défaut dans le dossier des jeux. Un fichier qui existe est remplacé après un second
clic.

## Jeux de règles

Un jeu de règles, ce sont les paramètres d'une ou plusieurs GPO, pris comme un tout : les
paramètres de registre de leurs fichiers `Registry.pol` (ordinateur et utilisateur), leur modèle
de sécurité (`GptTmpl.inf` : stratégies de comptes, droits utilisateur, options de sécurité,
services, groupes restreints...), leur stratégie d'audit avancée (`audit.csv`) et leurs extensions
côté client. Les préférences et les scripts n'en font pas partie, comme dans Policy Analyzer.

| Jeu de règles fait de | Commande |
|---|---|
| fichiers `.PolicyRules`, ou tous ceux d'un dossier (`Documents\PolicyAnalyzer` pour Policy Analyzer) | `Get-PSGPOPolicyRuleSet -Path` |
| GPO du domaine, telles qu'elles sont | `Get-PSGPOPolicyRuleSet -Name` |
| sauvegardes de HGPM | `Get-PSGPOBackup ... \| Get-PSGPOPolicyRuleSet` |
| sauvegardes de GPMC (le dossier `GPOs` d'une baseline de sécurité) ou de HGPM (leur dossier, une GPO, une sauvegarde) | `Get-PSGPOPolicyRuleSet -BackupPath` |
| les GPO qui s'appliquent à un domaine ou une UO, par priorité | `Get-PSGPOPolicyRuleSet -Container` |
| l'état effectif de cet ordinateur pour les paramètres d'autres jeux (Windows uniquement) | `Get-PSGPOPolicyRuleSet -EffectiveState` |

`Export-PSGPOPolicyRuleSet` enregistre des jeux dans un fichier `.PolicyRules`, comme l'écrit
`GPO2PolicyRules.exe` : Policy Analyzer l'ouvre, et `LGPO.exe /p` l'applique à la stratégie locale
d'un ordinateur. Plusieurs jeux sont fusionnés en un fichier, comme le fait `Merge-PolicyRules.ps1`.

```powershell
# Les GPO du domaine qui durcissent les postes, enregistrées pour Policy Analyzer
Get-PSGPOPolicyRuleSet -Name 'Postes - *' -SetName 'Postes' |
    Export-PSGPOPolicyRuleSet -Path "$HOME\Documents\PolicyAnalyzer\Postes.PolicyRules"

# La baseline de Microsoft, à partir de ses sauvegardes de GPO (ce que contient son fichier .PolicyRules)
Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows 11 v25H2 Security Baseline\GPOs'
```

## Les GPO d'une UO, par priorité

Policy Analyzer ne dit pas quelle GPO d'un jeu l'emporte. HGPM le fait pour les GPO qui
s'appliquent à un domaine ou une UO : `Get-PSGPOPolicyRuleSet -Container`, ou *Les GPO qui
s'appliquent à un domaine ou une UO, par ordre de priorité* dans **GPO du domaine...** de la
fenêtre, les ordonne comme l'onglet *Héritage de stratégie de groupe* de GPMC :

1. les liens appliqués d'abord, du domaine vers l'UO (celui le plus proche du domaine l'emporte) ;
2. puis les autres liens, de l'UO vers le domaine, jusqu'à une UO qui bloque l'héritage (ses
   propres liens compris) ;
3. les liens désactivés, et les GPO dont tous les paramètres sont désactivés, écartés ; les
   paramètres ordinateur ou utilisateur que l'état d'une GPO désactive aussi.

Chaque paramètre montre alors la valeur de la GPO de priorité 1 qui le définit : deux GPO de l'UO
en désaccord ne sont pas un conflit, la priorité tranche (gris clair), et les détails listent
chaque GPO avec sa priorité, celle qui est *appliquée* en premier. Un `**delvals.` d'une GPO plus
prioritaire efface les valeurs de sa clé que les autres écrivent, comme le client les applique
(`[[[Delete all values]]]`). Le filtrage de sécurité, les filtres WMI et le traitement en boucle
dépendent de chaque ordinateur ou utilisateur : ils ne sont pas pris en compte, ni les liens des
sites.

```powershell
$baseline = Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules
$portables = Get-PSGPOPolicyRuleSet -Container 'OU=Laptops,OU=Workstations,DC=contoso,DC=com'
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $portables -ConflictOnly
```

## Comparer des jeux de règles

`Compare-PSGPOPolicyRuleSet` donne une ligne par paramètre configuré par l'un des jeux, et une
colonne par jeu avec sa valeur :

| Cellule | Signification | Dans Excel |
|---|---|---|
| une valeur | le jeu configure le paramètre, une fois | blanc, jaune quand un autre jeu a une autre valeur |
| vide | le jeu ne configure pas le paramètre | gris |
| une valeur, définie plusieurs fois | deux GPO du jeu donnent la même valeur au paramètre | gris clair |
| `***CONFLICT***` | deux GPO du jeu donnent des valeurs différentes au paramètre | jaune |
| `[[[delete]]]` | la GPO supprime la valeur de registre | |
| `[[[Delete all values]]]` | la GPO supprime toutes les valeurs de la clé (avant d'écrire une liste) | |

Une ligne est un **conflit** quand deux jeux, ou deux GPO d'un jeu, donnent des valeurs différentes
au paramètre ; une **différence** quand c'est un conflit ou qu'un jeu ne configure pas le paramètre
(`-ConflictOnly`, `-DifferenceOnly` : « Show only Conflicts » et « Show only Differences » de
Policy Analyzer). Comme dans Policy Analyzer :

- les listes dont l'ordre ne compte pas sont comparées dans n'importe quel ordre : les comptes d'un
  droit utilisateur ou d'un groupe restreint, les chaînes d'un `REG_MULTI_SZ` ;
- un `REG_DWORD` 5 n'est pas un `REG_SZ` 5 : les cellules montrent alors le type de chaque valeur ;
- la priorité des GPO d'un jeu n'est pas prise en compte : un jeu montre que ses GPO ne sont pas
  d'accord, pas laquelle l'emporte.

Chaque paramètre est montré comme dans GPMC : les valeurs de registre par la stratégie et l'option
des modèles d'administration chargés avec `Initialize-PSGPOAdmx` (sinon, et pour les valeurs
qu'aucun ADMX n'explique, comme *Extra Registry Settings*), les paramètres de sécurité et les
sous-catégories d'audit par leur nom, les comptes par leur nom plutôt que leur SID. La ligne garde
aussi le paramètre tel que Policy Analyzer le liste (`PolicyType` : HKLM, HKCU, Security Template,
Audit Policy ; `Group` : la clé ou la section ; `Setting`), son explication et, dans `Cells`, la
valeur que lui donne chaque GPO.

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions
$baseline = Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules
$domaine = Get-PSGPOPolicyRuleSet -Name 'Postes - *' -SetName 'Domaine'
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domaine -DifferenceOnly |
    Format-Table Scope, Name, Option, MSFT-Win11-v25H2, Domaine
```

Un jeu seul montre ses propres conflits et doublons : les GPO appliquées ensemble qui configurent
le même paramètre.

## L'état effectif de cet ordinateur (Windows uniquement)

!!! note "Windows uniquement"
    L'état effectif est celui de l'ordinateur Windows sur lequel HGPM tourne : le bouton
    **Comparer à l'état effectif** n'apparaît que sous Windows, et `Get-PSGPOPolicyRuleSet
    -EffectiveState` s'arrête sous Linux.

Comme **Compare to Effective State** de Policy Analyzer, **Comparer à l'état effectif** compare
les jeux cochés à ce qu'ont maintenant cet ordinateur et l'utilisateur de la session. Pour chaque
paramètre des jeux, HGPM lit :

| Paramètres | Lus dans | Administrateur |
|---|---|---|
| Modèles d'administration et autres paramètres du registre, de l'ordinateur et de l'utilisateur | le registre (HKLM, HKCU) | non |
| Options de sécurité (`[Registry Values]`), démarrage des services | le registre | non |
| Stratégies de comptes, droits utilisateur, autres paramètres de sécurité | `secedit /export` (la base de sécurité de l'ordinateur, où la stratégie de groupe les applique) | oui |
| Stratégie d'audit avancée | `auditpol /backup` | oui |

![La baseline de Microsoft face à l'état effectif d'un ordinateur Windows 11](../assets/screenshots/61-policy-analyzer-effective-state.fr.png)

- L'état effectif est un jeu de règles à part entière, une colonne à côté des jeux cochés : un
  paramètre que l'ordinateur n'a pas y est vide (gris), une valeur supprimée est `[[[delete]]]`,
  un droit utilisateur que personne n'a est vide.
- Il est enregistré dans le dossier des jeux de règles comme Policy Analyzer l'enregistre,
  `EffectiveState_<ordinateur>_<aaaaMMjj-HHmmss>.PolicyRules`, et listé avec les autres jeux.
- `secedit` et `auditpol` demandent PowerShell **lancé en administrateur** : sinon, le registre est
  lu et la fenêtre, ou un avertissement de la commande, dit combien de paramètres de sécurité et
  d'audit ne le sont pas.
- Les paramètres utilisateur sont ceux du compte qui lance PowerShell : lancé en administrateur
  sous un autre compte, ce sont ceux de ce compte.

```powershell
# PowerShell lancé en administrateur
$baseline = Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules
$etat = Get-PSGPOPolicyRuleSet -EffectiveState -RuleSet $baseline
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $etat -DifferenceOnly | Format-Table Name, MSFT-Win11-v25H2, $etat.Name
Export-PSGPOPolicyRuleSet -RuleSet $etat -Path ".\$($etat.Name).PolicyRules"
```

## Écrire un jeu de règles dans une GPO

`Import-PSGPOPolicyRuleSet` écrit les paramètres d'un jeu de règles dans une GPO du domaine, comme
`LGPO.exe /p` applique un fichier `.PolicyRules` à la stratégie locale d'un ordinateur, aussi bien
sur Active Directory que sur Samba AD : une baseline de sécurité de Microsoft devient une GPO sans
ses sauvegardes GPMC, et sans Windows. Dans la fenêtre, **Écrire dans une GPO...** le fait pour le
jeu sélectionné.

- Les paramètres de registre vont dans les fichiers `Registry.pol` de la GPO (ordinateur et
  utilisateur), le modèle de sécurité dans `GptTmpl.inf`, la stratégie d'audit avancée dans
  `audit.csv` ; la GPO déclare les extensions côté client dont ils ont besoin, y compris celles que
  liste le jeu (protection contre les exploits, LAPS...), et sa version augmente.
- **Fusionnés** par défaut : un paramètre du jeu remplace le même paramètre de la GPO (un
  `**delvals.` vide d'abord les valeurs de sa clé, comme pour une liste), les autres paramètres de
  la GPO restent. `-Replace` (*Remplacer les paramètres de registre...* dans la fenêtre) ne laisse
  que ceux du jeu.
- Seules les GPO du jeu indiquées (`-PolicyName`, la liste de la fenêtre) sont écrites : une
  baseline contient des GPO pour les ordinateurs, les utilisateurs, les contrôleurs de domaine...
  Un paramètre auquel deux d'entre elles donnent des valeurs différentes prend la valeur de la
  dernière, après un avertissement.
- La GPO est d'abord sauvegardée (`-NoBackup` l'évite), et le changement est journalisé
  (`ImportPolicyRuleSet`). Ses liens, son état, ses autorisations, ses préférences et ses scripts
  ne changent pas.
- Un `REG_DWORD_BIG_ENDIAN` n'est pas écrit : Policy Analyzer ne garde pas sa donnée.

```powershell
Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules |
    Import-PSGPOPolicyRuleSet -TargetName 'Postes - Baseline' -PolicyName '*- Computer' -CreateIfNeeded -WhatIf
```

![Les paramètres d'une baseline de sécurité écrits dans une GPO du domaine](../assets/screenshots/55-policy-analyzer-write.fr.png)

## Classeur Excel

`Export-PSGPOPolicyRuleComparison` enregistre une comparaison dans un classeur Excel, écrit par
HGPM (ni Excel ni aucun module ne sont nécessaires, sur toutes les plateformes) : une feuille
*Comparison* avec les couleurs ci-dessus, l'en-tête figé et des filtres sur chaque colonne, et une
feuille *GPOs* avec les GPO de chaque jeu. Avec `-All`, comme « Export all data to Excel », il
contient aussi la valeur de chaque GPO, l'explication et la référence de chaque paramètre.

```powershell
Compare-PSGPOPolicyRuleSet -RuleSet $baseline, $domaine |
    Export-PSGPOPolicyRuleComparison -Path ./Baseline-vs-domaine.xlsx -All
```
