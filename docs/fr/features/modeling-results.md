# Modélisation, résultats et mise à jour

GPMC a trois façons de savoir ce qui s'applique où : la **modélisation de stratégie de groupe**,
qui le calcule à partir de l'annuaire ; les **résultats de stratégie de groupe**, qui lisent ce
qu'un ordinateur a consigné ; la **mise à jour de stratégie de groupe**, qui fait appliquer leurs
GPO aux ordinateurs tout de suite. HGPM les a en commandes, sous Windows et Linux.

## Modélisation de stratégie de groupe { #modelisation-de-strategie-de-groupe }

`Get-PSGPOModeling` donne les GPO qu'un ordinateur et un utilisateur appliqueraient, à partir de
l'annuaire seul : rien ne s'exécute sur l'ordinateur.

- **L'ordre des liens**, comme Windows les applique : le site de l'ordinateur (`-Site`), le
  domaine, les OU au-dessus du compte ; les liens appliqués (enforced) du site vers le bas, les
  autres de l'OU vers le haut jusqu'à une OU qui bloque l'héritage. Une GPO liée deux fois
  s'applique une fois.
- **Le jeton** : le SID du compte et ses groupes, imbriqués compris (`tokenGroups`), Tout le monde
  et Utilisateurs authentifiés. À la place d'un compte, le domaine ou une OU (un conteneur, comme
  GPMC le permet) : le groupe de tous les ordinateurs ou utilisateurs du domaine, et les groupes
  donnés avec `-ComputerGroup` et `-UserGroup`. Un annuaire en mémoire (`Import-PSGPODirectory`)
  n'a pas de comptes : des conteneurs seulement.
- **Le traitement par bouclage** d'après les GPO de l'ordinateur appliquées (*Configurer le mode de
  traitement par bouclage de la stratégie de groupe utilisateur*), ou donné avec `-Loopback` :
  **Merge** (fusion) ajoute les GPO utilisateur de l'ordinateur après celles de l'utilisateur,
  **Replace** (remplacement) les prend seules.
- **Les filtres WMI** ne sont pas exécutés : supposés vrais, sauf ceux donnés avec
  `-FalseWmiFilter`.

Chaque GPO de chaque partie est appliquée, avec sa priorité (1 l'emporte), ou refusée, avec sa
raison :

| Raison | Pourquoi |
|---|---|
| Disabled link | le lien n'est pas activé |
| Disabled GPO | l'état de la GPO désactive cette partie |
| Denied (security) | un refus pour l'un des SID du jeton |
| Not applied (security filtering) | pas d'*Appliquer la stratégie de groupe* avec *Lecture* pour le jeton |
| Inaccessible (the computer cannot read it, MS16-072) | une GPO utilisateur que l'ordinateur ne peut pas lire : Windows ne l'applique pas, même à ses utilisateurs |
| WMI filter not found | son filtre WMI n'est plus dans le domaine : les ordinateurs ignorent la GPO |
| WMI filter false | son filtre WMI est donné faux |
| Empty | aucun paramètre dans cette partie : sa version est 0, ou aucune extension côté client ne la déclare |
| Not found | le lien nomme une GPO absente du domaine (un autre domaine de la forêt) |

```powershell
$Modeling = Get-PSGPOModeling -Computer 'PC-LYON-042' -User 'CONTOSO\jdoe' -Site 'Lyon-Site'
$Modeling.ComputerGpos | Format-Table Precedence, Name, Link, Enforced, Reason
$Modeling.UserGpos | Where-Object Applied

# Une OU à la place d'un ordinateur, avec les groupes dont il serait membre.
Get-PSGPOModeling -Computer 'OU=Kiosks,OU=Workstations,DC=contoso,DC=com' -ComputerGroup 'APPLY_C - Kiosks'
```

## Résultats de stratégie de groupe { #resultats-de-strategie-de-groupe }

`Get-PSGPOResult` lit ce qu'un ordinateur et un utilisateur ont appliqué la dernière fois, tel que
l'ordinateur l'a consigné : les GPO de chaque partie, appliquées avec leur priorité ou refusées
avec leur raison, où elles sont liées ; avec gpresult, les groupes de sécurité de l'ordinateur et
de l'utilisateur, leur SOM et leur site, l'état de chaque extension côté client.

- **Windows** : `gpresult /x`, sur cet ordinateur ou un autre (`-ComputerName`, son pare-feu
  laissant passer le RSoP), pour l'utilisateur donné ou celui qui l'exécute ; la partie ordinateur
  demande un administrateur.
- **Linux**, membre d'un domaine : `samba-gpupdate --rsop`, qui lit la stratégie avec le compte
  machine : root seulement (`sudo pwsh`). Il donne aussi les paramètres de chaque GPO
  (`Settings`).
- **`-Path`** lit un fichier fait ailleurs : le XML de `gpresult /x`, ou ce qu'a affiché
  `samba-gpupdate --rsop`. Sous Linux, c'est la façon de le lire avec le ticket Kerberos d'un
  utilisateur (root a le compte machine, pas ce ticket) :

```powershell
Get-PSGPOResult | Select-Object -ExpandProperty ComputerGpos | Format-Table Precedence, Name, Link, Reason
Get-PSGPOResult -ComputerName PC-LYON-042 -User 'CONTOSO\jdoe'

# Linux : le résultat en root, lu en utilisateur.
#   sudo samba-gpupdate --rsop --target=Computer > /tmp/rsop-computer.txt
Get-PSGPOResult -Path /tmp/rsop-computer.txt -Scope Computer
```

## Mise à jour de stratégie de groupe { #mise-a-jour-de-strategie-de-groupe }

`Invoke-PSGPOUpdate` fait appliquer leurs GPO aux ordinateurs tout de suite ; `-Force` réapplique
chaque paramètre.

- **Windows** : `gpupdate` sur cet ordinateur ; sur d'autres ordinateurs (`-ComputerName`),
  `Invoke-GPUpdate` de RSAT quand il est là, comme GPMC (une tâche planifiée sur l'ordinateur, pour
  lui et pour chaque utilisateur connecté), sinon `gpupdate` par la communication à distance
  PowerShell.
- **Linux** : `samba-gpupdate`, root seulement ; la partie utilisateur pour l'utilisateur donné
  (`-User`). `-WhatIf` ne demande pas root.

```powershell
Invoke-PSGPOUpdate -Target Computer -Force
Invoke-PSGPOUpdate -ComputerName PC-LYON-041, PC-LYON-042
```

## Vérifié sur les deux labos

Sur le membre Windows de `powershell.labo` et sur le contrôleur de domaine Samba de
`hardenbox.labo`, la modélisation de l'ordinateur et de l'utilisateur donne les GPO que
l'ordinateur a appliquées, dans le même ordre ; la mise à jour du membre Windows se voit dans son
résultat relu.
