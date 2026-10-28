# Tests

Les tests sont des tests [Pester](https://pester.dev) 5, dans `CI/tests`, lancés sur le module
construit.

```powershell
pwsh -File CI/03_Build.ps1
$Config = New-PesterConfiguration
$Config.Run.Path = 'CI/tests'
$Config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $Config
```

| Fichier | Couvre |
|---|---|
| `PSGPOTools.Model.tests.ps1`, `GPOToolsUtility.tests.ps1` | ADMX, ADML, catégories, stratégies |
| `PSGPOTools.RegistryPol.tests.ps1`, `PSGPOTools.Setting.tests.ps1` | Registry.pol, l'état de chaque stratégie du jeu ADMX, rapports de paramètres |
| `PSGPOTools.AccessControl.tests.ps1` | descripteurs de sécurité, filtrage de sécurité, ACL SYSVOL |
| `PSGPOTools.Backup.tests.ps1` | sauvegardes, comparaison, restauration, notes, écart, corbeille, modèles |
| `PSGPOTools.Configuration.tests.ps1` | la configuration du domaine |
| `PSGPOTools.Hardening.tests.ps1` | ce que pourrait faire un fichier, un attribut, un outil ou un domaine hostile ([durcissement](hardening.md)) |
| `PSGPOTools.Workflow.tests.ps1` | le workflow d'approbation |
| `PSGPOTools.Delegation.tests.ps1` | les droits lus dans l'annuaire |
| `PSGPOTools.Ldap.tests.ps1` | LDAP, gPLink, samba-tool, RSAT (simulés), et face à un contrôleur de domaine |
| `PSGPOTools.PasswordPolicy.tests.ps1` | les stratégies de mot de passe affinées : les valeurs de l'annuaire, les vérifications, le PSO qui s'applique et pourquoi, les commandes |
| `PSGPOTools.Gui.tests.ps1` | les vraies fenêtres des deux consoles (`-OnShown`) |
| `PSGPOTools.Health.tests.ps1` | la santé des GPO et leur réplication entre contrôleurs de domaine (trois simulés) |
| `PSGPOTools.AvaloniaInstall.tests.ps1` | le runtime Avalonia : ses paquets et fichiers épinglés, d'où ils viennent, les vérifications avant son chargement |
| `PSGPOTools.Release.tests.ps1` | la construction reproductible, le paquet d'une release (SHA256SUMS, signature, catalogue), les règles des workflows |
| `PSGPOTools.Public.tests.ps1` | les commandes exportées |
| `PSGPOTools.Update.tests.ps1` | les versions de HGPM et `Test-PSGPOUpdate` (la Gallery simulée) |

## Face à un contrôleur de domaine

Les tests d'intégration tournent quand on leur donne un contrôleur de domaine, avec un ticket
Kerberos d'un administrateur du domaine :

```bash
kinit administrator@HARDENBOX.LABO
export PSGPOTOOLS_TEST_LDAP_SERVER=dc.hardenbox.labo   # lit le domaine
export PSGPOTOOLS_TEST_LDAP_WRITE=1                    # crée, lie, écrit et supprime aussi
pwsh -c 'Invoke-Pester CI/tests'
```

Avec `PSGPOTOOLS_TEST_LDAP_WRITE=1`, ils créent une OU et des GPO nommées `PSGPOTools test ...`, les
lient, écrivent leurs paramètres, en suppriment et en restaurent une, et suppriment tout ce qu'ils
ont créé à la fin, quoi qui ait échoué. Pour les stratégies de mot de passe (Linux, `samba-tool`),
ils créent un utilisateur, un groupe de sécurité global et un local de domaine, et des PSO nommés
`PSO test ...` : protégés contre la suppression accidentelle, renommés, appliqués directement et
par les groupes, une modification faite entre-temps refusée, le PSO trouvé par la console comparé à
`msDS-ResultantPSO` ; puis ils les suppriment.

Avec aussi `PSGPOTOOLS_TEST_LAB_SCRIPTS=1` (Linux), ils lancent les scripts Linux du
[labo](../getting-started/lab.md), `New-PSGPOTierLab.ps1` et `Grant-PSGPOTierDelegation.ps1`, deux fois
chacun : les OU, groupes et comptes des tiers, le mot de passe du labo (un ticket Kerberos de
`tiers1`), la délégation des liens et de la création de GPO (le workflow activé pour le test). Ils changent le domaine pour de
bon : le job `test-samba` de la CI le définit, sur son domaine jetable seulement.

Les écritures d'une approbation (`PSGPOTools.Hardening.tests.ps1`) sont testées avec des mocks :
leur ordre (SYSVOL, les objets que contient la GPO, puis la GPO), la GPO laissée en attente quand
SYSVOL échoue, les permissions retirées et signalées. Le circuit complet, avec ses deux comptes,
tourne aussi contre le contrôleur de domaine (*Approval written to a domain controller*), après les
scripts du lab :

- `tiers1`, dans un processus à lui avec son ticket Kerberos, crée une GPO : elle attend, personne
  ne l'applique ; `tiers1` y ajoute une permission à lui (Domain Users, contrôle total) ;
- l'administrateur l'approuve : Domain Admins est propriétaire de la GPO et de son dossier SYSVOL,
  la permission ajoutée par `tiers1` et ses propres droits ont disparu (et sont signalés),
  Authenticated Users l'applique ;
- `tiers1` ne peut plus l'écrire ;
- une GPO que `tiers1` modifie après son examen n'est pas approuvée, et reste en attente.

La configuration du domaine est gardée et réécrite octet pour octet. Sur un lab à vous,
`PSGPOTOOLS_TEST_TIER1_CCACHE` donne le ticket d'un créateur (`FILE:/tmp/krb5cc_tiers1`) à la place
du mot de passe du lab.

### Ce qu'un job doit lancer

`CI/Invoke-Tests.ps1 -RequireRun` nomme les blocs (`Describe`, `Context`, jokers) pour lesquels un
lancement existe : un de leurs tests sauté avec son bloc (un runtime d'Avalonia manquant, une
variable du domaine mal nommée) ou non lancé, ou aucun de leurs tests, fait échouer le lancement. Un
test qui se saute lui-même pour une autre plateforme (`-Skip:$IsWindows`) non. Chaque lancement écrit
un tableau de ses fichiers (réussis, échoués, sautés, non lancés) dans le résumé de son job sur
GitHub (`GITHUB_STEP_SUMMARY`).

## CI

`.github/workflows/ci.yml` lance quatre jobs à chaque push sur `master` et `main`, et à chaque pull
request (avec le seul droit de lire le dépôt ; les actions épinglées à un commit, Pester,
PSScriptAnalyzer et le générateur du site à une version) :

| Job | Lance |
|---|---|
| `build` | construit le module une fois (`CI/03_Build.ps1`), vérifie que son manifeste est celui du dépôt, et le donne aux autres jobs (l'artefact `module`) : ils testent celui-là, et la release le publie |
| `test` | reconstruit le module sous Windows et vérifie qu'il a les mêmes octets (la construction est reproductible), PSScriptAnalyzer sur `Code/` (`PSScriptAnalyzerSettings.psd1` : aucune erreur, aucun avertissement), puis tous les tests sur `windows-latest` ; les fenêtres doivent tourner (`-RequireRun`) |
| `test-linux` | tous les tests sur `ubuntu-latest` (Avalonia sur Xvfb) ; les fenêtres doivent tourner |
| `test-samba` | les tests qui écrivent dans un domaine, contre un contrôleur Samba AD provisionné sur la machine de la CI (`CI.TEST`), avec un ticket Kerberos de son administrateur ; la lecture du domaine, les scripts du lab, l'approbation, les modifications et les stratégies de mot de passe doivent tourner |

La page de chaque commande publique (`docs/<langue>/reference/commands/`, et son entrée dans le menu) est
écrite à partir de son aide par `CI/Update-CommandReference.ps1`, après `CI/03_Build.ps1` ; le premier
`.LINK` de l'aide d'une commande est sa page, que `Get-Help <commande> -Online` ouvre. Un test vérifie que
les pages sont celles de l'aide.

`Install-PSGPOAdmx` télécharge `sources/PolicyDefinitions` depuis GitHub et n'installe que les fichiers
qu'épingle `HGPM/Resources/PolicyDefinitions.json` (chaque ensemble, les `.admx` et chaque langue :
son nombre de fichiers et un SHA-256, fins de ligne et casse des noms mises à part). Après un changement de
`sources/PolicyDefinitions`, `CI/Update-AdmxCatalog.ps1` réécrit le catalogue ; un test le vérifie.

`.github/workflows/release.yml` publie le module sur la PowerShell Gallery pour un tag de version
(`v0.1.3-alpha`) seulement, jamais pour un commit. Il lance les jobs de la CI sur le commit tagué, puis,
sous Windows, avec les droits dont il a besoin et ceux-là seulement :

1. `CI/04_Publish.ps1` vérifie la version (le tag est la version du manifeste, `CHANGELOG.md` a sa
   section, la galerie ne l'a pas encore) ;
2. `CI/05_Package.ps1` fait le paquet à partir du module que les tests ont exécuté (l'artefact `module`,
   jamais une construction à lui) : signé avec Authenticode, avec son catalogue `HGPM.cat`, quand les
   secrets `CODE_SIGNING_PFX` (le PFX en Base64) et `CODE_SIGNING_PASSWORD` sont donnés ; son archive,
   les [archives hors ligne](../getting-started/offline.md) avec le runtime Avalonia de chaque
   plateforme, et `SHA256SUMS` ;
3. `actions/attest` atteste chaque fichier de `SHA256SUMS` (`gh attestation verify`) ;
4. `CI/04_Publish.ps1` publie le paquet avec le secret `PSGALLERY_API_KEY`, et la release GitHub est
   créée avec les notes de la version, les archives et `SHA256SUMS`.

Les secrets sont ceux de l'environnement `psgallery`, dont les règles de protection s'appliquent avant
qu'ils soient donnés.

La documentation est construite et publiée par `.github/workflows/docs.yml`. Il fait la page Historique des
versions à partir de `CHANGELOG.md`, et met la version du module (`ModuleVersion` de son manifeste) et le
commit à partir duquel le site est construit en pied de chaque page.
