# Le lanceur

`Start-HGPM` ouvre le lanceur de HGPM : une tuile pour chacun de ses outils. Un clic sur une tuile
ouvre l'outil, dans la langue du lanceur, dans un processus PowerShell à lui : plusieurs outils
peuvent être ouverts à la fois, un outil en erreur ne ferme pas les autres, et ils restent ouverts
une fois le lanceur fermé. La tuile d'un outil ouvert est désactivée jusqu'à la fermeture de sa
fenêtre.

```powershell
Import-Module HGPM
Start-HGPM
Start-HGPM -Language en-US      # le lanceur et les outils en anglais
```

![Le lanceur](../assets/screenshots/56-launcher.fr.png)

## Les outils

| | Outil | Commande | Ce qu'il fait |
|---|---|---|---|
| ![](../assets/screenshots/57-tile-group-policy.fr.png){ width="150" } | [Gestion de stratégie de groupe](console.md) | `Show-GPOManagerAvalonia` | Les GPO du domaine, leurs liens, paramètres, délégation et sauvegardes, comme GPMC |
| ![](../assets/screenshots/58-tile-password-settings.fr.png){ width="150" } | [Paramètres de mot de passe](password-policies.md) | `Show-PSOManagerAvalonia` | Les stratégies de mot de passe affinées (PSO), et celle que reçoit un utilisateur ou un groupe |
| ![](../assets/screenshots/59-tile-wmi-filter-creator.fr.png){ width="150" } | [Créateur de filtres WMI](wmi-filter-creator.md) | `Show-WmiFilterCreatorAvalonia` | Des filtres WMI construits à partir de requêtes prêtes à l'emploi, vérifiés, testés, exportés en `.mof` |
| ![](../assets/screenshots/60-tile-policy-analyzer.fr.png){ width="150" } | [Policy Analyzer](policy-analyzer.md) | `Show-PolicyAnalyzerAvalonia` | Les GPO et les baselines de sécurité de Microsoft comparées paramètre par paramètre |
| ![](../assets/screenshots/62-tile-audit-log.fr.png){ width="150" } | [Journal d'audit](audit-log.md) | `Show-AuditLogAvalonia` | Ce que les consoles et les commandes ont modifié dans le domaine : qui, quand, d'où, sur quelle GPO |

Une tuile ouvre son outil avec ses paramètres par défaut : le domaine de l'ordinateur, les fichiers
ADMX choisis la dernière fois. Pour donner des paramètres à un outil (`-Server`, `-Credential`,
`-PolicyDefinitions`...), lancez plutôt sa commande. Quand un outil ne s'ouvre pas, le lanceur dit
pourquoi sous ses tuiles.

## Langue et thème

- **La liste des langues** (English, Français) change aussitôt la langue du lanceur, et celle des
  outils ouverts ensuite. Le choix est gardé dans les paramètres de l'utilisateur : `Start-HGPM`
  démarre dessus la fois suivante ; `Start-HGPM -Language` en choisit toujours une autre.
- **Mode sombre / Mode clair** change le thème de toutes les fenêtres de HGPM : le lanceur, les
  outils ouverts et ceux ouverts ensuite, et les fenêtres qu'ils ouvrent (fichiers ADMX,
  configuration...). Le choix est aussi gardé dans les paramètres de l'utilisateur : les outils
  ouverts dans leurs propres processus le suivent en une seconde, et le démarrage suivant part de
  lui.
