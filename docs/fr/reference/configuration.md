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
| `Backup.Path` | vide | les [sauvegardes centrales](../features/backup-history.md#les-sauvegardes-centrales-pour-le-tier-0), les mêmes pour toutes les consoles : un partage d'un serveur de fichiers (`\\serveur\gpo-backups`), pas SYSVOL, préparé par `Initialize-PSGPOBackupShare`, pour le Tier 0 seulement ; vide : le dossier de l'onglet Historique de chaque compte |
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
| `Audit.Purgers` | vide | groupes qui lancent la rétention (`Invoke-PSGPOAuditRetention`) : ils lisent tous les tiers, suppriment les fichiers des anciens mois et écrivent les archives, sans être administrateurs du domaine (le groupe d'un gMSA) |
| `Audit.RetentionMonths` | `13` | mois que garde le journal central : `Invoke-PSGPOAuditRetention` archive les plus anciens dans `Archive`, puis supprime leurs fichiers ; `0` garde tout |

## Log

| Réglage | Par défaut | |
|---|---|---|
| `Log.Level` | `Warning` | ce que garde le [journal technique](../features/audit-log.md#le-journal-technique) de chaque console : `Error`, `Warning`, `Information` (les commandes qui échouent), `Verbose` (chaque commande) |
| `Log.RetentionDays` | `30` | jours pendant lesquels les fichiers du journal technique sont gardés |
| `Log.SystemLog` | `$true` | les modifications du journal d'audit et les erreurs envoyées au [journal du système](../features/audit-log.md#le-journal-du-systeme-pour-un-siem) : le journal des événements Windows (source HGPM) ou syslog/journald |

## Console

| Réglage | Par défaut | |
|---|---|---|
| `Console.MinimumVersion` | vide | version de HGPM dont une console a besoin au minimum (`0.1.14`) : une console plus ancienne n'utilise pas la configuration, et les comptes qui ne sont pas administrateurs du domaine n'y créent aucune GPO ([durcissement](../technical/hardening.md#configuration-fails-closed)) ; vide : toutes les versions |

Un réglage qu'une console ne connaît pas (ajouté par une version plus récente de HGPM) est ignoré
avec un avertissement, les autres sont utilisés, et la console le garde quand elle enregistre la
configuration. Mettez d'abord toutes les consoles à jour, puis réglez `Console.MinimumVersion` : les
consoles antérieures à 0.1.14 ne le connaissent pas, et ignorent toute la configuration.

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
