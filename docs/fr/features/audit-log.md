# Journal d'audit

![La tuile Journal d'audit](../assets/screenshots/62-tile-audit-log.fr.png){ align=right width="170" }

`Show-AuditLogAvalonia` (ou la tuile **Journal d'audit** de `Start-HGPM`) montre le journal d'audit
de HGPM : chaque modification acceptée par le domaine, depuis une console ou une commande, la plus
récente d'abord. Qui, quand, depuis quel ordinateur, sur quel contrôleur de domaine, quoi et sur
quelle GPO, UO ou réglage. Il ne demande aucun droit sur le domaine : seulement la lecture du
dossier du journal.

```powershell
Show-AuditLogAvalonia
Show-AuditLogAvalonia -Path \\fichiers\gpo-audit              # un autre dossier
Show-AuditLogAvalonia -Server dc.hardenbox.labo -Language fr-FR
```

![Le journal d'audit](../assets/screenshots/63-audit-log.fr.png)

## Les modifications

| Colonne | |
|---|---|
| **Heure** | quand, à l'heure de l'ordinateur (le journal garde l'UTC) |
| **Compte** | le compte de l'annuaire qui a fait la modification |
| **Action** | quoi, par son nom : *GPO créée*, *Lien modifié*, *Paramètres d'une GPO enregistrés*, *GPO approuvée*... |
| **GPO ou objet** | la GPO, sinon l'UO, le domaine ou la configuration |
| **Tier** | le dossier du journal central où elle est : Tier 0, 1, 2, Sans tier |
| **Ordinateur**, **Domaine** | d'où, sur quel domaine |

- **La période** : les dernières 24 heures, 7 jours, 30 jours (au départ) ou tout.
- **Le domaine** et **l'action** : ceux que contient le journal.
- **La recherche** lit tous les textes d'une modification, détails compris : chaque mot doit être
  trouvé (`registry.pol tiers1`).
- **Les détails** de la modification choisie : tout ce que le journal en garde, comme le contrôleur
  de domaine, la GPO et son identifiant, et ses détails (les options d'un lien modifiées, le
  fichier enregistré avec son SHA-256 et sa nouvelle version, les droits des créateurs à une
  approbation...).
- **Exporter en CSV...** : les modifications affichées, telles qu'elles sont filtrées, l'heure en UTC
  (ISO 8601), les détails en JSON.

## Où est le journal

Le dossier est `Audit.Path` de la [configuration du domaine](configuration.md) : la fenêtre lit le
domaine une fois affichée (`-Server`, sinon le domaine de l'ordinateur). Sans domaine, ou quand la
configuration ne donne pas de dossier, c'est le dossier `Audit` des sauvegardes du compte, que seule
sa console écrit. **Parcourir...** et **Actualiser** lisent un autre dossier, ou relisent le même.

Le journal est **activé par défaut** : `Audit.Enabled = $false` dans la configuration du domaine
l'arrête, les modifications étant toujours faites. Voir [le journal d'audit](backup-history.md#journal-daudit)
pour ce que contient chaque ligne.

```powershell
# Les mêmes modifications dans un script
Get-PSGPOAuditLog -After (Get-Date).AddDays(-7) -Action SaveGpoFile, ApproveGpo |
    Export-Csv .\audit.csv -NoTypeInformation
```

## Le journal central, un dossier par tier

Un journal partagé par les consoles est sur **un partage d'un serveur de fichiers**, `Audit.Path`
de la configuration du domaine. Pas SYSVOL : il est copié sur chaque contrôleur de domaine (DFSR),
le journal grossirait sur chacun d'eux, et deux contrôleurs qui complètent le même fichier
perdraient des lignes ; Samba ne copie pas du tout SYSVOL.

Le partage a un dossier par tier, et les droits des rôles :

| Dossier | Y écrit (son propre fichier) | Le lit |
|---|---|---|
| `Tier0` | les approbateurs du workflow (`Workflow.Approvers`), Admins du domaine | le Tier 0, les lecteurs |
| `Tier1` | les groupes de `Audit.Tiers.Tier1` | le Tier 1, le Tier 0, les lecteurs |
| `Tier2` | les groupes de `Audit.Tiers.Tier2` | le Tier 2, le Tier 0, les lecteurs |
| `Unassigned` | un compte sans tier | le Tier 0, les lecteurs |

- Chaque compte ajoute ses modifications à **son propre fichier** :
  `<tier>\<domaine>-<aaaa-MM>-<compte>-<ordinateur>.jsonl`. Deux consoles n'écrivent jamais le même
  fichier ; personne d'autre que les administrateurs ne supprime un fichier ni ne change ses droits.
- **Le Tier 0 lit tous les tiers**, un compte du Tier 1 ou du Tier 2 les modifications de son tier
  seulement, les lecteurs (`Audit.Readers`, les auditeurs) tout, sans écrire. La fenêtre montre ce
  que le compte peut lire, et le tier de chaque modification.
- Le tier d'un compte est lu dans ses groupes à la lecture du domaine : un administrateur du domaine
  ou un approbateur est Tier 0, puis les groupes de `Audit.Tiers`.

### 1. Le partage

=== "Windows"

    Sur un serveur de fichiers Windows, en administrateur :

    [Télécharger windows/New-PSGPOAuditShare.ps1](../assets/scripts/windows/New-PSGPOAuditShare.ps1){ download }

    ```powershell
    .\New-PSGPOAuditShare.ps1                                  # \\<serveur>\gpo-audit, D:\Shares\GPO-Audit
    .\New-PSGPOAuditShare.ps1 -Name gpo-audit -Path E:\Shares\GPO-Audit -WhatIf
    ```

    ??? example "windows/New-PSGPOAuditShare.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/windows/New-PSGPOAuditShare.ps1"
        ```

=== "Linux"

    Sur un serveur Samba (un serveur membre, ou le contrôleur de domaine d'un lab), en root :

    [Télécharger linux/New-PSGPOAuditShare.sh](../assets/scripts/linux/New-PSGPOAuditShare.sh){ download }

    ```bash
    sudo ./New-PSGPOAuditShare.sh                             # //<serveur>/gpo-audit, /srv/gpo-audit
    sudo ./New-PSGPOAuditShare.sh gpo-audit /srv/gpo-audit
    ```

    ??? example "linux/New-PSGPOAuditShare.sh"

        ```bash
        --8<-- "docs/assets/scripts/linux/New-PSGPOAuditShare.sh"
        ```

### 2. Les rôles, dans la configuration du domaine

Dans **Paramètres** de la console (un administrateur du domaine), ou `Configuration.psd1` :

```powershell
Audit = @{
    Path = '\\fichiers.contoso.com\gpo-audit'
    Tiers = @{ Tier1 = 'GPO-Tier1-Admins'; Tier2 = 'GPO-Tier2-Admins' }
    Readers = 'GPO-Auditeurs'
}
```

### 3. Les dossiers et leurs droits

`Initialize-PSGPOAuditShare` crée les dossiers des tiers et écrit leurs droits à partir des rôles.
À relancer chaque fois que les groupes des tiers changent : les fichiers sont gardés.

```powershell
Initialize-PSGPOAuditShare -WhatIf
Initialize-PSGPOAuditShare                                   # Audit.Path de la configuration
Initialize-PSGPOAuditShare -Path //fichiers.contoso.com/gpo-audit -Server dc.contoso.com    # Linux
```

### 4. Les journaux des consoles, déplacés dedans

Les modifications que les consoles écrivaient avant, dans le dossier `Audit` des sauvegardes de leur
compte :

```powershell
Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -WhatIf
Import-PSGPOAuditLog -Path "$HOME/PSGPOTools Backups/Audit" -Remove
```

Chaque modification va dans le fichier de son compte, de son ordinateur et de son mois, dans le
dossier du tier de son compte ; une modification déjà présente n'est pas écrite deux fois, et
`-Remove` supprime les fichiers lus.
