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
| `PSGPOTools.Workflow.tests.ps1` | le workflow d'approbation |
| `PSGPOTools.Delegation.tests.ps1` | les droits lus dans l'annuaire |
| `PSGPOTools.Ldap.tests.ps1` | LDAP, gPLink, samba-tool, RSAT (simulés), et face à un contrôleur de domaine |
| `PSGPOTools.Gui.tests.ps1` | la vraie fenêtre (`-OnShown`) |
| `PSGPOTools.Public.tests.ps1` | les commandes exportées |

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
ont créé à la fin, quoi qui ait échoué.

Avec aussi `PSGPOTOOLS_TEST_LAB_SCRIPTS=1` (Linux), ils lancent les scripts Linux du
[labo](../getting-started/lab.md), `New-PSGPOTierLab.ps1` et `Grant-PSGPOTierDelegation.ps1`, deux fois
chacun : les OU, groupes et comptes des tiers, le mot de passe du labo (un ticket Kerberos de
`tiers1`), la délégation des liens et de la création de GPO (le workflow activé pour le test). Ils changent le domaine pour de
bon : le job `test-samba` de la CI le définit, sur son domaine jetable seulement.

Les écritures d'une approbation (`PSGPOTools.Hardening.tests.ps1`) sont testées avec des mocks :
leur ordre (SYSVOL, les objets que contient la GPO, puis la GPO), la GPO laissée en attente quand
SYSVOL échoue, les permissions retirées et signalées. Le workflow complet, qui demande deux comptes
(Tier 0 et Tier 1), a été testé pas à pas dans le labo, `kinit` changeant de compte entre les
étapes ([approbation](../workflows/approval.md)).

## CI

`.github/workflows/ci.yml` lance trois jobs à chaque push sur `master`, `main` et `avalonia` :

| Job | Lance |
|---|---|
| `test` | PSScriptAnalyzer sur `Code/` (`PSScriptAnalyzerSettings.psd1` : aucune erreur, aucun avertissement), puis tous les tests sur `windows-latest`, la fenêtre comprise |
| `test-linux` | tous les tests sur `ubuntu-latest`, la fenêtre comprise (Avalonia sur Xvfb) |
| `test-samba` | les tests qui écrivent dans un domaine, contre un contrôleur Samba AD provisionné sur la machine de la CI (`CI.TEST`), avec un ticket Kerberos de son administrateur |

La page de chaque commande publique (`docs/<langue>/reference/commands/`, et son entrée dans le menu) est
écrite à partir de son aide par `CI/Update-CommandReference.ps1`, après `CI/03_Build.ps1` ; le premier
`.LINK` de l'aide d'une commande est sa page, que `Get-Help <commande> -Online` ouvre. Un test vérifie que
les pages sont celles de l'aide.

`Install-PSGPOAdmx` télécharge `sources/PolicyDefinitions` depuis GitHub et n'installe que les fichiers
qu'épingle `PSGPOTools/Resources/PolicyDefinitions.json` (chaque ensemble, les `.admx` et chaque langue :
son nombre de fichiers et un SHA-256, fins de ligne et casse des noms mises à part). Après un changement de
`sources/PolicyDefinitions`, `CI/Update-AdmxCatalog.ps1` réécrit le catalogue ; un test le vérifie.

`.github/workflows/release.yml` publie le module sur la PowerShell Gallery pour un tag de version
(`v0.1.2-alpha`) seulement, jamais pour un commit : il lance les trois jobs de la CI sur le commit tagué,
puis `CI/04_Publish.ps1` (le tag est la version du manifeste, `CHANGELOG.md` a sa section, la galerie ne
l'a pas encore) avec le secret `PSGALLERY_API_KEY` de l'environnement `psgallery`, et crée la release
GitHub avec les notes de la version.

La documentation est construite et publiée par `.github/workflows/docs.yml`. Il fait la page Historique des
versions à partir de `CHANGELOG.md`, et met la version du module (`ModuleVersion` de son manifeste) et le
commit à partir duquel le site est construit en pied de chaque page.
