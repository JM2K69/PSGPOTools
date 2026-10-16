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

Le workflow d'approbation, qui demande deux comptes (Tier 0 et Tier 1), a été testé pas à pas dans
le labo, `kinit` changeant de compte entre les étapes ([approbation](../workflows/approval.md)).

## CI

`.github/workflows/ci.yml` lance les tests sur `windows-latest` (la fenêtre comprise) ; la
documentation est construite et publiée par `.github/workflows/docs.yml`.
