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

    [Télécharger windows/New-PSGPOShare.ps1](../assets/scripts/windows/New-PSGPOShare.ps1){ download }

    ```powershell
    .\New-PSGPOShare.ps1 -Name gpo-audit                     # \\<serveur>\gpo-audit, D:\Shares\gpo-audit
    .\New-PSGPOShare.ps1 -Name gpo-audit -Path E:\Shares\GPO-Audit -WhatIf
    ```

    ??? example "windows/New-PSGPOShare.ps1"

        ```powershell
        --8<-- "docs/assets/scripts/windows/New-PSGPOShare.ps1"
        ```

=== "Linux"

    Sur un serveur Samba (un serveur membre, ou le contrôleur de domaine d'un lab), en root :

    [Télécharger linux/New-PSGPOShare.sh](../assets/scripts/linux/New-PSGPOShare.sh){ download }

    ```bash
    sudo ./New-PSGPOShare.sh                             # //<serveur>/gpo-audit, /srv/gpo-audit
    sudo ./New-PSGPOShare.sh gpo-audit /srv/gpo-audit
    ```

    ??? example "linux/New-PSGPOShare.sh"

        ```bash
        --8<-- "docs/assets/scripts/linux/New-PSGPOShare.sh"
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

## Rétention et archives

Le journal central garde `Audit.RetentionMonths` mois (13 par défaut ; `0` garde tout) : ce mois-ci
et ceux d'avant. `Invoke-PSGPOAuditRetention` met les fichiers d'un mois plus ancien, de tous les
tiers, dans `Archive\audit-<aaaa-MM>.zip` (avec leur dossier), vérifie que l'archive les contient,
puis les supprime ; un mois déjà archivé reçoit les fichiers écrits depuis. Le dossier `Archive` a
les droits du partage : le Tier 0 et les lecteurs le lisent. La rétention est écrite dans le
journal lui-même (`PurgeAuditLog`).

Seuls les administrateurs suppriment des fichiers du partage : planifiez-la avec l'un d'eux.

=== "Windows"

    ```powershell
    Invoke-PSGPOAuditRetention -WhatIf
    # Chaque mois, en tâche planifiée d'un administrateur du domaine
    $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -Command "Import-Module HGPM; Invoke-PSGPOAuditRetention"'
    Register-ScheduledTask -TaskName 'HGPM audit retention' -Action $action -Trigger (New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Sunday -At 3am) -User 'CONTOSO\hgpm-admin' -Password (Read-Host 'Mot de passe')
    ```

=== "Linux"

    ```bash
    # Chaque mois, avec le ticket d'un administrateur (un keytab : kinit -k -t /etc/hgpm.keytab hgpm-admin)
    echo '0 3 1 * * hgpm kinit -k -t /etc/hgpm.keytab hgpm-admin && pwsh -NoProfile -Command "Import-Module HGPM; Invoke-PSGPOAuditRetention -Server dc.contoso.com"' | sudo tee /etc/cron.d/hgpm-audit-retention
    ```

## Le journal du système, pour un SIEM

Avec `Log.SystemLog` (activé par défaut), chaque modification du journal d'audit et chaque erreur
du journal technique partent aussi dans le journal du système, où un SIEM les collecte :

| | Windows | Linux |
|---|---|---|
| Où | le journal d'événements **Application**, source **HGPM** | syslog / journald, étiquette **hgpm** (`logger`) |
| Une modification | Information, l'ID d'événement de son action | `user.notice`, `[<ID d'événement>]` |
| Un avertissement, une erreur | Warning 2000, Error 3000 | `user.warning`, `user.err` |
| Une fois par ordinateur | `Register-PSGPOEventSource`, en administrateur | rien |

Le message dit quoi, par qui, d'où et sur quoi, puis l'entrée du journal d'audit en JSON :

```text
HGPM audit: ApproveGpo by HARDENBOX\Administrator from dc on hardenbox.labo: T1 - Servers - Proxy - CN={AFE8...}
{"Format":"PSGPOTools.Audit/1","Time":"2026-10-24T15:44:02Z","Domain":"hardenbox.labo",...}
```

| ID | Action | ID | Action |
|---|---|---|---|
| 1001 | NewGpo | 1023 | SetBlockInheritance |
| 1002 | RenameGpo | 1030 | SetGpoPermission |
| 1003 | SetGpoStatus | 1031 | SetGpoSecurityFiltering |
| 1004 | RemoveGpo | 1032 | NewFilteringGroups |
| 1005 | RemoveDeletedGpoBackup | 1040 | SetWmiFilter |
| 1006 | RestoreGpo | 1041 | NewWmiFilter |
| 1007 | ImportGpo | 1042 | EditWmiFilter |
| 1008 | SaveGpoFile | 1043 | RemoveWmiFilter |
| 1009 | ImportPolicyRuleSet | 1044 | SetWmiFilterPermission |
| 1010 | PendingGpo | 1050 | NewPasswordPolicy |
| 1011 | ApproveGpo | 1051 | SetPasswordPolicy |
| 1020 | NewLink | 1052 | RemovePasswordPolicy |
| 1021 | SetLink | 1060 | SaveConfiguration |
| 1022 | RemoveLink | 1061 | InstallAdmx |
| 1062 | InitializeAuditShare | 1063 | InitializeBackupShare |
| 1064 | PurgeAuditLog | 2000, 3000 | un avertissement, une erreur |

```powershell
Register-PSGPOEventSource                                                # Windows, une fois, en administrateur
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'HGPM' } -MaxEvents 20
```

```bash
journalctl -t hgpm --since today                                         # Linux
```

## Le journal technique

Ce qui se passe mal là où tourne une console, pour en trouver la cause après coup : les erreurs de
LDAP, de SYSVOL, des fenêtres, et les commandes du système (`samba-tool`, `smbclient`, `python3`,
`secedit`, `auditpol`) qui échouent, avec la commande, son code de sortie et ce qu'elle a écrit.
C'est le journal de l'ordinateur et de son utilisateur, pas du domaine :

| | |
|---|---|
| Où | `%LOCALAPPDATA%\PSGPOTools\Logs` (Windows), `~/.local/share/PSGPOTools/Logs` (Linux) |
| Fichiers | `hgpm-<aaaa-MM-jj>.log`, une entrée par ligne, ses détails en retrait dessous |
| Quoi | `Log.Level` : `Error`, `Warning` (par défaut), `Information` (les commandes qui échouent), `Verbose` (chaque commande) |
| Combien de temps | `Log.RetentionDays` jours (30), supprimés quand la console y écrit la première fois |

```text
2026-10-26T09:14:03.512Z ERROR       LDAP         LDAP connection to dc.hardenbox.labo:389 failed: ...
    Exception: System.DirectoryServices.Protocols.LdapException: The LDAP server is unavailable.
2026-10-26T09:15:40.077Z INFORMATION smbclient    Exit code 1.
    Command: smbclient //dc.hardenbox.labo/gpo-audit --use-kerberos=required -c 'ls'
    Error: NT_STATUS_ACCESS_DENIED listing \*
```

Pour trouver un problème : `Log.Level = 'Verbose'` dans **Paramètres**, refaire le problème, puis
le fichier du jour.
