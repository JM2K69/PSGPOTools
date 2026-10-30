# Production

Le [lab](lab.md) montre HGPM sur un domaine fait pour lui. Cette page donne l'ordre à suivre sur un
vrai domaine : chaque étape avec ce qu'elle fait, qui la lance et comment la vérifier. Les rôles
sont ceux du [modèle de sécurité](../technical/security-model.md) : le **Tier 0** (les
administrateurs du domaine et les approbateurs), le **Tier 1** et le **Tier 2** (les techniciens,
qui créent des GPO qui attendent une approbation).

## Avant de commencer

| Quoi | Nécessaire |
|---|---|
| Les consoles | PowerShell 7.4 ou plus, sur les postes d'administration de chaque tier (Windows ou Linux) |
| Réseau, vers les contrôleurs de domaine | LDAP 389 (signé et chiffré) ou LDAPS 636, Kerberos 88, SMB 445 (SYSVOL), DNS 53 |
| Réseau, vers le serveur de fichiers | SMB 445 : le partage du journal d'audit, le partage des sauvegardes |
| Linux | `smbclient`, `samba-tool`, `python3-samba`, `krb5-user`, un ticket Kerberos (`kinit`) |
| Le premier lancement d'une console | nuget.org (ou un flux interne) pour le runtime Avalonia, ou le runtime installé avant ([installation](installation.md#le-runtime-avalonia), [hors ligne](offline.md)) |
| Les groupes | les approbateurs (Tier 0), les créateurs de chaque tier, les auditeurs, les purgeurs : des groupes du domaine, créés avant |

Gardez les consoles d'un domaine sur **la même version** de HGPM : la [configuration](../reference/configuration.md#console)
d'une console plus récente est ignorée par une plus ancienne.

## Les étapes

