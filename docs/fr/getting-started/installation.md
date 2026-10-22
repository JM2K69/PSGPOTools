# Installation

HGPM est un module PowerShell. Il demande **PowerShell 7.4 ou plus** sur toutes les
plateformes ; le reste dépend de ce que vous en faites, et où.

## Le module

Installez-le depuis la PowerShell Gallery, ou construisez-le depuis le dépôt (la branche `master`) :

=== "PowerShell Gallery"

    Avec PSResourceGet, le module de PowerShell 7.4 et suivants qui remplace PowerShellGet
    (`Install-Module`) :

    ```powershell
    Install-PSResource -Name HGPM -Prerelease -Scope CurrentUser   # versions alpha
    Import-Module HGPM
    ```

    `-Prerelease` tant que HGPM n'a que des versions alpha. Plus tard,
    `Update-PSResource -Name HGPM -Prerelease` installe une version plus récente
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
catalogue nuget.org) avant d'extraire quoi que ce soit, puis les met en place d'un coup.

- Ils vont dans le dossier du module quand on peut y écrire, sinon dans le dossier de données de
  l'utilisateur.
- `PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1` interdit le téléchargement (ordinateurs hors ligne).
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
ou du SYSVOL d'un contrôleur de domaine Samba, sinon demande un dossier. Là où il n'y en a pas (un
ordinateur Linux, un domaine sans magasin central), `Install-PSGPOAdmx` télécharge la copie du
dépôt depuis GitHub (`sources/PolicyDefinitions` : 236 fichiers `.admx`, leurs fichiers `.adml` en
22 langues), au tag de la version du module. Chaque ensemble de fichiers (les `.admx`, chaque
langue) est vérifié avec le SHA-256 que le module épingle avant que rien ne soit écrit.

```powershell
Install-PSGPOAdmx                                    # en-US et la langue de la session, à côté du module
Install-PSGPOAdmx -UICulture en-US, fr-FR            # les langues choisies
Install-PSGPOAdmx -AllLanguages -Path ~/PolicyDefinitions
Install-PSGPOAdmx -CentralStore -Server dc.hardenbox.labo -UICulture en-US, fr-FR   # le magasin central du domaine
```

Sans `-Path`, les fichiers vont à côté du module quand on peut y écrire, sinon dans le dossier de
données de l'utilisateur (`PSGPOTools/PolicyDefinitions`) : la console les y trouve. Avec
`-CentralStore`, ils vont dans `SYSVOL\<domaine>\Policies\PolicyDefinitions` du contrôleur de
domaine (un compte qui peut écrire SYSVOL : un administrateur du domaine), comme pour GPMC : toutes
les consoles du domaine les lisent alors. Les fichiers ADMX déjà présents sont gardés, ceux de même
nom remplacés ; s'il y en a déjà, ajoutez `-Force`. Avant la première publication d'une version
(pas encore de tag), donnez la branche : `-Ref master`.

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
HGPM 0.1.5-alpha
HGPM 0.1.6-alpha is available on the PowerShell Gallery: Update-PSResource -Name HGPM -Prerelease, then open a new PowerShell session.
```

L'import lit la Gallery au plus une fois par jour (`UpdateCheck.json` dans le dossier de données
local de l'utilisateur, `PSGPOTools`), et attend 3 secondes au plus : sans réseau, il ne donne que
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
# InstalledVersion : 0.1.4-alpha
# LatestVersion    : 0.1.5-alpha
# UpdateAvailable  : True
# UpdateCommand    : Update-PSResource -Name HGPM -Prerelease

if (Test-PSGPOUpdate -Quiet) { Update-PSResource -Name HGPM -Prerelease }
```

Un module construit depuis le dépôt se met à jour avec `git pull` et `CI/03_Build.ps1` ; la
commande propose alors `Install-PSResource`, pour installer la version de la Gallery à côté. Les
changements de chaque version sont dans le [journal des modifications](../changelog.md).
