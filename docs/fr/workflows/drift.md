# Écart avec la version approuvée

Objectif : savoir quand une GPO n'est plus ce qui a été approuvé, quel que soit l'auteur du
changement et l'outil utilisé.

## 1. Approuver une version

Une fois une GPO relue, étiquetez sa sauvegarde comme approuvée : onglet **History** >
sélectionnez la sauvegarde > cochez **Approved version** > **Save notes** ; ou au moment de la
sauvegarde :

```powershell
Backup-PSGPO -Path /srv/gpo-backups -Name 'C - Servers - Security Baseline' -Comment "Relue avec l'équipe sécurité" -Approve
```

Le nœud approuvé est vert sur la frise.

## 2. Voir l'écart

Au-dessus de la frise de la GPO, la console la compare à sa version approuvée :

- en vert : **la GPO est sa version approuvée** ;
- en orange : **elle a changé depuis sa version approuvée** (`+ajoutés ~modifiés -retirés`), et
  **Show the changes** les liste, paramètre par paramètre.

## 3. Vérifier toutes les GPO à intervalles réguliers

```powershell
$Drift = Get-PSGPODrift -Server dc.hardenbox.labo -Path /srv/gpo-backups | Where-Object State -EQ 'Drifted'
foreach ($Gpo in $Drift) {
    "$($Gpo.DisplayName) : changée depuis son approbation du $($Gpo.Approved) par $($Gpo.ApprovedBy)"
    $Gpo.Changes | Format-Table Change, Path, Name, Before, After | Out-String
}
```

Envoyez-le par mail ou à votre supervision : une GPO changée hors du processus de changement (GPMC
par quelqu'un d'autre, `samba-tool`, un script) apparaît ici.

## 4. Ensuite

- le changement est bon : approuvez la nouvelle version (sauvegardez-la avec `-Approve`) ;
- il ne l'est pas : restaurez la version approuvée ([Sauvegarder et restaurer](backup-and-restore.md)).
