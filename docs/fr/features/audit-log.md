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
