# Configuration reference

Every setting, with its default. The [configuration of the domain](../features/configuration.md)
holds only those it changes.

## NewGpo

What the window proposes for a new GPO.

| Setting | Default | |
|---|---|---|
| `NewGpo.DefaultName` | `New Group Policy Object` | name proposed |
| `NewGpo.Status` | `Enabled` | `Enabled`, `ComputerOnly` (user settings disabled), `UserOnly` (computer settings disabled) |
| `NewGpo.SecurityFilteringGroups.Create` | `$false` | *Create the security filtering groups* checked when the form opens |
| `NewGpo.SecurityFilteringGroups.Container` | empty | where the groups are created: a distinguished name, or a path below the domain (`OU=GPO,OU=Groups`); empty: the users container |
| `NewGpo.SecurityFilteringGroups.ApplyPrefix` | `APPLY_` | prefix of the group whose members alone apply the GPO |
| `NewGpo.SecurityFilteringGroups.DenyPrefix` | `DENY_` | prefix of the group whose members never apply it |
| `NewGpo.SecurityFilteringGroups.Scope` | `Global` | `Global`, `DomainLocal`, `Universal` |
| `NewGpo.SecurityFilteringGroups.ApplyDescription` | `Members apply the GPO {0}` | description; `{0}` is the name of the GPO |
| `NewGpo.SecurityFilteringGroups.DenyDescription` | `Members do not apply the GPO {0}` | description |

The prefixes cannot be empty, hold a character a group name cannot hold (`" / \ [ ] : ; | = , + * ? < > @`),
nor be the same.

## Backup

| Setting | Default | |
|---|---|---|
| `Backup.ApprovedLabel` | `Approved` | label of the approved versions: the newest backup with it is the reference of the drift |
| `Backup.TemplateLabel` | `Template` | label of the templates of new GPOs |

A label has at most 64 characters, without comma, tab or line break; the two labels differ.

## Audit

| Setting | Default | |
|---|---|---|
| `Audit.Enabled` | `$true` | the changes are written to the [audit log](../features/audit-log.md); `$false`: they are not (the changes are still made) |
| `Audit.Path` | empty | the [central audit log](../features/audit-log.md#the-central-log-a-folder-per-tier), the same for every console: a share of a file server (`\\server\gpo-audit`), not SYSVOL, prepared by `Initialize-PSGPOAuditShare`; empty: the folder `Audit` of the backups of the account |
| `Audit.Tiers.Tier1` | empty | groups of Tier 1, separated by commas: they write in the folder `Tier1` of the central log and read the changes of their tier |
| `Audit.Tiers.Tier2` | empty | groups of Tier 2: the folder `Tier2` |
| `Audit.Readers` | empty | groups that read every tier without writing (auditors) |

## View

| Setting | Default | |
|---|---|---|
| `View.ShowUnmanaged` | `$true` | every account sees the whole domain, as GPMC: what it does not manage is greyed, read only; `$false`: it sees only what it manages, and an account without delegation sees nothing ([delegation](../features/delegation.md)) |

## Workflow

The [approval workflow](../workflows/approval.md).

| Setting | Default | |
|---|---|---|
| `Workflow.Enabled` | `$false` | the workflow is used |
| `Workflow.Approvers` | `Domain Admins` | groups of the approvers (Tier 0), separated by commas |
| `Workflow.Creators` | empty | groups of the creators (Tier 1), separated by commas; required when the workflow is enabled |
| `Workflow.ApprovedOwner` | `Domain Admins` | owner of the approved GPOs: one group of the approvers |
| `Workflow.CreatorRights` | `ReadOnly` | what the approval proposes for the creators: `ReadOnly` or `EditSettings` |

The groups are names of the domain (`sAMAccountName`, with or without `DOMAIN\`), or SIDs. A name
the domain does not know stops the creation of GPOs, rather than give the wrong rights.

## Example

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
