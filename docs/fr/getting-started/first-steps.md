# Premiers pas

## Commencer par le lanceur

```powershell
Import-Module HGPM
Start-HGPM
```

[Le lanceur](../features/launcher.md) a une tuile pour chaque outil de HGPM : Gestion de stratégie
de groupe, Paramètres de mot de passe, Créateur de filtres WMI, Policy Analyzer et Journal
d'audit. Un clic ouvre
l'outil sur le domaine de l'ordinateur, dans la langue choisie dans sa liste. Chaque outil est aussi
une commande, qui prend les paramètres que la tuile ne donne pas, comme ci-dessous.

![Le lanceur](../assets/screenshots/56-launcher.fr.png)

## Ouvrir la console sur votre domaine

```powershell
Import-Module HGPM
Show-GPOManagerAvalonia
```

Sans paramètre, la console trouve le domaine toute seule : le domaine de l'ordinateur (Windows,
ou `smb.conf` / `krb5.conf` sous Linux), ou l'ordinateur lui-même quand c'est un contrôleur de
domaine. Donnez-lui le contrôleur de domaine quand elle ne peut pas :

```powershell
# Linux : d'abord un ticket Kerberos
kinit administrator@HARDENBOX.LABO
Show-GPOManagerAvalonia -Server dc.hardenbox.labo
```

Quand le domaine ne peut pas être lu (pas de ticket, serveur injoignable…), la fenêtre s'ouvre
quand même et dit pourquoi. Quand aucun domaine n'est trouvé, elle montre un annuaire d'exemple
sous un bandeau **environnement de démonstration**, pour découvrir la console hors ligne.

## Les modèles d'administration

L'éditeur de stratégies a besoin des fichiers ADMX et ADML. La première fois, quand aucun magasin
central du domaine n'est trouvé, une fenêtre demande le dossier `PolicyDefinitions` (le dossier local sous
Windows, une copie ou le magasin central de SYSVOL sous Linux) et la langue de ses ADML, détectée
d'après le nom de ses dossiers de langue ; le choix est mémorisé, et redemandé après un chargement
qui a échoué. Ensuite, la console s'ouvre aussitôt et les lit la première fois qu'elle en a besoin
(l'éditeur, les onglets **Paramètres** et **Historique**, un rapport), sous un bandeau : quelques
secondes une fois, puis une seconde environ depuis [le cache](installation.md#admx-cache) des fichiers déjà lus. Un modèle sans
ADML dans la langue prend celui d'en-US, comme l'éditeur de stratégie de groupe, et un fichier
illisible est laissé de côté : le bandeau le nomme.

![La console lit les modèles d'administration la première fois qu'elle en a besoin](../assets/screenshots/82-admx-loading.fr.png)

Vous pouvez aussi les charger à l'avance :

```powershell
Initialize-PSGPOAdmx -Path \\hardenbox.labo\SYSVOL\hardenbox.labo\Policies\PolicyDefinitions -UICulture en-US
Show-GPOManagerAvalonia
```

## Se repérer dans la fenêtre

![Les détails d'une GPO](../assets/screenshots/02-gpo-details.fr.png)

- **À gauche** : le domaine, ses OU avec leurs liens de GPO (par ordre de lien),
  **Group Policy Objects**, et **Deleted GPOs** (la corbeille, tirée des sauvegardes).
- **À droite** : les détails de la sélection, et pour une GPO ses onglets **Settings** et
  **History**.
- **Clic droit** : ce que vous pouvez faire à cet endroit, comme dans GPMC (créer et lier, lier une
  GPO existante, modifier, supprimer un lien, supprimer, restaurer, approuver…). Seul ce que votre
  compte a le droit de faire est proposé.
- **En haut** : le navigateur ADMX, la fenêtre **Settings** (configuration du domaine), les thèmes
  clair et sombre.
- **En bas** : cet ordinateur, son domaine, et le contrôleur de domaine avec son service
  d'annuaire.

## La console des stratégies de mot de passe

`Show-PSOManagerAvalonia` ouvre la deuxième console de HGPM, pour les stratégies de mot de passe
affinées (PSO) du domaine, comme le Centre d'administration Active Directory : les mêmes `-Server`,
`-Credential`, `-UseSsl` et `-Language`.

```powershell
Show-PSOManagerAvalonia -Server dc.hardenbox.labo -Language fr-FR
```

![La console des stratégies de mot de passe](../assets/screenshots/29-pso-list.fr.png)

Voir [stratégies de mot de passe](../features/password-policies.md).

## En ligne de commande

Tout ce que fait la fenêtre est aussi une commande, pour les scripts et les tâches planifiées :

```powershell
$Directory = Get-PSGPODirectory -Server dc.hardenbox.labo
Backup-PSGPO -Directory $Directory -Path /srv/gpo-backups
Get-PSGPODrift -Directory $Directory -Path /srv/gpo-backups | Where-Object State -EQ Drifted
```

Voir [les commandes](../reference/commands.md).
