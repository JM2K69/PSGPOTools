# Installation

HGPM est un module PowerShell. Il demande **PowerShell 7.4 ou plus** sur toutes les
plateformes ; le reste dépend de ce que vous en faites, et où.

## Le module

Installez-le depuis la PowerShell Gallery, ou construisez-le depuis le dépôt (la branche `master`) :

=== "PowerShell Gallery"

    Avec PSResourceGet, le module de PowerShell 7.4 et suivants qui remplace PowerShellGet
    (`Install-Module`) :

    ```powershell
    Install-PSResource -Name HGPM -Scope CurrentUser
    Import-Module HGPM
    ```

    Depuis la 0.2.0, HGPM a des versions publiées : plus de `-Prerelease`. Une version alpha installée
    avant (0.1.x-alpha, avec `-Prerelease`) passe à la version publiée avec
    `Update-PSResource -Name HGPM`, qui installe aussi les versions plus récentes ensuite
    ([mises à jour](#mises-a-jour)).

=== "Depuis le dépôt"

    ```powershell
    git clone https://github.com/JM2K69/PSGPOTools.git
    cd PSGPOTools
    pwsh -File CI/03_Build.ps1          # construit HGPM/HGPM.psm1 depuis Code/
    Import-Module ./HGPM/HGPM.psd1
    ```

## Le runtime Avalonia

La fenêtre fonctionne sur Avalonia 11. Ses assemblies ne sont pas livrées avec le module : à la
première ouverture d'une fenêtre, la console télécharge les 21 paquets NuGet de
`Resources/AvaloniaPackages.json` pour le runtime de l'ordinateur (`win-x64`, `win-arm64`,
`linux-x64`, `linux-arm64`, `osx`), vérifie chacun avec son SHA-512 épinglé (l'empreinte du
catalogue nuget.org) avant d'extraire quoi que ce soit, puis chaque fichier du runtime avec son
SHA-256 épinglé, et les met en place d'un coup. La console vérifie de nouveau ces fichiers à chaque
chargement, et refuse une bibliothèque ajoutée à côté.

- Ils vont dans le dossier du module quand on peut y écrire, sinon dans le dossier de données de
  l'utilisateur.
- `PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1` interdit le téléchargement (ordinateurs hors ligne : les
  [archives hors ligne](offline.md) de chaque release ont le runtime).
- `PSGPOTOOLS_NUGET_SOURCE` les prend dans un flux NuGet interne, ou un dossier de fichiers
  `.nupkg`, au lieu de nuget.org ; les empreintes épinglées s'appliquent de même
  ([installation hors ligne](offline.md#un-flux-nuget-interne)). Un téléchargement est essayé
  trois fois, deux minutes chacune.
- `Avalonia/Get-AvaloniaBinaries.ps1` les installe à l'avance, ou pour un autre ordinateur. Il
  charge le module : depuis le dépôt, construisez-le d'abord (`CI/03_Build.ps1`).

```powershell
./HGPM/Avalonia/Get-AvaloniaBinaries.ps1 -Rid linux-x64
```

Les commandes qui n'ouvrent pas de fenêtre (sauvegardes, écart, approbation…) n'ont jamais besoin
d'Avalonia.

## Les fichiers ADMX

Le module n'embarque pas de fichiers ADMX : la console lit ceux du magasin central du domaine
(`\domaine\SYSVOL\domaine\Policies\PolicyDefinitions`), de Windows (`%windir%\PolicyDefinitions`)
ou du SYSVOL d'un contrôleur de domaine Samba, sinon demande un dossier. Comme GPMC, elle prend
le magasin central du domaine qu'elle montre dès qu'il a des fichiers ADMX (sous Linux, par le
partage SYSVOL monté : [le magasin central sous Linux](#central-store-linux)) ; un dossier choisi
dans sa fenêtre est lu quand il n'y a pas de magasin central. **Modèles d'administration**, dans
l'arborescence de l'éditeur, dit d'où ils viennent : son dossier est bleu quand ils viennent du
magasin central, et son info-bulle et ses détails donnent le dossier. `Initialize-PSGPOAdmx` sans
`-Path` prend aussi le magasin central. Les fichiers d'un dossier
sont analysés une fois, puis lus dans un cache de l'utilisateur tant qu'ils gardent leurs noms,
tailles et dates (`%LOCALAPPDATA%\PSGPOTools\Admx` sous Windows ; `$XDG_CACHE_HOME/PSGPOTools/Admx`,
sinon `~/.cache/PSGPOTools/Admx` ailleurs ; `-NoCache` les analyse). Là où il n'y en a pas (un
ordinateur Linux, un domaine sans magasin central), `Install-PSGPOAdmx` installe ceux de Windows
depuis le paquet de Microsoft, *Administrative Templates (.admx) for Windows 11* (un `.msi` de
download.microsoft.com : 236 fichiers `.admx`, leurs fichiers `.adml` en 22 langues). HGPM ne les
livre ni ne les redistribue : ce sont les fichiers de Microsoft, selon ses conditions. La commande
extrait le paquet sans l'installer (`msiexec /a` sous Windows ; sous Linux et macOS `msiextract`,
du paquet `msitools` : `sudo apt install msitools`, `sudo dnf install msitools`,
`brew install msitools`). Le module épingle le paquet (sa taille et son SHA-256) et chaque ensemble
de ses fichiers (les `.admx`, chaque langue) : un paquet ou des fichiers qui diffèrent sont refusés
avant que rien ne soit écrit.

```powershell
Install-PSGPOAdmx                                    # en-US et la langue de la session, à côté du module
Install-PSGPOAdmx -UICulture en-US, fr-FR            # les langues choisies
Install-PSGPOAdmx -AllLanguages -Path ~/PolicyDefinitions
Install-PSGPOAdmx -CentralStore -Server dc.hardenbox.labo -UICulture en-US, fr-FR   # le magasin central du domaine
Install-PSGPOAdmx -MsiPath './Administrative Templates (.admx) for Windows 11 Sep 2026 Update.msi'   # sans internet
```

Sans `-Path`, les fichiers vont à côté du module quand on peut y écrire, sinon dans le dossier de
données de l'utilisateur (`PSGPOTools/PolicyDefinitions`) : la console les y trouve. Avec
`-CentralStore`, ils vont dans `SYSVOL\<domaine>\Policies\PolicyDefinitions` du contrôleur de
domaine (un compte qui peut écrire SYSVOL : un administrateur du domaine), comme pour GPMC : toutes
les consoles du domaine les lisent alors. Les fichiers ADMX déjà présents sont gardés, ceux de même
nom remplacés ; s'il y en a déjà, ajoutez `-Force`. Un ordinateur sans internet : téléchargez le
paquet sur un autre (la page de Microsoft est dans l'erreur d'un téléchargement qui échoue) et
donnez-le avec `-MsiPath` ; il est vérifié comme un téléchargement.

### Les fichiers ADMX d'autres produits { #product-admx }

Les stratégies des autres produits que Windows viennent avec leurs propres fichiers ADMX, qu'un
administrateur ajoute au magasin central pour GPMC : la console les y lit aussi, dans le même
dossier que ceux de Windows. `Install-PSGPOProductAdmx` installe ceux de sept produits depuis leurs
éditeurs, comme `Install-PSGPOAdmx` ceux de Windows, dans un dossier ou le magasin central :

| Produit (`-Name`) | Éditeur | Paquet | Fichiers ADMX |
|---|---|---|---|
| `Office` : Microsoft 365 Apps, Office LTSC, Office 2016 à 2024 | Microsoft | `admintemplates_x64_<version>_en-us.exe` | `office16.admx`, `word16.admx`, `excel16.admx`, `outlk16.admx`... (12 fichiers, 12 langues) |
| `Firefox` | Mozilla | `policy_templates_v<version>.zip` (GitHub) | `firefox.admx`, `mozilla.admx` |
| `AdobeAcrobat`, `AdobeReader` | Adobe | `AcrobatADMTemplate.zip`, `ReaderADMTemplate.zip` | `AcrobatDC.admx`, `AcrobatReaderDC.admx` (en-US seulement) |
| `Edge` | Microsoft | `MicrosoftEdgePolicyTemplates.cab` | `msedge.admx`, `msedgeupdate.admx`, `msedgewebview2.admx` |
| `Chrome`, `GoogleUpdate` | Google | `policy_templates.zip`, `googleupdateadmx.zip` | `chrome.admx`, `GoogleUpdate.admx`, et `google.admx` qu'ils partagent |

```powershell
Get-PSGPOProductAdmx | Format-Table Name, Publisher, Version, Languages   # les produits et la version épinglée
Install-PSGPOProductAdmx -Name Office, Firefox -CentralStore -Server dc.hardenbox.labo -UICulture en-US, fr-FR
Install-PSGPOProductAdmx -Name Edge, Chrome, GoogleUpdate     # à côté de ceux de Windows (Install-PSGPOAdmx)
Install-PSGPOProductAdmx -Name Office -PackagePath ./admintemplates_x64_5568_1000_en-us.exe   # sans internet
Install-PSGPOProductAdmx -SourcePath ~/Downloads/Zoom/PolicyDefinitions -CentralStore -Server dc.hardenbox.labo
```

Comme pour Windows, le module épingle le paquet de chaque produit (`HGPM/Resources/AdmxProducts.json` :
son adresse, sa taille et son SHA-256) et le SHA-256 de chacun de ses fichiers `.admx` et `.adml` :
un paquet ou un fichier qui diffère est refusé avant que rien ne soit écrit. Les paquets sont ceux
de leurs éditeurs, sous leurs conditions ; HGPM ne les livre ni ne les redistribue. Rien d'un paquet
n'est exécuté : une archive zip est lue, un cabinet extrait (`expand` sous Windows, `cabextract` ou
7-Zip sous Linux et macOS : `sudo apt install cabextract`), et le programme d'Office est lu pour le
cabinet qu'il contient. Les fichiers sont retrouvés dans le paquet par leur contenu, où qu'il les
range : le paquet d'Office met les fichiers `.adml` de ses 12 langues côte à côte (`word16.adml`,
`word16.adml0`...), chacun épinglé à sa place dans le dossier de sa langue.

- Les langues : `-UICulture`, `-AllLanguages`, par défaut en-US et la langue de la session. Une
  langue qu'un produit n'a pas est laissée avec un avertissement : GPMC et HGPM montrent ses
  stratégies en en-US.
- Les fichiers `.admx` d'un produit déjà présents ne sont remplacés qu'avec `-Force` ;
  `google.admx`, que Chrome et Google Update partagent, n'arrête pas le second.
- Un fichier qui déclare l'espace de noms d'un fichier d'un autre nom déjà présent est refusé : GPMC
  refuse un magasin où deux fichiers déclarent un même espace de noms. Un produit dont les fichiers
  utilisent ceux de Windows (`windows.admx`) est installé avec un avertissement quand ils n'y sont pas.
- `-CentralStore` inscrit l'installation dans le journal d'audit (`InstallAdmx`, avec le produit, sa
  version et le SHA-256 de son paquet).

Une version d'un produit plus récente que celle épinglée, ou un autre produit (Zoom, 7-Zip,
FSLogix...) : extrayez ses fichiers et donnez leur dossier avec `-SourcePath`. Le dossier (ses
fichiers `.admx`, et un dossier par langue avec les fichiers `.adml`) est vérifié comme GPMC le lit :
chaque fichier `.admx` a son fichier `.adml` dans chaque langue installée, avec les chaînes et les
présentations qu'il nomme. Les dossiers des langues prennent le nom de leur culture (`fr-FR`, pas
`fr-fr`) : le SYSVOL d'un contrôleur de domaine Samba les distingue, une copie faite sur son disque
laisserait un dossier de langue que la console ne lit pas. Pour les mainteneurs,
`CI/Update-AdmxProductCatalog.ps1` épingle un nouveau paquet d'un produit.

