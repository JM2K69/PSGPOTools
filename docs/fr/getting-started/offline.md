# Installation hors ligne

Pour un poste d'administration (PAW) ou un réseau sans internet. Chaque release de GitHub a le
module avec le runtime Avalonia de chaque plateforme, le SHA-256 de chaque fichier, et leur
attestation : une preuve, signée par GitHub, qu'ils ont été construits par le workflow du dépôt
depuis le commit du tag.

## Ce que contient une release

| Fichier | Contenu |
|---|---|
| `HGPM-<version>.zip` | le module, comme sur la PowerShell Gallery (sans le runtime Avalonia) |
| `HGPM-<version>-win-x64.zip`, `-win-arm64`, `-linux-x64`, `-linux-arm64` | le module avec le runtime Avalonia de la plateforme, dans `Avalonia/bin/<rid>` |
| `SHA256SUMS` | le SHA-256 de chaque archive et de chaque fichier du module |

Le module des archives, et de la PowerShell Gallery, est celui que les tests de la CI ont exécuté :
il est construit une fois, et la construction est reproductible (les mêmes octets depuis les mêmes
sources, sous Windows et sous Linux : la CI le vérifie à chaque commit).

## Vérifier ce que vous avez téléchargé

Le SHA-256 d'une archive, comparé à `SHA256SUMS` :

```powershell
$archive = 'HGPM-0.1.21-alpha-win-x64.zip'
$expected = (Get-Content SHA256SUMS | Where-Object { $_.EndsWith("  $archive") }).Split(' ')[0]
(Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -eq $expected
```

Son attestation, avec la CLI GitHub (depuis un ordinateur qui a internet) :

```bash
gh attestation verify HGPM-0.1.21-alpha-win-x64.zip --repo JM2K69/PSGPOTools
```

Elle dit que le fichier a été construit par le workflow Release du dépôt, depuis le commit du tag,
et échoue pour tout autre fichier. Un fichier d'un module installé depuis la PowerShell Gallery se
vérifie de la même façon (`HGPM.psm1`, `HGPM.psd1`...) : `SHA256SUMS` les a tous.

## L'installer

Windows : débloquez l'archive avant de l'extraire. Téléchargés depuis internet, ses fichiers
seraient marqués, et la stratégie d'exécution `RemoteSigned` refuserait les scripts non signés.

```powershell
Unblock-File .\HGPM-0.1.21-alpha-win-x64.zip
Expand-Archive .\HGPM-0.1.21-alpha-win-x64.zip -DestinationPath $env:TEMP\HGPM-0.1.21
$modules = "$env:ProgramFiles\PowerShell\Modules\HGPM"      # tous les utilisateurs ; $HOME\Documents\PowerShell\Modules\HGPM pour un seul
New-Item -ItemType Directory -Path $modules -Force | Out-Null
Copy-Item $env:TEMP\HGPM-0.1.21\HGPM "$modules\0.1.21" -Recurse
```

Linux :

```bash
unzip HGPM-0.1.21-alpha-linux-x64.zip -d /tmp/hgpm
mkdir -p ~/.local/share/powershell/Modules/HGPM      # un utilisateur ; /usr/local/share/powershell/Modules pour tous
cp -r /tmp/hgpm/HGPM ~/.local/share/powershell/Modules/HGPM/0.1.21
```

Ensuite, pour que rien ne soit jamais cherché sur internet :

| Variable | Effet |
|---|---|
| `PSGPOTOOLS_AVALONIA_NO_DOWNLOAD=1` | le runtime Avalonia n'est jamais téléchargé : celui de l'archive est utilisé |
| `PSGPOTOOLS_SKIP_UPDATE_CHECK=1` | la PowerShell Gallery n'est pas lue pour une version plus récente |

Les fichiers ADMX viennent du magasin central du domaine, ou de `%windir%\PolicyDefinitions` ;
sous Linux, d'une copie : le dossier `sources/PolicyDefinitions` de l'archive des sources de la
release (`Initialize-PSGPOAdmx -Path`, [Installation](installation.md#les-fichiers-admx)).

## Le runtime est vérifié à chaque fois

Chaque fichier du runtime Avalonia a son SHA-256 épinglé dans le module
(`Resources/AvaloniaPackages.json`). La console les vérifie à chaque chargement, et refuse une
bibliothèque ajoutée à côté : une archive modifiée, ou un fichier du runtime remplacé dans un
dossier où d'autres peuvent écrire, n'est jamais chargé. Le message nomme ce qui diffère ; supprimez
le dossier du runtime, et extrayez-le de nouveau (ou laissez la console l'installer, vérifié).

## Un flux NuGet interne

Là où les ordinateurs joignent un flux interne mais pas nuget.org, `PSGPOTOOLS_NUGET_SOURCE` le
donne :

- l'adresse de son index de service (`https://nuget.example.com/v3/index.json` : Artifactory,
  Nexus, ProGet, Azure Artifacts...), ou l'adresse de base de ses paquets
  (`.../v3-flatcontainer/`) ;
- ou un dossier de fichiers `.nupkg` (un partage), à plat ou rangés comme un flux les range.

Quelle que soit la source, un paquet n'est installé qu'avec son SHA-512 épinglé, et chaque fichier
avec son SHA-256. Un téléchargement est essayé trois fois, deux minutes chacune, par le proxy du
système.

## La signature

Quand la release est signée avec Authenticode (le certificat est un secret du workflow de
release), chaque script du module est signé, et le catalogue `HGPM.cat` liste chaque fichier du
module :

```powershell
$module = "$env:ProgramFiles\PowerShell\Modules\HGPM\0.1.21"
Get-AuthenticodeSignature "$module\HGPM.psm1"
# Le runtime d'une archive hors ligne n'est pas dans le catalogue (le module le vérifie, ci-dessus), ni le fichier qu'ajoute Install-PSResource.
$skip = @(Get-ChildItem "$module\Avalonia\bin" -Recurse -File -ErrorAction SilentlyContinue).Name + 'PSGetModuleInfo.xml'
Test-FileCatalog -Path $module -CatalogFilePath "$module\HGPM.cat" -FilesToSkip $skip
```

Les releases ne sont pas encore signées : avec la stratégie d'exécution `AllSigned`, signez le
module avec le certificat de votre organisation (`Set-AuthenticodeSignature`) une fois vérifié comme
ci-dessus.

## Le reconstruire

Chacun peut reconstruire le module depuis le tag, et le comparer à la release :

```powershell
git clone --branch v0.1.21-alpha https://github.com/JM2K69/PSGPOTools
cd PSGPOTools
./CI/03_Build.ps1
(Get-FileHash HGPM/HGPM.psm1 -Algorithm SHA256).Hash.ToLower()   # la ligne HGPM/HGPM.psm1 de SHA256SUMS
```

Pour une release signée, la signature ajoutée aux scripts change leurs octets : vérifiez plutôt la
signature (ci-dessus).