| # | Étape | Qui | Commande ou endroit | Vérification |
|---|---|---|---|---|
| 1 | Installer le module sur chaque poste d'administration | chaque compte | `Install-PSResource HGPM -Prerelease` | `Get-Module HGPM -ListAvailable` |
| 2 | Les fichiers ADMX : le magasin central du domaine (avant l'étape 5 : un créateur pourrait le créer), ou une copie à côté du module | Tier 0 | le magasin central (`SYSVOL\<domaine>\Policies\PolicyDefinitions`), ou `Install-PSGPOAdmx` | la console liste les stratégies |
| 3 | La configuration du domaine : ouvrir la console une fois | un Domain Admin | `Show-GPOManagerAvalonia` crée `SYSVOL\<domaine>\PSGPOTools\Configuration.psd1` | `Get-PSGPOConfiguration` |
| 4 | Les rôles du circuit d'approbation | un Domain Admin | **Paramètres** : `Workflow.Enabled`, `Workflow.Approvers`, `Workflow.Creators`, `Workflow.ApprovedOwner`, `Workflow.CreatorRights` | `Get-PSGPOConfiguration` : aucun problème ; un rôle dans les deux listes est refusé |
| 5 | La création de GPO pour les créateurs | un Domain Admin | `Initialize-PSGPOWorkflow -Apply` | `Initialize-PSGPOWorkflow` : chaque droit `Present`, le magasin central au Tier 0 |
| 6 | Les liens de chaque tier sur ses UO | un Domain Admin | l'onglet Délégation des UO, comme GPMC (le script du lab `Grant-PSGPOTierDelegation.ps1` en est un exemple) | un technicien voit ses UO, les autres grisées |
| 7 | Le partage du journal d'audit | l'administrateur du serveur de fichiers | `New-PSGPOShare.ps1` (Windows) ou `New-PSGPOShare.sh` (Samba) ([journal d'audit](../features/audit-log.md#1-le-partage)) | le partage existe, seuls les administrateurs ont le contrôle total |
| 8 | Le journal d'audit : son partage et ses rôles | un Domain Admin | **Paramètres** : `Audit.Path`, `Audit.Tiers`, `Audit.Readers`, `Audit.Purgers` ; puis `Initialize-PSGPOAuditShare` | l'outil Journal d'audit d'un technicien : son tier seulement, ses modifications *Vérifiées* |
| 9 | Les sauvegardes centrales, pour le Tier 0 | un Domain Admin | **Paramètres** : `Backup.Path` ; `Initialize-PSGPOBackupShare` ; sous Linux `New-PSGPOShareMount.sh --fstab` | l'onglet Historique du Tier 0 ; aucun pour les techniciens |
| 10 | Le journal du système, pour un SIEM | un administrateur de chaque poste Windows | `Register-PSGPOEventSource` (Linux : journald, rien à faire) | les événements de source HGPM ([identifiants](../features/audit-log.md#le-journal-du-systeme-pour-un-siem)) |
| 11 | La rétention du journal d'audit | un Domain Admin | un gMSA dans un groupe de `Audit.Purgers`, une tâche mensuelle ([rétention](../features/audit-log.md#retention-et-archives)) | `Invoke-PSGPOAuditRetention -WhatIf` en tant que gMSA |
| 12 | La version des consoles | un Domain Admin, une fois toutes les consoles à jour | **Paramètres** : `Console.MinimumVersion` | une console plus ancienne ne crée aucune GPO |
| 13 | La posture du domaine, chaque jour | un Domain Admin, puis un gMSA | `Test-PSGPOSecurityPosture`, puis une tâche quotidienne avec `-SystemLog` ([ci-dessous](#the-posture-each-day)) | aucun constat *High* ; les événements 4000 et 4001 dans le SIEM |

## La posture, chaque jour { #the-posture-each-day }

`Test-PSGPOSecurityPosture` dit qui peut créer, modifier et lier des GPO hors du Tier 0 et du
circuit ([durcissement](../technical/hardening.md#posture)). Il ne fait que lire : planifiez-le avec
un compte sans groupe, chaque jour, avec `-SystemLog` ; le SIEM alerte sur l'événement 4001 (un
constat *High*).

=== "Windows (un gMSA)"

    ```powershell
    # Une fois, en administrateur du domaine
    New-ADServiceAccount -Name hgpm-posture -DNSHostName hgpm-posture.contoso.com -PrincipalsAllowedToRetrieveManagedPassword 'ADMIN-SERVER$'
    Install-ADServiceAccount hgpm-posture                                     # sur ADMIN-SERVER
    Register-PSGPOEventSource                                                 # sur ADMIN-SERVER, en administrateur

    # Chaque jour, en tant que gMSA : -LogonType Password sans mot de passe, Windows le récupère
    $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -Command "Import-Module HGPM; Test-PSGPOSecurityPosture -SystemLog | Out-Null"'
    $principal = New-ScheduledTaskPrincipal -UserId 'CONTOSO\hgpm-posture$' -LogonType Password
    Register-ScheduledTask -TaskName 'HGPM posture' -Action $action -Principal $principal -Trigger (New-ScheduledTaskTrigger -Daily -At 6am)
    ```

=== "Linux (un keytab)"

    ```bash
    # Une fois, sur un contrôleur de domaine Samba, en root
    samba-tool user add hgpm-posture --random-password
    samba-tool domain exportkeytab /root/hgpm-posture.keytab --principal=hgpm-posture
    # Copié sur l'ordinateur du contrôle, pour le seul compte hgpm
    sudo install -o hgpm -g hgpm -m 600 hgpm-posture.keytab /etc/hgpm/hgpm-posture.keytab

    # Chaque jour
    echo '0 6 * * * hgpm kinit -k -t /etc/hgpm/hgpm-posture.keytab hgpm-posture && pwsh -NoProfile -Command "Import-Module HGPM; Test-PSGPOSecurityPosture -Server dc.contoso.com -SystemLog | Out-Null"' | sudo tee /etc/cron.d/hgpm-posture
    ```

## La recette

Avant que les techniciens l'utilisent, comme dans le [lab](lab.md#3-la-console-en-technicien) :

1. Un technicien du Tier 1 crée une GPO sur une UO de son tier : elle attend une approbation,
   ne s'applique à personne, et l'approbateur la voit dans **En attente d'approbation**.
2. L'approbateur l'approuve avec ses groupes de filtrage : Domain Admins en est propriétaire, le
   technicien ne fait que la lire (ou modifie ses paramètres avec `EditSettings`).
3. Le technicien essaie une UO du Tier 2 : elle est grisée, le lien est refusé.
4. L'outil Journal d'audit montre les modifications, *Vérifiées* ; le SIEM reçoit les événements de
   source HGPM.

## Durcir le déploiement

- Seul le Tier 0 écrit `SYSVOL\<domaine>\PSGPOTools` : la configuration décide des rôles.
- Gardez `Workflow.Creators` et `Workflow.Approvers` séparés ; jamais un groupe de tous les comptes.
- Ne donnez aucun autre usage aux approbateurs, à Domain Admins et aux purgeurs : ils sont du Tier 0.
- Planifiez avec un gMSA ou un compte dédié et son keytab (mode 600), jamais avec le mot de passe
  d'un Domain Admin dans une tâche planifiée.
- Vérifiez la posture chaque jour ([ci-dessus](#the-posture-each-day)) : un droit donné à côté
  du circuit, puis oublié, donne les contrôleurs de domaine à un compte hors du Tier 0.
- Auditez aussi les contrôleurs de domaine ([Windows et Samba](../technical/dc-audit.md)) : une
  modification faite avec un autre outil que HGPM est dans leurs journaux, pas dans le sien.
- Envoyez le journal du système au SIEM : il garde une copie de chaque modification hors de portée
  des techniciens.

## Retour arrière

| À retirer | Comment |
|---|---|
| Le circuit d'approbation | **Paramètres** : `Workflow.Enabled` = `False` ; puis retirez les droits ajoutés par `Initialize-PSGPOWorkflow -Apply` : le droit de créer des objets `groupPolicyContainer` sur `CN=Policies,CN=System` et le droit de créer des dossiers dans `SYSVOL\<domaine>\Policies`, pour chaque groupe de créateurs (`dsacls` sous Windows, `samba-tool dsacl` et `smbcacls` sous Samba). Tant qu'ils sont là, une console sans la configuration ne crée aucune GPO ([échec en sécurité](../technical/hardening.md#configuration-fails-closed)) |
| La configuration du domaine | supprimez `SYSVOL\<domaine>\PSGPOTools`, une fois la délégation retirée |
| Le journal d'audit et les sauvegardes | gardez les partages aussi longtemps que l'entreprise garde ses preuves, puis supprimez-les |
| Le journal du système | `Remove-EventLog -Source HGPM`, sur chaque poste Windows |
| Le module | `Uninstall-PSResource HGPM` ; les données de chaque compte : `%LOCALAPPDATA%\PSGPOTools`, `~/.local/share/PSGPOTools` |

Les GPO, leurs liens et leurs approbations restent tels qu'ils sont : ils sont au domaine, comme
GPMC les laisse.