### Le magasin central sous Linux { #central-store-linux }

Sous Windows, la console et `Initialize-PSGPOAdmx` lisent le magasin central du domaine par son
partage, `\\<domaine>\SYSVOL\<domaine>\Policies\PolicyDefinitions`, comme GPMC. Linux n'a pas de
chemin vers un partage : HGPM lit le magasin central par le partage SYSVOL **monté** (mount.cifs),
qu'il trouve de lui-même dans `/proc/mounts` et `/etc/fstab`, le SYSVOL du contrôleur de domaine lu
en premier. Sans lui, il ne regarde que le SYSVOL d'un contrôleur de domaine Samba, sur son disque
(`/var/lib/samba/sysvol/<domaine>/Policies/PolicyDefinitions`), que Samba réserve à root et à
`BUILTIN\Administrators` : la console d'un compte, sur le contrôleur de domaine ou sur un autre
ordinateur Linux, ne l'y trouve pas et lit un dossier de l'ordinateur. Créer le magasin central
depuis Linux ne suffit donc pas : toutes les consoles sous Windows le lisent aussitôt, une console
sous Linux une fois le partage SYSVOL monté.

**1. Créer le magasin central**, depuis Linux, avec le ticket Kerberos d'un compte qui écrit dans
SYSVOL (un administrateur du domaine). Les fichiers passent par SMB (`smbclient`) ; le paquet de
Windows demande `msitools`, ceux d'Office et d'Edge `cabextract` :

