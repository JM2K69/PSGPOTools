# Référence de la configuration

Chaque réglage, avec sa valeur par défaut. La [configuration du domaine](../features/configuration.md)
ne contient que ceux qu'elle change.

## NewGpo

Ce que la fenêtre propose pour une nouvelle GPO.

| Réglage | Par défaut | |
|---|---|---|
| `NewGpo.DefaultName` | `New Group Policy Object` | nom proposé |
| `NewGpo.Status` | `Enabled` | `Enabled`, `ComputerOnly` (paramètres utilisateur désactivés), `UserOnly` (paramètres ordinateur désactivés) |
| `NewGpo.SecurityFilteringGroups.Create` | `$false` | *Create the security filtering groups* coché à l'ouverture du formulaire |
| `NewGpo.SecurityFilteringGroups.Container` | vide | où créer les groupes : un nom distinctif, ou un chemin sous le domaine (`OU=GPO,OU=Groups`) ; vide : le conteneur des utilisateurs |
| `NewGpo.SecurityFilteringGroups.ApplyPrefix` | `APPLY_` | préfixe du groupe dont seuls les membres appliquent la GPO |
| `NewGpo.SecurityFilteringGroups.DenyPrefix` | `DENY_` | préfixe du groupe dont les membres ne l'appliquent jamais |
| `NewGpo.SecurityFilteringGroups.Scope` | `Global` | `Global`, `DomainLocal`, `Universal` |
| `NewGpo.SecurityFilteringGroups.ApplyDescription` | `Members apply the GPO {0}` | description ; `{0}` est le nom de la GPO |
| `NewGpo.SecurityFilteringGroups.DenyDescription` | `Members do not apply the GPO {0}` | description |

Les préfixes ne peuvent être ni vides, ni contenir un caractère interdit dans un nom de groupe
(`" / \ [ ] : ; | = , + * ? < > @`), ni être identiques.

## Backup

| Réglage | Par défaut | |
|---|---|---|
| `Backup.ApprovedLabel` | `Approved` | étiquette des versions approuvées : la sauvegarde la plus récente qui la porte est la référence de l'écart |
| `Backup.TemplateLabel` | `Template` | étiquette des modèles de nouvelles GPO |

Une étiquette fait au plus 64 caractères, sans virgule, tabulation ni saut de ligne ; les deux
étiquettes sont différentes.

## Audit

| Réglage | Défaut | |
|---|---|---|
| `Audit.Enabled` | `$true` | les modifications sont écrites dans le [journal d'audit](../features/audit-log.md) ; `$false` : elles ne le sont pas (les modifications sont toujours faites) |
| `Audit.Path` | vide | le [journal d'audit central](../features/audit-log.md#le-journal-central-un-dossier-par-tier), le même pour toutes les consoles : un partage d'un serveur de fichiers (`\\serveur\gpo-audit`), pas SYSVOL, préparé par `Initialize-PSGPOAuditShare` ; vide : le dossier `Audit` des sauvegardes du compte |
| `Audit.Tiers.Tier1` | vide | groupes du Tier 1, séparés par des virgules : ils écrivent dans le dossier `Tier1` du journal central et lisent les modifications de leur tier |
| `Audit.Tiers.Tier2` | vide | groupes du Tier 2 : le dossier `Tier2` |
| `Audit.Readers` | vide | groupes qui lisent tous les tiers sans écrire (auditeurs) |

## View

| Réglage | Par défaut | |
|---|---|---|
| `View.ShowUnmanaged` | `$true` | chaque compte voit tout le domaine, comme GPMC : ce qu'il ne gère pas est grisé, en lecture seule ; `$false` : il ne voit que ce qu'il gère, et un compte sans délégation ne voit rien ([délégation](../features/delegation.md)) |

## Workflow

Le [workflow d'approbation](../workflows/approval.md).

| Réglage | Par défaut | |
|---|---|---|
| `Workflow.Enabled` | `$false` | le workflow est utilisé |
| `Workflow.Approvers` | `Domain Admins` | groupes des approbateurs (Tier 0), séparés par des virgules |
| `Workflow.Creators` | vide | groupes des créateurs (Tier 1), séparés par des virgules ; obligatoire quand le workflow est activé |
| `Workflow.ApprovedOwner` | `Domain Admins` | propriétaire des GPO approuvées : un groupe des approbateurs |
| `Workflow.CreatorRights` | `ReadOnly` | ce que l'approbation propose pour les créateurs : `ReadOnly` ou `EditSettings` |

Les groupes sont des noms du domaine (`sAMAccountName`, avec ou sans `DOMAINE\`), ou des SID. Un
nom inconnu du domaine bloque la création de GPO, plutôt que de donner de mauvais droits.

## Exemple

```powershell
# \\dc.hardenbox.labo\SYSVOL\hardenbox.labo\PSGPOTools\Configuration.psd1
@{
    NewGpo = @{
        Status = 'ComputerOnly'
        SecurityFilteringGroups = @{
            Create = $true
            Container = 'OU=Groups,OU=Tier 1'
            Scope = 'DomainLocal'
        }
    }
    Workflow = @{
        Enabled = $true
        Creators = 'GPO-Tier1-Admins, GPO-Tier2-Admins'
        CreatorRights = 'EditSettings'
    }
}
```
