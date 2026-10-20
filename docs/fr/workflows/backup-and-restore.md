# Sauvegarder et restaurer

Objectif : garder l'historique de chaque GPO, voir ce qui a changé, et revenir à une version.

## 1. Sauvegarder à intervalles réguliers

Une sauvegarde n'est écrite que si la GPO a changé : la même commande peut donc tourner toutes les
heures.

=== "Linux (timer systemd)"

    ```ini
    # /etc/systemd/system/psgpo-backup.service
    [Service]
    Type=oneshot
    User=gpo-backup
    # Un keytab donne au compte son ticket Kerberos sans mot de passe.
    ExecStartPre=/usr/bin/kinit -k -t /etc/gpo-backup.keytab gpo-backup@HARDENBOX.LABO
    ExecStart=/usr/bin/pwsh -NoProfile -Command "Backup-PSGPO -Server dc.hardenbox.labo -Path /srv/gpo-backups"

    # /etc/systemd/system/psgpo-backup.timer
    [Timer]
    OnCalendar=hourly
    [Install]
    WantedBy=timers.target
    ```

=== "Windows (tâche planifiée)"

    ```powershell
    $Action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -Command "Backup-PSGPO -Path D:\GPO_Backup"'
    $Trigger = New-ScheduledTaskTrigger -Once -At 00:00 -RepetitionInterval (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName 'HGPM backup' -Action $Action -Trigger $Trigger -User 'CONTOSO\gpo-backup' -Password (Read-Host)
    ```

Le compte doit pouvoir lire les GPO et leurs dossiers SYSVOL ; Authenticated Users le peut.

## 2. Commenter un changement

Avant ou après un changement, sauvegardez avec la raison, depuis l'onglet History (le champ de
commentaire au-dessus de la frise) ou en ligne de commande :

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Name 'T1 - Servers - Baseline' -Comment 'CHG-1024 : signature SMB exigée'
```

## 3. Voir ce qui a changé

Onglet **History** de la GPO : sélectionnez un nœud de la frise, ses changements sont listés avec
leur valeur avant et après. Entre deux sauvegardes quelconques :

```powershell
$Backups = Get-PSGPOBackup -Path /srv/gpo-backups -Name 'T1 - Servers - Baseline'
Compare-PSGPOBackup -ReferenceBackup $Backups[-1] -DifferenceBackup $Backups[0] |
    Format-Table Change, Path, Name, Before, After
```

![Les changements d'une sauvegarde](../assets/screenshots/04-history.png)

## 4. Restaurer une version

Sélectionnez le nœud > **Restore this version...** > **Restore**. La GPO telle qu'elle est est
d'abord sauvegardée : on peut annuler la restauration de la même façon.

```powershell
Get-PSGPOBackup -Path /srv/gpo-backups -Name 'T1 - Servers - Baseline' | Select-Object -Last 1 |
    Restore-PSGPO -Server dc.hardenbox.labo
```

!!! tip
    `-WhatIf` dit ce que ferait une restauration ; `-Confirm:$false` restaure sans demander, dans un
    script.