```bash
sudo apt install smbclient msitools cabextract        # Debian et Ubuntu
kinit administrator@HARDENBOX.LABO
```

```powershell
$domain = Get-PSGPODirectory -Server dc.hardenbox.labo
Install-PSGPOAdmx -CentralStore -Directory $domain -UICulture en-US, fr-FR                     # Windows
Install-PSGPOProductAdmx -Name Office, Firefox, Edge -CentralStore -Directory $domain -UICulture en-US, fr-FR
```

```bash
smbclient //dc.hardenbox.labo/sysvol --use-kerberos=required -c 'ls hardenbox.labo\Policies\PolicyDefinitions\*.admx'
```

Écrivez les fichiers par SMB, comme ces commandes, pas par une copie sur le disque du contrôleur de
domaine : là, un dossier de langue `fr-fr` à côté de `fr-FR` serait un autre dossier, que les
consoles ne lisent pas.

**2. Monter le partage SYSVOL sur chaque console Linux**, en root, avec le script des
[sauvegardes centrales](../features/backup-history.md) : Kerberos, multi-utilisateur (chaque compte
atteint le partage avec son propre ticket, le serveur vérifie ses droits), `--fstab` pour qu'il se
monte de lui-même à chaque démarrage. Il demande `cifs-utils` et `keyutils` :

```bash
sudo ./New-PSGPOShareMount.sh //dc.hardenbox.labo/sysvol --fstab          # /mnt/sysvol
ls /mnt/sysvol/hardenbox.labo/Policies/PolicyDefinitions
```

[Télécharger linux/New-PSGPOShareMount.sh](../assets/scripts/linux/New-PSGPOShareMount.sh){ download }

**3. Rien à choisir** : la console trouve le magasin dans le montage, avant tout dossier choisi
auparavant, et le relit à chaque démarrage, depuis [le cache](#admx-cache) tant que ses fichiers ne
changent pas ; ses **Modèles d'administration** sont bleus, le dossier du magasin dans leur
info-bulle. `Initialize-PSGPOAdmx` sans `-Path` le prend aussi :

```powershell
Initialize-PSGPOAdmx -UICulture fr-FR            # /mnt/sysvol/hardenbox.labo/Policies/PolicyDefinitions
```

Sur le labo Samba, le magasin de Windows et de sept produits (258 fichiers `.admx`, 11 699
stratégies) est analysé en 7 secondes environ par le montage, puis lu en 4 secondes environ depuis
le cache.

![Les modèles d'administration lus depuis le magasin central, monté sous Linux : un dossier bleu, le magasin dans ses détails](../assets/screenshots/95-central-store.fr.png){ width="560" }

### Le cache des fichiers ADMX { #admx-cache }

Analyser un dossier `PolicyDefinitions` prend quelques secondes, et chaque console du lanceur
s'ouvre dans un processus à elle : ce qu'un chargement lit est gardé dans un cache de
l'utilisateur, un fichier par dossier et par langue (`%LOCALAPPDATA%\PSGPOTools\Admx` sous
Windows ; `$XDG_CACHE_HOME/PSGPOTools/Admx`, sinon `~/.cache/PSGPOTools/Admx` ailleurs).

- **Quand il est écrit** : la première fois qu'un dossier est chargé dans une langue, par ce qui le
  charge : la console des GPO la première fois qu'elle a besoin des stratégies (l'éditeur, les
  onglets **Paramètres** et **Historique**, un rapport ; jamais pour les liaisons, la délégation ou
  l'approbation), ou avant de s'ouvrir avec `-PolicyDefinitions` ; l'éditeur seul (`-NoDirectory`)
  et Policy Analyzer à leur démarrage ; **Charger** dans la fenêtre des ADMX ;
  `Initialize-PSGPOAdmx`. Il est écrit à côté, puis renommé : une console qui s'ouvre pendant ce
  temps lit l'ancien fichier ou le nouveau, jamais la moitié d'un.
- **Quand il est lu** : tant que les fichiers `.admx`, et les fichiers `.adml` de la langue et
  d'en-US, gardent leurs noms, tailles et dates, avec la même version de HGPM. Un fichier ajouté,
  modifié ou supprimé (un nouveau modèle dans le magasin central), ou une mise à jour de HGPM, et le
  chargement suivant analyse de nouveau les fichiers et réécrit le cache : quelques secondes encore
  une fois.
- **Quand il n'est pas écrit** : avec `-NoCache`, après une erreur, ou quand un fichier a été
  écarté pour une raison qui peut passer (le réseau, les droits) : le chargement suivant analyse de
  nouveau les fichiers plutôt que de garder un chargement auquel il en manque. Un cache qui ne peut
  pas être écrit ne fait que ralentir le chargement suivant.
- **Le vider** : supprimez son dossier, rien d'autre n'est perdu ; le chargement suivant le réécrit.

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\PSGPOTools\Admx"   # Windows
Remove-Item -Recurse -Force ~/.cache/PSGPOTools/Admx              # Linux, sans XDG_CACHE_HOME
```

## Windows

| Besoin | Pourquoi | Comment |
|---|---|---|
| Un compte du domaine | la console lit le domaine avec l'identité de la session (Kerberos) | ouvrez une session avec, ou `-Credential` avec `-UseSsl` |
| Outils RSAT de gestion des stratégies de groupe | créer et supprimer des GPO (`New-GPO`, `Remove-GPO`) | `Add-WindowsCapability -Online -Name 'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'` (Windows 10/11), `Install-WindowsFeature GPMC` (Server) |
| Outils RSAT Active Directory | facultatif : seuls les scripts de test s'en servent | `Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'` |

Le module GroupPolicy est un module Windows PowerShell : PowerShell 7 le masque à
`Get-Module -ListAvailable` et le charge par sa compatibilité Windows PowerShell. La console le
trouve avec `-SkipEditionCheck`.

SYSVOL est lu et écrit par son chemin UNC (`\\dc\SYSVOL\domaine\Policies\{GUID}`), avec
l'identité de la session.

!!! warning "Une session ouverte en SSH avec une clé"
    Une session OpenSSH ouverte avec une clé n'a pas d'identifiants réseau (ouverture S4U) : les
    connexions LDAP échouent et SYSVOL est inaccessible. Lancez la console dans une session
    interactive, ou en SSH avec un mot de passe.

## Linux

| Besoin | Pourquoi | Debian / Ubuntu | RHEL / Fedora |
|---|---|---|---|
| Bibliothèque cliente OpenLDAP | LDAP depuis .NET | `apt install libldap2` | `dnf install openldap` |
| Module SASL GSSAPI | Kerberos sur LDAP | `apt install libsasl2-modules-gssapi-mit` | `dnf install cyrus-sasl-gssapi` |
| Client Kerberos | le ticket qu'utilise la console | `apt install krb5-user` | `dnf install krb5-workstation` |
| `smbclient` | lire et écrire SYSVOL | `apt install smbclient` | `dnf install samba-client` |
| `samba-tool`, bindings Python de Samba | créer et supprimer des GPO, droits SYSVOL | `apt install python3-samba samba-common-bin` | `dnf install samba-tools python3-samba` |
| `msitools`, `cabextract` | installer les fichiers ADMX : de Windows (`Install-PSGPOAdmx`), d'Office et d'Edge (`Install-PSGPOProductAdmx`) | `apt install msitools cabextract` | `dnf install msitools cabextract` |
| `cifs-utils`, `keyutils` | lire le magasin central : le partage SYSVOL monté ([le magasin central sous Linux](#central-store-linux)) | `apt install cifs-utils keyutils` | `dnf install cifs-utils keyutils` |
| Une session graphique | la fenêtre (X11, ou Wayland avec XWayland) | | |

La console s'authentifie en **Kerberos** : prenez d'abord un ticket, et donnez le contrôleur de
domaine par son nom DNS (Kerberos demande le nom, pas l'adresse IP).

```bash
kinit administrator@HARDENBOX.LABO
klist
```

Aucun mot de passe n'est jamais donné à `samba-tool` ni à `smbclient`, ni envoyé en LDAP en
clair : avec `-Credential`, utilisez `-UseSsl` (LDAPS), et les modifications demandent tout de
même un ticket Kerberos.

!!! note "-Credential sous Windows"
    Sous Windows, un domaine lu avec `-Credential` (et `-UseSsl`) est modifié avec ce compte dans
    l'annuaire **et dans SYSVOL** : la console ouvre une connexion SMB à `\\<dc>\SYSVOL` avec
    lui, comme `net use \\<dc>\SYSVOL /user:...`. Windows n'a qu'un compte par serveur dans une
    session : si la session atteint déjà ce serveur avec un autre compte, la console le dit
    (`net use \\<dc>\* /delete` ferme ces connexions). Créer et supprimer une GPO passent par RSAT,
    qui ne connaît que l'identité de la session : ils sont refusés avec `-Credential`.

## Vérifier l'installation

```powershell
Import-Module HGPM
Get-Command -Module HGPM        # les commandes publiques
Get-PSGPODirectory -Server dc.hardenbox.labo | Select-Object DomainName, Account, Source
```

La barre d'état de la fenêtre dit aussi ce que la console a trouvé : cet ordinateur, son domaine,
le contrôleur de domaine et son service d'annuaire.

## Mises à jour

L'import du module donne sa version, et la commande qui installe une version plus récente quand la
PowerShell Gallery en a une :

```text
PS> Import-Module HGPM
HGPM 0.2.0
HGPM 0.2.1 is available on the PowerShell Gallery: Update-PSResource -Name HGPM, then open a new PowerShell session.
```

L'import lit la Gallery au plus une fois par jour (`UpdateCheck.json` dans le dossier de données
local de l'utilisateur, `PSGPOTools`), et attend 8 secondes au plus : sans réseau, il ne donne que
la version, et ne réessaie pas avant une heure. Il ne la lit pas dans une CI, dans une session lancée avec `-NonInteractive`, ni avec
`PSGPOTOOLS_SKIP_UPDATE_CHECK=1`. La nouvelle version sert à une nouvelle session PowerShell : celle
en cours garde le module qu'elle a importé.

`Test-PSGPOUpdate` dit si une version plus récente de HGPM est publiée sur la PowerShell Gallery,
et donne la commande qui l'installe. Elle compare la version chargée à la dernière de la Gallery
comme des versions sémantiques : `0.1.4-alpha` passe avant `0.1.4-beta`, elle-même avant `0.1.4`.
Les préversions comptent quand la version chargée en est une (ou avec `-Prerelease`).

```powershell
Test-PSGPOUpdate
# Name             : HGPM
# InstalledVersion : 0.2.0
# LatestVersion    : 0.2.1
# UpdateAvailable  : True
# UpdateCommand    : Update-PSResource -Name HGPM

if (Test-PSGPOUpdate -Quiet) { Update-PSResource -Name HGPM }
```

### Mettre à jour HGPM

1. **Fermez** les consoles (`Show-GPOManagerAvalonia`, `Show-PSOManagerAvalonia`) et les sessions
   PowerShell qui ont importé HGPM : une session garde le module qu'elle a importé.
2. **Installez** la nouvelle version, comme le module a été installé :

    === "PowerShell Gallery"

        ```powershell
        Update-PSResource -Name HGPM
        ```

        La nouvelle version s'installe à côté de l'ancienne (un dossier par version dans
        `Modules/HGPM`). Un module installé pour tous les utilisateurs (`-Scope AllUsers`) se met à
        jour en administrateur, avec `-Scope AllUsers` (`sudo pwsh` sous Linux). Installé avec
        PowerShellGet (`Install-Module`) : `Update-Module -Name HGPM`.

    === "Depuis le dépôt"

        ```bash
        cd PSGPOTools
        git pull
        pwsh -File CI/03_Build.ps1
        ```

        L'import d'une copie du dépôt propose ensuite `Install-PSResource` : il installe la version
        de la Gallery à côté de la copie, qui garde la sienne.

3. **Vérifiez** dans une nouvelle session PowerShell : l'import donne la nouvelle version, sans la
   ligne `is available`, et la pastille de la barre d'état des consoles est verte.

    ```powershell
    Import-Module HGPM
    Get-PSResource -Name HGPM          # les versions installées
    ```

4. Si besoin, **supprimez** une ancienne version : `Uninstall-PSResource -Name HGPM -Version <version>`.

Les changements de chaque version sont dans le [journal des modifications](../changelog.md).
